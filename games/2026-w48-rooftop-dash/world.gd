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
const COYOTE := 0.10       # a jump still works this long after running off an edge
const BUFFER := 0.15       # a press this early before landing still jumps
const HALF_W := 22.0
const HEIGHT := 96.0  # matches the courier sprite at 2x, cap to shoes
const SPEED_START := 400.0
const SPEED_MAX := 800.0
const SPEED_RAMP := 30000.0  # px; by here the speed is 63% of the way to max
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
const WIRE_HIGH := 370.0
const WIRE_SAG := 30.0
## Live wires low over AC units: above a tapped jump's head (158 + 96 px),
## below a held one's (281 + 96 px), even where the wire sags.
const LIVE_HIGH := 340.0
const LIVE_REACH := 150.0     # how far the wire runs past the unit each side
const LIVE_FROM_M := 400.0
const AC_SIZE := Vector2(78, 62)   # the art at 2x
const ANTENNA_SIZE := Vector2(12, 150)  # the pole; the art is drawn around it
# --- Puzzle points ---------------------------------------------------------
## A bat hovers over a gap too wide for any jump. Jump into it and it carries
## you across. Two big (but jumpable) gaps come first, so the third looks like
## more of the same.
const BAT_GRAB := Vector2(70, 56)
const BAT_HIGH := 200.0       # bat centre above the roof
const BAT_GAP_X := 1.4        # the gap, in hold-jump reaches (plus 60 px)
## Laundry hangs in front of a wall too tall to jump, over a steam vent.
## Jump into it and the sheet catches the steam like a parachute.
const WALL_RISE := 340.0      # the wall, above the roof in front of it
const LAUNDRY_LINE := 200.0   # the line, above the roof
const LAUNDRY_LOW := 126.0    # the bottom of the clothes, above the roof
const STEAM_SLOW := 0.6       # forward speed while rising in the steam
const PUZZLE_POINTS := 50     # for finding the trick
## Awning: a building far too tall to jump, with a shop awning on its wall
## below the roof you are on. Drop onto it and it bounces you up.
const AWNING_DROP := 110.0    # the awning, below the roof in front of it
const AWNING_W := 200.0
## Zipline: a handle at jump height by the roof's edge, on a cable down to a
## lower roof too far to reach.
const ZIP_DROP := 240.0
const ZIP_DROP_MIN := 160.0   # less where the city is already low
const ZIP_GRIP := 190.0       # the handle, above the roof
const ZIP_SLOW := 1.3         # it rides faster than you run
## Cradle: a window-washer's cradle hanging deep in the gap in front of a
## tall building. Land in it and it lifts you to the top.
const CRADLE_DROP := 150.0
const CRADLE_W := 140.0
const CRADLE_RISE := 300.0    # the tall building, above the roof you left
## Crane: a hook over a huge gap. It swings you down and up towards a higher
## roof; tap to let go on the way up, or you swing into the wall.
const CRANE_HIGH := 200.0     # the hook, above the roof
const CRANE_UP := 120.0       # the far roof, above the near one
const CRANE_DIP := 300.0      # how far the swing dips
const CRANE_KICK := -600.0    # the push you get when you let go
const CRANE_HANG := 130.0     # feet below the hook while hanging
const CRANE_WINDOW := 9       # ticks you can let go on and still make it
## Through the flat: a tall building with one open window in its wall.
const SILL_RISE := 200.0      # the window sill, above the roof in front of it
const ROOM_H := 320.0         # floor to ceiling inside the flat
const FLAT_TOP := 170.0       # building above the flat's ceiling
const WINDOW_T := 0.14        # seconds of launch you get to hit the window
const FURNITURE_SIZE := Vector2(96, 60)

## Balcony steps: narrow balconies stepping down a building's face, each
## with wet laundry hanging from the balcony above, low enough that a held
## jump hits it.
const BALC_N := 4
const BALC_STEP := 70.0       # each balcony, below the one before
const BALC_W := 0.5           # balcony width, in seconds of running
const RACK_LOW := 315.0       # bottom of the laundry above, over the balcony floor
const RACK_TOP := 395.0       # the balcony slab above, over the floor

