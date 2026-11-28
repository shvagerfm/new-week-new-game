class_name Game
extends Node2D
## One level: the tiers of a Christmas tree spin one after another and the elf
## throws ornaments at them. Draws itself (placeholder art, replaced by PNGs in
## art/ when they exist, see Art).

signal won(time: float, all_candies: bool)
signal failed(reason: String)
signal tier_finished(index: int)
signal changed  # HUD needs a refresh
signal popup(text: String, color: Color)
signal sound(name: String)

enum { READY, PLAYING, TRANSITION, FAILED, WON }

const SPEED := 3000.0  # ornament flight, px/s
const STICK := 64.0  # pin length from the rim to the ball
const BALL := 15.0
const COOLDOWN := 0.14
const HIT_ARC := deg_to_rad(13.0)  # candies and stars count within this
const ORNAMENT_COLORS := [Color("e8333a"), Color("f6c343"), Color("3d8bfd"), Color("d9dde8"),
	Color("a355e0"), Color("ff7ac8")]
const THEMES := {
	"forest": {"sky": [Color("0d1b2e"), Color("27466b")], "tier": [Color("1f5a36"), Color("2f7d4a"), Color("49a061")], "trim": Color("e9f1ff")},
	"gingerbread": {"sky": [Color("1d1430"), Color("5a3b5e")], "tier": [Color("1d5236"), Color("2c7247"), Color("3f8f58")], "trim": Color("c98b4d")},
	"ice": {"sky": [Color("0b2034"), Color("2b6c8a")], "tier": [Color("2c6c6a"), Color("3f8d88"), Color("8fd3d0")], "trim": Color("e6fbff")},
	"workshop": {"sky": [Color("2a1320"), Color("6b2c3a")], "tier": [Color("1e5a3a"), Color("2b7a4c"), Color("44985f")], "trim": Color("e84a4a")},
	"square": {"sky": [Color("08061a"), Color("2f2457")], "tier": [Color("174c33"), Color("226b45"), Color("38905c")], "trim": Color("ffd25e")},
}

var level: Dictionary
var state := READY
var tier_index := 0
var tier: Dictionary
var rotor: Rotor
var rot := 0.0  # radians, the tier's current angle
var left := 0  # ornaments still to throw on this tier
var hp_max := 0
var phase_index := 0
var stuck: Array = []  # {a: local angle, color}
var flying: Array = []  # {pos, color, fire}
var debris: Array = []  # {pos, vel, ang, spin, color, kind, life}
var sparks: Array = []  # {pos, vel, life, color, size}
var candies: Array = []  # local angles
var stars: Array = []
var candies_total := 0
var ice: Array = []  # [center, half width] radians
var elapsed := 0.0
var t := 0.0
var cooldown := 0.0
var throw_anim := 0.0
var shake := 0.0
var flash := 0.0
var slow_t := 0.0
var aim_t := 0.0
var shield := false
var fire_next := false
var used_boosters := {}
var continued := false
var fail_reason := ""
var transition_t := 0.0
var done_tiers: Array = []  # per finished tier: Array of ornament colors
var snow: Array = []
var center := Vector2.ZERO
var radius := 160.0
var time_scale := 1.0
var _end_timer := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 70:
		snow.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.4, 1.0)))


func start(index: int) -> void:
	level = Levels.get_level(index)
	tier_index = 0
	done_tiers = []
	elapsed = 0.0
	used_boosters = {}
	continued = false
	candies_total = 0
	_candies_hit = 0
	for tr in level.tiers:
		candies_total += tr.candies.size()
	debris.clear()
	sparks.clear()
	_begin_tier()
	state = PLAYING


func _begin_tier() -> void:
	tier = level.tiers[tier_index].duplicate(true)
	phase_index = 0
	left = tier.n
	hp_max = tier.n
	flying.clear()
	_apply_layout(tier)
	changed.emit()


## Sets rotation, hanging ornaments, ice and items from a tier or boss phase.
func _apply_layout(d: Dictionary) -> void:
	rotor = Rotor.new(d.rot)
	stuck.clear()
	for a in d.get("pre", []):
		stuck.append({"a": deg_to_rad(a), "color": _rand_color()})
	ice.clear()
	for p in d.get("ice", []):
		ice.append([deg_to_rad(p[0]), deg_to_rad(p[1]) * 0.5])
	if d.has("candies"):
		candies = d.candies.map(func(a): return deg_to_rad(a))
	if d.has("stars"):
		stars = d.stars.map(func(a): return deg_to_rad(a))
	tier["move"] = d.get("move", tier.get("move", 0.0))
	tier["pulse"] = d.get("pulse", tier.get("pulse", 0.0))


