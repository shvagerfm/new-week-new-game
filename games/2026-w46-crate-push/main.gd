extends Node2D
## Crate Push: a cargo robot puts battery crates back on their chargers to
## restart an abandoned space station.
##
## Screens: zone map -> level list -> board. Levels live in res://levels/
## (see README.md); the rules are in rules.gd.

const SAVE_PATH := "user://crate_push.cfg"

const TOP_BAR := 190.0
const BOTTOM_BAR := 250.0
const MARGIN := 20.0
const MAX_CELL := 110.0
const SWIPE_MIN := 36.0
const MOVE_TIME := 0.09
const BUMP_TIME := 0.12

const BOOSTERS := {
	"hint": {"label": "Hint", "uses": 3},
	"pull": {"label": "Pull", "uses": 1},
	"blast": {"label": "Blast", "uses": 1},
	"moves": {"label": "+5 moves", "uses": 1},
}

const C_BG := Color("171a29")
const C_FLOOR := Color("232740")
const C_WALL := Color("3b4170")
const C_WALL_EDGE := Color("2b3055")
const C_GOAL := Color("ffb347")
const C_BOX := Color("c98a4b")
const C_BOX_EDGE := Color("8f5a2b")
const C_DONE := Color("6fd08c")
const C_DONE_EDGE := Color("3f9460")
const C_PLAYER := Color("6ec3ff")
const C_EYE := Color("171a29")
const C_TEXT := Color("eeeeff")
const C_DIM := Color("9aa0c0")
const C_BUTTON := Color("2d3252")
const C_BUTTON_HOVER := Color("3a4068")
const C_STAR := Color("ffd23f")
const CRATE_COLORS := {"a": Color("ff6b6b"), "b": Color("5aa9ff"), "c": Color("c38bff")}
const PAD_COLORS := [Color("6fe0c0"), Color("ff8fd8"), Color("ffe066"), Color("8fa8ff")]

var zones: Array[Dictionary] = []
var best := {}        # level id -> stars (1..3)
var intro_seen := {}  # zone id -> true

var screen := ""
var zone_i := 0
var level_i := 0

# Board
var lv: Rules
var state := {}
var history: Array[Dictionary] = []
var finished := ""  # "", "won", or why the attempt failed
var uses := {}      # booster -> uses left this attempt
var booster_used := false
var armed := ""     # "pull" or "blast" while waiting for a direction
var hint_dir := Vector2i.ZERO
var hint_busy := false
var facing := Vector2i.DOWN

# Animation
var anim_t := 1.0
var player_from := Vector2.ZERO
var crate_moves := {}  # new pos -> old pos
var bump_t := 1.0
var bump_dir := Vector2.ZERO
var clock := 0.0

# Layout
var cell := 64.0
var origin := Vector2.ZERO

# Touch
var touch_index := -1
var swipe_start := Vector2.ZERO
var title_taps := 0

# UI
var ui: Control
var map_screen: Control
var zone_list: VBoxContainer
var map_stars: Label
var levels_screen: Control
var levels_title: Label
var levels_story: Label
var levels_grid: GridContainer
var play_hud: Control
var title_label: Label
var info_label: Label
var tip_label: Label
var toast_label: Label
var booster_row: HBoxContainer
var booster_buttons := {}
var undo_button: Button
var overlay: Control
var overlay_title: Label
var overlay_stars: Control
var overlay_text: Label
var overlay_buttons: HBoxContainer

var wall_style := StyleBoxFlat.new()
var crate_style := StyleBoxFlat.new()
var robot_style := StyleBoxFlat.new()


func _ready() -> void:
	zones = Campaign.load_zones()
	_load_progress()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_show_map()


# --- Screens --------------------------------------------------------------------

func _show_map() -> void:
	screen = "map"
	for c in zone_list.get_children():
		c.queue_free()
	var total := 0
	var got := 0
	for i in zones.size():
		var z: Dictionary = zones[i]
		var open := _zone_open(i)
		var stars := 0
		for l in z.levels:
			stars += best.get(l.id, 0)
		total += z.levels.size() * 3
		got += stars
		var b := _button("", _open_zone.bind(i))
		b.custom_minimum_size = Vector2(0, 118)
		b.disabled = not open
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "  %d   %s" % [i + 1, z.name if open else "Locked"]
		b.add_theme_font_size_override("font_size", 38)
		var right := _label("%d / %d" % [stars, z.levels.size() * 3] if open else "", 28, C_STAR)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_child(right)
		right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		right.offset_right = -28
		var stripe := ColorRect.new()
		stripe.color = z.color if open else C_DIM.darkened(0.5)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(stripe)
		stripe.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		stripe.offset_right = 10
		zone_list.add_child(b)
	map_stars.text = "%d / %d stars" % [got, total]
	_set_screen(map_screen)