## A billboard on a pole in a gap too wide to jump: you can stand on it
## only while its lights are on.
const BOARD_PERIOD := 1.5
const BOARD_ON := 0.95
const BOARD_LATE := 0.4       # it lights up as you pass this far along it
const BOARD_W := 0.55         # seconds of running
const BOARD_UP := 40.0        # its top, above the roof in front of it

## Which puzzle points can show up from which distance (metres).
const PIECES := {"bat": 230.0, "awning": 330.0, "laundry": 450.0, "zipline": 550.0,
	"cradle": 700.0, "crane": 850.0, "window": 950.0, "balcony": 1050.0, "billboard": 1150.0}

var rng := RandomNumberGenerator.new()
## {id, x0, x1, y, base, crumble, t, vy}. t is -1 until a crumbling roof is touched.
var roofs: Array = []
## {kind ("ac", "antenna", "skylight", "bat" or "laundry"), x0, x1, y0, y1, roof}.
## Bats and laundry are puzzle points: "grab" is true, and tx, ty say where
## they carry the courier.
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
var death_x := 0.0
var started := false
var t := 0.0

var start_x := 0.0
var bonus := 0
var combo := 0            # edge landings in a row; the multiplier is combo + 1
var parcels_taken := 0
var best_mult := 1        # the highest multiplier reached this run
var last_roof := -1
var ref_y := 0.0          # top of the last roof stood on, for falling out
## While a puzzle point carries the courier: {kind, x0, y0, x1, y1, rise_x, arc, slow, tap}.
## With tap, a press lets go (the crane).
var carry := {}
var carries := 0          # puzzle points solved this run
var next_piece_m := 230.0 # no puzzle point before this distance
var no_grab: Array = []   # tests turn kinds off here to prove the tricks are needed
var pieces_seen: Array = []  # puzzle kinds met so far this run, so new ones come first
var last_piece := ""


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


## Advances one tick. held is whether the jump button is down right now;
## tapped is true if a new press came in since the last tick, so a second
## thumb, or a tap shorter than a tick, still jumps.
## Returns events for sound and effects: {type: "jump" | "land" | "edge" |
## "combo_lost" | "parcel" | "crumble" | "die", ...}.
func step(held: bool, tapped := false) -> Array:
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
	var pressed := tapped or (held and not was_held)
	was_held = held
	buffer_t = 0.0 if pressed else buffer_t + DT

	if not carry.is_empty():
		buffer_t = 99.0
		if pressed and carry.get("tap", false):
			_release(ev, carry_vy() + CRANE_KICK)
			ev.append({"type": "jump"})
		else:
			_step_carry(ev)
		_collect(ev)
		_ensure_generated()
		return ev

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


## Moves along the bat's or the steam's path; no gravity, no collisions.
func _step_carry(ev: Array) -> void:
	x += speed() * DT * carry.slow
	var k := clampf((x - carry.x0) / (carry.rise_x - carry.x0), 0.0, 1.0)
	var arc: float = carry.arc * sin(PI * clampf((x - carry.x0) / (carry.x1 - carry.x0), 0.0, 1.0))
	var ny: float = lerpf(carry.y0, carry.y1, smoothstep(0.0, 1.0, k)) - arc
	vy = (ny - y) / DT
	y = ny
	if x >= carry.x1:
		_release(ev, 0.0)


## Lets go of the bat, the handle, the hook... and flies on from here.
func _release(ev: Array, new_vy: float) -> void:
	ev.append({"type": "release", "kind": carry.kind})
	carry = {}
	vy = new_vy
	air_t = 0.0
	jumped = true
	hold_jump = false
	ref_y = maxf(ref_y, y)


## The carry's vertical speed this tick, for letting go mid-swing.
func carry_vy() -> float:
	return vy


func _start_carry(o: Dictionary, ev: Array) -> void:
	o.used = true
	carries += 1
	var pts := PUZZLE_POINTS * multiplier()
	bonus += pts
	if o.has("snap_y"):
		y = o.snap_y   # hanging from the hook, whatever height you caught it at
	carry = {"kind": o.kind, "x0": x, "y0": y, "x1": o.tx, "y1": o.ty,
		"rise_x": maxf(o.rise_x, x + 30.0), "arc": o.arc, "slow": o.slow, "tap": o.get("tap", false)}
	grounded = false
	ground = {}
	hold_jump = false
	ev.append({"type": "grab", "kind": o.kind, "points": pts})


