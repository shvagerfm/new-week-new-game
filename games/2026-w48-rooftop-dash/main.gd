extends Node2D
## Rooftop Dash: a courier runs across night-city rooftops on their own; one
## button jumps, and holding it jumps higher. The rules live in world.gd;
## this script reads input, draws the city and runs the screens.

const SAVE_PATH := "user://rooftop_dash.cfg"
const RESTART_DELAY := 0.45   # after a fall, taps are ignored this long
const RUNNER_AT := 0.24       # the runner's place across the screen
const BUTTON := 72.0          # size of the corner buttons

enum State { TITLE, RUN, PAUSED, OVER }

var state := State.TITLE
var world: World
var cam := Vector2.ZERO
var shake := 0.0
var flash := 0.0
var over_t := 0.0
var time := 0.0
var best_score := 0
var best_m := 0.0
var passed_best := false
var new_best := false
var runs := 0
var muted := false

var touches := {}           # touch index -> true while a finger is down
var key_down := false
var particles: Array = []   # {p, v, life, max, col, size}
var popups: Array = []      # {p, text, life, col}

@onready var sfx: Sfx = $Sfx
var music: AudioStreamPlayer
var score_label: Label
var meters_label: Label
var mult_label: Label
var best_label: Label
var hint_label: Label
var title_label: Label


func _ready() -> void:
	_load()
	_build_hud()
	music = AudioStreamPlayer.new()
	var loop: AudioStreamWAV = preload("res://sfx/music.wav")
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(loop.get_length() * loop.mix_rate)
	music.stream = loop
	music.volume_db = -6.0
	add_child(music)
	_set_muted(muted)
	_new_world()
	_show_title()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _corner_button(event.position):
				return
			touches[event.index] = true
			_on_press()
		else:
			touches.erase(event.index)
	elif event is InputEventKey and not event.echo:
		var k: Key = event.keycode
		if k in [KEY_SPACE, KEY_UP, KEY_W, KEY_ENTER, KEY_KP_ENTER, KEY_Z]:
			key_down = event.pressed
			if event.pressed:
				_on_press()
		elif event.pressed and k == KEY_M:
			_set_muted(not muted)
		elif event.pressed and k in [KEY_ESCAPE, KEY_P]:
			if state == State.RUN:
				_pause()
			elif state == State.PAUSED:
				_resume()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.RUN:
		_pause()


func _held() -> bool:
	return key_down or not touches.is_empty()


## True if the press landed on the sound or pause button (and was handled).
func _corner_button(pos: Vector2) -> bool:
	var vw := get_viewport_rect().size.x
	if Rect2(vw - BUTTON - 16, 24, BUTTON, BUTTON).grow(8).has_point(pos):
		_set_muted(not muted)
		sfx.play("click")
		return true
	if state in [State.RUN, State.PAUSED] and Rect2(16, 24, BUTTON, BUTTON).grow(8).has_point(pos):
		if state == State.RUN:
			_pause()
		else:
			_resume()
		return true
	return false


func _on_press() -> void:
	match state:
		State.TITLE:
			_start_run()
		State.PAUSED:
			_resume()
		State.OVER:
			if over_t >= RESTART_DELAY:
				_new_world()
				_start_run()


# --- Screens ---------------------------------------------------------------

func _new_world() -> void:
	world = World.new()
	cam = Vector2(world.x - get_viewport_rect().size.x * RUNNER_AT, _cam_target_y())
	particles.clear()
	popups.clear()
	passed_best = false
	new_best = false


func _start_run() -> void:
	state = State.RUN
	world.start()
	world.was_held = true  # the press that started the run isn't a jump
	runs += 1
	title_label.hide()
	hint_label.hide()
	_set_hud_visible(true)
	sfx.play("click")
	if not muted:
		music.pitch_scale = 1.0
		music.volume_db = -6.0
		music.play()


func _show_title() -> void:
	state = State.TITLE
	_set_hud_visible(false)
	title_label.show()
	var s := "Tap, click or press Space to jump.\nHold it to jump higher.\n\nLand right on a roof's edge\nto grow the multiplier."
	if best_score > 0:
		s += "\n\nBest  %d   ·   %d m" % [best_score, int(best_m)]
	s += "\n\nTap to run"
	hint_label.text = s
	hint_label.offset_top = 240
	hint_label.show()