func _open_zone(i: int) -> void:
	zone_i = i
	var z: Dictionary = zones[i]
	if not intro_seen.has(z.id):
		intro_seen[z.id] = true
		_save_progress()
		_show_levels()
		_show_overlay(z.name, z.story, -1, [["Let's go", _hide_overlay]])
		return
	_show_levels()


func _show_levels() -> void:
	screen = "levels"
	var z: Dictionary = zones[zone_i]
	levels_title.text = "%d  %s" % [zone_i + 1, z.name]
	levels_title.add_theme_color_override("font_color", z.color)
	levels_story.text = z.story.get_slice("\n", 0)
	for c in levels_grid.get_children():
		c.queue_free()
	for i in z.levels.size():
		var id: String = z.levels[i].id
		var b := _button("", _start_level.bind(zone_i, i))
		b.custom_minimum_size = Vector2(140, 140)
		b.disabled = not _level_open(zone_i, i)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(_label(str(i + 1), 44, C_TEXT if not b.disabled else C_DIM))
		var st := _stars_view(best.get(id, 0), 15.0)
		box.add_child(st)
		levels_grid.add_child(b)
	_set_screen(levels_screen)


func _set_screen(c: Control) -> void:
	for s in [map_screen, levels_screen, play_hud]:
		s.visible = s == c
	overlay.hide()
	queue_redraw()


# --- Progress -------------------------------------------------------------------

func _zone_open(i: int) -> bool:
	if i == 0:
		return true
	var prev: Array = zones[i - 1].levels
	return best.has(prev[prev.size() - 1].id)


func _level_open(z: int, i: int) -> bool:
	if not _zone_open(z):
		return false
	return i == 0 or best.has(zones[z].levels[i - 1].id)


func _boosters_for(z: int) -> Array[String]:
	var out: Array[String] = []
	for i in z + 1:
		var b: String = zones[i].booster
		if b != "" and BOOSTERS.has(b):
			out.append(b)
	return out


func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best = cfg.get_value("progress", "best", {})
	intro_seen = cfg.get_value("progress", "intro_seen", {})


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "intro_seen", intro_seen)
	cfg.save(SAVE_PATH)


func _stars_for(moves: int, par: int, used: bool) -> int:
	if par <= 0:
		return 2 if used else 3
	var stars := 1
	if moves <= par:
		stars = 3
	elif moves <= par + maxi(4, par / 3):
		stars = 2
	if used:
		stars = mini(stars, 2)
	return stars


# --- Board ----------------------------------------------------------------------

func _start_level(z: int, i: int) -> void:
	zone_i = z
	level_i = i
	lv = zones[z].levels[i].rules
	screen = "play"
	_set_screen(play_hud)
	_restart_attempt()
	_layout()


func _restart_attempt() -> void:
	state = lv.start.duplicate(true)
	history.clear()
	finished = ""
	booster_used = false
	armed = ""
	hint_dir = Vector2i.ZERO
	facing = Vector2i.DOWN
	uses.clear()
	for b in _boosters_for(zone_i):
		uses[b] = BOOSTERS[b].uses
	overlay.hide()
	_snap()
	_update_hud()


func _restart() -> void:
	if finished == "won":
		_restart_attempt()
		return
	if history.is_empty():
		return
	# Restart can be undone: the current position goes onto the history.
	history.append(state)
	state = lv.start.duplicate(true)
	finished = ""
	armed = ""
	hint_dir = Vector2i.ZERO
	overlay.hide()
	_snap()
	_update_hud()


func _undo() -> void:
	if history.is_empty() or finished == "won":
		return
	state = history.pop_back()
	finished = ""
	armed = ""
	hint_dir = Vector2i.ZERO
	overlay.hide()
	_snap()
	_update_hud()