func is_boss_tier() -> bool:
	return tier.has("phases")


func _rand_color() -> Color:
	return ORNAMENT_COLORS[randi() % ORNAMENT_COLORS.size()]


# ------------------------------------------------------------------ geometry

func _layout(at_t: float) -> void:
	var vp := get_viewport_rect().size
	var base_r: float = tier.get("radius", 160.0)
	var top := 250.0
	var bottom := vp.y - 330.0
	var cy := clampf(lerpf(top, bottom, 0.42), top + base_r + 40.0, bottom - base_r - STICK - 60.0)
	center = Vector2(vp.x * 0.5 + sin(at_t * 1.25) * tier.get("move", 0.0), cy)
	radius = base_r * (1.0 + tier.get("pulse", 0.0) * sin(at_t * 2.2))


func elf_pos() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(vp.x * 0.5, vp.y - 175.0)


func spawn_pos() -> Vector2:
	return elf_pos() + Vector2(0, -120)


func _dir(local_a: float) -> Vector2:
	return Vector2.from_angle(local_a + rot)


## Does a flying ornament (pin tip, ball) touch a hanging one (rim point, ball)?
static func _hits(tip: Vector2, ball: Vector2, rim: Vector2, sb: Vector2) -> bool:
	return _seg_dist(tip, rim, sb) < 5.0 or tip.distance_to(sb) < BALL + 3.0 \
		or ball.distance_to(sb) < BALL * 2.0 - 4.0 or _seg_dist(sb, tip, ball) < BALL


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


static func _ang_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


# ------------------------------------------------------------------ input

func throw() -> void:
	if state != PLAYING or cooldown > 0.0 or left - flying.size() <= 0:
		return
	cooldown = COOLDOWN
	throw_anim = 1.0
	flying.append({"pos": spawn_pos(), "color": _rand_color(), "fire": fire_next})
	fire_next = false
	sound.emit("throw")
	changed.emit()


func use_booster(kind: String) -> bool:
	if state != PLAYING or used_boosters.has(kind):
		return false
	match kind:
		"slow":
			slow_t = 5.0
		"shield":
			if shield:
				return false
			shield = true
		"aim":
			aim_t = 8.0
		"magnet":
			if stuck.is_empty():
				return false
			_remove_near_bottom(3)
		"fire":
			if fire_next:
				return false
			fire_next = true
	used_boosters[kind] = true
	sound.emit("booster")
	changed.emit()
	return true


func _remove_near_bottom(count: int) -> void:
	var bottom := PI * 0.5 - rot
	stuck.sort_custom(func(x, y): return _ang_diff(x.a, bottom) < _ang_diff(y.a, bottom))
	for i in mini(count, stuck.size()):
		var s: Dictionary = stuck.pop_front()
		_knock_off(s)


func _knock_off(s: Dictionary) -> void:
	var d := _dir(s.a)
	debris.append({"pos": center + d * (radius + STICK * 0.5), "vel": d * 420.0 + Vector2(0, -200),
		"ang": d.angle(), "spin": randf_range(-12, 12), "color": s.color, "kind": "ornament", "life": 1.6})