func _pause() -> void:
	state = State.PAUSED
	touches.clear()
	key_down = false
	music.stream_paused = true
	hint_label.text = "Paused\n\nTap to keep running"
	hint_label.offset_top = 0
	hint_label.show()


func _resume() -> void:
	state = State.RUN
	world.was_held = true
	music.stream_paused = false
	hint_label.hide()


func _game_over() -> void:
	state = State.OVER
	over_t = 0.0
	var sc := world.score()
	if sc > best_score:
		best_score = sc
		new_best = true
	best_m = maxf(best_m, world.meters())
	_save()
	var tw := create_tween()
	tw.tween_property(music, "pitch_scale", 0.5, 0.5)
	tw.parallel().tween_property(music, "volume_db", -40.0, 0.5)
	tw.tween_callback(music.stop)


func _show_results() -> void:
	var why := {"fall": "Fell between the roofs", "wall": "Ran into a wall",
		"ac": "Tripped on an air conditioner", "antenna": "Hit an antenna",
		"wire": "Caught in a wire"}
	var s := "%s\n\n%d m   ·   %d parcels\n\nScore  %d\n" % [why.get(world.death, ""),
		int(world.meters()), world.parcels_taken, world.score()]
	s += "New best!" if new_best else "Best  %d" % best_score
	s += "\n\nTap to run again"
	hint_label.text = s
	hint_label.offset_top = 80
	hint_label.show()


# --- Loop ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if state == State.PAUSED:
		return
	if state == State.TITLE:
		world.step(false)
		return
	var was_alive := world.alive
	for e in world.step(_held() and state == State.RUN):
		_on_event(e)
	if was_alive and not world.alive:
		_game_over()
	if state == State.RUN and world.alive:
		if best_m > 0.0 and not passed_best and world.meters() > best_m:
			passed_best = true
			_popup(Vector2(world.x, world.y - 110.0), "Best distance!", Art.GOLD)
			sfx.play("best")


func _process(delta: float) -> void:
	time += delta
	var vp := get_viewport_rect().size
	if state != State.PAUSED:
		var tx := world.x - vp.x * RUNNER_AT
		if world.alive:
			cam.x = tx
		cam.y = lerpf(cam.y, _cam_target_y(), 1.0 - exp(-3.5 * delta))
		# Keep the runner on screen when falling or jumping far from the roofs.
		cam.y = clampf(cam.y, world.y - vp.y * 0.82, world.y - vp.y * 0.25) if world.alive else cam.y
		shake = maxf(shake - delta * 40.0, 0.0)
		flash = maxf(flash - delta * 3.0, 0.0)
		_update_effects(delta)
	if state == State.OVER:
		over_t += delta
		if over_t >= RESTART_DELAY and not hint_label.visible:
			_show_results()
	if state == State.RUN:
		music.pitch_scale = 1.0 + 0.2 * world.speed_frac()
	_update_hud()
	queue_redraw()


## The camera keeps the roofs about 60% down the screen, halfway between the
## roof the runner last stood on and the next one, so a drop is seen coming.
func _cam_target_y() -> float:
	var ahead := world.ref_y
	for r in world.roofs:
		if r.x0 > world.x:
			ahead = r.base
			break
	return lerpf(world.ref_y, ahead, 0.5) - get_viewport_rect().size.y * 0.6


func _on_event(e: Dictionary) -> void:
	match e.type:
		"jump":
			sfx.play("jump", 0.05)
			_dust(Vector2(world.x - 8, world.y), 5, -1.0)
		"land":
			var impact: float = e.impact
			sfx.play("land", 0.08, linear_to_db(clampf(impact / 1400.0, 0.3, 1.0)))
			_dust(Vector2(world.x, world.y), int(clampf(impact / 120.0, 3, 12)), 1.0)
			if impact > 1000.0:
				shake = maxf(shake, (impact - 900.0) / 90.0)
		"edge":
			sfx.play("edge", 0.0, 0.0, 1.0 + 0.12 * (e.mult - 2))
			_popup(Vector2(world.x, world.y - 90.0), "EDGE!  x%d" % e.mult, Art.ORANGE)
			_sparks(Vector2(e.x, e.y), 14)
		"combo_lost":
			sfx.play("combo_lost")
		"parcel":
			sfx.play("parcel", 0.04)
			_popup(Vector2(e.x, e.y - 24.0), "+%d" % e.points, Art.GOLD)
			_sparks(Vector2(e.x, e.y), 8)
		"crumble":
			sfx.play("crumble")
		"collapse":
			_dust(Vector2(e.x, e.y), 16, 0.0)
		"die":
			shake = 16.0
			if e.reason == "fall":
				sfx.play("fall")
			else:
				sfx.play("hit")
				flash = 1.0
				_sparks(Vector2(world.x, world.y - 30), 10)