func _try_move(dir: Vector2i) -> void:
	if screen != "play" or finished != "" or overlay.visible:
		return
	_snap()
	facing = dir
	if armed == "blast":
		armed = ""
		var b := lv.blast(state, dir)
		if b.is_empty():
			_toast("No inner wall there to blast.")
		else:
			_use_booster("blast")
			history.append(state)
			state = b
		_update_hud()
		return
	var pull: bool = armed == "pull" and state.boxes.has(state.p - dir)
	var next := lv.step(state, dir, pull)
	if next.is_empty():
		_bump(dir)
		return
	if pull:
		armed = ""
		_use_booster("pull")
	history.append(state)
	_start_animation(state, next)
	state = next
	hint_dir = Vector2i.ZERO
	var o := lv.outcome(state)
	if o == "won":
		_on_won()
	elif o != "":
		finished = o
		_on_failed(o)
	_update_hud()


func _on_won() -> void:
	finished = "won"
	var lid: String = zones[zone_i].levels[level_i].id
	var stars := _stars_for(state.moves, lv.par, booster_used)
	var first_clear := not best.has(lid)
	best[lid] = maxi(best.get(lid, 0), stars)
	_save_progress()
	var last_in_zone: bool = level_i == zones[zone_i].levels.size() - 1
	var text := "%d moves" % state.moves
	if lv.par > 0:
		text += "   ·   best possible %d" % lv.par
	if booster_used and stars < 3:
		text += "\nTools used: 2 stars at most."
	var buttons := [["Replay", _restart_attempt]]
	if not last_in_zone:
		buttons.append(["Next", _start_level.bind(zone_i, level_i + 1)])
	elif zone_i < zones.size() - 1:
		if first_clear:
			text += "\n\n%s is powered up. %s is open." % [zones[zone_i].name, zones[zone_i + 1].name]
		buttons.append(["Next zone", _go_next_zone])
	else:
		text += "\n\nThe core is back online. The station lights up. Thanks, Kip!"
		buttons.append(["Map", _show_map])
	await get_tree().create_timer(0.45).timeout
	if finished == "won" and screen == "play":
		_show_overlay("Charged!", text, stars, buttons)


func _go_next_zone() -> void:
	_show_map()
	_open_zone(zone_i + 1)


func _on_failed(reason: String) -> void:
	await get_tree().create_timer(0.35).timeout
	if finished == reason and screen == "play":
		_show_overlay("Oops", reason, -1, [["Undo", _undo], ["Restart", _restart]])


func _use_booster(b: String) -> void:
	uses[b] = uses.get(b, 0) - 1
	booster_used = true


func _on_booster(b: String) -> void:
	if screen != "play" or finished != "" or uses.get(b, 0) <= 0:
		return
	match b:
		"pull", "blast":
			armed = "" if armed == b else b
			if armed == "pull":
				_toast("Walk away from a crate to pull it along.")
			elif armed == "blast":
				_toast("Swipe toward the wall to blast.")
		"moves":
			if lv.limit <= 0:
				_toast("This room has no move limit.")
				return
			history.append(state)
			state = state.duplicate(true)
			state.bonus += 5
			_use_booster(b)
		"hint":
			_run_hint()
	_update_hud()


func _run_hint() -> void:
	if hint_busy:
		return
	hint_busy = true
	_toast("Scanning...")
	var for_state := state
	var sol = await lv.solve(state, 150000, get_tree())
	hint_busy = false
	if state != for_state or screen != "play":
		return
	if sol == null or sol == "":
		_toast("No way forward from here. Try Undo.")
		return
	_use_booster("hint")
	hint_dir = {"u": Vector2i.UP, "d": Vector2i.DOWN, "l": Vector2i.LEFT, "r": Vector2i.RIGHT}[sol[0]]
	_toast("")
	_update_hud()


func _toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	if text != "":
		var tw := create_tween()
		tw.tween_interval(1.8)
		tw.tween_property(toast_label, "modulate:a", 0.0, 0.5)


# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			swipe_start = event.position
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
	elif event is InputEventScreenDrag and event.index == touch_index:
		# Keep dragging to keep walking: every swipe length moves one cell.
		var delta: Vector2 = event.position - swipe_start
		if delta.length() >= maxf(SWIPE_MIN, cell * 0.55):
			if absf(delta.x) > absf(delta.y):
				_try_move(Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT)
			else:
				_try_move(Vector2i.DOWN if delta.y > 0 else Vector2i.UP)
			swipe_start = event.position
	elif event is InputEventKey and event.pressed:
		_on_key(event)


