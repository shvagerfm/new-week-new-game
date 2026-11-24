extends Node2D
## Rooftop Dash: a courier runs across night-city rooftops on their own; one
## button jumps, and holding it jumps higher. The rules live in world.gd;
## this script reads input, draws the city and runs the screens.

const SAVE_PATH := "user://rooftop_dash.cfg"
const RESTART_DELAY := 0.45   # after a fall, taps are ignored this long
const RUNNER_AT := 0.24       # the runner's place across the screen
const BUTTON := 88.0          # size of the corner buttons, about 48 pt on a phone
const EDGE := 40.0            # their gap from the sides, clear of rounded corners and notches

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
var stride := 0              # footfalls so far, for the step sound
var parcel_t := -9.0          # world time of the last parcel, for the rising pitch
var parcel_run := 0
var sink_y := INF            # where the courier went through a skylight
var land_t := -1.0          # world time of the last landing, for the squash frame

var touches := {}           # touch index -> true while a finger is down
var key_down := false
var tapped := false         # a press came in since the last tick
var particles: Array = []   # {p, v, life, max, col, size}
var popups: Array = []      # {p, text, life, col}

@onready var sfx: Sfx = $Sfx
var music: Music
var score_label: Label
var meters_label: Label
var mult_label: Label
var best_label: Label
var hint_label: Label
var screens: Screens
var results_shown := false
var final_score := 0        # the run's score and distance at the moment it ended
var final_m := 0.0
var rotate_label: Label


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load()
	screens = Screens.new()
	screens.main = self
	add_child(screens)
	_build_hud()
	music = Music.new()
	add_child(music)
	_set_muted(muted)
	_init_fullscreen()
	_new_world()
	_show_title()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if _fullscreen_button(event):
			return
		if event.pressed:
			if _portrait() or _corner_button(event.position):
				return
			touches[event.index] = true
			_on_press(event.position)
		else:
			touches.erase(event.index)
	elif event is InputEventKey and not event.echo:
		var k: Key = event.keycode
		if k in [KEY_SPACE, KEY_UP, KEY_W, KEY_ENTER, KEY_KP_ENTER, KEY_Z]:
			key_down = event.pressed
			if event.pressed and not _portrait():
				_on_press()
		elif event.pressed and k == KEY_C and CONTINUE_ON and state == State.OVER and results_shown:
			_continue()
		elif event.pressed and k == KEY_M:
			_set_muted(not muted)
		elif event.pressed and k == KEY_F and _can_fullscreen:
			_toggle_fullscreen()
		elif event.pressed and k in [KEY_ESCAPE, KEY_P]:
			if state == State.OVER and k == KEY_ESCAPE and results_shown:
				_to_menu()
			elif state == State.RUN:
				_pause()
			elif state == State.PAUSED:
				_resume()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.RUN:
		_pause()


func _held() -> bool:
	return key_down or not touches.is_empty()


## A phone held upright: the game needs the width, so it waits for a turn.
func _portrait() -> bool:
	var vp := get_viewport_rect().size
	return vp.y > vp.x


func _release_all() -> void:
	touches.clear()
	key_down = false
	tapped = false


# --- Fullscreen --------------------------------------------------------------
## A button left of the sound button fills the whole screen, hiding the
## browser's bars. Browsers only allow that inside a user gesture, and on a
## phone a touch counts as one only when the finger lifts, so the button acts
## on release. iPhone Safari has no fullscreen for pages, so there the button
## is hidden (Add to Home Screen is the way to lose the bars on an iPhone).
var _can_fullscreen := false
var _fs_armed := false


func _init_fullscreen() -> void:
	if OS.has_feature("web"):
		_can_fullscreen = bool(JavaScriptBridge.eval(
			"!!(document.fullscreenEnabled || document.webkitFullscreenEnabled)", true))
	else:
		_can_fullscreen = OS.has_feature("pc")


func _fullscreen_rect() -> Rect2:
	var vw := get_viewport_rect().size.x
	return Rect2(vw - 2.0 * BUTTON - EDGE - 24.0, 24, BUTTON, BUTTON)


## Handles a touch (or click) on the fullscreen button: armed on press,
## toggled on release. True if the event was the button's.
func _fullscreen_button(event: InputEventScreenTouch) -> bool:
	if not _can_fullscreen:
		return false
	var hit := _fullscreen_rect().grow(12).has_point(event.position)
	if event.pressed:
		_fs_armed = hit
		return hit
	if _fs_armed:
		_fs_armed = false
		if hit:
			_toggle_fullscreen()
			sfx.play("click")
		return true
	return false