# --- Effects ---------------------------------------------------------------

func _dust(at: Vector2, n: int, dir: float) -> void:
	for i in n:
		particles.append({"p": at + Vector2(randf_range(-14, 14), -4),
			"v": Vector2(randf_range(-160, 60) + dir * 60.0, randf_range(-140, -30)),
			"life": 0.0, "max": randf_range(0.3, 0.6), "col": Color("8da0d8"), "size": 4.0})


func _sparks(at: Vector2, n: int) -> void:
	for i in n:
		var a := randf() * TAU
		particles.append({"p": at, "v": Vector2(cos(a), sin(a)) * randf_range(120, 320),
			"life": 0.0, "max": randf_range(0.25, 0.5),
			"col": Art.GOLD if i % 2 == 0 else Art.ORANGE, "size": 4.0})


func _popup(at: Vector2, text: String, col: Color) -> void:
	popups.append({"p": at, "text": text, "life": 0.0, "col": col})


func _update_effects(delta: float) -> void:
	for p in particles:
		p.life += delta
		p.v.y += 600.0 * delta
		p.p += p.v * delta
	particles = particles.filter(func(p): return p.life < p.max)
	for p in popups:
		p.life += delta
		p.p.y -= 50.0 * delta
	popups = popups.filter(func(p): return p.life < 1.1)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var vp := get_viewport_rect().size
	var off := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO
	var c := (cam - off).snapped(Vector2(Art.P, Art.P))
	_draw_sky(vp, c)
	draw_set_transform(-c)
	_draw_best_flag(vp, c)
	for w in world.wires:
		_draw_wire_posts(w)
	for r in world.roofs:
		_draw_roof(r, c, vp)
	for o in world.obstacles:
		_draw_obstacle(o)
	for p in world.parcels:
		if not p.taken:
			var bob := snappedf(sin(time * 4.0 + p.x * 0.01) * 4.0, 4.0)
			Art.sprite(self, Art.PARCEL, Vector2(p.x - 12, p.y - 10 + bob).snapped(Vector2(4, 4)))
	_draw_runner()
	for w in world.wires:
		_draw_wire(w)
	for p in particles:
		var a: float = 1.0 - p.life / p.max
		var col: Color = p.col
		col.a = a
		draw_rect(Rect2(p.p.snapped(Vector2(4, 4)), Vector2(p.size, p.size)), col)
	var font := ThemeDB.fallback_font
	for p in popups:
		var col: Color = p.col
		col.a = clampf(2.0 - p.life * 2.0, 0.0, 1.0)
		var size := 34
		var w := font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string_outline(font, p.p - Vector2(w * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(0.04, 0.05, 0.12, col.a))
		draw_string(font, p.p - Vector2(w * 0.5, 0), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	draw_set_transform(Vector2.ZERO)
	_draw_speed_lines(vp)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 0.55, 0.3, flash * 0.35))
	if state == State.OVER or state == State.PAUSED or state == State.TITLE:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.04, 0.1, 0.55 if state != State.OVER else clampf(over_t * 2.0, 0.0, 0.6)))
	_draw_buttons(vp)