func _on_key(event: InputEventKey) -> void:
	var handled := true
	match event.physical_keycode:
		KEY_UP, KEY_W:
			_try_move(Vector2i.UP)
		KEY_DOWN, KEY_S:
			_try_move(Vector2i.DOWN)
		KEY_LEFT, KEY_A:
			_try_move(Vector2i.LEFT)
		KEY_RIGHT, KEY_D:
			_try_move(Vector2i.RIGHT)
		KEY_Z, KEY_U, KEY_BACKSPACE:
			if screen == "play":
				_undo()
		KEY_R:
			if screen == "play" and not event.echo:
				_restart()
		KEY_H:
			if screen == "play":
				_on_booster("hint")
		KEY_ESCAPE:
			_back()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if overlay.visible and not event.echo:
				var bs := overlay_buttons.get_children()
				if not bs.is_empty():
					(bs[bs.size() - 1] as Button).pressed.emit()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _back() -> void:
	if overlay.visible and screen != "play":
		_hide_overlay()
	elif screen == "play":
		_show_levels()
	elif screen == "levels":
		_show_map()


func _on_title_tapped() -> void:
	# Seven taps on the title unlock every zone, for testing.
	title_taps += 1
	if title_taps == 7:
		for z in zones:
			for l in z.levels:
				if not best.has(l.id):
					best[l.id] = 1
		_save_progress()
		_show_map()


# --- Animation & drawing --------------------------------------------------------

func _process(delta: float) -> void:
	if screen != "play":
		return
	clock += delta
	anim_t = minf(anim_t + delta / MOVE_TIME, 1.0)
	bump_t = minf(bump_t + delta / BUMP_TIME, 1.0)
	queue_redraw()


func _start_animation(old: Dictionary, new: Dictionary) -> void:
	crate_moves.clear()
	player_from = Vector2(old.p)
	var gone: Array = old.boxes.keys().filter(func(p): return not new.boxes.has(p))
	var came: Array = new.boxes.keys().filter(func(p): return not old.boxes.has(p))
	if gone.size() == 1 and came.size() == 1 and _straight(gone[0], came[0]):
		crate_moves[came[0]] = Vector2(gone[0])
	anim_t = 0.0 if _straight(old.p, new.p) else 1.0