func _support_at(s: Dictionary) -> bool:
	if s.get("kind", "") == "billboard" and not board_lit(s):
		return false
	return x + HALF_W > s.x0 + 2.0 and x - HALF_W < s.x1 - 2.0


## True while the billboard's lights are on (tests can keep them off).
func board_lit(o: Dictionary) -> bool:
	return not "billboard" in no_grab and fmod(t + o.phase, BOARD_PERIOD) < BOARD_ON


## Seconds until the billboard's lights next change, for drawing its warning.
func board_left(o: Dictionary) -> float:
	var k := fmod(t + o.phase, BOARD_PERIOD)
	return BOARD_ON - k if k < BOARD_ON else BOARD_PERIOD - k


func _top_of(s: Dictionary) -> float:
	return s.y if s.has("id") else s.y0


func _try_land(py: float, ev: Array) -> void:
	# Awnings and cradles catch you from above and start their ride.
	for o in obstacles:
		if o.get("pad", false) and not o.used and not o.kind in no_grab \
				and x > o.x0 and x < o.x1 and py <= o.y0 + 0.5 and y >= o.y0:
			y = o.y0
			_start_carry(o, ev)
			return
	var best := {}
	var best_top := INF
	for s in roofs + obstacles:
		if s.has("kind") and not s.kind in ["ac", "furniture", "billboard"]:
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
	if best.get("inside", false):
		_enter_flat(best, ev)
	if best.get("kind", "") == "billboard" and not best.used:
		best.used = true
		carries += 1
		var pts := PUZZLE_POINTS * multiplier()
		bonus += pts
		ev.append({"type": "grab", "kind": "billboard", "points": pts})
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
				best_mult = maxi(best_mult, multiplier())
				ev.append({"type": "edge", "mult": multiplier(), "x": best.x0, "y": best.y})
			elif combo > 0:
				combo = 0
				ev.append({"type": "combo_lost"})


## Landing on the flat's floor for the first time: the window trick is done.
func _enter_flat(f: Dictionary, ev: Array) -> void:
	for o in obstacles:
		if o.kind == "window" and o.roof == f.id and not o.used:
			o.used = true
			carries += 1
			var pts := PUZZLE_POINTS * multiplier()
			bonus += pts
			ev.append({"type": "grab", "kind": "window", "points": pts})


func _collide(px: float, ev: Array) -> void:
	var body := Rect2(x - HALF_W, y - HEIGHT, HALF_W * 2.0, HEIGHT)
	for r in roofs:
		if r.x1 < body.position.x or r.x0 > body.end.x:
			continue
		# A building with a flat cut through it is solid only down to the
		# flat's ceiling; the flat's floor is a roof of its own.
		var depth: float = r.hole_top - r.y - 8.0 if r.has("hole_top") else 4000.0
		if body.intersects(Rect2(r.x0, r.y + 8.0, r.x1 - r.x0, depth)):
			_die("ceiling" if r.has("hole_top") and body.position.y > r.hole_top - 40.0 else "wall", ev)
			return
	for o in obstacles:
		if o.get("grab", false):
			if o.get("pad", false):
				continue
			if not o.kind in no_grab and not grounded and not o.used and body.intersects(Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0)):
				_start_carry(o, ev)
				return
			continue
		if o.kind == "billboard":
			continue  # you pass through it when you don't land on it
		if o.kind == "window":
			# Shut (only in tests), the window is just more wall.
			if o.kind in no_grab and body.intersects(Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0)):
				_die("wall", ev)
				return
			continue
		if o.kind == "skylight":
			# Glass in the roof: running onto it (feet over the pane) breaks it.
			if grounded and ground.get("id", -1) == o.roof and x > o.x0 + 6.0 and x < o.x1 - 6.0:
				_die("skylight", ev)
				return
			continue
		var top: float = o.y0 + (6.0 if o.kind in ["ac", "furniture"] else 0.0)
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