## After a rewarded ad on the fail panel.
func continue_after_fail() -> void:
	continued = true
	if fail_reason == "stars":
		left += 3
	else:
		_remove_near_bottom(2)
	shield = true
	state = PLAYING
	changed.emit()


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	var dt := delta * time_scale
	t += dt
	_update_fx(dt)
	if state == READY:
		queue_redraw()
		return
	var spd := rotor.step(dt) if state != FAILED else rotor.speed * 0.3
	if slow_t > 0.0:
		spd *= 0.4
		slow_t -= dt
	if state == PLAYING:
		# Spin and flight move together in small steps, so fast tiers can't skip
		# an ornament past a hanging one between frames.
		var steps := 8
		var sdt := dt / steps
		for k in steps:
			_layout(t - dt + sdt * (k + 1))
			rot += deg_to_rad(spd) * sdt
			_update_flying(sdt)
	else:
		_layout(t)
		rot += deg_to_rad(spd) * dt
	aim_t = maxf(aim_t - dt, 0.0)
	cooldown -= dt
	throw_anim = maxf(throw_anim - dt * 5.0, 0.0)
	if state == PLAYING:
		elapsed += delta
		if left <= 0 and flying.is_empty():
			_tier_complete()
	elif state == TRANSITION:
		transition_t += dt
		if transition_t >= 0.85:
			tier_index += 1
			if tier_index >= level.tiers.size():
				_win()
			else:
				_begin_tier()
				state = PLAYING
	elif state == FAILED or state == WON:
		_end_timer -= delta
		if _end_timer <= 0.0 and _end_timer > -100.0:
			_end_timer = -1000.0
			time_scale = 1.0
			if state == FAILED:
				failed.emit(fail_reason)
			else:
				var all_c := candies_total == 0 or _candies_hit == candies_total
				won.emit(elapsed, all_c)
	queue_redraw()


var _candies_hit := 0


func _update_flying(dt: float) -> void:
	var i := 0
	while i < flying.size():
		var f: Dictionary = flying[i]
		f.pos.y -= SPEED * dt
		if _check(f) != "":
			flying.remove_at(i)
		else:
			i += 1


## Returns "" while still flying, otherwise what happened.
func _check(f: Dictionary) -> String:
	var tip: Vector2 = f.pos
	var ball: Vector2 = tip + Vector2(0, STICK)
	for j in range(stuck.size() - 1, -1, -1):
		var s: Dictionary = stuck[j]
		var d := _dir(s.a)
		var sb := center + d * (radius + STICK)
		if _hits(tip, ball, center + d * radius, sb):
			if f.fire:
				stuck.remove_at(j)
				_knock_off(s)
				_burst(sb, Color("ff9a3c"), 14)
				sound.emit("fire")
				continue
			if shield:
				shield = false
				_bounce(f)
				_burst(tip, Color("8fd8ff"), 12)
				popup.emit(Loc.t("shield"), Color("8fd8ff"))
				sound.emit("shield")
				changed.emit()
				return "shielded"
			_bounce(f)
			_fail("clash", tip)
			return "clash"
	if tip.distance_to(center) <= radius:
		var a := wrapf((tip - center).angle() - rot, -PI, PI)
		for p in ice:
			if _ang_diff(a, p[0]) < p[1]:
				if f.fire:
					ice.erase(p)
					_burst(tip, Color("c9f4ff"), 18)
					sound.emit("shatter")
					break
				if shield:
					shield = false
					_bounce(f)
					popup.emit(Loc.t("shield"), Color("8fd8ff"))
					sound.emit("shield")
					changed.emit()
					return "shielded"
				_burst(tip, Color("c9f4ff"), 20)
				_bounce(f)
				_fail("ice", tip)
				sound.emit("shatter")
				return "ice"
		_stick(f, a)
		return "stuck"
	return ""


func _stick(f: Dictionary, a: float) -> void:
	stuck.append({"a": a, "color": f.color})
	left -= 1
	shake = maxf(shake, 5.0)
	flash = 1.0
	var rim := center + _dir(a) * radius
	_burst(rim, Color("fff6c8"), 6)
	sound.emit("thunk")
	for c in candies.duplicate():
		if _ang_diff(a, c) < HIT_ARC:
			candies.erase(c)
			_candies_hit += 1
			_burst(rim, Color("ff6b8a"), 14)
			popup.emit(Loc.t("candy"), Color("ff9bb0"))
			sound.emit("candy")
	for s in stars.duplicate():
		if _ang_diff(a, s) < HIT_ARC:
			stars.erase(s)
			_burst(rim, Color("ffd84a"), 18)
			sound.emit("star")
	if is_boss_tier():
		var phases: Array = tier.phases
		if phase_index < phases.size() and left <= phases[phase_index].at and left > 0:
			_next_phase(phases[phase_index])
			phase_index += 1
	changed.emit()


func _next_phase(p: Dictionary) -> void:
	for s in stuck:
		_knock_off(s)
	var keep_stars := stars
	_apply_layout(p)
	stars = keep_stars
	shake = 16.0
	flash = 2.0
	popup.emit(Loc.t("phase"), Color("ffd25e"))
	sound.emit("phase")