func _straight(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x or a.y == b.y


func _snap() -> void:
	anim_t = 1.0
	bump_t = 1.0
	crate_moves.clear()
	queue_redraw()


func _bump(dir: Vector2i) -> void:
	bump_dir = Vector2(dir)
	bump_t = 0.0


func _layout() -> void:
	if lv == null:
		return
	var view := get_viewport_rect().size
	var area := Rect2(Vector2(MARGIN, TOP_BAR), view - Vector2(MARGIN * 2.0, TOP_BAR + BOTTOM_BAR))
	cell = floorf(minf(minf(area.size.x / lv.size.x, area.size.y / lv.size.y), MAX_CELL))
	origin = (area.position + (area.size - Vector2(lv.size) * cell) / 2.0).floor()
	wall_style.bg_color = C_WALL
	wall_style.border_color = C_WALL_EDGE
	wall_style.border_width_bottom = int(cell * 0.12)
	wall_style.set_corner_radius_all(int(cell * 0.12))
	crate_style.set_corner_radius_all(int(cell * 0.14))
	crate_style.set_border_width_all(int(cell * 0.08))
	robot_style.set_corner_radius_all(int(cell * 0.2))
	robot_style.bg_color = C_PLAYER
	queue_redraw()


func _cell_rect(p: Vector2) -> Rect2:
	return Rect2(origin + p * cell, Vector2(cell, cell))


func _draw() -> void:
	if screen != "play" or lv == null:
		return
	var on := lv.hazards_on(state)
	for p in lv.inside:
		_draw_floor(p, on)
	for p in lv.walls:
		if not state.blasted.has(p):
			draw_style_box(wall_style, _cell_rect(Vector2(p)).grow(-cell * 0.02))
	for p in lv.goals:
		var col: Color = C_GOAL if lv.goals[p] == "" else CRATE_COLORS[lv.goals[p]]
		var c := _cell_rect(Vector2(p)).get_center()
		draw_arc(c, cell * 0.24, 0.0, TAU, 32, col, cell * 0.07, true)
		draw_circle(c, cell * 0.07, col, true, -1.0, true)

	var k := 1.0 - pow(1.0 - anim_t, 3.0)
	for p: Vector2i in state.boxes:
		var pos := Vector2(p)
		if crate_moves.has(p) and anim_t < 1.0:
			pos = crate_moves[p].lerp(pos, k)
		_draw_crate(pos, state.boxes[p], _crate_done(p) and anim_t >= 1.0)

	var ppos := player_from.lerp(Vector2(state.p), k) if anim_t < 1.0 else Vector2(state.p)
	if bump_t < 1.0:
		ppos += bump_dir * 0.12 * sin(bump_t * PI)
	_draw_robot(ppos)
	if hint_dir != Vector2i.ZERO:
		var c := _cell_rect(Vector2(state.p)).get_center()
		var d := Vector2(hint_dir)
		var tip := c + d * cell * (0.9 + 0.08 * sin(clock * 6.0))
		var side := Vector2(-d.y, d.x) * cell * 0.22
		draw_colored_polygon(PackedVector2Array([tip, tip - d * cell * 0.3 + side, tip - d * cell * 0.3 - side]), C_TEXT)


func _crate_done(p: Vector2i) -> bool:
	if not lv.goals.has(p):
		return false
	return lv.goals[p] == "" or lv.goals[p] == state.boxes[p]


func _draw_floor(p: Vector2i, on: bool) -> void:
	var r := _cell_rect(Vector2(p))
	var c := r.get_center()
	if lv.walls.has(p):  # blasted wall
		draw_rect(r, C_FLOOR.darkened(0.15))
		return
	if lv.crumble.has(p):
		var st: String = state.crumbled.get(p, "")
		if st == "pit":
			draw_rect(r, Color("0b0c14"))
			draw_rect(Rect2(r.position, Vector2(cell, cell * 0.18)), Color("1c1f33"))
			return
		draw_rect(r, C_FLOOR if st == "filled" else Color("3a3346"))
		if st == "filled":
			draw_rect(r.grow(-cell * 0.12), Color("2d3150"), false, cell * 0.04)
		else:
			var col := Color("1d1a26")
			draw_polyline(PackedVector2Array([r.position + Vector2(0.2, 0.15) * cell, c, r.position + Vector2(0.75, 0.3) * cell]), col, cell * 0.04, true)
			draw_line(c, r.position + Vector2(0.55, 0.85) * cell, col, cell * 0.04, true)
		return
	draw_rect(r, C_FLOOR)
	if lv.ice.has(p):
		draw_rect(r, Color(0.62, 0.86, 0.96, 0.32))
		draw_line(r.position + Vector2(0.2, 0.55) * cell, r.position + Vector2(0.45, 0.3) * cell, Color(1, 1, 1, 0.55), cell * 0.04, true)
		draw_line(r.position + Vector2(0.5, 0.75) * cell, r.position + Vector2(0.75, 0.5) * cell, Color(1, 1, 1, 0.35), cell * 0.04, true)
	elif lv.arrows.has(p):
		var d := Vector2(lv.arrows[p])
		var s := Vector2(-d.y, d.x)
		for i in 2:
			var tip := c + d * cell * (0.08 + 0.22 * i - 0.05)
			draw_polyline(PackedVector2Array([tip - d * cell * 0.16 + s * cell * 0.2, tip, tip - d * cell * 0.16 - s * cell * 0.2]), Color("7fd6ff", 0.8), cell * 0.07, true)
	elif lv.plates.has(p):
		var pressed: bool = state.boxes.has(p)
		var pr := r.grow(-cell * 0.14)
		draw_rect(pr, Color("ffb347", 0.55 if pressed else 0.12))
		draw_rect(pr, Color("ffb347", 0.9), false, cell * 0.05)
	elif lv.fire.has(p):
		if on:
			_draw_fire(c)
		else:
			for i in 3:
				draw_circle(c + Vector2(i - 1, 0.3) * cell * 0.18, cell * 0.05, Color("5a5f7a"))
	elif lv.holes.has(p):
		if on:
			draw_circle(c, cell * 0.42, Color("120a1f"), true, -1.0, true)
			for i in 3:
				var a := clock * 2.5 + i * TAU / 3.0
				draw_arc(c, cell * (0.18 + 0.08 * i), a, a + 2.2, 16, Color("a35cff", 0.8 - i * 0.2), cell * 0.05, true)
		else:
			draw_arc(c, cell * 0.38, 0.0, TAU, 32, Color("4a3a6a"), cell * 0.05, true)
	elif lv.teleports.has(p):
		var tw: Vector2i = lv.teleports[p]
		var pair := mini(p.x * 100 + p.y, tw.x * 100 + tw.y)
		var col: Color = PAD_COLORS[_pad_index(pair)]
		draw_arc(c, cell * 0.38, 0.0, TAU, 32, col, cell * 0.07, true)
		draw_arc(c, cell * (0.12 + 0.12 * fmod(clock * 0.8, 1.0)), 0.0, TAU, 24, Color(col, 0.7), cell * 0.04, true)
	elif lv.doors.has(p):
		if state.open.has(p):
			draw_rect(r.grow(-cell * 0.06), Color("8a5a2b", 0.5), false, cell * 0.04)
		else:
			draw_rect(r.grow(-cell * 0.04), Color("8a5a2b"))
			draw_rect(r.grow(-cell * 0.04), Color("5e3b1a"), false, cell * 0.06)
			draw_circle(c - Vector2(0, cell * 0.06), cell * 0.09, Color("2a1a0a"))
			draw_rect(Rect2(c + Vector2(-0.04, 0) * cell, Vector2(0.08, 0.2) * cell), Color("2a1a0a"))
	if lv.has_pickup(state, p):
		if lv.pickups[p] == "k":
			var g := Color("ffd23f")
			draw_arc(c + Vector2(-0.14, 0) * cell, cell * 0.12, 0.0, TAU, 20, g, cell * 0.06, true)
			draw_line(c + Vector2(-0.02, 0) * cell, c + Vector2(0.3, 0) * cell, g, cell * 0.07)
			draw_line(c + Vector2(0.22, 0) * cell, c + Vector2(0.22, 0.12) * cell, g, cell * 0.06)
		else:
			draw_circle(c, cell * 0.3, Color("e8f0ff"), true, -1.0, true)
			var f := ThemeDB.fallback_font
			var fs := int(cell * 0.3)
			var w := f.get_string_size("+5", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, c + Vector2(-w / 2.0, fs * 0.35), "+5", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_BG)


func _pad_index(pair: int) -> int:
	var keys: Array = []
	for p: Vector2i in lv.teleports:
		var tw: Vector2i = lv.teleports[p]
		var k := mini(p.x * 100 + p.y, tw.x * 100 + tw.y)
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	return keys.find(pair) % PAD_COLORS.size()


func _draw_fire(c: Vector2) -> void:
	var f := sin(clock * 9.0 + c.x) * 0.05
	var flames := [[Color("ff5a36"), 0.36], [Color("ff9a3c"), 0.26], [Color("ffe066"), 0.15]]
	for fl in flames:
		var h: float = fl[1] * (1.0 + f)
		var w: float = fl[1] * 0.8
		var base := c + Vector2(0, cell * 0.3)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0) * cell,
			base + Vector2(-w * 0.7, -h * 1.2) * cell,
			base + Vector2(f * 2.0, -h * 2.2) * cell,
			base + Vector2(w * 0.7, -h * 1.2) * cell,
			base + Vector2(w, 0) * cell,
		]), fl[0])