## Brings the courier back after a death, at the start of the next safe
## roof past where it happened, standing still on it, and running on.
## Score, parcels and the multiplier carry on.
func revive() -> void:
	var r := {}
	for c in roofs:
		if c.x0 > death_x and not c.crumble and c.t < 0.0 and c.x1 - c.x0 > 120.0 \
				and not c.has("hole_top"):
			r = c
			break
	if r.is_empty():
		return
	x = r.x0 + 16.0
	y = _top_of(r)
	vy = 0.0
	grounded = true
	ground = r
	air_t = 0.0
	jumped = false
	buffer_t = 99.0
	hold_t = 0.0
	hold_jump = false
	was_held = true
	alive = true
	death = ""
	dead_vx = 0.0
	carry = {}
	ref_y = y
	last_roof = r.id
	_ensure_generated()


func _die(reason: String, ev: Array) -> void:
	death_x = x
	alive = false
	death = reason
	grounded = false
	if reason == "fall":
		dead_vx = speed() * 0.6
	elif reason == "skylight":
		dead_vx = speed() * 0.15  # straight down through the glass
		vy = 0.0
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

	if not prev.crumble and m > next_piece_m and rng.randf() < 0.5:
		var kind := _pick_piece(m, prev.base)
		match kind:
			"bat": _gen_bat(prev, v)
			"laundry": _gen_steam(prev, v)
			"awning": _gen_awning(prev, v)
			"zipline": _gen_zipline(prev, v)
			"cradle": _gen_cradle(prev, v)
			"crane": _gen_crane(prev, v)
			"window": _gen_window(prev, v)
			"balcony": _gen_balconies(prev, v)
			"billboard": _gen_billboard(prev, v)
		last_piece = kind
		if not kind in pieces_seen:
			pieces_seen.append(kind)
		next_piece_m = m + rng.randf_range(280.0, 480.0)
		return

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
	# Every roof from 60 m gets something to deal with; the chance of one
	# more after it grows with difficulty, so long roofs are never empty.
	while m > 60.0 and (not placed or rng.randf() < lerpf(0.65, 0.9, d)):
		var kind := _pick_kind(m)
		var size: Vector2 = {"ac": AC_SIZE, "antenna": ANTENNA_SIZE}.get(kind, Vector2.ZERO)
		if kind == "skylight":
			size = Vector2(snappedf(rng.randf_range(0.3, lerpf(0.45, 0.6, d)) * flat_tap, 8.0), 8.0)
		# A jump from right before it must land back on this roof.
		var room: float = r.x1 - (flat_hold * 0.85 if kind == "antenna" else flat_tap * 0.95) - size.x - cursor
		if room < 0.0:
			break
		var ox := snappedf(cursor + rng.randf() * minf(room, v * 0.5), 4.0)
		obstacles.append({"kind": kind, "x0": ox, "x1": ox + size.x, "y0": r.y - size.y, "y1": r.y, "roof": r.id})
		placed = true
		# A live wire strung low over an AC unit: a short tap clears both, a
		# held jump runs the head into the wire.
		if kind == "ac" and m > LIVE_FROM_M and rng.randf() < lerpf(0.3, 0.55, d):
			var ax := maxf(r.x0 + 24.0, ox - LIVE_REACH)
			var bx := minf(r.x1 - 24.0, ox + size.x + LIVE_REACH)
			wires.append({"ax": ax, "ay": r.y - LIVE_HIGH, "bx": bx, "by": r.y - LIVE_HIGH, "h": LIVE_HIGH, "live": true})
		if kind == "antenna" and rng.randf() < 0.5:
			parcels.append({"x": ox + size.x * 0.5, "y": r.y - size.y - 40.0, "taken": false})
		cursor = ox + size.x + maxf(flat_tap, flat_hold * 0.8) + v * 0.35
	if not placed and m > 10.0 and rng.randf() < 0.3:
		var px: float = r.x0 + v * 0.5
		for i in 3:
			if px + i * 64.0 < r.x1 - 40.0:
				parcels.append({"x": px + i * 64.0, "y": r.y - 44.0, "taken": false})


## Which obstacle comes next. New kinds join as the run goes on.
func _pick_kind(m: float) -> String:
	var kinds := {"ac": 3.0}
	if m > 150.0:
		kinds["skylight"] = 2.0
	if m > 350.0:
		kinds["antenna"] = 1.6
	var total := 0.0
	for k in kinds:
		total += kinds[k]
	var pick := rng.randf() * total
	for k in kinds:
		pick -= kinds[k]
		if pick <= 0.0:
			return k
	return "ac"


