class_name World
extends RefCounted
## One run as plain data and rules, with no drawing, so tests can play it too.
## x grows to the right, y grows down, the runner's (x, y) is the middle of
## the feet. main.gd calls step() 60 times a second and draws the result.

const DT := 1.0 / 60.0
const GRAVITY := 3000.0
const JUMP_V := -1000.0
## Holding the button on the way up softens gravity, for a higher, longer jump.
const HOLD_GRAVITY := 0.42
const HOLD_MAX := 0.24
const MAX_FALL := 1900.0
const COYOTE := 0.08       # a jump still works this long after running off an edge
const BUFFER := 0.12       # a press this early before landing still jumps
const HALF_W := 22.0
const HEIGHT := 96.0  # matches the courier sprite at 2x, cap to shoes
const SPEED_START := 400.0
const SPEED_MAX := 800.0
const SPEED_RAMP := 40000.0  # px; by here the speed is 63% of the way to max
const PX_PER_M := 50.0
## Landing this close to a roof's front edge counts as an edge landing.
const EDGE_ZONE := 40.0
const MAX_MULT := 5
const CRUMBLE_DELAY := 0.25
const PARCEL_R := 30.0
const PARCEL_POINTS := 25
const EDGE_POINTS := 10
const AHEAD := 3200.0
const BEHIND := 1400.0
## Wires hang this high over the roof they start from: a tap passes under,
## a held jump hits them.
const WIRE_HIGH := 350.0
const WIRE_SAG := 30.0
const AC_SIZE := Vector2(78, 62)   # the art at 2x
const ANTENNA_SIZE := Vector2(12, 200)  # the pole; the art is drawn around it

var rng := RandomNumberGenerator.new()
## {id, x0, x1, y, base, crumble, t, vy}. t is -1 until a crumbling roof is touched.
var roofs: Array = []
## {kind ("ac" or "antenna"), x0, x1, y0, y1, roof}
var obstacles: Array = []
## {ax, ay, bx, by}: hangs from a to b with WIRE_SAG in the middle.
var wires: Array = []
## {x, y, taken}
var parcels: Array = []
var next_id := 0

var x := 0.0
var y := 0.0
var vy := 0.0
var grounded := true
var ground := {}          # the roof or obstacle under the feet
var air_t := 0.0
var jumped := false
var buffer_t := 99.0
var hold_t := 0.0
var hold_jump := false
var was_held := false
var alive := true
var death := ""
var dead_vx := 0.0
var started := false
var t := 0.0

var start_x := 0.0
var bonus := 0
var combo := 0            # edge landings in a row; the multiplier is combo + 1
var parcels_taken := 0
var last_roof := -1
var ref_y := 0.0          # top of the last roof stood on, for falling out


func _init(seed_value := 0, fresh := true) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	if not fresh:
		return
	ground = _add_roof(-1200.0, 1000.0, 0.0, false)
	last_roof = ground.id
	_ensure_generated()


# --- Queries ---------------------------------------------------------------

func speed() -> float:
	return speed_at(x)


func speed_at(at: float) -> float:
	var k := 1.0 - exp(-maxf(at - start_x, 0.0) / SPEED_RAMP)
	return SPEED_START + (SPEED_MAX - SPEED_START) * k


## 0 at the start, 1 from 1200 m on.
func difficulty_at(at: float) -> float:
	return clampf((at - start_x) / (PX_PER_M * 1200.0), 0.0, 1.0)


func meters() -> float:
	return maxf(x - start_x, 0.0) / PX_PER_M


func score() -> int:
	return int(meters()) + bonus


func multiplier() -> int:
	return combo + 1


func speed_frac() -> float:
	return (speed() - SPEED_START) / (SPEED_MAX - SPEED_START)


## Horizontal distance a jump covers before it falls back to dy below the
## launch height (dy < 0 is higher). 0 if it never gets that high.
static func reach(v: float, dy: float, hold: bool) -> float:
	var yy := 0.0
	var vv := JUMP_V
	var ht := 0.0
	var xx := 0.0
	for i in 400:
		var g := GRAVITY
		if hold and vv < 0.0 and ht < HOLD_MAX:
			g *= HOLD_GRAVITY
			ht += DT
		vv = minf(vv + g * DT, MAX_FALL)
		yy += vv * DT
		xx += v * DT
		if vv > 0.0 and yy >= dy:
			return xx
	return 0.0