func _bounce(f: Dictionary) -> void:
	debris.append({"pos": f.pos + Vector2(0, STICK * 0.5), "vel": Vector2(randf_range(-260, 260), 700),
		"ang": -PI * 0.5, "spin": randf_range(-16, 16), "color": f.color, "kind": "ornament", "life": 1.6})


func _fail(reason: String, at: Vector2) -> void:
	state = FAILED
	fail_reason = reason
	shake = 18.0
	_burst(at, Color("ffffff"), 16)
	sound.emit("clash" if reason == "clash" else "fail")
	_end_timer = 0.75
	changed.emit()


func _tier_complete() -> void:
	if not stars.is_empty():
		state = FAILED
		fail_reason = "stars"
		sound.emit("fail")
		_end_timer = 0.5
		changed.emit()
		return
	var colors := []
	for s in stuck:
		colors.append(s.color)
	done_tiers.append(colors)
	state = TRANSITION
	transition_t = 0.0
	sound.emit("tier")
	tier_finished.emit(tier_index)
	if tier_index == level.tiers.size() - 1:
		popup.emit(Loc.t("perfect"), Color("ffe680"))
		time_scale = 0.45
	for k in 3:
		_burst(center + Vector2.from_angle(randf() * TAU) * radius, Color("fff2a8"), 10)
	changed.emit()


func _win() -> void:
	state = WON
	_end_timer = 0.35
	sound.emit("win")
	changed.emit()


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(120, 420)
		sparks.append({"pos": at, "vel": v, "life": randf_range(0.3, 0.7), "color": color, "size": randf_range(2.5, 6.0)})


func _update_fx(dt: float) -> void:
	shake = maxf(shake - dt * 40.0, 0.0)
	flash = maxf(flash - dt * 4.0, 0.0)
	for s in sparks:
		s.pos += s.vel * dt
		s.vel *= 0.92
		s.life -= dt
	sparks = sparks.filter(func(s): return s.life > 0.0)
	for d in debris:
		d.vel.y += 1500.0 * dt
		d.pos += d.vel * dt
		d.ang += d.spin * dt
		d.life -= dt
	debris = debris.filter(func(d): return d.life > 0.0)
	position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake if shake > 0.0 else Vector2.ZERO


## Would a throw right now land safely? null when unknown (no aim booster).
func aim_safe() -> bool:
	return not is_nan(predict_landing(true))


## Flies a ghost ornament from the elf with the tier's real spin program and
## returns where it would land (radians, in the tier's frame), or NAN if it would
## hit a hanging ornament or (with check_ice) an ice plate. Used by the aim
## booster and the test bot. A small margin makes it a bit cautious.
func predict_landing(check_ice := false) -> float:
	var vp := get_viewport_rect().size
	var ghost := rotor.clone()
	var tip := spawn_pos()
	var ang := rot
	var frame := 1.0 / 60.0
	var steps := 8
	var sdt := frame / steps
	var tt := 0.0
	for f in 60:
		var spd := ghost.step(frame)
		if slow_t - tt > 0.0:
			spd *= 0.4
		for k in steps:
			tt += sdt
			ang += deg_to_rad(spd) * sdt
			tip.y -= SPEED * sdt
			var tf := t + tt
			var c := Vector2(vp.x * 0.5 + sin(tf * 1.25) * tier.get("move", 0.0), center.y)
			var r: float = tier.get("radius", 160.0) * (1.0 + tier.get("pulse", 0.0) * sin(tf * 2.2))
			if tip.y > c.y + r + STICK + BALL * 2.0 + 10.0:
				continue
			for s in stuck:
				for m in [0.0, -0.05, 0.05]:
					var d := Vector2.from_angle(s.a + ang + m)
					if _hits(tip, tip + Vector2(0, STICK), c + d * r, c + d * (r + STICK)):
						return NAN
			if tip.distance_to(c) <= r:
				var a := wrapf((tip - c).angle() - ang, -PI, PI)
				if check_ice:
					for p in ice:
						if _ang_diff(a, p[0]) < p[1] + 0.05:
							return NAN
				return a
	return NAN


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var vp := get_viewport_rect().size
	var theme: Dictionary = THEMES.get(level.get("theme", "forest"), THEMES.forest)
	_draw_background(vp, theme)
	if state == READY:
		return
	_draw_tree_preview(vp, theme)
	if state == TRANSITION:
		var k := ease(clampf(transition_t / 0.85, 0.0, 1.0), 2.0)
		var target := Vector2(70, 250)
		draw_set_transform(center.lerp(target, k) - center * (1.0 - k * 0.8), 0.0, Vector2.ONE * (1.0 - k * 0.8))
		_draw_tier(theme, center, radius)
		draw_set_transform(Vector2.ZERO)
	else:
		_draw_tier(theme, center, radius)
	if aim_t > 0.0 and state == PLAYING:
		var ok := aim_safe()
		var col := Color(0.4, 1.0, 0.5, 0.75) if ok else Color(1.0, 0.35, 0.35, 0.75)
		var sp := spawn_pos()
		var y := sp.y
		while y > center.y + radius * 0.6:
			draw_line(Vector2(sp.x, y), Vector2(sp.x, y - 14), col, 4.0)
			y -= 28
	for f in flying:
		_draw_ornament(f.pos + Vector2(0, STICK), -PI * 0.5, f.color, f.fire)
	for d in debris:
		_draw_ornament(d.pos, d.ang, d.color, false)
	_draw_elf()
	for s in sparks:
		draw_circle(s.pos, s.size * clampf(s.life * 2.0, 0.0, 1.0), s.color)