func _draw_crate(pos: Vector2, kind: String, done: bool) -> void:
	var r := _cell_rect(pos).grow(-cell * 0.08)
	var fill := C_BOX
	var edge := C_BOX_EDGE
	if kind == "&":
		fill = Color("8d93a8")
		edge = Color("5b6075")
	elif CRATE_COLORS.has(kind):
		fill = CRATE_COLORS[kind]
		edge = fill.darkened(0.4)
	if done:
		if kind == "$":
			fill = C_DONE
			edge = C_DONE_EDGE
		else:
			edge = Color("ffffff")
	crate_style.bg_color = fill
	crate_style.border_color = edge
	draw_style_box(crate_style, r)
	var inner := r.grow(-cell * 0.2)
	var shade := Color(0, 0, 0, 0.2)
	if kind == "&":
		for corner in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
			draw_circle(corner, cell * 0.05, shade)
		draw_rect(inner.grow(-cell * 0.08), shade, false, cell * 0.05)
	else:
		# Battery bolt
		var c := r.get_center()
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.06, -0.24) * cell, c + Vector2(-0.12, 0.03) * cell, c + Vector2(0.0, 0.03) * cell,
			c + Vector2(-0.06, 0.24) * cell, c + Vector2(0.12, -0.03) * cell, c + Vector2(0.0, -0.03) * cell,
		]), Color(1, 1, 1, 0.55) if done else shade)