## How high the feet get above the launch point.
static func apex(hold: bool) -> float:
	var yy := 0.0
	var vv := JUMP_V
	var ht := 0.0
	var top := 0.0
	for i in 400:
		var g := GRAVITY
		if hold and vv < 0.0 and ht < HOLD_MAX:
			g *= HOLD_GRAVITY
			ht += DT
		vv = minf(vv + g * DT, MAX_FALL)
		yy += vv * DT
		top = minf(top, yy)
		if vv > 0.0:
			break
	return -top


## Points along a wire, for drawing and for hits.
static func wire_points(w: Dictionary, n := 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var k := float(i) / n
		var p := Vector2(lerpf(w.ax, w.bx, k), lerpf(w.ay, w.by, k))
		p.y += WIRE_SAG * 4.0 * k * (1.0 - k)
		pts.append(p)
	return pts


# --- Simulation ------------------------------------------------------------

func start() -> void:
	started = true


## Advances one tick. held is whether the jump button is down right now.
## Returns events for sound and effects: {type: "jump" | "land" | "edge" |
## "combo_lost" | "parcel" | "crumble" | "die", ...}.
func step(held: bool) -> Array:
	var ev: Array = []
	_update_roofs(ev)
	if not alive:
		vy = minf(vy + GRAVITY * DT, MAX_FALL)
		y += vy * DT
		x += dead_vx * DT
		dead_vx *= 0.97
		return ev
	if not started:
		return ev
	t += DT
	var pressed := held and not was_held
	was_held = held
	buffer_t = 0.0 if pressed else buffer_t + DT

	if buffer_t <= BUFFER and (grounded or (air_t <= COYOTE and not jumped)):
		vy = JUMP_V
		grounded = false
		ground = {}
		jumped = true
		hold_t = 0.0
		hold_jump = true
		buffer_t = 99.0
		ev.append({"type": "jump"})

	if hold_jump and (not held or vy >= 0.0 or hold_t >= HOLD_MAX):
		hold_jump = false
	var g := GRAVITY
	if hold_jump:
		g *= HOLD_GRAVITY
		hold_t += DT

	var px := x
	var py := y
	x += speed() * DT
	if grounded:
		var s := _support_at(ground)
		if s:
			y = _top_of(ground)
		else:
			grounded = false
			ground = {}
			air_t = 0.0
			vy = 0.0
	if not grounded:
		air_t += DT
		vy = minf(vy + g * DT, MAX_FALL)
		y += vy * DT
		if vy >= 0.0:
			_try_land(py, ev)

	_collide(px, ev)
	_collect(ev)
	if alive and y > ref_y + 420.0:
		_die("fall", ev)
	_ensure_generated()
	return ev


func _support_at(s: Dictionary) -> bool:
	return x + HALF_W > s.x0 + 2.0 and x - HALF_W < s.x1 - 2.0


func _top_of(s: Dictionary) -> float:
	return s.y if s.has("id") else s.y0


func _try_land(py: float, ev: Array) -> void:
	var best := {}
	var best_top := INF
	for s in roofs + obstacles:
		if s.has("kind") and s.kind != "ac":
			continue
		var top := _top_of(s)
		if _support_at(s) and py <= top + 0.5 and y >= top and top < best_top:
			best = s
			best_top = top
	if best.is_empty():
		return
	var impact := vy
	y = best_top
	vy = 0.0
	grounded = true
	ground = best
	jumped = false
	air_t = 0.0
	ev.append({"type": "land", "impact": impact})
	if best.has("id"):
		ref_y = best.y
		if best.crumble and best.t < 0.0:
			best.t = 0.0
			ev.append({"type": "crumble"})
		if best.id != last_roof:
			last_roof = best.id
			var off: float = x - best.x0
			if off <= EDGE_ZONE:
				combo = mini(combo + 1, MAX_MULT - 1)
				bonus += EDGE_POINTS * multiplier()
				ev.append({"type": "edge", "mult": multiplier(), "x": best.x0, "y": best.y})
			elif combo > 0:
				combo = 0
				ev.append({"type": "combo_lost"})


func _collide(px: float, ev: Array) -> void:
	var body := Rect2(x - HALF_W, y - HEIGHT, HALF_W * 2.0, HEIGHT)
	for r in roofs:
		if r.x1 < body.position.x or r.x0 > body.end.x:
			continue
		if body.intersects(Rect2(r.x0, r.y + 8.0, r.x1 - r.x0, 4000.0)):
			_die("wall", ev)
			return
	for o in obstacles:
		var top: float = o.y0 + (6.0 if o.kind == "ac" else 0.0)
		if body.intersects(Rect2(o.x0, top, o.x1 - o.x0, o.y1 - top)):
			if not (grounded and ground == o):
				_die(o.kind, ev)
				return
	for w in wires:
		if w.bx < body.position.x or w.ax > body.end.x:
			continue
		for p in wire_points(w, 40):
			if body.grow(-2.0).has_point(p):
				_die("wire", ev)
				return


func _collect(ev: Array) -> void:
	var c := Vector2(x, y - HEIGHT * 0.5)
	for p in parcels:
		if not p.taken and c.distance_to(Vector2(p.x, p.y)) < PARCEL_R + 20.0:
			p.taken = true
			parcels_taken += 1
			var pts := PARCEL_POINTS * multiplier()
			bonus += pts
			ev.append({"type": "parcel", "x": p.x, "y": p.y, "points": pts})


func _die(reason: String, ev: Array) -> void:
	alive = false
	death = reason
	grounded = false
	if reason == "fall":
		dead_vx = speed() * 0.6
	else:
		dead_vx = -speed() * 0.25
		vy = -500.0
	ev.append({"type": "die", "reason": reason})


func _update_roofs(ev: Array) -> void:
	for r in roofs:
		if r.t < 0.0:
			continue
		r.t += DT
		if r.t > CRUMBLE_DELAY:
			if r.vy == 0.0:
				ev.append({"type": "collapse", "x": (r.x0 + r.x1) * 0.5, "y": r.y})
			r.vy = minf(r.vy + GRAVITY * 0.45 * DT, MAX_FALL)
			r.y += r.vy * DT
			if grounded and ground == r:
				y = r.y


# --- City generation -------------------------------------------------------

func _add_roof(x0: float, x1: float, base: float, crumble: bool) -> Dictionary:
	var r := {"id": next_id, "x0": snappedf(x0, 4.0), "x1": snappedf(x1, 4.0), "y": base,
		"base": base, "crumble": crumble, "t": -1.0, "vy": 0.0}
	next_id += 1
	roofs.append(r)
	return r


func _ensure_generated() -> void:
	while roofs.back().x1 < x + AHEAD:
		_gen_roof()
	var cut := x - BEHIND
	if roofs[0].x1 > cut:
		return
	roofs = roofs.filter(func(r): return r.x1 > cut or r == ground)
	obstacles = obstacles.filter(func(o): return o.x1 > cut)
	wires = wires.filter(func(w): return w.bx > cut)
	parcels = parcels.filter(func(p): return p.x > cut)


func _gen_roof() -> void:
	var prev: Dictionary = roofs.back()
	var d := difficulty_at(prev.x1)
	var m: float = (prev.x1 - start_x) / PX_PER_M
	var v := speed_at(prev.x1)

	# Height of the next roof: up to ~140 px higher or ~200 px lower,
	# pulled back toward the middle so the city doesn't drift away.
	var dy := rng.randf_range(-100.0 - 40.0 * d, 140.0 + 60.0 * d)
	if prev.base + dy < -520.0:
		dy = absf(dy)
	elif prev.base + dy > 520.0:
		dy = -absf(dy)
	if m < 60.0:
		dy *= 0.4
	dy = snappedf(dy, 8.0)

	var launch: float = prev.x1
	if prev.crumble:
		launch = prev.x0 + v * (CRUMBLE_DELAY + 0.1)
	var hold_reach := reach(v, dy, true)
	var tap_reach := reach(v, dy, false)
	var frac := rng.randf_range(0.3, lerpf(0.62, 0.86, d))
	if rng.randf() < 0.2:
		frac = rng.randf_range(0.12, 0.3)  # short hops keep the rhythm varied
	var x0 := maxf(launch + (hold_reach - 12.0) * frac, prev.x1 + 40.0)
	var gap: float = x0 - prev.x1

	var crumble: bool = m > 300.0 and not prev.crumble and rng.randf() < lerpf(0.06, 0.22, d)
	var length := v * rng.randf_range(lerpf(1.6, 1.0, d), lerpf(3.0, 2.2, d))
	if crumble:
		length = v * rng.randf_range(0.6, 0.75)
	var r := _add_roof(x0, x0 + length, prev.base + dy, crumble)

	# A wire across the gap: only where a short tap clears the gap easily.
	var wired := false
	if m > 150.0 and not prev.crumble and absf(dy) <= 64.0 and gap <= tap_reach * 0.7 \
			and gap >= 90.0 and rng.randf() < lerpf(0.12, 0.35, d):
		wires.append({"ax": prev.x1 - 8.0, "ay": prev.y - WIRE_HIGH,
			"bx": r.x0 + 8.0, "by": r.y - WIRE_HIGH})
		wired = true

	# A parcel at the top of a held jump over the gap.
	if not wired and not prev.crumble and m > 20.0 and rng.randf() < 0.35:
		var a := apex(true)
		var t_up := 0.36
		parcels.append({"x": launch + v * t_up, "y": prev.y - a * 0.8 - HEIGHT * 0.5, "taken": false})

	if crumble:
		return
	_gen_obstacles(r, v, m, d)


func _gen_obstacles(r: Dictionary, v: float, m: float, d: float) -> void:
	var flat_tap := reach(v, 0.0, false)
	var flat_hold := reach(v, 0.0, true)
	var cursor: float = r.x0 + v * 0.65
	var placed := false
	while m > 100.0 and rng.randf() < lerpf(0.4, 0.8, d):
		var antenna := m > 350.0 and rng.randf() < 0.45
		var size := ANTENNA_SIZE if antenna else AC_SIZE
		# A jump from right before it must land back on this roof.
		var room: float = r.x1 - (flat_hold * 0.85 if antenna else flat_tap * 0.95) - size.x - cursor
		if room < 0.0:
			break
		var ox := snappedf(cursor + rng.randf() * minf(room, v * 0.8), 4.0)
		var o := {"kind": "antenna" if antenna else "ac", "x0": ox, "x1": ox + size.x,
			"y0": r.y - size.y, "y1": r.y, "roof": r.id}
		obstacles.append(o)
		placed = true
		if antenna and rng.randf() < 0.5:
			parcels.append({"x": ox + size.x * 0.5, "y": r.y - size.y - 40.0, "taken": false})
		cursor = ox + size.x + maxf(flat_tap, flat_hold * 0.8) + v * 0.35
	if not placed and m > 10.0 and rng.randf() < 0.3:
		var px: float = r.x0 + v * 0.5
		for i in 3:
			if px + i * 64.0 < r.x1 - 40.0:
				parcels.append({"x": px + i * 64.0, "y": r.y - 44.0, "taken": false})


# --- Copies for the test bot ----------------------------------------------

func clone() -> World:
	var w := World.new(1, false)
	w.rng.seed = rng.seed
	w.rng.state = rng.state
	w.roofs = roofs.duplicate(true)
	w.obstacles = obstacles.duplicate(true)
	w.wires = wires.duplicate(true)
	w.parcels = parcels.duplicate(true)
	w.ground = {}
	for s in w.roofs + w.obstacles:
		if not ground.is_empty() and s.x0 == ground.x0 and s.get("id", -2) == ground.get("id", -2) \
				and s.get("kind", "") == ground.get("kind", ""):
			w.ground = s
	for k in ["next_id", "x", "y", "vy", "grounded", "air_t", "jumped", "buffer_t", "hold_t",
			"hold_jump", "was_held", "alive", "death", "dead_vx", "started", "t", "start_x",
			"bonus", "combo", "parcels_taken", "last_roof", "ref_y"]:
		w.set(k, get(k))
	return w