# --- Puzzle points ---------------------------------------------------------

## Two big gaps that a full hold just clears, then one that nothing clears,
## with a bat hovering over its near side. Parcels trail along the bat's path.
func _gen_bat(prev: Dictionary, v: float) -> void:
	var r := prev
	for i in 2:
		var gap := (reach(v, 0.0, true) - 12.0) * rng.randf_range(0.84, 0.9)
		var x0: float = r.x1 + gap
		r = _add_roof(x0, x0 + v * rng.randf_range(1.0, 1.3), r.base, false)
	var far: float = r.x1 + reach(v, 40.0, true) * BAT_GAP_X + 60.0
	var land := _add_roof(far, far + v * 2.2, r.base + 40.0, false)
	var bx: float = r.x1 + v * 0.25
	var by: float = r.y - BAT_HIGH
	var tx: float = land.x0 + 110.0
	var ty: float = land.y - 30.0
	obstacles.append({"kind": "bat", "grab": true, "used": false, "roof": r.id,
		"x0": bx - BAT_GRAB.x * 0.5, "x1": bx + BAT_GRAB.x * 0.5,
		"y0": by - BAT_GRAB.y * 0.5, "y1": by + BAT_GRAB.y * 0.5,
		"tx": tx, "ty": ty, "rise_x": tx, "arc": 70.0, "slow": 1.0})
	for k in [0.35, 0.55, 0.75]:
		var px := lerpf(bx, tx, k)
		parcels.append({"x": px, "y": lerpf(by + 40.0, ty - 50.0, k) - 70.0 * sin(PI * k), "taken": false})