func _draw_robot(pos: Vector2) -> void:
	var r := _cell_rect(pos)
	var body := Rect2(r.position + Vector2(0.17, 0.26) * cell, Vector2(0.66, 0.6) * cell)
	if armed != "":
		var glow := Color("ffd23f") if armed == "pull" else Color("ff5a36")
		draw_circle(r.get_center(), cell * 0.5, Color(glow, 0.25 + 0.1 * sin(clock * 8.0)), true, -1.0, true)
	var ant := Vector2(body.get_center().x, body.position.y)
	draw_line(ant, ant - Vector2(0, cell * 0.14), C_PLAYER, cell * 0.05)
	draw_circle(ant - Vector2(0, cell * 0.16), cell * 0.06, C_GOAL, true, -1.0, true)
	draw_style_box(robot_style, body)
	var visor := Rect2(body.position + Vector2(0.09, 0.12) * cell, Vector2(0.48, 0.22) * cell)
	draw_rect(visor, C_EYE)
	var look := Vector2(facing) * cell * 0.06
	for s in [-1.0, 1.0]:
		draw_circle(visor.get_center() + Vector2(s * cell * 0.11, 0) + look, cell * 0.05, C_PLAYER, true, -1.0, true)


# --- HUD ------------------------------------------------------------------------

func _update_hud() -> void:
	if lv == null or screen != "play":
		return
	var z: Dictionary = zones[zone_i]
	title_label.text = "%d-%d  ·  %s" % [zone_i + 1, level_i + 1, lv.title]
	var info := "Moves %d" % state.moves
	if lv.limit > 0:
		info = "Moves %d / %d" % [state.moves, lv.budget(state)]
	if lv.par > 0:
		info += "    Best %d" % lv.par
	var placed := 0
	for g in lv.goals:
		if state.boxes.has(g) and _crate_done(g):
			placed += 1
	info += "    Charged %d / %d" % [placed, lv.goals.size()]
	if state.keys > 0:
		info += "    Keys %d" % state.keys
	info_label.text = info
	tip_label.text = lv.tip
	tip_label.visible = lv.tip != "" and state.moves < 6
	undo_button.disabled = history.is_empty()
	for b in booster_buttons:
		var btn: Button = booster_buttons[b]
		btn.visible = uses.has(b)
		btn.text = "%s ×%d" % [BOOSTERS[b].label, uses.get(b, 0)]
		btn.disabled = uses.get(b, 0) <= 0 or (b == "moves" and lv.limit <= 0)
		btn.add_theme_color_override("font_color", z.color if armed == b else C_TEXT)
	booster_row.visible = not uses.is_empty()
	queue_redraw()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_map()
	_build_levels()
	_build_play()
	_build_overlay()


func _build_map() -> void:
	map_screen = _full_rect(ui)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 14)
	map_screen.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 32
	col.offset_right = -32
	col.offset_top = 60
	col.offset_bottom = -40
	var title := _label("CRATE PUSH", 64, C_GOAL)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_on_title_tapped())
	col.add_child(title)
	col.add_child(_label("Kip the cargo robot is restarting a dark space station, one battery crate at a time.", 26, C_DIM))
	map_stars = _label("", 28, C_STAR)
	col.add_child(map_stars)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	zone_list = VBoxContainer.new()
	zone_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone_list.add_theme_constant_override("separation", 14)
	scroll.add_child(zone_list)