func _draw_background(vp: Vector2, theme: Dictionary) -> void:
	var bg := Art.tex("bg_" + level.get("theme", "forest"))
	if bg:
		var sc := maxf(vp.x / bg.get_width(), vp.y / bg.get_height())
		var sz := Vector2(bg.get_width(), bg.get_height()) * sc
		draw_texture_rect(bg, Rect2((vp - sz) * 0.5 - position, sz), false)
	else:
		var top: Color = theme.sky[0]
		var bot: Color = theme.sky[1]
		var bands := 24
		for i in bands:
			var y0 := vp.y * i / bands
			draw_rect(Rect2(-20, y0 - 20 * int(i == 0), vp.x + 40, vp.y / bands + 1 + 20 * int(i == 0)), top.lerp(bot, float(i) / bands))
		# distant fir silhouettes and snowy ground
		var hill := Color(bot.darkened(0.45), 1.0)
		for i in 9:
			var x := vp.x * (i + 0.5) / 8.0 - 40.0
			var h := 120.0 + 40.0 * sin(i * 2.3)
			var gy := vp.y - 300.0
			draw_colored_polygon(PackedVector2Array([Vector2(x - 50, gy), Vector2(x, gy - h), Vector2(x + 50, gy)]), hill)
		draw_rect(Rect2(-20, vp.y - 300, vp.x + 40, 320), Color("dfe9f5"))
		draw_rect(Rect2(-20, vp.y - 300, vp.x + 40, 10), Color("b7c7dc"))
	for s in snow:
		var p := Vector2(fposmod(s.x * vp.x + sin(t * 0.6 + s.y * 9.0) * 20.0, vp.x),
			fposmod(s.y * vp.y + t * 40.0 * s.z, vp.y))
		draw_circle(p, 2.0 + 2.0 * s.z, Color(1, 1, 1, 0.55 * s.z))


