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
	_new_world()
	_show_title()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
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
		elif event.pressed and k == KEY_M:
			_set_muted(not muted)
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
			if screens.button_at(pos) == "menu":
				_to_menu()
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


## The results panel itself is drawn by screens.gd; the top HUD steps aside.
func _show_results() -> void:
	results_shown = true
	_set_hud_visible(false)


# --- Loop ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if state == State.PAUSED:
		return
	if state == State.TITLE:
		world.step(false)
		return
	var was_alive := world.alive
	var run := state == State.RUN
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


func _process(delta: float) -> void:
	time += delta
	var vp := get_viewport_rect().size
	if _portrait() and state == State.RUN:
		_pause()
	_update_rotate_hint()
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
			land_t = world.t
			var impact: float = e.impact
			sfx.play("land", 0.08, linear_to_db(clampf(impact / 1400.0, 0.3, 1.0)))
			_dust(Vector2(world.x, world.y), int(clampf(impact / 120.0, 3, 12)), 1.0)
			if impact > 1000.0:
				shake = maxf(shake, (impact - 900.0) / 90.0)
		"grab":
			if e.kind == "bat":
				sfx.play("squeak", 0.05)
				_popup(Vector2(world.x, world.y - 170.0), "BAT RIDE!  +%d" % e.points, Art.GOLD)
			else:
				sfx.play("cloth")
				_popup(Vector2(world.x, world.y - 170.0), "STEAM LIFT!  +%d" % e.points, Art.GOLD)
			sfx.play("best", 0.0, -8.0)
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
			"life": 0.0, "max": randf_range(0.4, 0.8), "col": SKY_GLASS.lightened(0.3), "size": 6.0})


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
			_draw_parcel(p)
	_draw_runner(c)
	for w in world.wires:
		_draw_wire(w)
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
## In the roof tiles the walkable surface is 26 px down, and rows 34-64 are
## facade (brick and a window) that repeats down to the street.
const ROOF_TOP := 26.0
const FACADE_Y := 34.0
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
	var y := roundf(r.y / S) * S
	if r.crumble and r.t >= 0.0 and r.vy == 0.0:
		y += S * float(randi_range(-1, 1))
	var x0: float = r.x0
	var x1: float = r.x1
	var bottom := c.y + vp.y + 8.0
	var mid := 3 if r.crumble else 1
	# Crumbling roofs are cracked and a little rust-red, so they read early.
	var tint := Color(1.25, 0.82, 0.8) if r.crumble else Color.WHITE
	# The roof itself: coping, slab and the first row of facade.
	_roof_strip(x0, x1, y, ROOF_TOP, TILE - ROOF_TOP, mid, tint)
	# More facade below, band after band, down past the bottom of the screen.
	var band := (TILE - FACADE_Y) * S
	var yy := y + (TILE - ROOF_TOP) * S
	var row := 0
	while yy < bottom:
		_roof_strip(x0, x1, yy, FACADE_Y, TILE - FACADE_Y, 3 if r.crumble and row == 0 else 1, tint)
		yy += band
		row += 1
	# The bonus edge: land in this strip to grow the multiplier. It glows on
	# roofs still ahead, with chevrons pointing at the edge.
	if x0 > world.x and state != State.TITLE:
		var pulse := 0.55 + 0.35 * sin(time * 6.0)
		var zone := World.EDGE_ZONE
		draw_rect(Rect2(x0, y - 6, zone, 6), Color(Art.GOLD, pulse))
		draw_rect(Rect2(x0, y - 2, zone, 4), Color(Art.ORANGE, pulse))
		for k in 3:
			var cx := x0 + 6 + k * 12
			draw_rect(Rect2(cx, y - 16 - (k % 2) * 0, 4, 4), Color(Art.GOLD, pulse))
			draw_rect(Rect2(cx - 4, y - 20, 4, 4), Color(Art.GOLD, pulse * 0.8))
			draw_rect(Rect2(cx - 4, y - 12, 4, 4), Color(Art.GOLD, pulse * 0.8))


## Placeholder art for the newer obstacles, until their sprites are drawn.
const SKY_GLASS := Color("7fd0ff")
const SKY_FRAME := Color("2a3360")
const LAUNDRY := [Color("ff8a3d"), Color("e8ecff"), Color("4a78ff"), Color("ffd27a"), Color("ff4d5e")]