func _draw_sky(vp: Vector2, c: Vector2) -> void:
	# Bands from deep blue at the top to a warm haze at the horizon.
	var horizon := vp.y * 0.8 - c.y * 0.08
	var bands: int = Art.SKY.size()
	var band_h := snappedf(maxf(horizon, 200.0) / bands, 4.0)
	draw_rect(Rect2(Vector2.ZERO, vp), Art.SKY[0])
	for i in range(1, bands):
		var y0 := band_h * i
		draw_rect(Rect2(0, y0, vp.x, vp.y - y0), Art.SKY[i])
		# A dithered seam between bands.
		for x in range(0, int(vp.x), 8):
			draw_rect(Rect2(x + (4 if (x / 8) % 2 == 0 else 0), y0 - 4, 4, 4), Art.SKY[i])
	# Stars in the upper sky, drifting slowly.
	for i in 70:
		var h := Art.hash3(i, 11)
		var sx := fposmod(float(h % 4000) - c.x * 0.02, vp.x + 40.0)
		var sy := float((h >> 12) % 1000) / 1000.0 * horizon * 0.6
		var tw := 0.5 + 0.5 * sin(time * (1.0 + (h % 7) * 0.3) + h)
		draw_rect(Rect2(snappedf(sx, 4), snappedf(sy, 4), 4, 4), Color(0.85, 0.88, 1.0, 0.25 + 0.6 * tw))
	# The moon.
	var mc := Vector2(snappedf(vp.x * 0.84, 4), snappedf(horizon * 0.2, 4))
	for yy in range(-9, 10):
		for xx in range(-9, 10):
			if xx * xx + yy * yy <= 81:
				var col := Color("ffe9c4") if xx * xx + yy * yy < 64 else Color("f5cf98")
				if (xx - 3) * (xx - 3) + (yy + 2) * (yy + 2) < 5 or (xx + 3) * (xx + 3) + (yy - 3) * (yy - 3) < 3:
					col = Color("e8c08c")
				draw_rect(Rect2(mc.x + xx * 4, mc.y + yy * 4, 4, 4), col)
	# Three layers of skyline, the farther the slower.
	_draw_skyline(vp, c, horizon, 0.12, 0.05, 96.0, 1, Art.FAR, 0.3)
	_draw_skyline(vp, c, horizon + 60.0, 0.25, 0.1, 128.0, 2, Art.MID, 0.4)
	_draw_skyline(vp, c, horizon + 140.0, 0.45, 0.18, 160.0, 3, Art.NEAR, 0.5)
	# The streets far below fade to black, so the gaps between roofs read as drops.
	var deep := snappedf(horizon + 100.0 - (c.y - _cam_rest()) * 0.3, 4.0)
	for i in 8:
		draw_rect(Rect2(0, deep + i * 24, vp.x, vp.y), Color(0.01, 0.015, 0.05, 0.16))


func _draw_skyline(vp: Vector2, c: Vector2, base: float, fx: float, fy: float, slot: float,
		layer: int, col: Color, lights: float) -> void:
	var scroll := c.x * fx
	var y_base := snappedf(base - (c.y - _cam_rest()) * fy, 4.0)
	var first := floori(scroll / slot) - 1
	var last := first + ceili(vp.x / slot) + 2
	for i in range(first, last + 1):
		var h := Art.hash3(i, layer)
		var w := snappedf(slot * (0.55 + (h % 40) / 100.0), 8.0)
		var bh := snappedf((90.0 + float((h >> 6) % 200)) * (0.7 + layer * 0.25), 8.0)
		var x0 := snappedf(i * slot - scroll, 4.0)
		var top := y_base - bh
		draw_rect(Rect2(x0, top, w, vp.y - top + 400), col)
		# Roof details: a step, a mast or a water tank.
		match h % 5:
			0:
				draw_rect(Rect2(x0 + 8, top - 16, w * 0.4, 16), col)
			1:
				draw_rect(Rect2(x0 + w * 0.5, top - 40, 4, 40), col)
				if layer == 3 and int(time * 1.5 + i) % 3 == 0:
					draw_rect(Rect2(x0 + w * 0.5 - 4, top - 44, 8, 4), Color("ff4d5e"))
			2:
				draw_rect(Rect2(x0 + w - 32, top - 24, 20, 16), col)
				draw_rect(Rect2(x0 + w - 28, top - 8, 4, 8), col)
				draw_rect(Rect2(x0 + w - 20, top - 8, 4, 8), col)
		# Lit windows.
		var cols := int(w / 16.0)
		var rows := int(bh / 20.0)
		for ry in rows:
			for rx in cols:
				var wh := Art.hash3(i, rx * 31 + ry, layer)
				if float(wh % 100) / 100.0 < lights * 0.35:
					var wc: Color = Art.WINDOW_ON[wh % 3]
					wc.a = 0.2 + 0.12 * layer
					draw_rect(Rect2(x0 + 6 + rx * 16, top + 12 + ry * 20, 4, 4 + layer * 2), wc)


## Where the camera sits when the runner is on the first roof, so the
## skyline starts at the same place every run.
func _cam_rest() -> float:
	return -get_viewport_rect().size.y * 0.6