## A plain roof that ends at a wall too tall to jump. Laundry hangs in front
## of it over a steam vent: jump into the laundry and the steam lifts you up.
func _gen_steam(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	var a := _add_roof(x0, x0 + v * 2.6, prev.base, false)
	var b := _add_roof(a.x1, a.x1 + v * 2.2, a.base - WALL_RISE, false)
	obstacles.append({"kind": "laundry", "grab": true, "used": false, "roof": a.id,
		"x0": a.x1 - v * 0.95, "x1": a.x1 - v * 0.5,
		"y0": a.y - LAUNDRY_LINE, "y1": a.y - LAUNDRY_LOW,
		"tx": b.x0 + 120.0, "ty": b.y - 30.0, "rise_x": b.x0 - 16.0, "arc": 0.0, "slow": STEAM_SLOW,
		"vent": a.x1 - v * 0.72 + 16.0})  # under the laundry, so the lift starts where the steam is


## The next puzzle point: one not met yet if any has just unlocked, else
## any but the last one. Some need room above or below to fit the city.
func _pick_piece(m: float, base: float) -> String:
	var ok: Array = []
	for k in PIECES:
		if m < PIECES[k]:
			continue
		var rise: float = {"laundry": WALL_RISE, "awning": WALL_RISE, "cradle": CRADLE_RISE,
			"crane": CRANE_UP, "window": SILL_RISE, "billboard": BOARD_UP}.get(k, 0.0)
		var drop: float = {"zipline": ZIP_DROP_MIN, "bat": 40.0,
			"balcony": BALC_STEP * BALC_N - 96.0}.get(k, 0.0)
		if base - rise < -520.0 or base + drop > 520.0:
			continue
		ok.append(k)
	if ok.is_empty():
		return "bat"
	var fresh := ok.filter(func(k): return not k in pieces_seen)
	if not fresh.is_empty():
		return fresh[0]
	if ok.size() > 1:
		ok.erase(last_piece)
	return ok[rng.randi() % ok.size()]


## A roof ending at a wall far too tall to jump; an awning sticks out of the
## wall below the roof's level. Drop off the edge onto it and it bounces you up.
func _gen_awning(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	var a := _add_roof(x0, x0 + v * 2.0, prev.base, false)
	var bx0: float = a.x1 + AWNING_W + 60.0
	var b := _add_roof(bx0, bx0 + v * 2.2, a.base - WALL_RISE, false)
	obstacles.append({"kind": "awning", "grab": true, "pad": true, "used": false, "roof": b.id,
		"x0": b.x0 - AWNING_W, "x1": b.x0, "y0": a.y + AWNING_DROP, "y1": a.y + AWNING_DROP + 24.0,
		"tx": b.x0 + 120.0, "ty": b.y - 30.0, "rise_x": b.x0 - 12.0, "arc": 0.0, "slow": 0.35})
	parcels.append({"x": b.x0 + 40.0, "y": b.y - 80.0, "taken": false})


## A handle at jump height by the edge of a roof, on a cable down to a much
## lower roof too far away to jump to.
func _gen_zipline(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	var a := _add_roof(x0, x0 + v * 2.2, prev.base, false)
	var drop := minf(ZIP_DROP, 520.0 - a.base)
	var far: float = a.x1 + reach(v, drop, true) * 1.35 + 80.0
	var land := _add_roof(far, far + v * 2.4, a.base + drop, false)
	var hx: float = a.x1 - v * 0.15
	var hy: float = a.y - ZIP_GRIP
	var tx: float = land.x0 + 170.0
	var ty: float = land.y - 24.0
	obstacles.append({"kind": "zipline", "grab": true, "used": false, "roof": a.id,
		"x0": hx - 30.0, "x1": hx + 30.0, "y0": hy - 28.0, "y1": hy + 28.0,
		"tx": tx, "ty": ty, "rise_x": tx, "arc": -30.0, "slow": ZIP_SLOW,
		# The cable, from the top of a pole on this roof to one on the far roof.
		"ax": hx - 60.0, "ay": hy - 56.0, "bx": tx + 80.0, "by": ty - 150.0, "a_roof": a.y, "b_roof": land.y})
	for k in [0.3, 0.5, 0.7]:
		parcels.append({"x": lerpf(hx, tx, k), "y": lerpf(hy + 60.0, ty - 60.0, k), "taken": false})


## A tall building with a window-washer's cradle hanging deep in the gap in
## front of it. Hop down into the cradle and it winches you up to the top.
func _gen_cradle(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	var a := _add_roof(x0, x0 + v * 2.0, prev.base, false)
	var bx0: float = a.x1 + 220.0 + CRADLE_W
	var b := _add_roof(bx0, bx0 + v * 2.2, a.base - CRADLE_RISE, false)
	obstacles.append({"kind": "cradle", "grab": true, "pad": true, "used": false, "roof": b.id,
		"x0": b.x0 - CRADLE_W - 10.0, "x1": b.x0 - 10.0, "y0": a.y + CRADLE_DROP, "y1": a.y + CRADLE_DROP + 40.0,
		"tx": b.x0 + 120.0, "ty": b.y - 30.0, "rise_x": b.x0 - 14.0, "arc": 0.0, "slow": 0.08, "top": b.y})


## A crane hook over a gap far too wide, with the far roof higher up. The
## hook swings you down and up; let go on the way up to reach the roof.
func _gen_crane(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	var a := _add_roof(x0, x0 + v * 2.2, prev.base, false)
	var hx: float = a.x1 + v * 0.2
	var hy: float = a.y - CRANE_HIGH
	var feet := hy + CRANE_HANG
	var fy: float = a.y - CRANE_UP
	# The widest gap that still leaves a fair moment to let go.
	var span := v * 2.0
	while span > v * 1.2 and crane_window(hx, feet, hx + span, fy, v) < CRANE_WINDOW:
		span -= 16.0
	var far: float = hx + span
	var f := _add_roof(far, far + v * 2.4, a.base - CRANE_UP, false)
	obstacles.append({"kind": "crane", "grab": true, "tap": true, "used": false, "roof": a.id,
		"x0": hx - 35.0, "x1": hx + 35.0, "y0": hy - 28.0, "y1": hy + 28.0, "snap_y": feet,
		"tx": f.x0 - 40.0, "ty": f.y + 60.0, "rise_x": f.x0 - 40.0, "arc": -CRANE_DIP, "slow": 1.0,
		"pivot_x": (hx + f.x0) * 0.5, "pivot_y": a.y - 440.0})


## A building too tall to jump, with a flat cut through it: one open window
## in the front wall, up where only a well-timed held jump reaches, across an
## alley you can fall into. Inside the ceiling is low (a held jump hits it)
## and the furniture is in the way, so you hop it with short taps. You run
## out through the back window onto a lower roof.
func _gen_window(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	var a := _add_roof(x0, x0 + v * 2.2, prev.base, false)
	# The alley: as wide as it can be while a held jump still meets the
	# window for WINDOW_T seconds of launch.
	var span := window_span(v, SILL_RISE - 8.0)
	var gap := snappedf(maxf(span.y - HALF_W - v * WINDOW_T, maxf(span.x - HALF_W, 60.0)), 4.0)
	var bx0: float = a.x1 + gap
	var sill: float = a.base - SILL_RISE
	var ceil_y := sill - ROOM_H
	var length := v * rng.randf_range(2.6, 3.0)
	var b := _add_roof(bx0, bx0 + length, ceil_y - FLAT_TOP, false)
	b.hole_top = ceil_y
	var f := _add_roof(bx0, b.x1, sill, false)
	f.inside = true
	f.ceil = ceil_y
	obstacles.append({"kind": "window", "used": false, "roof": f.id,
		"x0": bx0 - 4.0, "x1": bx0 + 12.0, "y0": ceil_y, "y1": sill})
	# Furniture: a first piece a little after you land, then one more if
	# there is room, each a tap apart.
	var tap := reach(v, 0.0, false)
	var cursor: float = bx0 + v * 0.75
	for i in 3:
		var room: float = f.x1 - tap * 0.95 - FURNITURE_SIZE.x - cursor
		if room < 0.0:
			break
		var ox := snappedf(cursor + rng.randf() * minf(room, v * 0.25), 4.0)
		obstacles.append({"kind": "furniture", "style": rng.randi() % 3, "roof": f.id,
			"x0": ox, "x1": ox + FURNITURE_SIZE.x, "y0": sill - FURNITURE_SIZE.y, "y1": sill})
		parcels.append({"x": ox + FURNITURE_SIZE.x * 0.5, "y": sill - FURNITURE_SIZE.y - 70.0, "taken": false})
		cursor = ox + FURNITURE_SIZE.x + tap + v * 0.3
	# Out the back and down onto a lower roof.
	var cx0: float = f.x1 + reach(v, 40.0, false) * 0.35
	_add_roof(cx0, cx0 + v * 2.2, sill + 40.0, false)


## While a full held jump at speed v has its feet at least h above the
## launch height: (first x, last x) after launch, in px.
static func window_span(v: float, h: float) -> Vector2:
	var yy := 0.0
	var vv := JUMP_V
	var ht := 0.0
	var xx := 0.0
	var first := -1.0
	for i in 400:
		var g := GRAVITY
		if vv < 0.0 and ht < HOLD_MAX:
			g *= HOLD_GRAVITY
			ht += DT
		vv = minf(vv + g * DT, MAX_FALL)
		yy += vv * DT
		xx += v * DT
		if -yy >= h and first < 0.0:
			first = xx
		if first >= 0.0 and -yy < h:
			return Vector2(first, xx - v * DT)
	return Vector2.ZERO


## Balconies stepping down the face of a building, too far apart to skip
## one and too narrow to land on carelessly. Wet laundry hangs from the
## balcony above each one, so only short taps work: a held jump runs your
## head into the washing. The last step is a roof again.
func _gen_balconies(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	# Up a little first if the city is already low, so the steps fit.
	var base: float = minf(prev.base, snappedf(520.0 - BALC_STEP * BALC_N, 8.0))
	var a := _add_roof(x0, x0 + v * 2.0, base, false)
	var tap := reach(v, BALC_STEP, false)
	# The gap: past the top of a tap (so you don't rise into the next
	# balcony's laundry) and short of where it comes down.
	var rise_x := v * (-JUMP_V / GRAVITY) + HALF_W * 2.0
	var last := a
	var first_x := 0.0
	for i in BALC_N:
		var gap := snappedf(maxf(tap * rng.randf_range(0.55, 0.7), rise_x), 4.0)
		var bx0: float = last.x1 + gap
		var b := _add_roof(bx0, bx0 + v * BALC_W, last.base + BALC_STEP, false)
		b.balcony = i
		if i == 0:
			first_x = bx0
		obstacles.append({"kind": "rack", "roof": b.id, "x0": b.x0, "x1": b.x1,
			"y0": b.y - RACK_TOP, "y1": b.y - RACK_LOW, "style": rng.randi() % 4})
		parcels.append({"x": bx0 - gap * 0.45, "y": last.y - 150.0, "taken": false})
		last = b
	# One building behind them all, drawn from the first balcony.
	for r in roofs:
		if r.get("balcony", -1) == 0 and r.x0 == first_x:
			r.wall_x0 = first_x - 30.0
			r.wall_x1 = last.x1 + 30.0
			r.wall_top = a.y - RACK_TOP - 60.0
	var cx0: float = last.x1 + snappedf(maxf(tap * 0.6, rise_x), 4.0)
	_add_roof(cx0, cx0 + v * 2.2, last.base, false)


## A gap far too wide to jump, with a billboard on a pole in the middle.
## Its lights blink on and off; only while they are on can you stand on it.
## Time the jump to land on it lit, then jump off before it goes dark.
func _gen_billboard(prev: Dictionary, v: float) -> void:
	var x0: float = prev.x1 + reach(v, 0.0, false) * 0.5
	var a := _add_roof(x0, x0 + v * 2.4, prev.base, false)
	var hold := reach(v, 0.0, true)
	var w := snappedf(v * BOARD_W, 4.0)
	var gap := snappedf(maxf(hold * 0.45, (hold * 1.4 - w) * 0.5), 4.0)
	var bx0: float = a.x1 + gap
	# You always run at the same speed, so the moment you pass any spot is
	# known now: the lights come on only as you pass BOARD_LATE of the way
	# along, so landing early drops you through the dark board.
	var on_t := time_at(bx0 + w * BOARD_LATE)
	obstacles.append({"kind": "billboard", "used": false, "roof": a.id,
		"x0": bx0, "x1": bx0 + w, "y0": a.y - BOARD_UP, "y1": a.y - BOARD_UP + 96.0,
		"phase": fposmod(-on_t, BOARD_PERIOD)})
	parcels.append({"x": bx0 + w * 0.5, "y": a.y - BOARD_UP - 60.0, "taken": false})
	var cx0: float = bx0 + w + gap
	_add_roof(cx0, cx0 + v * 2.2, a.base, false)


## When the courier, running on from here, reaches x.
func time_at(at: float) -> float:
	var tt := t
	var px := x
	while px < at:
		var dx := minf(50.0, at - px)
		tt += dx / speed_at(px + dx * 0.5)
		px += dx
	return tt


## How many ticks of the crane's swing you can let go on and still land on
## the far roof (top fy, front edge fx), swinging from (x0, y0) at speed v.
static func crane_window(x0: float, y0: float, fx: float, fy: float, v: float) -> int:
	var x1 := fx - 40.0
	var y1 := fy + 60.0
	var ok := 0
	var n := int((x1 - x0) / (v * DT))
	for k in n:
		# Ride k ticks, then let go.
		var px := x0 + v * DT * (k + 1)
		var py := _crane_y(px, x0, y0, x1, y1)
		var vv := (py - _crane_y(px - v * DT, x0, y0, x1, y1)) / DT + CRANE_KICK
		for i in 200:
			var oy := py
			vv = minf(vv + GRAVITY * DT, MAX_FALL)
			px += v * DT
			py += vv * DT
			if vv >= 0.0 and oy <= fy + 0.5 and py >= fy and px + HALF_W > fx + 2.0:
				ok += 1
				break
			if px + HALF_W > fx and py > fy + 8.0:
				break
			if py > fy + 600.0:
				break
	return ok


static func _crane_y(px: float, x0: float, y0: float, x1: float, y1: float) -> float:
	var k := clampf((px - x0) / (x1 - x0), 0.0, 1.0)
	return lerpf(y0, y1, smoothstep(0.0, 1.0, k)) + CRANE_DIP * sin(PI * k)


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
			"bonus", "combo", "best_mult", "parcels_taken", "last_roof", "ref_y",
			"carry", "carries", "next_piece_m", "no_grab", "pieces_seen", "last_piece"]:
		w.set(k, get(k))
	w.carry = carry.duplicate()
	w.pieces_seen = pieces_seen.duplicate()
	return w