func _draw_obstacle(o: Dictionary) -> void:
	match o.kind:
		"skylight":
			_draw_skylight(o)
			return
		"bat":
			if not o.used:
				var bob := roundf(sin(time * 5.0 + o.x0) * 3.0) * 2.0
				_draw_bat(Vector2((o.x0 + o.x1) * 0.5, (o.y0 + o.y1) * 0.5 + bob), 8.0)
			return
		"laundry":
			_draw_steam(o)
			_draw_laundry(o)
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


## A glass roof light, raised a little above the roof, with a moving glint.
func _draw_skylight(o: Dictionary) -> void:
	var y: float = o.y1
	var x0: float = o.x0
	var x1: float = o.x1
	# A low glass roof, 28 px tall, lit from inside so it reads from afar.
	draw_rect(Rect2(x0 - 8, y - 6, x1 - x0 + 16, 14), Color(1, 0.75, 0.4, 0.35))
	draw_rect(Rect2(x0 - 4, y - 32, x1 - x0 + 8, 36), SKY_FRAME)
	draw_rect(Rect2(x0 + 4, y - 28, x1 - x0 - 8, 24), SKY_GLASS.darkened(0.15))
	draw_rect(Rect2(x0 + 4, y - 28, x1 - x0 - 8, 6), SKY_GLASS.lightened(0.3))
	for k in range(int(x0) + 28, int(x1) - 12, 28):  # mullions
		draw_rect(Rect2(k, y - 28, 4, 24), SKY_FRAME)
	var g := fposmod(time * 160.0 + x0, (x1 - x0) + 160.0) - 80.0
	if g > 4.0 and g < x1 - x0 - 20:
		draw_rect(Rect2(x0 + snappedf(g, 4), y - 24, 8, 16), Color(1, 1, 1, 0.75))
		draw_rect(Rect2(x0 + snappedf(g, 4) + 12, y - 24, 4, 16), Color(1, 1, 1, 0.5))


## A line between two poles with clothes pegged on, swaying a little.
func _draw_laundry(o: Dictionary) -> void:
	var a := Vector2(o.x0 - 16, o.y0)
	var b := Vector2(o.x1 + 16, o.y0)
	for p in [a, b]:
		draw_rect(Rect2(p.x - 4, p.y - 8, 8, World.LAUNDRY_LINE + 8), WIRE_DARK)
		draw_rect(Rect2(p.x - 4, p.y - 8, 2, World.LAUNDRY_LINE + 8), WIRE_EDGE.darkened(0.3))
	var n := int((b.x - a.x) / S)
	for i in n + 1:
		var t := float(i) / n
		var q := Vector2(lerpf(a.x, b.x, t), a.y + 12.0 * sin(PI * t))
		draw_rect(Rect2((q / S).round() * S, Vector2(S, S)), WIRE_EDGE)
	var x: float = o.x0 + 4.0
	var i := 0
	while x < o.x1 - 20.0:
		if o.used and i == 1:  # the sheet the courier took
			x += 40.0
			i += 1
			continue
		var h := Art.hash3(int(o.x0), i)
		var w := 28.0 + float(h % 3) * 12.0
		w = minf(w, o.x1 - x)
		var t := (x + w * 0.5 - a.x) / (b.x - a.x)
		var top := a.y + 12.0 * sin(PI * t)
		var length: float = o.y1 - top - float(h % 4) * 6.0
		var sway := roundf(sin(time * 2.5 + i) * 1.5) * 2.0
		var col: Color = LAUNDRY[h % LAUNDRY.size()]
		var r := Rect2(snappedf(x + sway, S), snappedf(top, S), snappedf(w, S), snappedf(length, S))
		draw_rect(r.grow(2), INK_DARK)
		draw_rect(r, col)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), col.lightened(0.3))
		if h % 2 == 0:  # stripes
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.5), Vector2(r.size.x, 6)), col.darkened(0.3))
		draw_rect(Rect2(r.position + Vector2(4, -6), Vector2(4, 10)), Art.TEXT)  # pegs
		draw_rect(Rect2(r.end.x - 8, r.position.y - 6, 4, 10), Art.TEXT)
		x += w + 10.0
		i += 1


const INK_DARK := Color("0a0c1c")