func _draw_tier(theme: Dictionary, c: Vector2, r: float) -> void:
	var boss_top := is_boss_tier()
	var tex := Art.tex("boss_star" if boss_top else "tier_" + level.get("theme", "forest"))
	# ornaments hanging behind are drawn first so the pins tuck under the rim
	for s in stuck:
		var d := _dir(s.a)
		_draw_ornament(c + d * (r + STICK), d.angle(), s.color, false, c + d * (r - 8.0))
	if tex:
		draw_set_transform(c, rot, Vector2.ONE * (2.0 * r / tex.get_width()))
		draw_texture(tex, -Vector2(tex.get_width(), tex.get_height()) * 0.5)
		draw_set_transform(Vector2.ZERO)
	elif boss_top:
		_draw_star_body(c, r)
	else:
		var cols: Array = theme.tier
		var pts := PackedVector2Array()
		var n := 36
		for i in n * 2:
			var a := rot + TAU * i / (n * 2)
			pts.append(c + Vector2.from_angle(a) * (r * (1.0 if i % 2 == 0 else 0.9)))
		draw_colored_polygon(pts, cols[0])
		draw_circle(c, r * 0.86, cols[1])
		for k in 3:
			var rr := r * (0.78 - 0.2 * k)
			for i in 18:
				var a := rot + TAU * (i + 0.5 * k) / 18.0
				var tip := c + Vector2.from_angle(a) * rr
				var b1 := c + Vector2.from_angle(a - 0.12) * (rr - 26.0)
				var b2 := c + Vector2.from_angle(a + 0.12) * (rr - 26.0)
				draw_colored_polygon(PackedVector2Array([tip, b1, b2]), cols[2] if k % 2 == 0 else cols[0])
		draw_circle(c, r * 0.16, Color("6b4428"))
		draw_circle(c, r * 0.1, Color("8a5a36"))
		# a garland in the theme's trim colour
		for i in 24:
			var a := rot + TAU * i / 24.0
			draw_circle(c + Vector2.from_angle(a) * r * 0.62, 4.5, theme.trim)
	if flash > 0.0:
		draw_circle(c, r, Color(1, 1, 1, 0.12 * minf(flash, 1.0)))
	for p in ice:
		var pts := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var a: float = rot + p[0] - p[1] + 2.0 * p[1] * i / steps
			pts.append(c + Vector2.from_angle(a) * (r + 2.0))
		for i in range(steps, -1, -1):
			var a: float = rot + p[0] - p[1] + 2.0 * p[1] * i / steps
			pts.append(c + Vector2.from_angle(a) * (r - 22.0))
		draw_colored_polygon(pts, Color(0.75, 0.93, 1.0, 0.92))
		draw_polyline(pts, Color(1, 1, 1, 0.9), 2.0)
	for a in candies:
		_draw_candy(c + _dir(a) * (r + 6.0), a + rot)
	for a in stars:
		_draw_star(c + _dir(a) * (r + 4.0), 17.0, Color("ffd84a"), a + rot + PI * 0.5)


func _draw_star_body(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color("b8860b"))
	draw_circle(c, r * 0.93, Color("f2c230"))
	_draw_star(c, r * 0.8, Color("ffe680"), rot - PI * 0.5)
	_draw_star(c, r * 0.5, Color("fff4c2"), rot - PI * 0.5)
	# a face, so the boss has a personality
	var eye := Vector2(r * 0.17, -r * 0.06)
	for sx in [-1.0, 1.0]:
		var e := c + Vector2(eye.x * sx, eye.y).rotated(rot)
		draw_circle(e, r * 0.06, Color("3b2a10"))
	var hp_k := float(left) / maxf(hp_max, 1)
	var brow := Color("3b2a10")
	for sx in [-1.0, 1.0]:
		var a0 := c + Vector2(r * 0.08 * sx, -r * 0.16).rotated(rot)
		var a1 := c + Vector2(r * 0.27 * sx, -r * (0.2 + 0.06 * (1.0 - hp_k))).rotated(rot)
		draw_line(a0, a1, brow, 5.0)
	draw_arc(c + Vector2(0, r * 0.12).rotated(rot), r * 0.14, rot + 0.3, rot + PI - 0.3, 12, brow, 5.0)


func _draw_star(at: Vector2, size: float, color: Color, ang: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := size if i % 2 == 0 else size * 0.45
		pts.append(at + Vector2.from_angle(ang + TAU * i / 10.0) * rr)
	draw_colored_polygon(pts, color)
	draw_polyline(pts + PackedVector2Array([pts[0]]), color.darkened(0.35), 2.0)


func _draw_candy(at: Vector2, ang: float) -> void:
	var d := Vector2.from_angle(ang + PI * 0.5)
	for sx in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([at + d * 10 * sx, at + d * 22 * sx + d.orthogonal() * 8,
			at + d * 22 * sx - d.orthogonal() * 8]), Color("ff4d6d"))
	draw_circle(at, 11.0, Color("fff3f6"))
	draw_arc(at, 7.0, ang, ang + PI, 8, Color("ff4d6d"), 4.0)