func _draw_roof(r: Dictionary, c: Vector2, vp: Vector2) -> void:
	var y := snappedf(r.y, 4.0)
	if r.crumble and r.t >= 0.0 and r.vy == 0.0:
		y += snappedf(randf_range(-4, 4), 4.0)
	var x0: float = r.x0
	var w: float = r.x1 - r.x0
	var bottom := c.y + vp.y + 8.0
	var h := Art.hash3(r.id, 5)
	var body: Color = Art.BODY[h % 3]
	draw_rect(Rect2(x0, y, w, bottom - y), body)
	# A lit front face on the left and a shaded side on the right, so every
	# gap has a clear wall on both sides.
	draw_rect(Rect2(x0, y, 8, bottom - y), Art.FACE)
	draw_rect(Rect2(x0 + w - 8, y, 8, bottom - y), body.darkened(0.4))
	# Windows: a grid, some lit orange.
	var cols := int((w - 24) / 32.0)
	var y_win := y + 44.0
	var row := 0
	while y_win < bottom:
		for cx in cols:
			var wh := Art.hash3(r.id, cx, row)
			var lit := wh % 100 < 34
			var wc: Color = Art.WINDOW_ON[wh % 3] if lit else Art.WINDOW_OFF
			draw_rect(Rect2(x0 + 16 + cx * 32, y_win, 12, 16), wc)
			if lit and wh % 7 == 0:
				draw_rect(Rect2(x0 + 16 + cx * 32, y_win + 8, 12, 4), wc.darkened(0.4))
		y_win += 52.0
		row += 1
	# The parapet along the top.
	if r.crumble:
		draw_rect(Rect2(x0 - 4, y - 4, w + 8, 12), Art.BRICK)
		draw_rect(Rect2(x0 - 4, y - 4, w + 8, 4), Art.BRICK.lightened(0.25))
		for i in range(0, int(w), 24):
			var ch := Art.hash3(r.id, i)
			draw_rect(Rect2(x0 + i + (ch % 3) * 4, y, 4, 8), Color("2a1a26"))
			draw_rect(Rect2(x0 + i + 4 + (ch % 3) * 4, y + 4, 4, 8), Color("2a1a26"))
	else:
		draw_rect(Rect2(x0 - 4, y - 4, w + 8, 12), Art.LIP)
		draw_rect(Rect2(x0 - 4, y - 4, w + 8, 4), Art.LIP_HI)
		draw_rect(Rect2(x0 - 4, y + 8, w + 8, 4), Color(0, 0, 0, 0.35))
	# The front edge glows a little: that's where edge landings score.
	draw_rect(Rect2(x0 - 4, y - 4, 8, 4), Art.ORANGE.lerp(Art.LIP_HI, 0.5 + 0.5 * sin(time * 5.0)))


func _draw_obstacle(o: Dictionary) -> void:
	var x0: float = o.x0
	var y0: float = o.y0
	var w: float = o.x1 - o.x0
	var h: float = o.y1 - o.y0
	if o.kind == "ac":
		draw_rect(Rect2(x0, y0, w, h), Art.STEEL_DARK)
		draw_rect(Rect2(x0 + 4, y0 + 4, w - 8, h - 8), Art.STEEL)
		draw_rect(Rect2(x0, y0, w, 4), Art.WIRE)
		# The fan, spinning.
		var fc := Vector2(x0 + w * 0.38, y0 + h * 0.5)
		for yy in range(-3, 4):
			for xx in range(-3, 4):
				if xx * xx + yy * yy <= 10:
					draw_rect(Rect2(fc.x + xx * 4 - 2, fc.y + yy * 4 - 2, 4, 4), Art.STEEL_DARK)
		var a := time * 14.0
		for k in 2:
			var d := Vector2(cos(a + k * PI * 0.5), sin(a + k * PI * 0.5)) * 8.0
			draw_rect(Rect2((fc + d).snapped(Vector2(4, 4)) - Vector2(2, 2), Vector2(4, 4)), Art.STEEL)
			draw_rect(Rect2((fc - d).snapped(Vector2(4, 4)) - Vector2(2, 2), Vector2(4, 4)), Art.STEEL)
		for i in 3:
			draw_rect(Rect2(x0 + w - 20, y0 + 12 + i * 8, 12, 4), Art.STEEL_DARK)
	else:
		draw_rect(Rect2(x0 - 8, o.y1 - 8, w + 16, 8), Art.STEEL_DARK)
		draw_rect(Rect2(x0, y0, w, h), Art.STEEL_DARK)
		draw_rect(Rect2(x0, y0, 4, h), Art.STEEL)
		for i in 3:
			var by := y0 + 24 + i * 36
			var bw := 28 - i * 6
			draw_rect(Rect2(x0 + w * 0.5 - bw * 0.5, by, bw, 4), Art.STEEL)
		var on := int(time * 2.0) % 2 == 0
		draw_rect(Rect2(x0 - 2, y0 - 8, w + 4, 8), Color("ff4d5e") if on else Color("7a2030"))
		if on:
			draw_rect(Rect2(x0 - 6, y0 - 12, w + 12, 16), Color(1, 0.3, 0.37, 0.25))