## A vent at the foot of the wall, puffing steam up its whole height, so the
## way up is there to be seen before the player knows how to use it.
func _draw_steam(o: Dictionary) -> void:
	var vx: float = o.vent
	var floor_y: float = o.y0 + World.LAUNDRY_LINE
	draw_rect(Rect2(vx - 14, floor_y - 28, 28, 28), WIRE_DARK)
	draw_rect(Rect2(vx - 18, floor_y - 32, 36, 8), WIRE_EDGE.darkened(0.2))
	var height := World.WALL_RISE + 160.0
	for i in 14:
		var k := fposmod(time * 0.55 + i / 14.0, 1.0)
		var h := Art.hash3(i, int(vx))
		var px := vx + sin(k * 9.0 + i) * 14.0 - k * 50.0
		var py := floor_y - 30.0 - k * height
		var size := 16.0 + k * 40.0 + float(h % 3) * 4.0
		var col := Color(0.85, 0.9, 1.0, 0.45 * (1.0 - k))
		draw_rect(Rect2(snappedf(px - size * 0.5, 4), snappedf(py - size * 0.5, 4), snappedf(size, 4), snappedf(size, 4)), col)


func _draw_parcel(p: Dictionary) -> void:
	var bob := roundf(sin(time * 4.0 + p.x * 0.01) * 2.0) * S
	# Cell (192, 64); the box is centred at (32, 50) in the cell.
	draw_texture_rect_region(TILES, Rect2(roundf(p.x) - 32 * S, roundf(p.y) - 50 * S + bob, TILE * S, TILE * S),
		Rect2(3 * TILE, TILE, TILE, TILE))


func _draw_wire_posts(w: Dictionary) -> void:
	for p in [Vector2(w.ax, w.ay), Vector2(w.bx, w.by)]:
		var top := roundf(p.y)
		draw_rect(Rect2(p.x - 4, top, 8, World.WIRE_HIGH), WIRE_DARK)
		draw_rect(Rect2(p.x - 4, top, 2, World.WIRE_HIGH), WIRE_EDGE.darkened(0.3))
		draw_rect(Rect2(p.x - 12, top + 6, 24, 6), WIRE_DARK)
		draw_rect(Rect2(p.x - 12, top + 6, 24, 2), WIRE_EDGE)


func _draw_wire(w: Dictionary) -> void:
	var pts := World.wire_points(w, int((w.bx - w.ax) / S))
	for p in pts:
		var q := (p / S).round() * S
		draw_rect(Rect2(q - Vector2(1, 2), Vector2(S, S * 2.0)), WIRE_DARK)
		draw_rect(Rect2(q - Vector2(1, 2), Vector2(S, S)), WIRE_EDGE)
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
	var pos := (Vector2(world.x - FRAME * 0.5 * S, world.y - FEET * S) / S).round() * S
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
	# Carried: hanging from a bat, or under the sheet in the steam.
	# Placeholder poses until the art exists: the jump frame, arms up.
	var sway := sin(time * 6.0) * 0.08
	draw_set_transform(-c + Vector2(world.x, world.y - World.HEIGHT), sway)
	draw_texture_rect_region(COURIER, Rect2(Vector2(-FRAME * 0.5 * S, -FEET * S + World.HEIGHT), size),
		Rect2(F_JUMP * FRAME, 0, FRAME, FRAME))
	draw_set_transform(-c)
	var hands := Vector2(world.x + 6, world.y - World.HEIGHT - 6)
	if world.carry.kind == "bat":
		_draw_bat(hands + Vector2(0, -22), 14.0)
	else:
		_draw_sheet(hands)


## The bat, flapping; rate is wing beats a second.
func _draw_bat(at: Vector2, rate: float) -> void:
	Art.sprite(self, Art.BAT[int(time * rate) % 2], (at - Vector2(36, 24)).round(), 6.0)


## The sheet held overhead like a parachute, with two corners in the hands.
func _draw_sheet(hands: Vector2) -> void:
	var top := hands + Vector2(0, -92)
	var w := 120.0
	var billow := roundf(sin(time * 9.0) * 2.0) * 2.0
	for k in [-1.0, 1.0]:
		var corner := top + Vector2(k * w * 0.5, 18)
		var n := 10
		for i in n:
			var q: Vector2 = hands.lerp(corner, float(i) / n)
			draw_rect(Rect2((q / S).round() * S, Vector2(S, S)), Art.TEXT.darkened(0.3))
	var r := Rect2(top.x - w * 0.5, top.y - billow, w, 24 + billow)
	draw_rect(r.grow(2), INK_DARK)
	draw_rect(r, Art.TEXT)
	draw_rect(Rect2(r.position.x, r.end.y - 6, r.size.x, 6), Color("4a78ff"))


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