func _build_levels() -> void:
	levels_screen = _full_rect(ui)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 20)
	levels_screen.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 32
	col.offset_right = -32
	col.offset_top = 40
	col.offset_bottom = -40
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var back := _button("<", _show_map)
	back.custom_minimum_size = Vector2(96, 96)
	top.add_child(back)
	levels_title = _label("", 44, C_TEXT)
	levels_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(levels_title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(96, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	levels_story = _label("", 26, C_DIM)
	col.add_child(levels_story)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(center)
	levels_grid = GridContainer.new()
	levels_grid.columns = 4
	levels_grid.add_theme_constant_override("h_separation", 18)
	levels_grid.add_theme_constant_override("v_separation", 18)
	center.add_child(levels_grid)


func _build_play() -> void:
	play_hud = _full_rect(ui)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_hud.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 36
	top.offset_bottom = 136
	var back := _button("<", _show_levels)
	back.custom_minimum_size = Vector2(96, 96)
	top.add_child(back)
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(titles)
	title_label = _label("", 34, C_TEXT)
	titles.add_child(title_label)
	info_label = _label("", 24, C_DIM)
	titles.add_child(info_label)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(96, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)

	tip_label = _label("", 26, C_DIM)
	play_hud.add_child(tip_label)
	tip_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tip_label.offset_left = 30
	tip_label.offset_right = -30
	tip_label.offset_top = 132
	tip_label.offset_bottom = 186

	toast_label = _label("", 28, C_STAR)
	play_hud.add_child(toast_label)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_top = -BOTTOM_BAR - 40
	toast_label.offset_bottom = -BOTTOM_BAR + 4

	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 14)
	play_hud.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -BOTTOM_BAR + 20
	bottom.offset_bottom = -36
	bottom.alignment = BoxContainer.ALIGNMENT_END
	booster_row = HBoxContainer.new()
	booster_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	booster_row.add_theme_constant_override("separation", 12)
	bottom.add_child(booster_row)
	for b in BOOSTERS:
		var btn := _button(BOOSTERS[b].label, _on_booster.bind(b))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 74)
		btn.add_theme_font_size_override("font_size", 26)
		booster_row.add_child(btn)
		booster_buttons[b] = btn
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)
	bottom.add_child(row)
	undo_button = _button("Undo", _undo)
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_button.custom_minimum_size = Vector2(0, 100)
	row.add_child(undo_button)
	var restart := _button("Restart", _restart)
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart.custom_minimum_size = Vector2(0, 100)
	row.add_child(restart)


func _build_overlay() -> void:
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0.05, 0.06, 0.1, 0.86)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	overlay.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 50
	box.offset_right = -50
	overlay_title = _label("", 64, C_GOAL)
	box.add_child(overlay_title)
	overlay_stars = _stars_view(0, 48.0)
	box.add_child(overlay_stars)
	overlay_text = _label("", 30, C_TEXT)
	box.add_child(overlay_text)
	overlay_buttons = HBoxContainer.new()
	overlay_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_buttons.add_theme_constant_override("separation", 20)
	box.add_child(overlay_buttons)
	overlay.hide()


## buttons: [[label, callable], ...]; the last one is the default (Enter).
func _show_overlay(title: String, text: String, stars: int, buttons: Array) -> void:
	overlay_title.text = title
	overlay_text.text = text
	overlay_stars.visible = stars >= 0
	overlay_stars.set_meta("stars", maxi(stars, 0))
	overlay_stars.queue_redraw()
	for c in overlay_buttons.get_children():
		c.queue_free()
	for b in buttons:
		var btn := _button(b[0], b[1])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 104)
		overlay_buttons.add_child(btn)
	overlay.show()


func _hide_overlay() -> void:
	overlay.hide()


func _full_rect(parent: Control) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


func _stars_view(n: int, radius: float) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(radius * 7.0, radius * 2.2)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.set_meta("stars", n)
	c.draw.connect(func() -> void:
		var got: int = c.get_meta("stars")
		for i in 3:
			var center := Vector2(radius * (1.2 + 2.3 * i), radius * 1.1)
			var pts := PackedVector2Array()
			for j in 10:
				var a := -PI / 2.0 + j * PI / 5.0
				var rr := radius if j % 2 == 0 else radius * 0.45
				pts.append(center + Vector2(cos(a), sin(a)) * rr)
			c.draw_colored_polygon(pts, C_STAR if i < got else Color(C_DIM, 0.3)))
	return c


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for walking
	b.pressed.connect(action)
	return b


func _make_theme() -> Theme:
	var t := Theme.new()
	t.set_font_size("font_size", "Button", 38)
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = C_BUTTON_HOVER if st == "hover" or st == "pressed" else C_BUTTON
		if st == "disabled":
			s.bg_color.a = 0.45
		s.set_corner_radius_all(22)
		s.content_margin_left = 14
		s.content_margin_right = 14
		t.set_stylebox(st, "Button", s)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", C_GOAL)
	t.set_color("font_disabled_color", "Button", Color(C_DIM, 0.5))
	return t