func _draw_ornament(ball: Vector2, ang: float, color: Color, fire: bool, pin_from := Vector2.INF) -> void:
	var d := Vector2.from_angle(ang)
	var pin_start := pin_from if pin_from != Vector2.INF else ball - d * STICK
	var tex := Art.tex("ornament")
	draw_line(pin_start, ball - d * BALL, Color("d8c27a"), 4.0)
	draw_line(ball - d * BALL, ball - d * (BALL - 2.0), Color("8f7a3a"), 8.0)
	if tex:
		draw_set_transform(ball, ang - PI * 0.5, Vector2.ONE * (2.4 * BALL / tex.get_width()))
		draw_texture(tex, -Vector2(tex.get_width(), tex.get_height()) * 0.5, color)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_circle(ball, BALL, color.darkened(0.25))
		draw_circle(ball, BALL - 2.5, color)
		draw_circle(ball - Vector2(4, 4), 4.0, Color(1, 1, 1, 0.65))
	if fire:
		for i in 5:
			var off := Vector2(randf_range(-6, 6), randf_range(0, 24))
			draw_circle(ball + off, randf_range(5, 10), Color(1.0, randf_range(0.4, 0.7), 0.1, 0.7))


func _draw_elf() -> void:
	var p := elf_pos()
	var tex := Art.tex("elf")
	var lift := -10.0 * throw_anim
	if tex:
		# The art raises its hand at the top left, so it is shifted right to put
		# that hand under the throw line.
		var h := 250.0
		var sc := h / tex.get_height()
		var w := tex.get_width() * sc
		draw_texture_rect(tex, Rect2(p + Vector2(-w * 0.16, -h * 0.66 + lift), Vector2(w, h)), false)
	else:
		# body, belt, head, hat, ears
		draw_colored_polygon(PackedVector2Array([p + Vector2(-48, 70), p + Vector2(48, 70), p + Vector2(26, -10), p + Vector2(-26, -10)]), Color("2e9e4f"))
		draw_rect(Rect2(p + Vector2(-40, 30), Vector2(80, 12)), Color("7a3b16"))
		draw_rect(Rect2(p + Vector2(-8, 28), Vector2(16, 16)), Color("ffd25e"))
		var head := p + Vector2(0, -42 + lift * 0.5)
		for sx in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([head + Vector2(24 * sx, -4), head + Vector2(48 * sx, -16), head + Vector2(26 * sx, 10)]), Color("f2c19c"))
		draw_circle(head, 30, Color("f6cfae"))
		draw_circle(head + Vector2(-10, 0), 4, Color("2a1a12"))
		draw_circle(head + Vector2(10, 0), 4, Color("2a1a12"))
		draw_circle(head + Vector2(-18, 10), 6, Color(1, 0.5, 0.5, 0.45))
		draw_circle(head + Vector2(18, 10), 6, Color(1, 0.5, 0.5, 0.45))
		draw_arc(head + Vector2(0, 8), 9, 0.3, PI - 0.3, 8, Color("8a3a2a"), 3.0)
		draw_colored_polygon(PackedVector2Array([head + Vector2(-32, -14), head + Vector2(32, -14), head + Vector2(22, -58), head + Vector2(40, -96), head + Vector2(2, -66)]), Color("d8343a"))
		draw_rect(Rect2(head + Vector2(-34, -20), Vector2(68, 12)), Color("f4f4f4"))
		draw_circle(head + Vector2(40, -96), 9, Color("f4f4f4"))
		# arm with the next ornament
		var hand := p + Vector2(40, -40 + lift * 3.0)
		draw_line(p + Vector2(22, 0), hand, Color("2e9e4f"), 12.0)
		draw_circle(hand, 9, Color("f6cfae"))
	if state == PLAYING and left - flying.size() > 0 and cooldown <= 0.0:
		_draw_ornament(spawn_pos() + Vector2(0, STICK), -PI * 0.5, Color("f6c343"), fire_next)
	if shield:
		draw_arc(p + Vector2(0, -20), 100, 0, TAU, 40, Color(0.55, 0.85, 1.0, 0.6 + 0.2 * sin(t * 6)), 5.0)


## Left side: the tree as it is being built, finished tiers stacked bottom-up.
func _draw_tree_preview(vp: Vector2, theme: Dictionary) -> void:
	var total: int = level.tiers.size()
	TreeArt.draw_tree(self, Rect2(14, 150, 112, 180), total, done_tiers, theme, false, tier_index if state != WON else -1, t)