func _draw_wire_posts(w: Dictionary) -> void:
	for p in [Vector2(w.ax, w.ay), Vector2(w.bx, w.by)]:
		var top := snappedf(p.y, 4.0)
		draw_rect(Rect2(p.x - 4, top, 8, World.WIRE_HIGH), Art.STEEL_DARK)
		draw_rect(Rect2(p.x - 12, top + 8, 24, 4), Art.STEEL_DARK)


func _draw_wire(w: Dictionary) -> void:
	var pts := World.wire_points(w, int((w.bx - w.ax) / 4.0))
	for p in pts:
		draw_rect(Rect2(p.snapped(Vector2(4, 4)) - Vector2(2, 2), Vector2(4, 4)), Art.WIRE)
	# A spark runs along it now and then, so it catches the eye.
	var k := fmod(time * 0.8 + w.ax * 0.001, 1.6)
	if k < 1.0:
		var i := int(k * (pts.size() - 1))
		draw_rect(Rect2(pts[i].snapped(Vector2(4, 4)) - Vector2(4, 4), Vector2(8, 8)), Art.GOLD)


func _draw_runner() -> void:
	var rows: Array
	var bob := 0.0
	if not world.alive:
		rows = Art.courier("fall")
	elif not world.started:
		rows = Art.courier("run_b") if fmod(time, 3.0) > 0.2 else Art.courier("run_b", true)
	elif not world.grounded:
		rows = Art.courier("jump" if world.vy < 200.0 else "fall", world.vy < 0.0)
	else:
		var f := int(world.x / 34.0) % 4
		rows = Art.courier(["run_a", "run_b", "run_c", "run_d"][f], f % 2 == 0)
		bob = -4.0 if f % 2 == 1 else 0.0
	var pos := Vector2(world.x - 24.0, world.y - 64.0 + bob).snapped(Vector2(4, 4))
	if not world.alive and world.death != "fall":
		# Tumble backwards after a hit.
		var ang := -over_t * 9.0
		draw_set_transform(-((cam).snapped(Vector2(4, 4))) + pos + Vector2(24, 32), ang)
		Art.sprite(self, rows, Vector2(-24, -32))
		draw_set_transform(-(cam.snapped(Vector2(4, 4))))
		return
	Art.sprite(self, rows, pos)