func _is_fullscreen() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval(
			"!!(document.fullscreenElement || document.webkitFullscreenElement)", true))
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(function () {
			var d = document, el = d.documentElement;
			if (d.fullscreenElement || d.webkitFullscreenElement) {
				(d.exitFullscreen || d.webkitExitFullscreen).call(d);
				return;
			}
			var req = el.requestFullscreen || el.webkitRequestFullscreen;
			var p = req.call(el, {navigationUI: 'hide'});
			// On phones, keep it sideways while full screen, where allowed.
			if (p && p.then) p.then(function () {
				if (screen.orientation && screen.orientation.lock)
					screen.orientation.lock('landscape').catch(function () {});
			}).catch(function () {});
		})()""", true)
	elif _is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## True if the press landed on the sound or pause button (and was handled).
func _corner_button(pos: Vector2) -> bool:
	var vw := get_viewport_rect().size.x
	if Rect2(vw - BUTTON - EDGE, 24, BUTTON, BUTTON).grow(12).has_point(pos):
		_set_muted(not muted)
		sfx.play("click")
		return true
	if state in [State.RUN, State.PAUSED] and Rect2(EDGE, 24, BUTTON, BUTTON).grow(12).has_point(pos):
		if state == State.RUN:
			_pause()
		else:
			_resume()
		return true
	return false


## pos is where a tap landed; keys pass nothing and act like the main button.
func _on_press(pos := Vector2(-1, -1)) -> void:
	match state:
		State.RUN:
			tapped = true
		State.TITLE:
			_start_run()
		State.PAUSED:
			_resume()
		State.OVER:
			if over_t < RESTART_DELAY:
				return
			var b: String = screens.button_at(pos)
			if b == "menu":
				_to_menu()
			elif b == "continue":
				_continue()
			else:
				_new_world()
				_start_run()


func _to_menu() -> void:
	sfx.play("click")
	_new_world()
	_show_title()


# --- Screens ---------------------------------------------------------------

func _new_world() -> void:
	world = World.new()
	cam = Vector2(world.x - get_viewport_rect().size.x * RUNNER_AT, _cam_target_y())
	particles.clear()
	popups.clear()
	land_t = -1.0
	sink_y = INF
	passed_best = false
	new_best = false


func _start_run() -> void:
	_cued.clear()
	state = State.RUN
	world.start()
	_release_all()
	world.was_held = true  # the press that started the run isn't a jump
	runs += 1
	results_shown = false
	hint_label.hide()
	_set_hud_visible(true)
	sfx.play("click")
	if not muted:
		music.start()


func _show_title() -> void:
	state = State.TITLE
	results_shown = false
	_set_hud_visible(false)
	hint_label.hide()


func _pause() -> void:
	state = State.PAUSED
	_release_all()
	music.set_paused(true)
	hint_label.text = "Paused\n\nTap to keep running"
	hint_label.offset_top = 0
	hint_label.show()


func _resume() -> void:
	state = State.RUN
	world.was_held = true
	tapped = false
	music.set_paused(false)
	hint_label.hide()


func _game_over() -> void:
	state = State.OVER
	over_t = 0.0
	_release_all()
	# The body keeps tumbling after death, so freeze the numbers now.
	var sc := world.score()
	final_score = sc
	final_m = world.meters()
	if sc > best_score:
		best_score = sc
		new_best = true
	best_m = maxf(best_m, final_m)
	_save()
	var tw := create_tween()
	tw.tween_property(music, "pitch_scale", 0.5, 0.5)
	tw.parallel().tween_property(music, "volume_db", -40.0, 0.5)
	tw.tween_callback(music.stop)


## Continue after a death: for testing, so a tricky spot far into a run can
## be tried again without running there from the start. Set to false to
## take the button out.
const CONTINUE_ON := true


## Picks the run up again on the next safe roof past where it ended. The
## score carries on; the best score was already saved at the death.
func _continue() -> void:
	world.revive()
	if not world.alive:
		return
	sfx.play("click")
	state = State.RUN
	_release_all()
	world.was_held = true
	results_shown = false
	new_best = false
	sink_y = INF
	passed_best = best_m <= world.meters()
	_prev_pos = Vector2(world.x, world.y)
	hint_label.hide()
	_set_hud_visible(true)
	if not muted:
		music.start()


## The results panel itself is drawn by screens.gd; the top HUD steps aside.
func _show_results() -> void:
	results_shown = true
	_set_hud_visible(false)


# --- Loop ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if state == State.PAUSED:
		return
	if state == State.TITLE:
		_prev_pos = Vector2(world.x, world.y)
		world.step(false)
		return
	var was_alive := world.alive
	var run := state == State.RUN
	_prev_pos = Vector2(world.x, world.y)
	for e in world.step(_held() and run, tapped and run):
		_on_event(e)
	tapped = false
	if was_alive and not world.alive:
		_game_over()
	if state == State.RUN and world.alive:
		# A quiet footstep on every stride (each 3 run frames of 26 px).
		var s := int(world.x / 78.0)
		if s != stride:
			stride = s
			if world.grounded and world.t - land_t > 0.1:
				sfx.play("step", 0.08, -10.0)
		if best_m > 0.0 and not passed_best and world.meters() > best_m:
			passed_best = true
			_popup(Vector2(world.x, world.y - 160.0), "Best distance!", Art.GOLD)
			sfx.play("best")


## The world steps 60 times a second, but screens refresh at 60, 90, 120 or
## 144 Hz and browsers don't keep a steady beat. Drawing the latest step
## makes the city lurch (two steps in one frame, none in the next), so the
## runner and the camera are drawn between the last two steps instead.
var _prev_pos := Vector2.ZERO


func _render_pos() -> Vector2:
	var now := Vector2(world.x, world.y)
	if state == State.PAUSED or _prev_pos.distance_to(now) > 200.0:
		return now  # paused, or a new run: nothing to blend
	return _prev_pos.lerp(now, Engine.get_physics_interpolation_fraction())


func _process(delta: float) -> void:
	time += delta
	var vp := get_viewport_rect().size
	if _portrait() and state == State.RUN:
		_pause()
	_update_rotate_hint()
	if state != State.PAUSED:
		var rp := _render_pos()
		var tx := rp.x - vp.x * RUNNER_AT
		if world.alive:
			cam.x = tx
		cam.y = lerpf(cam.y, _cam_target_y(), 1.0 - exp(-3.5 * delta))
		# Keep the runner on screen when falling or jumping far from the roofs.
		cam.y = clampf(cam.y, rp.y - vp.y * 0.82, rp.y - vp.y * 0.25) if world.alive else cam.y
		shake = maxf(shake - delta * 40.0, 0.0)
		flash = maxf(flash - delta * 3.0, 0.0)
		_update_effects(delta)
	if state == State.OVER:
		over_t += delta
		if over_t >= RESTART_DELAY and not results_shown:
			_show_results()
	if state == State.RUN:
		music.set_speed(world.speed_frac())
	_update_hud()
	queue_redraw()


## The camera keeps the roofs about 60% down the screen, halfway between the
## roof the runner last stood on and the next one, so a drop is seen coming.
func _cam_target_y() -> float:
	var ahead := world.ref_y
	for r in world.roofs:
		if r.x0 > world.x and not r.has("hole_top"):   # the flat, not the tall roof above it
			ahead = r.base
			break
	var vp := get_viewport_rect().size
	var target := lerpf(world.ref_y, ahead, 0.5) - vp.y * 0.6
	# An awning or a cradle hangs below the roofs: lower the view in good
	# time so it is on screen well before the jump that needs it.
	for o in world.obstacles:
		if o.get("pad", false) and not o.used and o.x0 - world.x < vp.x * 1.4 and o.x1 > world.x - 100.0:
			target = maxf(target, o.y1 + 150.0 - vp.y)
	return target


func _on_event(e: Dictionary) -> void:
	match e.type:
		"jump":
			sfx.play("jump", 0.05)
			_dust(Vector2(world.x - 8, world.y), 5, -1.0)
		"land":
			land_t = world.t
			var impact: float = e.impact
			sfx.play("land", 0.08, linear_to_db(clampf(impact / 1400.0, 0.3, 1.0)))
			_dust(Vector2(world.x, world.y), int(clampf(impact / 120.0, 3, 12)), 1.0)
			if impact > 1000.0:
				shake = maxf(shake, (impact - 900.0) / 90.0)
		"grab":
			grab_t = world.t
			var names := {"bat": "BAT RIDE!", "laundry": "STEAM LIFT!", "awning": "BOING!",
				"zipline": "ZIPLINE!", "cradle": "GOING UP!", "crane": "CRANE!  TAP TO LET GO",
				"window": "WINDOW!  NOW TAP", "billboard": "BILLBOARD!"}
			_popup(Vector2(world.x, world.y - 170.0), "%s  +%d" % [names.get(e.kind, "NICE!"), e.points], Art.GOLD)
			match e.kind:
				"bat":
					sfx.play("squeak", 0.05)
				"laundry":
					sfx.play("cloth")
				"awning":
					sfx.play("jump", 0.0, 0.0, 0.7)
				"window":
					sfx.play("curtain")
				"billboard":
					sfx.play("land", 0.05)
				_:
					sfx.play("clang", 0.05, -6.0)
			sfx.play("best", 0.0, -8.0)
		"release":
			release_t = world.t
		"edge":
			sfx.play("edge", 0.0, 0.0, 1.0 + 0.12 * (e.mult - 2))
			_popup(Vector2(world.x, world.y - 140.0), "EDGE!  x%d" % e.mult, Art.ORANGE)
			_sparks(Vector2(e.x, e.y), 14)
		"combo_lost":
			sfx.play("combo_lost")
		"parcel":
			# Parcels close together climb a major scale.
			parcel_run = parcel_run + 1 if world.t - parcel_t < 1.2 else 0
			parcel_t = world.t
			var step: int = [0, 2, 4, 5, 7, 9, 12][mini(parcel_run, 6)]
			sfx.play("parcel", 0.0, 0.0, pow(2.0, step / 12.0))
			_popup(Vector2(e.x, e.y - 24.0), "+%d" % e.points, Art.GOLD)
			_sparks(Vector2(e.x, e.y), 8)
		"crumble":
			sfx.play("crumble")
		"collapse":
			_dust(Vector2(e.x, e.y), 16, 0.0)
			sfx.play("collapse", 0.05)
		"die":
			shake = 16.0
			if e.reason == "fall":
				sfx.play("fall")
			elif e.reason == "skylight":
				sfx.play("glass")
				sink_y = world.y
				sink_x = world.x
				_shards(Vector2(world.x, world.y), 16)
			else:
				# Each obstacle sounds like what it is.
				sfx.play({"wire": "zap", "antenna": "clang"}.get(e.reason, "hit"))
				flash = 1.0
				_sparks(Vector2(world.x, world.y - 30), 10)


# --- Effects ---------------------------------------------------------------

func _dust(at: Vector2, n: int, dir: float) -> void:
	for i in n:
		particles.append({"p": at + Vector2(randf_range(-14, 14), -4),
			"v": Vector2(randf_range(-160, 60) + dir * 60.0, randf_range(-140, -30)),
			"life": 0.0, "max": randf_range(0.3, 0.6), "col": Color("8da0d8"), "size": 4.0})


func _shards(at: Vector2, n: int) -> void:
	for i in n:
		particles.append({"p": at + Vector2(randf_range(-30, 30), -4),
			"v": Vector2(randf_range(-140, 140), randf_range(-320, -80)),
			"life": 0.0, "max": randf_range(0.4, 0.8), "col": Color("c9f0ff"), "size": 6.0})


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
	# Everything that follows the runner (the courier, a rope, a carried
	# trick) reads world.x and world.y, so they are set to the blended
	# position for the draw and put back after it.
	var now := Vector2(world.x, world.y)
	var rp := _render_pos()
	world.x = rp.x
	world.y = rp.y
	_draw_frame()
	world.x = now.x
	world.y = now.y


func _draw_frame() -> void:
	var vp := get_viewport_rect().size
	var off := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO
	# Whole pixels, not 4 px steps: at 400-800 px/s a 4 px grid makes the
	# scroll alternate between short and long jumps, which reads as judder.
	var c := (cam - off).round()
	_draw_sky(vp, c)
	draw_set_transform(-c)
	_cam_now = c
	_fx_back.clear()
	_fx_front.clear()
	_draw_backdrop(c, vp)
	_draw_scene_fx(_fx_back)   # the falling pot and the disco lights go behind the roofs
	_fx_back.clear()
	_draw_best_flag(vp, c)
	for w in world.wires:
		_draw_wire_posts(w)
	for r in world.roofs:
		_draw_roof(r, c, vp)
	_draw_scene_fx(_fx_back)
	for o in world.obstacles:
		_draw_obstacle(o)
	for p in world.parcels:
		if not p.taken:
			_draw_parcel(p)
	_draw_runner(c)
	for w in world.wires:
		_draw_wire(w)
	_draw_scene_fx(_fx_front)
	for p in particles:
		var a: float = 1.0 - p.life / p.max
		var col: Color = p.col
		col.a = a
		draw_rect(Rect2(p.p.snapped(Vector2(4, 4)), Vector2(p.size, p.size)), col)
	var font := screens.bold
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
	if _portrait():
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.04, 0.1, 0.8))
	elif state == State.OVER or state == State.PAUSED or state == State.TITLE:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.03, 0.04, 0.1, 0.55 if state != State.OVER else clampf(over_t * 2.0, 0.0, 0.6)))
	_draw_buttons(vp)


# --- Art from sprites/ -----------------------------------------------------
## Everything on the gameplay layer is pixel art drawn at 2x. The skylines are
## already full-screen paintings, drawn 1:1.
const S := 2.0
const TILES: Texture2D = preload("res://sprites/rooftop.png")
const SKY_FAR: Texture2D = preload("res://sprites/skyline-far.png")
const SKY_MID: Texture2D = preload("res://sprites/skyline-middle.png")
const SKY_NEAR: Texture2D = preload("res://sprites/skyline-near.png")
const TILE := 64.0
## In the roof tiles the walkable surface is 26 px down; rows 26-35 are the
## coping. The facade below it comes from facade.png.
const ROOF_TOP := 26.0
const WIRE_DARK := Color("1d2347")
const WIRE_EDGE := Color("9aa9ee")

var _sky_fill := {}   # texture -> [top colour, bottom colour] for the edges


func _layer_fill(tex: Texture2D) -> Array:
	if not _sky_fill.has(tex):
		var img := tex.get_image()
		_sky_fill[tex] = [img.get_pixel(4, 2), img.get_pixel(4, img.get_height() - 2)]
	return _sky_fill[tex]


func _draw_sky(vp: Vector2, c: Vector2) -> void:
	var dy := c.y - _cam_rest()
	# Far: sky, moon and haze. Slow, because the moon repeats every 1280 px.
	_draw_layer(SKY_FAR, vp, c.x * 0.04, clampf(-dy * 0.03, -40, 40), Color.WHITE, MOON)
	_draw_layer(SKY_MID, vp, c.x * 0.15, clampf(-dy * 0.08, -90, 90) + 70.0, Color(0.8, 0.8, 0.9))
	# Near is darkened so it never reads as a roof you can land on.
	_draw_layer(SKY_NEAR, vp, c.x * 0.35, clampf(-dy * 0.15, -120, 120) + 170.0, Color(0.55, 0.55, 0.72))
	# The streets far below fade to black, so the gaps read as drops.
	var deep := roundf(vp.y * 0.72 - dy * 0.3)
	for i in 8:
		draw_rect(Rect2(0, deep + i * 24, vp.x, vp.y), Color(0.01, 0.015, 0.05, 0.14))


## Tiles a skyline layer across the screen, scrolled by sx, moved down by oy,
## and fills above and below it with its edge colours. A layer is painted for
## a 720 px tall screen: a 1280x720 one is drawn 1:1, a 640x360 one at 2x.
## On a wide phone screen two copies of the far layer show at once, so every
## other copy has its moon covered with a patch of plain sky from further right.
const MOON := Rect2(141, 61, 84, 86)
const MOON_PATCH_DX := 300.0


func _draw_layer(tex: Texture2D, vp: Vector2, sx: float, oy: float, tint: Color,
		moon := Rect2()) -> void:
	var k := roundf(720.0 / tex.get_height())
	var w := tex.get_width() * k
	var h := tex.get_height() * k
	var top := roundf((oy + vp.y - h) / k) * k  # bottom-aligned to the screen
	var fill := _layer_fill(tex)
	if top > 0.0 and fill[0].a > 0.5:
		draw_rect(Rect2(0, 0, vp.x, top), fill[0] * tint)
	var s := roundf(sx / k) * k
	var x := -fposmod(s, w)
	var n := floori(s / w)
	while x < vp.x:
		draw_texture_rect(tex, Rect2(x, top, w, h), false, tint)
		if moon.has_area() and n % 2 != 0:
			draw_texture_rect_region(tex, Rect2(x + moon.position.x * k, top + moon.position.y * k,
				moon.size.x * k, moon.size.y * k), Rect2(moon.position + Vector2(MOON_PATCH_DX, 0), moon.size), tint)
		x += w
		n += 1
	if top + h < vp.y:
		draw_rect(Rect2(0, top + h, vp.x, vp.y - top - h), fill[1] * tint)


## Where the camera sits when the runner is on the first roof, so the
## skyline starts at the same place every run.
func _cam_rest() -> float:
	return -get_viewport_rect().size.y * 0.6


## Draws one horizontal strip of a roof from x0 to x1: the left-end tile,
## middle tiles, and the right-end tile, using source rows sy..sy+sh.
func _roof_strip(x0: float, x1: float, y: float, sy: float, sh: float, mid_col: int,
		tint := Color.WHITE) -> void:
	_tint = tint
	var tw := TILE * S
	var w := x1 - x0
	var h := sh * S
	if w < tw * 2.0:
		var half := roundf(w * 0.5 / S) * S
		_tile(Rect2(x0, y, half, h), Rect2(0, sy, half / S, sh))
		_tile(Rect2(x0 + half, y, w - half, h), Rect2(2 * TILE + TILE - (w - half) / S, sy, (w - half) / S, sh))
		return
	_tile(Rect2(x0, y, tw, h), Rect2(0, sy, TILE, sh))
	var x := x0 + tw
	while x < x1 - tw:
		var part := minf(tw, x1 - tw - x)
		_tile(Rect2(x, y, part, h), Rect2(mid_col * TILE, sy, part / S, sh))
		x += part
	_tile(Rect2(x1 - tw, y, tw, h), Rect2(2 * TILE, sy, TILE, sh))


var _tint := Color.WHITE


func _tile(dst: Rect2, src: Rect2) -> void:
	draw_texture_rect_region(TILES, dst, src, _tint)


func _draw_roof(r: Dictionary, c: Vector2, vp: Vector2) -> void:
	if r.get("inside", false):
		_draw_flat(r)
		return
	if r.has("balcony"):
		_draw_balcony(r, c, vp)
		return
	var y := roundf(r.y / S) * S
	if r.crumble and r.t >= 0.0 and r.vy == 0.0:
		y += S * float(randi_range(-1, 1))
	var x0: float = r.x0
	var x1: float = r.x1
	var bottom := c.y + vp.y + 8.0
	var mid := 3 if r.crumble else 1
	# Crumbling roofs are cracked and a little rust-red, so they read early.
	var tint := Color(1.25, 0.82, 0.8) if r.crumble else Color.WHITE
	# The roof itself: the coping, then the facade floor after floor, down
	# past the bottom of the screen.
	_roof_strip(x0, x1, y, ROOF_TOP, CAP_H, mid, tint)
	_draw_facade(r, y + CAP_H * S, bottom, tint, c, vp)
	# The bonus edge: land in this strip to grow the multiplier. It glows on
	# roofs still ahead, with chevrons pointing at the edge.
	if x0 > world.x and state != State.TITLE and not r.has("hole_top"):
		var pulse := 0.55 + 0.35 * sin(time * 6.0)
		var zone := World.EDGE_ZONE
		draw_rect(Rect2(x0, y - 6, zone, 6), Color(Art.GOLD, pulse))
		draw_rect(Rect2(x0, y - 2, zone, 4), Color(Art.ORANGE, pulse))
		for k in 3:
			var cx := x0 + 6 + k * 12
			draw_rect(Rect2(cx, y - 16 - (k % 2) * 0, 4, 4), Color(Art.GOLD, pulse))
			draw_rect(Rect2(cx - 4, y - 20, 4, 4), Color(Art.GOLD, pulse * 0.8))
			draw_rect(Rect2(cx - 4, y - 12, 4, 4), Color(Art.GOLD, pulse * 0.8))


# --- Facades and window scenes ---------------------------------------------
## Below the coping (rows 26-35 of rooftop.png) each building is facade.png:
## 64x64 cells, one floor each, with a see-through window opening that
## shows a room from window-rooms.png, or on some roofs a little animated
## scene from window-scenes.png. The scenes never hurt; they are there to pull
## the eye away from the roofs.
const FACADE: Texture2D = preload("res://sprites/facade.png")
const ROOMS: Texture2D = preload("res://sprites/window-rooms.png")
const SCENES: Texture2D = preload("res://sprites/window-scenes.png")
const PROPS: Texture2D = preload("res://sprites/window-props.png")
const CAP_H := 10.0
const WIN := Rect2(16, 12, 32, 40)     # the opening in a window cell
const WIN_W := 32.0
const WIN_H := 40.0
const SCENES_FROM_M := 150.0            # no scenes on the first roofs
const SCENE_EVERY_M := 350.0            # at most one scene per stretch this long
const SCENE_CHANCE := 75                # percent of stretches that get one
enum Scene {CAT, DISCO, GRANNY, COUPLE, GRANDPA, DOG, MIRROR}
const DISCO_COLS := [Color("ff4d5e"), Color("4a78ff"), Color("ffd27a"), Color("4caf50"), Color("8a66b8"), Color("ff8a3d")]

## Effects the scenes throw out, drawn over the roofs (back) or over the
## courier (front). Rebuilt every frame.
var _fx_back: Array = []
var _fx_front: Array = []


## The facade cells of a building, left to right: [x, width, column]. Column
## 0 and 3 are the ends, 1 a window, 2 plain wall.
func _facade_cells(r: Dictionary) -> Array:
	var cw := TILE * S
	var x0: float = r.x0
	var x1: float = r.x1
	var w := x1 - x0
	if w < cw * 2.0:
		var half := roundf(w * 0.5 / S) * S
		return [[x0, half, 0], [x0 + half, w - half, 3]]
	var cells := [[x0, cw, 0]]
	var n := floori((w - cw * 2.0) / cw)
	var extra := w - cw * 2.0 - n * cw
	var x := x0 + cw
	if extra > 0.0:
		cells.append([x, extra, 2])
		x += extra
	for i in n:
		# Mostly windows, now and then a stretch of plain brick.
		cells.append([x, cw, 2 if Art.hash3(int(x0), i, 5) % 4 == 0 else 1])
		x += cw
	cells.append([x1 - cw, cw, 3])
	return cells


func _draw_facade(r: Dictionary, top: float, bottom: float, tint: Color, c: Vector2, vp: Vector2) -> void:
	var cw := TILE * S
	var cells := _facade_cells(r)
	var row := 64.0 if r.crumble else 0.0
	var floor_i := 0
	var yy := top
	while yy < bottom:
		if yy + cw > c.y:
			for i in cells.size():
				var cell: Array = cells[i]
				var x: float = cell[0]
				var w: float = cell[1]
				if x + w < c.x or x > c.x + vp.x:
					continue
				var col: int = cell[2]
				# The right end and a short left end are cut from the cell's far side.
				var sx := col * TILE + (TILE - w / S if col == 3 else 0.0)
				if col == 1:
					var at := Vector2(x + WIN.position.x * S, yy + WIN.position.y * S)
					_draw_room(at, Art.hash3(int(r.x0), i, floor_i))
				draw_texture_rect_region(FACADE, Rect2(x, yy, w, cw), Rect2(sx, row, w / S, TILE), tint)
		yy += cw
		floor_i += 1


## Scenes are rare so they surprise: the run is cut into stretches of
## SCENE_EVERY_M, and most stretches get one, at a spot somewhere in the
## middle. The kinds take turns, so the same one never comes twice in a row.
## Returns [spot in metres, kind], or [] for a stretch without one.
func _scene_in(b: int) -> Array:
	var hb := Art.hash3(b, int(world.rng.seed), 777)
	if b < 0 or hb % 100 >= SCENE_CHANCE:
		return []
	var spot := b * SCENE_EVERY_M + SCENE_EVERY_M * (0.15 + 0.7 * float((hb >> 8) % 1000) / 1000.0)
	if spot < SCENES_FROM_M:
		return []
	return [spot, (b * 3 + Art.hash3(int(world.rng.seed), 31) % Scene.size()) % Scene.size()]


# --- The scene building ------------------------------------------------------
## Each scene plays in one big window of a building in the background, between
## the skyline and the roofs. It drifts by at half the roofs' speed, so it
## stays on screen twice as long, and its window sits above the roof line.
const BACK_PAR := 0.5                    # how fast it moves, against the roofs
const BIG := Vector2(128, 160)           # the window opening, on screen
const BACK_CELLS := 3                    # the building is three facade cells wide
const BACK_TINT := Color(0.62, 0.62, 0.78)


## Draws the scene buildings on screen. Called under the camera transform; a
## point p on screen is drawn at p + c.
func _draw_backdrop(c: Vector2, vp: Vector2) -> void:
	var runner_sx := vp.x * RUNNER_AT
	var runner_wx := c.x + runner_sx
	var m := (runner_wx - world.start_x) / World.PX_PER_M
	var b0 := int(m / SCENE_EVERY_M)
	var cw := TILE * S
	var bw := cw * BACK_CELLS
	# The window sits below the score and above the roof line.
	var dy := clampf((c.y - _cam_rest()) * 0.25, -30.0, 30.0)
	var win_top := roundf(vp.y * 0.27 - dy)
	for b in range(b0 - 2, b0 + 4):
		var sc := _scene_in(b)
		if sc.is_empty():
			continue
		var wx: float = world.start_x + sc[0] * World.PX_PER_M
		var cx := roundf((wx - runner_wx) * BACK_PAR + runner_sx)
		if cx + bw < -40.0 or cx - bw > vp.x + 40.0:
			continue
		var left := cx - bw * 0.5
		var top := win_top - 72.0
		# The wall: an end cell, plain brick, an end cell, floor after floor.
		var yy := top
		while yy < vp.y:
			for i in BACK_CELLS:
				var col := 0 if i == 0 else (3 if i == BACK_CELLS - 1 else 2)
				draw_texture_rect_region(FACADE, Rect2(c + Vector2(left + i * cw, yy), Vector2(cw, cw)),
					Rect2(col * TILE, 0, TILE, TILE), BACK_TINT)
			yy += cw
		draw_rect(Rect2(c + Vector2(left - 8, top - 12), Vector2(bw + 16, 12)), Color("2a2440"))
		# The big window: warm light spilling out, a dark frame, the scene, a sill.
		var at := c + Vector2(cx - BIG.x * 0.5, win_top)
		draw_rect(Rect2(at, BIG).grow(28), Color(1.0, 0.78, 0.4, 0.10))
		draw_rect(Rect2(at, BIG).grow(10), Color("1a1420"))
		draw_rect(Rect2(at, BIG).grow(6), Color("5a4a6a"))
		_draw_scene(sc[1], at, {"x0": float(b * 1000 + 7)}, BIG, world.speed() * BACK_PAR)
		draw_rect(Rect2(at + Vector2(-18, BIG.y + 6), Vector2(BIG.x + 36, 12)), Color("8a7a9a"))
		draw_rect(Rect2(at + Vector2(-18, BIG.y + 18), Vector2(BIG.x + 36, 6)), Color("3a3050"))


func _draw_room(at: Vector2, h: int) -> void:
	var lit := h % 100 < 55
	var k := (h >> 7) % 4 if lit else 4
	draw_texture_rect_region(ROOMS, Rect2(at, Vector2(WIN_W, WIN_H) * S), Rect2(k * WIN_W, 0, WIN_W, WIN_H))
	_draw_glass(at, 0.10 if lit else 0.06)


## A pale streak across the glass, the same on every window.
func _draw_glass(at: Vector2, a: float) -> void:
	draw_rect(Rect2(at + Vector2(10, 0), Vector2(8, WIN_H * S)), Color(1, 1, 1, a))
	draw_rect(Rect2(at + Vector2(24, 0), Vector2(4, WIN_H * S)), Color(1, 1, 1, a * 0.6))


## Draws one window scene at the opening's top-left corner and queues what
## it throws out. Most scenes play as the courier comes near, so they peak
## when the eye should be on the next jump.
func _draw_scene(kind: int, at: Vector2, r: Dictionary, size := Vector2(WIN_W, WIN_H) * S,
		spd := 0.0) -> void:
	if spd <= 0.0:
		spd = world.speed()
	var k := size.x / (WIN_W * S)     # offsets below are for a 64x80 window
	var mid := at + size * 0.5
	var d := mid.x - world.x          # how far ahead of the courier
	var f := 0
	var shake := Vector2.ZERO
	match kind:
		Scene.CAT:
			f = clampi(int((1100.0 - d) / 110.0), 0, 5)
			if f >= 2:
				_cue(r, "meow", -4.0)
			if f >= 4:
				var t := (660.0 - d) / maxf(spd, 1.0)
				_fx_back.append({"kind": "pot", "from": at + Vector2(52, 66) * k, "t": t})
				if t > 0.75:
					_cue(r, "pot", -4.0)
		Scene.DISCO:
			f = int(time * 7.0) % 6
			if absf(d) < 1100.0:
				_fx_back.append({"kind": "disco", "at": mid, "seed": int(r.x0)})
				# A bar of music, again each bar while it is near.
				_cue(r, "disco", -7.0, "%d" % int(time / 2.0))
		Scene.GRANNY:
			f = clampi(int((900.0 - d) / 100.0), 0, 5)
			if f >= 3 and f < 5:
				_fx_front.append({"kind": "glint", "at": at + Vector2(30, 40) * k})
			if f == 5 and d > -500.0:
				_fx_front.append({"kind": "spot", "at": mid})
				_cue(r, "granny", -3.0)
		Scene.COUPLE:
			f = clampi(int((1000.0 - d) / 100.0), 0, 5)
			if f >= 4:
				_fx_front.append({"kind": "pillow", "from": at + Vector2(16, 24) * k, "t": (600.0 - d) / maxf(spd, 1.0)})
				_cue(r, "pillow", -3.0)
		Scene.GRANDPA:
			f = int(time * 5.0) % 6
			_fx_back.append({"kind": "tv", "at": mid})
			if (f == 1 or f == 4) and absf(d) < 900.0:
				_cue(r, "grunt", -6.0, "%d" % int(time * 5.0))
		Scene.DOG:
			if d > 700.0:
				f = 0
			elif d > 600.0:
				f = 1
			elif d > 150.0:
				f = 2 + int(time * 8.0) % 2
				_cue(r, "woof", -3.0, "%d" % int(time * 4.0))
				shake = Vector2(S * (int(time * 30.0) % 2), 0)
				_fx_front.append({"kind": "woof", "at": at + Vector2(size.x * 0.5, -40), "k": int(time * 8.0) % 2})
			else:
				f = 4 if d > 0.0 else 5
		Scene.MIRROR:
			# Poses for the mirror, spots the courier, then shuts the curtain.
			f = clampi(int((1000.0 - d) / 110.0), 0, 5)
			if f >= 4:
				_cue(r, "eek", -4.0)
			if f >= 5:
				_cue(r, "curtain", -4.0)
	# Frames are 32x40 now; a sheet drawn at 64x80 drops in as it is.
	var fw := SCENES.get_width() / 6.0
	var fh := SCENES.get_height() / float(Scene.size())
	draw_texture_rect_region(SCENES, Rect2(at + shake, size), Rect2(f * fw, kind * fh, fw, fh))
	draw_rect(Rect2(at + Vector2(10, 0) * k, Vector2(8 * k, size.y)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(at + Vector2(24, 0) * k, Vector2(4 * k, size.y)), Color(1, 1, 1, 0.07))


## Plays a scene's sound once per window (or once per beat, with a key that
## changes), however many frames the scene is drawn.
var _cued := {}


func _cue(r: Dictionary, sound: String, volume_db := 0.0, beat := "") -> void:
	var key := "%d:%s:%s" % [int(r.x0), sound, beat]
	if _cued.has(key):
		return
	if _cued.size() > 200:
		_cued.clear()
	_cued[key] = true
	sfx.play(sound, 0.04, volume_db)


func _prop(cell: Vector2i, center: Vector2, scale := S, rot := 0.0, mod := Color.WHITE) -> void:
	var size := Vector2(16, 16) * scale
	if rot == 0.0:
		draw_texture_rect_region(PROPS, Rect2((center - size * 0.5).round(), size), Rect2(cell * 16, Vector2(16, 16)), mod)
		return
	draw_set_transform(-_cam_now + center, rot)
	draw_texture_rect_region(PROPS, Rect2(-size * 0.5, size), Rect2(cell * 16, Vector2(16, 16)), mod)
	draw_set_transform(-_cam_now)


var _cam_now := Vector2.ZERO


func _draw_scene_fx(list: Array) -> void:
	for e in list:
		match e.kind:
			"pot":
				# Falls from the sill and breaks on the roof below, or is lost in the gap.
				var t: float = e.t
				var p: Vector2 = e.from + Vector2(t * 40.0, 0.5 * 1500.0 * t * t)
				if t < 1.4:
					_prop(Vector2i(int(t * 8.0) % 2, 0), p, S * 1.5)
			"disco":
				for i in 7:
					var a: float = time * (0.9 + i * 0.13) + i * 1.9 + e.seed
					var p: Vector2 = e.at + Vector2(sin(a) * 300.0, cos(a * 1.3) * 160.0 - 40.0)
					var col: Color = DISCO_COLS[i % DISCO_COLS.size()]
					col.a = 0.55
					_prop(Vector2i(2, 1), p.snapped(Vector2(4, 4)), S * 3.0, 0.0, col)
			"tv":
				var a: float = 0.10 + 0.07 * sin(time * 23.0) + 0.05 * sin(time * 7.0)
				draw_rect(Rect2(e.at - Vector2(100, 90), Vector2(200, 190)), Color(0.45, 0.65, 1.0, a))
			"glint":
				if int(time * 6.0) % 2 == 0:
					_prop(Vector2i(5, 1), e.at, S * 1.5)
			"spot":
				# Granny's lamp: a wide warm beam that follows the courier.
				var feet := Vector2(world.x, world.y)
				var pts := PackedVector2Array([e.at + Vector2(-20, -30), e.at + Vector2(20, -30),
					feet + Vector2(110, 0), feet + Vector2(-110, 0)])
				draw_colored_polygon(pts, Color(1.0, 0.85, 0.45, 0.22))
			"pillow":
				# Thrown out of the window, it tumbles towards the screen and grows.
				var t: float = e.t
				if t < 1.1:
					var p: Vector2 = e.from + Vector2(-t * 520.0, -t * 260.0 + t * t * 120.0)
					var a: float = clampf((1.1 - t) * 3.0, 0.0, 1.0)
					_prop(Vector2i(3 + int(t * 10.0) % 4, 0), p, S * (1.5 + t * 9.0), t * 5.0, Color(1, 1, 1, a))
					for i in 3:
						_prop(Vector2i(7, 0), p + Vector2(i * 50 - 30, 40 + t * 200.0 * (i + 1)), S * 1.5, t * 3.0 + i, Color(1, 1, 1, a))
			"woof":
				_prop(Vector2i(3 + e.k, 1), e.at + Vector2(0, -6 * e.k), S * 2.0)


# --- Puzzle points and skylights -------------------------------------------
## Each comes from its own sheet in sprites/, drawn at 2x. The art list says
## what each frame is and where its anchor points are.
const TRICKS: Texture2D = preload("res://sprites/courier-tricks.png")
const BAT_TEX: Texture2D = preload("res://sprites/bat.png")
const STEAM_TEX: Texture2D = preload("res://sprites/steam.png")
const LAUNDRY_TEX: Texture2D = preload("res://sprites/laundry.png")
const SKYLIGHT_TEX: Texture2D = preload("res://sprites/skylight.png")
const AWNING_TEX: Texture2D = preload("res://sprites/awning.png")
const ZIP_TEX: Texture2D = preload("res://sprites/zipline.png")
const CRADLE_TEX: Texture2D = preload("res://sprites/cradle.png")
const CRANE_TEX: Texture2D = preload("res://sprites/crane.png")
## courier-tricks.png frames.
const T_HANG := 0
const T_CHUTE := 2
const T_SQUAT := 4
const T_LAUNCH := 5
const T_CRADLE := 6
const ROPE := Color("c9d4ff")
const ROPE_DARK := Color("1d2347")

var grab_t := -9.0            # world time of the last grab, for squash frames
var release_t := -9.0


## Draws a region of a sheet at 2x with its top-left at pos.
func _sheet(tex: Texture2D, src: Rect2, pos: Vector2, mod := Color.WHITE) -> void:
	draw_texture_rect_region(tex, Rect2((pos / S).round() * S, src.size * S), src, mod)


## A rope or cable from a to b, one art pixel thick.
func _rope(a: Vector2, b: Vector2, col := ROPE) -> void:
	var n := maxi(int(a.distance_to(b) / S), 1)
	for i in n + 1:
		var q := ((a.lerp(b, float(i) / n)) / S).round() * S
		draw_rect(Rect2(q, Vector2(S, S)), col)


## Puzzle points glow gold and sparkle until used, so a secret trick is
## spotted a screen ahead even when it is small or dark against the night.
func _draw_trick_glow(o: Dictionary) -> void:
	var c := Vector2((o.x0 + o.x1) * 0.5, (o.y0 + o.y1) * 0.5) as Vector2
	var r: float = minf(maxf(o.x1 - o.x0, o.y1 - o.y0) * 0.6 + 26.0, 80.0)
	var pulse: float = 0.5 + 0.5 * sin(time * 4.0 + o.x0 * 0.01)
	for i in 3:
		draw_circle(c, r * (1.0 - i * 0.25), Color(1.0, 0.82, 0.35, 0.07 + 0.05 * pulse))
	for i in 3:
		var a: float = time * 1.6 + i * TAU / 3.0 + o.x0
		var p := (c + Vector2(cos(a), sin(a)) * r).snapped(Vector2(4, 4))
		var sz := 8.0 if int(time * 6.0 + i) % 2 == 0 else 4.0
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Art.GOLD)


func _draw_obstacle(o: Dictionary) -> void:
	if (o.get("grab", false) or o.kind in ["window", "billboard"]) and not o.used:
		_draw_trick_glow(o)
	match o.kind:
		"window":
			return
		"furniture":
			_draw_furniture(o)
			return
		"rack":
			_draw_rack(o)
			return
		"billboard":
			_draw_billboard(o)
			return
		"skylight":
			_draw_skylight(o)
			return
		"bat":
			if not o.used:
				var bob := roundf(sin(time * 5.0 + o.x0) * 3.0) * 2.0
				var at := Vector2((o.x0 + o.x1) * 0.5, (o.y0 + o.y1) * 0.5 + bob)
				_sheet(BAT_TEX, Rect2(32 * (int(time * 8.0) % 2), 0, 32, 24), at - Vector2(16, 12) * S)
			return
		"laundry":
			_draw_steam(o)
			_draw_laundry(o)
			return
		"awning":
			_draw_awning(o)
			return
		"zipline":
			_draw_zipline(o)
			return
		"cradle":
			_draw_cradle(o)
			return
		"crane":
			_draw_crane(o)
			return
	if o.kind == "ac":
		# Cell (0, 64); the unit itself spans x 12-51, y 28-59 in the cell.
		draw_texture_rect_region(TILES, Rect2(o.x0 - 12 * S, o.y1 - 59 * S, TILE * S, TILE * S),
			Rect2(0, TILE, TILE, TILE))
		return
	# The antenna is stretched to its full height by repeating a stretch of
	# plain pole: mast and crossbars on top, lattice and base at the bottom.
	var cx: float = (o.x0 + o.x1) * 0.5
	var sx := TILE + 16.0          # cell x 16..48 holds the antenna
	var w := 32.0 * S
	var x := roundf(cx / S) * S - 16.0 * S
	var top_h := 15.0             # rows 4-19
	var base_h := 35.0            # rows 24-59
	var y0: float = o.y0
	var y1: float = o.y1
	# Brightened a little so the thin mast stands out against the night sky.
	var lift := Color(1.45, 1.45, 1.6)
	draw_texture_rect_region(TILES, Rect2(x, y0, w, top_h * S), Rect2(sx, TILE + 4, 32, top_h), lift)
	var yy := y0 + top_h * S
	var pole_end := y1 - base_h * S
	while yy < pole_end:
		var part := minf(5.0 * S, pole_end - yy)
		draw_texture_rect_region(TILES, Rect2(x, yy, w, part), Rect2(sx, TILE + 19, 32, part / S), lift)
		yy += part
	draw_texture_rect_region(TILES, Rect2(x, pole_end, w, base_h * S), Rect2(sx, TILE + 24, 32, base_h), lift)
	if int(time * 2.0) % 2 == 0:
		draw_rect(Rect2(cx - 10, y0 - 6, 20, 20), Color(1, 0.55, 0.2, 0.3))


## A glass roof light: left end, middle tiles, right end, 32 px tall, with
## the glass 4 px down. A glint runs across it.
func _draw_skylight(o: Dictionary) -> void:
	var y: float = o.y1 - 28.0
	var x0: float = o.x0 - 8.0
	var x1: float = o.x1 + 8.0
	draw_rect(Rect2(x0 - 4, o.y1 - 6, x1 - x0 + 8, 14), Color(1, 0.75, 0.4, 0.35))
	var broken: bool = not world.alive and world.death == "skylight" and world.x > o.x0 and world.x < o.x1
	var x := x0
	while x < x1:
		var cell := 1
		if x == x0:
			cell = 0
		elif x + 32.0 >= x1:
			cell = 2
		if broken and absf(x + 16.0 - sink_x) < 16.0:
			cell = 3
		var w := minf(32.0, x1 - x)
		_sheet(SKYLIGHT_TEX, Rect2(cell * 16, 0, w / S, 16), Vector2(x, y))
		x += 32.0
	var g := fposmod(time * 160.0 + o.x0, (x1 - x0) + 160.0) - 80.0
	if g > 8.0 and g < x1 - x0 - 24:
		draw_rect(Rect2(x0 + snappedf(g, 4), y + 8, 8, 16), Color(1, 1, 1, 0.6))
		draw_rect(Rect2(x0 + snappedf(g, 4) + 12, y + 8, 4, 16), Color(1, 1, 1, 0.4))


var sink_x := 0.0


## The washing line (laundry.png, left part) centred over the grab zone, its
## line at the top; the posts are carried on down to the roof.
func _draw_laundry(o: Dictionary) -> void:
	var cx: float = (o.x0 + o.x1) * 0.5
	var pos := Vector2(cx - 48.0 * S, o.y0 - 3.0 * S)
	var floor_y: float = o.y0 + World.LAUNDRY_LINE
	for px in [1.0, 92.0]:
		draw_rect(Rect2(pos.x + px * S, pos.y + 48.0 * S, 3.0 * S, floor_y - pos.y - 48.0 * S), ROPE_DARK)
	var sway := roundf(sin(time * 2.5) * 1.0) * S
	if o.used:
		# The sheet is gone: it is the courier's parachute now.
		_sheet(LAUNDRY_TEX, Rect2(0, 0, 58, 48), pos + Vector2(sway, 0))
		_sheet(LAUNDRY_TEX, Rect2(88, 0, 8, 48), pos + Vector2(88.0 * S, 0))
	else:
		_sheet(LAUNDRY_TEX, Rect2(0, 0, 96, 48), pos + Vector2(sway, 0))


const INK_DARK := Color("0a0c1c")


## The vent at the foot of the wall (steam.png cell 0), puffing steam up the
## whole height of the wall with the puff frames, so the way up can be seen
## before the player knows how to use it.
func _draw_steam(o: Dictionary) -> void:
	var vx: float = o.vent
	var floor_y: float = o.y0 + World.LAUNDRY_LINE
	_sheet(STEAM_TEX, Rect2(0, 0, 32, 32), Vector2(vx - 16.0 * S, floor_y - 32.0 * S))
	var height := World.WALL_RISE + 160.0
	for i in 14:
		var k := fposmod(time * 0.55 + i / 14.0, 1.0)
		var px := vx + sin(k * 9.0 + i) * 14.0 - k * 50.0
		var py := floor_y - 50.0 - k * height
		var f := 1 + mini(int(k * 4.0), 3)
		var size := Vector2(32, 32) * S * (0.7 + k * 0.9)
		var r := Rect2((Vector2(px, py) - size * 0.5).snapped(Vector2(S, S)), size.snapped(Vector2(S, S)))
		draw_texture_rect_region(STEAM_TEX, r, Rect2(f * 32, 0, 32, 32), Color(1, 1, 1, 0.8 * (1.0 - k * 0.6)))


# --- The flat ------------------------------------------------------------
## A flat cut through a tall building: wallpaper, a wooden floor, lamps on
## the low ceiling, an open window at each end with its curtains blowing.
## Drawn over the building's facade, before the furniture and the courier.
const FLAT_WALL := Color("4a2f45")
const FLAT_STRIPE := Color("553650")
const FLAT_DADO := Color("3a2336")
const FLAT_FLOOR := Color("7a4a2a")
const FLAT_FLOOR_HI := Color("b07040")
const FLAT_CEIL := Color("2a1c2c")
const FLAT_FRAME := Color("c8b8a0")
const CURTAIN := Color("d0605a")
const CURTAIN_DARK := Color("8a3a40")


func _draw_flat(f: Dictionary) -> void:
	var x0: float = f.x0
	var x1: float = f.x1
	var top: float = f.ceil
	var fl: float = f.y
	var h := fl - top
	# Warm light spills out of both windows, so the way in shows from afar.
	for i in 3:
		var g := 40.0 + i * 50.0
		draw_rect(Rect2(x0 - g, top + 20.0 - i * 10.0, g, h - 20.0 + i * 20.0), Color(1.0, 0.75, 0.4, 0.06))
		draw_rect(Rect2(x1, top + 20.0 - i * 10.0, g, h - 20.0 + i * 20.0), Color(1.0, 0.75, 0.4, 0.05))
	draw_rect(Rect2(x0, top, x1 - x0, h), FLAT_WALL)
	var sx := x0 + 16.0
	while sx < x1 - 8.0:
		draw_rect(Rect2(sx, top + 12.0, 8.0, h - 70.0), FLAT_STRIPE)
		sx += 40.0
	draw_rect(Rect2(x0, fl - 60.0, x1 - x0, 60.0), FLAT_DADO)
	draw_rect(Rect2(x0, fl - 62.0, x1 - x0, 4.0), FLAT_FRAME.darkened(0.4))
	# Pictures on the wall and lamps on the ceiling, spread along the room.
	var n := int((x1 - x0) / 260.0)
	for i in n:
		var px := x0 + 150.0 + i * 260.0 + float(Art.hash3(int(x0), i, 3) % 40)
		if px > x1 - 120.0:
			break
		var kind := Art.hash3(int(x0), i, 9) % 3
		var pic := Rect2(px, top + 90.0, 44.0 if kind != 1 else 32.0, 36.0 if kind != 1 else 44.0)
		draw_rect(pic.grow(4.0), Color("2a1a14"))
		draw_rect(pic, [Color("4a78ff"), Color("4caf50"), Color("ff8a3d")][kind].darkened(0.35))
		draw_rect(Rect2(pic.position + Vector2(6, pic.size.y - 12), Vector2(pic.size.x - 12, 6)), Color(1, 1, 1, 0.18))
		var lx := px - 60.0
		draw_rect(Rect2(lx - 1.0, top, 2.0, 40.0), Color("1a1420"))
		draw_rect(Rect2(lx - 16.0, top + 40.0, 32.0, 12.0), Art.GOLD.darkened(0.2))
		draw_circle(Vector2(lx, top + 58.0), 34.0, Color(1.0, 0.85, 0.5, 0.10))
		draw_rect(Rect2(lx - 6.0, top + 52.0, 12.0, 6.0), Color("fff2c0"))
	draw_rect(Rect2(x0, top, x1 - x0, 14.0), FLAT_CEIL)
	# The floor boards.
	draw_rect(Rect2(x0, fl, x1 - x0, 14.0), FLAT_FLOOR)
	draw_rect(Rect2(x0, fl, x1 - x0, 4.0), FLAT_FLOOR_HI)
	var bx := x0 + 24.0
	while bx < x1:
		draw_rect(Rect2(bx, fl + 4.0, 2.0, 10.0), FLAT_FLOOR.darkened(0.3))
		bx += 48.0
	# The window frames, open, with curtains billowing in the draught.
	for end in [[x0, 1.0], [x1, -1.0]]:
		var wx: float = end[0]
		var dir: float = end[1]
		var jamb := Rect2(wx - (0.0 if dir > 0.0 else 12.0), top, 12.0, h)
		draw_rect(Rect2(jamb.position.x - 6.0, top - 10.0, 24.0, 14.0), FLAT_FRAME)
		draw_rect(Rect2(jamb.position.x - 10.0, fl - 2.0, 32.0, 10.0), FLAT_FRAME)
		draw_rect(Rect2(jamb.position.x, top + 4.0, 4.0, 16.0), FLAT_FRAME)
		var sway := sin(time * 3.0 + wx * 0.01)
		for k in 8:
			var cy := top + 4.0 + k * 16.0
			var wv := 30.0 - k * 2.0 + sway * (6.0 + k * 2.0)
			var cx := wx + (8.0 if dir > 0.0 else -8.0 - wv)
			draw_rect(Rect2(cx, cy, wv, 16.0), CURTAIN if k % 2 == 0 else CURTAIN.darkened(0.1))
			draw_rect(Rect2(cx + (wv - 4.0 if dir > 0.0 else 0.0), cy, 4.0, 16.0), CURTAIN_DARK)


# --- The billboard --------------------------------------------------------
const BOARD_WORDS := ["PIZZA 24/7", "HOT DOGS", "NOODLES", "DELIVERY"]
const BOARD_COLS := [Color("ff4d5e"), Color("ffd27a"), Color("4caf50"), Color("4a78ff")]


## A neon billboard on a pole. Lit, its top is a ledge; dark, it is only
## an outline you fall past. Just before the lights go out they stutter.
func _draw_billboard(o: Dictionary) -> void:
	var r := Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0)
	var cx := r.get_center().x
	var bottom := _cam_now.y + get_viewport_rect().size.y + 8.0
	draw_rect(Rect2(cx - 8.0, r.end.y, 16.0, bottom - r.end.y), Color("1d2347"))
	draw_rect(Rect2(cx - 8.0, r.end.y, 4.0, bottom - r.end.y), Color("3a4478"))
	var lit: bool = world.board_lit(o)
	var left: float = world.board_left(o)
	var show := lit
	if left < 0.3 and int(time * 20.0) % 2 == 0:
		show = not lit   # stutter: about to change
	var k := Art.hash3(int(o.x0), 4) % BOARD_WORDS.size()
	var col: Color = BOARD_COLS[k]
	draw_rect(r.grow(6.0), Color("14101c"))
	draw_rect(Rect2(r.position.x - 6.0, r.position.y - 6.0, r.size.x + 12.0, 6.0), Color("8796c8") if show else Color("3a4478"))
	if show:
		for i in 3:
			draw_rect(r.grow(14.0 + i * 12.0), Color(col, 0.07))
		draw_rect(r, col.darkened(0.55))
		draw_rect(r.grow(-6.0), col.darkened(0.3))
	else:
		draw_rect(r, Color("0e0c16"))
		draw_rect(r.grow(-6.0), Color("15121f"))
	var font := screens.bold
	var text: String = BOARD_WORDS[k]
	var size := 28
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(cx - tw * 0.5, r.get_center().y + 10.0)
	if show:
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, col.darkened(0.6))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 0.95))
	else:
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, 0.18))
	# Bulbs along the top edge, the ledge you stand on.
	var bx := r.position.x
	while bx < r.end.x:
		draw_rect(Rect2(bx, r.position.y - 10.0, 6.0, 4.0), Art.GOLD if show else Color("2a2440"))
		bx += 16.0


# --- Balcony steps --------------------------------------------------------
const SLAB := Color("9a98b0")
const SLAB_DARK := Color("4a4860")
const RAIL := Color("2a2a3a")
const RAIL_HI := Color("6a6a88")
const CLOTHES := [Color("e8e0d0"), Color("4a78ff"), Color("ff4d5e"), Color("ffd27a"), Color("4caf50"), Color("c080e0")]


## A concrete balcony slab with a railing, its top at y.
func _slab(x0: float, x1: float, y: float) -> void:
	draw_rect(Rect2(x0 - 4.0, y, x1 - x0 + 8.0, 16.0), SLAB)
	draw_rect(Rect2(x0 - 4.0, y + 12.0, x1 - x0 + 8.0, 4.0), SLAB_DARK)
	draw_rect(Rect2(x0 - 4.0, y - 44.0, x1 - x0 + 8.0, 6.0), RAIL_HI)
	var px := x0
	while px <= x1:
		draw_rect(Rect2(px - 2.0, y - 40.0, 4.0, 40.0), RAIL)
		px += 16.0


func _draw_balcony(r: Dictionary, c: Vector2, vp: Vector2) -> void:
	if r.has("wall_x0"):
		# The building behind the balconies, darker so it reads as far.
		var wall := {"x0": r.wall_x0, "x1": r.wall_x1, "crumble": false}
		var top: float = r.wall_top
		draw_rect(Rect2(r.wall_x0 - 8.0, top - 12.0, r.wall_x1 - r.wall_x0 + 16.0, 12.0), Color("2a2440"))
		_draw_facade(wall, top, c.y + vp.y + 8.0, Color(0.55, 0.55, 0.7), c, vp)
	var y := roundf(r.y / S) * S
	# A dark doorway onto the balcony, lit inside.
	var dx: float = (r.x0 + r.x1) * 0.5 - 36.0
	draw_rect(Rect2(dx - 6.0, y - 186.0, 84.0, 186.0), Color("1a1420"))
	draw_rect(Rect2(dx, y - 180.0, 72.0, 180.0), Color(1.0, 0.72, 0.38, 0.55))
	draw_rect(Rect2(dx + 34.0, y - 180.0, 4.0, 180.0), Color("1a1420"))
	_slab(r.x0, r.x1, y)
	if r.x0 > world.x and state != State.TITLE:
		var pulse := 0.55 + 0.35 * sin(time * 6.0)
		draw_rect(Rect2(r.x0, y - 6, World.EDGE_ZONE, 6), Color(Art.GOLD, pulse))


## The balcony above: its slab and railing, and the washing hanging under
## it, the lowest piece right at the height that kills.
func _draw_rack(o: Dictionary) -> void:
	_slab(o.x0, o.x1, o.y0)
	var line_y: float = o.y0 + 22.0
	draw_rect(Rect2(o.x0, line_y - 2.0, o.x1 - o.x0, 2.0), ROPE)
	var n := maxi(int((o.x1 - o.x0) / 44.0), 2)
	var sway := sin(time * 2.5 + o.x0 * 0.01) * 3.0
	for i in n:
		var gx: float = o.x0 + 8.0 + i * (o.x1 - o.x0 - 16.0) / n
		var gw := 30.0
		var long: bool = (i + int(o.style)) % 2 == 0
		var bottom: float = o.y1 if long else o.y1 - 28.0
		var col: Color = CLOTHES[(i + int(o.style)) % CLOTHES.size()]
		var r := Rect2(gx + sway * (1.0 if long else 0.5), line_y, gw, bottom - line_y)
		draw_rect(r.grow(2.0), Color("140c14"))
		draw_rect(r, col)
		draw_rect(Rect2(r.position.x, r.end.y - 6.0, r.size.x, 6.0), col.darkened(0.25))
		# Drips: it is still wet.
		if int(time * 3.0 + i) % 3 == 0:
			draw_rect(Rect2(r.get_center().x, r.end.y + 4.0 + fmod(time * 60.0, 20.0), 2.0, 4.0), Color(0.6, 0.8, 1.0, 0.7))


## A sofa, a chest of drawers or a TV on its stand, in the flat's way.
func _draw_furniture(o: Dictionary) -> void:
	var r := Rect2(o.x0, o.y0, o.x1 - o.x0, o.y1 - o.y0)
	var out := Color("140c14")
	match int(o.style):
		0:  # sofa: back, cushions, arms
			draw_rect(r.grow(2.0), out)
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 28.0), Color("8a3a5a"))
			draw_rect(Rect2(r.position.x, r.position.y + 26.0, r.size.x, 22.0), Color("b0506e"))
			draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 1.0, r.position.y + 26.0, 2.0, 22.0), Color("6a2a44"))
			draw_rect(Rect2(r.position.x, r.position.y + 14.0, 12.0, 34.0), Color("6a2a44"))
			draw_rect(Rect2(r.end.x - 12.0, r.position.y + 14.0, 12.0, 34.0), Color("6a2a44"))
			draw_rect(Rect2(r.position.x + 6.0, r.end.y - 8.0, 6.0, 8.0), out)
			draw_rect(Rect2(r.end.x - 12.0, r.end.y - 8.0, 6.0, 8.0), out)
		1:  # chest of drawers with a lamp on top
			var body := Rect2(r.position.x + 6.0, r.position.y + 12.0, r.size.x - 12.0, r.size.y - 12.0)
			draw_rect(body.grow(2.0), out)
			draw_rect(body, Color("7a5030"))
			for k in 3:
				var dy := body.position.y + 4.0 + k * 13.0
				draw_rect(Rect2(body.position.x + 4.0, dy, body.size.x - 8.0, 10.0), Color("94643c"))
				draw_rect(Rect2(body.get_center().x - 4.0, dy + 4.0, 8.0, 2.0), Art.GOLD)
			draw_rect(Rect2(r.position.x + 20.0, r.position.y - 4.0, 4.0, 16.0), out)
			draw_rect(Rect2(r.position.x + 10.0, r.position.y - 14.0, 24.0, 12.0), Art.GOLD)
			draw_circle(Vector2(r.position.x + 22.0, r.position.y - 6.0), 22.0, Color(1.0, 0.85, 0.5, 0.12))
		_:  # TV on a low stand, the screen flickering
			var stand := Rect2(r.position.x, r.end.y - 20.0, r.size.x, 20.0)
			draw_rect(stand.grow(2.0), out)
			draw_rect(stand, Color("3a3040"))
			var tv := Rect2(r.position.x + 10.0, r.position.y, r.size.x - 20.0, r.size.y - 22.0)
			draw_rect(tv.grow(2.0), out)
			draw_rect(tv, Color("1a1a24"))
			var glow := 0.55 + 0.25 * sin(time * 17.0 + o.x0)
			draw_rect(tv.grow(-4.0), Color(0.35, 0.55, 1.0, glow))
			draw_rect(Rect2(tv.position + Vector2(8, 8), Vector2(18, 4)), Color(1, 1, 1, 0.35))


## The awning sticks out of the tall building's wall, its bracket on the
## right. It squashes when it catches you and springs back.
func _draw_awning(o: Dictionary) -> void:
	var f := 0
	var riding: bool = world.carry.get("kind", "") == "awning"
	if riding and world.t - grab_t < 0.12:
		f = 1
	elif riding or (o.used and world.t - release_t < 0.25):
		f = 2
	_sheet(AWNING_TEX, Rect2(f * 96, 0, 96, 32), Vector2(o.x1 - 96.0 * S, o.y0 - 6.0 * S))


## Two poles and a cable from one to the other; the handle hangs on the
## cable at the roof's edge, and rides down it with the courier.
func _draw_zipline(o: Dictionary) -> void:
	var a := Vector2(o.ax, o.ay)
	var b := Vector2(o.bx, o.by)
	for end in [[a, 0, o.a_roof], [b, 1, o.b_roof]]:
		var p: Vector2 = end[0]
		var top := p - Vector2(8, 4) * S
		draw_rect(Rect2(top.x + 6 * S, top.y + 64 * S, 4 * S, end[2] - top.y - 64 * S), ROPE_DARK)
		_sheet(ZIP_TEX, Rect2(end[1] * 16, 0, 16, 64), top)
	var riding: bool = world.carry.get("kind", "") == "zipline"
	if riding:
		# The cable bends where the handle weighs it down.
		var hands := _hands()
		var pos := hands - Vector2(8, 22) * S
		var wheel := pos + Vector2(8, 4) * S
		_rope(a, wheel)
		_rope(wheel, b)
		_sheet(ZIP_TEX, Rect2(48, 0, 16, 64), pos)
		return
	_rope(a, b)
	var hx: float = (o.x0 + o.x1) * 0.5
	if o.used:
		hx = b.x - 60.0
	var cy := lerpf(a.y, b.y, clampf((hx - a.x) / (b.x - a.x), 0.0, 1.0))
	_sheet(ZIP_TEX, Rect2(32, 0, 16, 64), Vector2(hx, cy) - Vector2(8, 4) * S)


## The cradle hangs on two ropes from a winch on the tall roof. It waits deep
## in the gap, rises with the courier in it, and stays up top.
func _draw_cradle(o: Dictionary) -> void:
	var top: float = o.top
	var bx0: float = o.x1 + 10.0
	_sheet(CRADLE_TEX, Rect2(128, 0, 64, 32), Vector2(bx0 - 20.0 * S, top - 32.0 * S))
	var floor_y: float = o.y0
	var riding: bool = world.carry.get("kind", "") == "cradle"
	if riding:
		floor_y = world.y
	elif o.used:
		floor_y = top
	var pos := Vector2((o.x0 + o.x1) * 0.5 - 32.0 * S, floor_y - 24.0 * S)
	for rx in [4.0, 60.0]:
		_rope(Vector2(pos.x + rx * S, top - 22.0 * S), pos + Vector2(rx * S, 0), ROPE_DARK)
	var f := 1 if riding and int(time * 6.0) % 2 == 0 else 0
	_sheet(CRADLE_TEX, Rect2(f * 64, 0, 64, 32), pos)


## A crane jib comes in from the top left; its cable runs down to the hook,
## which hangs by the roof's edge, swings with the courier, then hangs free.
func _draw_crane(o: Dictionary) -> void:
	var pv := Vector2(o.pivot_x, o.pivot_y)
	var x := pv.x - 16.0 * S - 32.0 * S
	var n := 0
	while n < 24:
		_sheet(CRANE_TEX, Rect2(0, 0, 32, 32), Vector2(x, pv.y - 26.0 * S))
		x -= 32.0 * S
		n += 1
	_sheet(CRANE_TEX, Rect2(32, 0, 32, 32), Vector2(pv.x - 16.0 * S, pv.y - 26.0 * S))
	var grip: Vector2
	if world.carry.get("kind", "") == "crane":
		grip = _hands()
	elif o.used:
		grip = pv + Vector2(sin(time * 1.5) * 30.0, 420.0)
	else:
		grip = Vector2((o.x0 + o.x1) * 0.5 + sin(time * 2.0) * 6.0, (o.y0 + o.y1) * 0.5 + 20.0)
	var pos := grip - Vector2(16, 28) * S
	_rope(pv + Vector2(0, 4), pos + Vector2(16, 0) * S, ROPE_DARK)
	_sheet(CRANE_TEX, Rect2(64, 0, 32, 32), pos)


## Where the courier's fists are in the hanging poses.
func _hands() -> Vector2:
	return Vector2(world.x, world.y - (FEET - 6.0) * S)



func _draw_parcel(p: Dictionary) -> void:
	var bob := roundf(sin(time * 4.0 + p.x * 0.01) * 2.0) * S
	# Cell (192, 64); the box is centred at (32, 50) in the cell.
	draw_texture_rect_region(TILES, Rect2(roundf(p.x) - 32 * S, roundf(p.y) - 50 * S + bob, TILE * S, TILE * S),
		Rect2(3 * TILE, TILE, TILE, TILE))


func _draw_wire_posts(w: Dictionary) -> void:
	for p in [Vector2(w.ax, w.ay), Vector2(w.bx, w.by)]:
		var top := roundf(p.y)
		var h: float = w.get("h", World.WIRE_HIGH)
		draw_rect(Rect2(p.x - 4, top, 8, h), WIRE_DARK)
		draw_rect(Rect2(p.x - 4, top, 2, h), WIRE_EDGE.darkened(0.3))
		draw_rect(Rect2(p.x - 12, top + 6, 24, 6), WIRE_DARK)
		draw_rect(Rect2(p.x - 12, top + 6, 24, 2), WIRE_EDGE)


func _draw_wire(w: Dictionary) -> void:
	var pts := World.wire_points(w, int((w.bx - w.ax) / S))
	for p in pts:
		var q := (p / S).round() * S
		draw_rect(Rect2(q - Vector2(1, 2), Vector2(S, S * 2.0)), WIRE_DARK)
		draw_rect(Rect2(q - Vector2(1, 2), Vector2(S, S)), WIRE_EDGE)
	# A live wire over an AC unit crackles all the time, so it reads as danger.
	if w.get("live", false):
		for j in 3:
			var i := (int(time * 20.0) * 7 + j * 11) % pts.size()
			if (int(time * 15.0) + j) % 3 != 0:
				var q := (pts[i] / S).round() * S
				draw_rect(Rect2(q - Vector2(6, 8), Vector2(4, 4)), Color("9fe8ff"))
				draw_rect(Rect2(q + Vector2(4, -4), Vector2(4, 4)), Art.GOLD)
				draw_rect(Rect2(q - Vector2(2, 2), Vector2(4, 4)), Color.WHITE)
	# A spark runs along it now and then, so it catches the eye.
	var k := fmod(time * 0.8 + w.ax * 0.001, 1.6)
	if k < 1.0:
		var i := int(k * (pts.size() - 1))
		draw_rect(Rect2((pts[i] / S).round() * S - Vector2(4, 4), Vector2(8, 8)), Art.GOLD)


## The courier sheet: 9 frames of 64x64 in a row (run 1-6, jump up, fall,
## landing squash), drawn at 2x with the feet 58 px down each frame.
const COURIER: Texture2D = preload("res://sprites/courier.png")
const FRAME := 64.0
const FEET := 58.0
const F_JUMP := 6
const F_FALL := 7
const F_LAND := 8
const SQUASH_TIME := 0.09


func _runner_frame() -> int:
	if not world.alive:
		return F_FALL
	if not world.started:
		return 0 if fmod(time, 3.0) > 0.25 else F_LAND
	if not world.grounded:
		return F_JUMP if world.vy < 150.0 else F_FALL
	if world.t - land_t < SQUASH_TIME:
		return F_LAND
	# One run frame per 26 px, so the legs keep pace with the speed.
	return int(world.x / 26.0) % 6


func _draw_runner(c: Vector2) -> void:
	var src := Rect2(_runner_frame() * FRAME, 0, FRAME, FRAME)
	var size := Vector2(FRAME, FRAME) * S
	var pos := Vector2(world.x - FRAME * 0.5 * S, world.y - FEET * S).round()
	if world.y > sink_y + 40.0:
		return  # gone through the skylight
	if not world.alive and world.death not in ["fall", "skylight"]:
		# Tumble backwards after a hit.
		draw_set_transform(-c + pos + size * 0.5, -over_t * 9.0)
		draw_texture_rect_region(COURIER, Rect2(-size * 0.5, size), src)
		draw_set_transform(-c)
		return
	if world.carry.is_empty():
		draw_texture_rect_region(COURIER, Rect2(pos, size), src)
		return
	# Carried: a pose from courier-tricks.png, by what is carrying you.
	var kind: String = world.carry.kind
	var f := T_HANG + int(time * 4.0) % 2
	match kind:
		"laundry":
			f = T_CHUTE + int(time * 6.0) % 2
		"awning":
			f = T_SQUAT if world.t - grab_t < 0.12 else T_LAUNCH
		"cradle":
			f = T_CRADLE + int(time * 3.0) % 2
	var tsrc := Rect2(f * FRAME, 0, FRAME, FRAME)
	if f <= T_HANG + 1:
		# Hanging: swing a little about the hands.
		var hands := _hands()
		draw_set_transform(-c + hands, sin(time * 6.0) * 0.1)
		draw_texture_rect_region(TRICKS, Rect2(Vector2(-FRAME * 0.5 * S, -6.0 * S), size), tsrc)
		draw_set_transform(-c)
		if kind == "bat":
			_sheet(BAT_TEX, Rect2(32 * (2 + int(time * 14.0) % 2), 0, 32, 24), hands - Vector2(16, 22) * S)
		return
	draw_texture_rect_region(TRICKS, Rect2(pos, size), tsrc)
	if kind == "laundry":
		# The sheet billows overhead, its corners in the fists.
		var fists := Vector2(world.x, world.y - (FEET - 18.0) * S)
		_sheet(LAUNDRY_TEX, Rect2(96, 0, 48, 48), fists - Vector2(32, 44) * S)



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
	draw_rect(Rect2(fx + 4, fy - 96, 52, 28 + wave), Art.GOLD)
	draw_string(screens.bold, Vector2(fx + 8, fy - 74), "BEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("0a0c1c"))


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
	# The icons are laid out on a 72 px square and scaled to the button size.
	var k := BUTTON / 72.0
	# Sound on/off, top right.
	draw_set_transform(Vector2(vp.x - BUTTON - EDGE, 24), 0.0, Vector2(k, k))
	draw_rect(Rect2(0, 0, 72, 72), Color(0.04, 0.05, 0.12, 0.5))
	var o := Vector2(16, 20)
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
	# Fullscreen, left of the sound button: corners pointing out, or in to leave.
	if _can_fullscreen:
		var fr := _fullscreen_rect()
		draw_set_transform(fr.position, 0.0, Vector2(k, k))
		draw_rect(Rect2(0, 0, 72, 72), Color(0.04, 0.05, 0.12, 0.5))
		# Four L shapes; out of fullscreen they sit in the corners with arms
		# pointing in, in fullscreen near the middle with arms pointing out.
		var inward := _is_fullscreen()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var tip: Vector2 = Vector2(36, 36) + c * (6.0 if inward else 20.0)
			var arm: Vector2 = c if inward else -c   # the way the arms point
			for along: Vector2 in [Vector2(arm.x, 0), Vector2(0, arm.y)]:
				var end: Vector2 = tip + along * 16.0
				var r := Rect2(tip, Vector2.ZERO).expand(end).grow(2)
				draw_rect(r, Art.TEXT)
	# Pause, top left, while running.
	if state == State.RUN:
		draw_set_transform(Vector2(EDGE, 24), 0.0, Vector2(k, k))
		draw_rect(Rect2(0, 0, 72, 72), Color(0.04, 0.05, 0.12, 0.5))
		draw_rect(Rect2(24, 20, 8, 32), Art.TEXT)
		draw_rect(Rect2(40, 20, 8, 32), Art.TEXT)
	draw_set_transform(Vector2.ZERO)


# --- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	score_label = _label(layer, 80, Art.TEXT)
	score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	score_label.offset_top = 24
	score_label.offset_bottom = 104
	meters_label = _label(layer, 36, Color("aab4e8"))
	meters_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	meters_label.offset_top = 100
	meters_label.offset_bottom = 136
	mult_label = _label(layer, 48, Art.ORANGE)
	mult_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mult_label.offset_top = 136
	mult_label.offset_bottom = 186
	best_label = _label(layer, 34, Art.GOLD)
	best_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	best_label.offset_top = 186
	best_label.offset_bottom = 222
	hint_label = _label(layer, 40, Art.TEXT)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_label.offset_top = 240
	hint_label.offset_left = 24
	hint_label.offset_right = -24
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rotate_label = _label(layer, 96, Art.TEXT)
	rotate_label.text = "Turn your phone\nsideways to run"
	rotate_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rotate_label.hide()


func _label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = screens.bold
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


## Upright, the other text hides behind one big "turn your phone" line.
func _update_rotate_hint() -> void:
	var up := _portrait()
	if rotate_label.visible == up:
		return
	rotate_label.visible = up
	for l in [score_label, meters_label, mult_label, best_label, hint_label]:
		l.modulate.a = 0.0 if up else 1.0


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
		music.start()
		music.set_speed(world.speed_frac())
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