func _draw_best_flag(vp: Vector2, c: Vector2) -> void:
	if best_m <= 0.0 or state == State.TITLE:
		return
	var fx := world.start_x + best_m * World.PX_PER_M
	if fx < c.x - 40 or fx > c.x + vp.x + 40:
		return
	var fy := world.ref_y
	for r in world.roofs:
		if fx >= r.x0 and fx <= r.x1:
			fy = r.y
	fx = snappedf(fx, 4.0)
	fy = snappedf(fy, 4.0)
	draw_rect(Rect2(fx, fy - 96, 4, 96), Art.WIRE)
	var wave := 4.0 if int(time * 4.0) % 2 == 0 else 0.0
	draw_rect(Rect2(fx + 4, fy - 96, 36, 20 + wave), Art.GOLD)
	draw_string(ThemeDB.fallback_font, Vector2(fx + 8, fy - 80), "BEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("0a0c1c"))


func _draw_speed_lines(vp: Vector2) -> void:
	if state != State.RUN or not world.alive:
		return
	var k := world.speed_frac()
	if k < 0.25:
		return
	for i in 10:
		var h := Art.hash3(i, 99)
		var y := float(h % 1000) / 1000.0 * vp.y
		var len := 60.0 + (h % 120)
		var x := fposmod(-(world.x * (1.2 + (h % 5) * 0.2)) + h, vp.x + len) - len
		draw_rect(Rect2(snappedf(x, 4), snappedf(y, 4), len, 4), Color(0.8, 0.85, 1.0, (k - 0.25) * 0.25))


func _draw_buttons(vp: Vector2) -> void:
	# Sound on/off, top right.
	var r := Rect2(vp.x - BUTTON - 16, 24, BUTTON, BUTTON)
	draw_rect(r, Color(0.04, 0.05, 0.12, 0.5))
	var o := r.position + Vector2(16, 20)
	draw_rect(Rect2(o + Vector2(0, 8), Vector2(8, 16)), Art.TEXT)
	for i in 4:
		draw_rect(Rect2(o + Vector2(8 + i * 4, 8 - i * 4), Vector2(4, 16 + i * 8)), Art.TEXT)
	if muted:
		for i in 5:
			draw_rect(Rect2(o + Vector2(28 + i * 4, 4 + i * 4), Vector2(4, 4)), Art.ORANGE)
			draw_rect(Rect2(o + Vector2(44 - i * 4, 4 + i * 4), Vector2(4, 4)), Art.ORANGE)
	else:
		draw_rect(Rect2(o + Vector2(30, 12), Vector2(4, 8)), Art.TEXT)
		draw_rect(Rect2(o + Vector2(38, 6), Vector2(4, 20)), Art.TEXT)
	# Pause, top left, while running.
	if state == State.RUN:
		var p := Rect2(16, 24, BUTTON, BUTTON)
		draw_rect(p, Color(0.04, 0.05, 0.12, 0.5))
		draw_rect(Rect2(p.position + Vector2(24, 20), Vector2(8, 32)), Art.TEXT)
		draw_rect(Rect2(p.position + Vector2(40, 20), Vector2(8, 32)), Art.TEXT)


# --- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	score_label = _label(layer, 64, Art.TEXT)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	score_label.offset_top = 24
	score_label.offset_bottom = 104
	meters_label = _label(layer, 28, Color("aab4e8"))
	meters_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	meters_label.offset_top = 100
	meters_label.offset_bottom = 136
	mult_label = _label(layer, 40, Art.ORANGE)
	mult_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mult_label.offset_top = 136
	mult_label.offset_bottom = 186
	best_label = _label(layer, 26, Art.GOLD)
	best_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	best_label.offset_top = 186
	best_label.offset_bottom = 222
	title_label = _label(layer, 84, Art.ORANGE)
	title_label.text = "ROOFTOP\nDASH"
	title_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 60
	title_label.offset_bottom = 260
	hint_label = _label(layer, 32, Art.TEXT)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_label.offset_top = 240
	hint_label.offset_left = 24
	hint_label.offset_right = -24
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = maxi(size / 5, 6)
	ls.outline_color = Color("0a0c1c")
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _set_hud_visible(v: bool) -> void:
	if not v:
		mult_label.text = ""
		best_label.text = ""
	for l in [score_label, meters_label, mult_label, best_label]:
		l.visible = v


func _update_hud() -> void:
	if state == State.TITLE:
		return
	score_label.text = str(world.score())
	meters_label.text = "%d m" % int(world.meters())
	var m := world.multiplier()
	mult_label.text = "x%d" % m if m > 1 and state == State.RUN else ""
	mult_label.scale = Vector2.ONE
	var left := best_m - world.meters()
	if state == State.RUN and runs > 0 and best_m > 0.0 and left > 0.0 and left <= 100.0:
		best_label.text = "%d m to your best" % ceili(left)
	elif state == State.RUN and world.meters() < 30.0 and runs <= 2:
		best_label.text = "Hold to jump higher"
	else:
		best_label.text = ""


# --- Sound and saving ------------------------------------------------------

func _set_muted(m: bool) -> void:
	muted = m
	sfx.muted = m
	if m:
		music.stop()
	elif state == State.RUN and world.alive:
		music.play()
	_save()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = cfg.get_value("run", "best_score", 0)
		best_m = cfg.get_value("run", "best_m", 0.0)
		muted = cfg.get_value("settings", "muted", false)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "best_score", best_score)
	cfg.set_value("run", "best_m", best_m)
	cfg.set_value("settings", "muted", muted)
	cfg.save(SAVE_PATH)
