extends Node2D
## Crate Push: a cargo robot puts battery crates back on their chargers to
## restart an abandoned space station.
##
## Screens: zone map -> level list -> board. Levels live in res://levels/
## (see README.md); the rules are in rules.gd.

const SAVE_PATH := "user://crate_push.cfg"

const TOP_BAR := 190.0
const BOTTOM_BAR := 460.0
const PAD_CELL := 104.0  # one arrow button of the on-screen d-pad
const HOLD_DELAY := 0.3  # hold an arrow this long to start walking
const HOLD_STEP := 0.14
const MARGIN := 20.0
const MAX_CELL := 110.0
const HERO_CELL := 120.0  # menu animation tile size
const HERO_LOOP := 4.4    # seconds per loop of the menu animation
const RIM := 0.16  # outer walls are drawn as a thin rim this many cells thick
const SWIPE_MIN := 36.0
const MOVE_TIME := 0.12
const STEP_TIME := 0.32  # the robot's hop, lean and dust after each step
const BUMP_TIME := 0.12

const BOOSTERS := {
	"hint": {"label": "Hint", "uses": 3, "icon": "hint"},
	"pull": {"label": "Pull", "uses": 1, "icon": "pull"},
	"blast": {"label": "Blast", "uses": 1, "icon": "wall-blast"},
	"moves": {"label": "+5", "uses": 1, "icon": "plus-five-moves"},
}

const C_BG := Color("171a29")
const C_FLOOR := Color("23263a")
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
const C_STAR := Color("3fe0c0")
const C_ORANGE := Color("ff8a1f")
const C_INK := Color("0d0f1a")
const CRATE_NAMES := {"a": "red", "b": "blue", "c": "green"}
const PAD_SPRITES := ["teleport-blue", "teleport-purple"]
const C_FLOOR_LINE := Color(1, 1, 1, 0.035)
const C_WALL_TOP := Color("59628f")
const C_WALL_SIDE := Color("2c3150")
const C_WALL_HI := Color("8a93c2")
const C_TARGET := Color("3fe0c0")
const TARGET_GLOW := {"a": Color("ff6b6b"), "b": Color("5aa9ff"), "c": Color("6fd08c")}

var zones: Array[Dictionary] = []
var best := {}        # level id -> stars (1..3)
var intro_seen := {}  # zone id -> true
var tips_seen := {}   # tip card id -> true (see tutorials.gd)
var tips_off := false

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
var step_t := 1.0
var step_dir := Vector2.ZERO
var step_push := false
var clock := 0.0

# Layout
var cell := 64.0
var outer := {}  # wall cells on the room's border, drawn as a thin rim
var core := Rect2i()  # floor and inner walls, the part of the map that gets drawn in full
var origin := Vector2.ZERO

# Touch
var touch_index := -1
var hold_dir := Vector2i.ZERO  # d-pad arrow being held
var hold_t := 0.0
var swipe_start := Vector2.ZERO
var title_taps := 0

# UI
var ui: Control
var menu_screen: Control
var menu_stars: Label
var menu_hero: Control
var menu_t := 0.0
var continue_button: Button
var map_screen: Control
var zone_list: VBoxContainer
var map_stars: Label
var levels_screen: Control
var levels_title: Label
var levels_story: Label
var levels_progress: Control
var levels_grid: GridContainer
var play_hud: Control
var title_label: Label
var info_label: Label
var tip_label: Label
var toast_label: Label
var booster_row: HBoxContainer
var booster_buttons := {}
var undo_button: Button
var restart_button: Button
var overlay: Control
var overlay_title: Label
var overlay_stars: Control
var overlay_text: Label
var overlay_buttons: HBoxContainer
var overlay_items: GridContainer
var tips_button: Button

# Tip cards
var card: PanelContainer
var card_icon: TextureRect
var card_title: Label
var card_text: Label
var card_ok: Button
var rings: Array[Panel] = []
var dpad: Control
var tip_now := ""     # the card on screen, or ""
var tip_queue: Array[String] = []
var tip_moves := 0    # moves made while the current card is up


func _ready() -> void:
	zones = Campaign.load_zones()
	_load_progress()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_show_menu()


# --- Screens --------------------------------------------------------------------

func _show_menu() -> void:
	screen = "menu"
	var got := 0
	var total := 0
	for z in zones:
		for l in z.levels:
			got += best.get(l.id, 0)
			total += 3
	menu_stars.text = "%d / %d" % [got, total]
	continue_button.visible = not best.is_empty() and _next_level() != Vector2i(-1, -1)
	tips_button.text = "Tips: Off" if tips_off else "Tips: On"
	_set_screen(menu_screen)


## The first open level without a win, or (-1, -1) when every level is won.
func _next_level() -> Vector2i:
	for z in zones.size():
		if not _zone_open(z):
			break
		for i in zones[z].levels.size():
			if not best.has(zones[z].levels[i].id):
				return Vector2i(z, i)
	return Vector2i(-1, -1)


func _continue() -> void:
	var n := _next_level()
	if n.x >= 0:
		_start_level(n.x, n.y)


func _show_map() -> void:
	screen = "map"
	for c in zone_list.get_children():
		c.queue_free()
	var total := 0
	var got := 0
	var current := _next_level().x
	for i in zones.size():
		var z: Dictionary = zones[i]
		var open := _zone_open(i)
		var stars := 0
		for l in z.levels:
			stars += best.get(l.id, 0)
		total += z.levels.size() * 3
		got += stars
		zone_list.add_child(_zone_row(i, open, stars, i == current))
	map_stars.text = "%d / %d" % [got, total]
	_set_screen(map_screen)


func _zone_row(i: int, open: bool, stars: int, current: bool) -> Button:
	var z: Dictionary = zones[i]
	var b := _button("", _open_zone.bind(i))
	b.custom_minimum_size = Vector2(0, 150)
	b.disabled = not open
	var m := Vector4(44, 44, 44, 44)
	var c := Vector4(30, 18, 30, 18)
	b.add_theme_stylebox_override("normal", UiArt.box("panel-frame", m, c))
	b.add_theme_stylebox_override("hover", UiArt.box("panel-frame", m, c, Color(1.15, 1.15, 1.2)))
	b.add_theme_stylebox_override("pressed", UiArt.box("panel-frame", m, c, Color(0.8, 0.8, 0.85)))
	b.add_theme_stylebox_override("disabled", UiArt.box("panel-frame", m, c, Color(0.6, 0.6, 0.65)))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 22)
	b.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 40
	row.offset_right = -34
	row.offset_top = 16
	row.offset_bottom = -16
	var icon := _ui_rect(UiArt.zone_icon(z.id), Vector2(104, 104))
	if not open:
		icon.modulate = Color(0.45, 0.45, 0.5)
	row.add_child(icon)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(names)
	var name_label := _label(z.name, 36, C_TEXT if open else C_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(name_label)
	var sub := _label("Zone %d" % (i + 1), 22, z.color if open else C_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	names.add_child(sub)
	if open:
		var count := HBoxContainer.new()
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.add_theme_constant_override("separation", 6)
		count.add_child(_ui_rect("star-filled", Vector2(40, 40)))
		var n := _label("%d/%d" % [stars, z.levels.size() * 3], 28, C_STAR)
		n.autowrap_mode = TextServer.AUTOWRAP_OFF
		count.add_child(n)
		row.add_child(count)
	else:
		row.add_child(_ui_rect("padlock", Vector2(56, 64)))
	if current:
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.draw_center = false
		st.border_color = C_ORANGE
		st.set_border_width_all(6)
		st.set_corner_radius_all(20)
		ring.add_theme_stylebox_override("panel", st)
		b.add_child(ring)
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.offset_left = 4
		ring.offset_top = 4
		ring.offset_right = -4
		ring.offset_bottom = -4
	return b


func _open_zone(i: int) -> void:
	zone_i = i
	var z: Dictionary = zones[i]
	if not intro_seen.has(z.id):
		intro_seen[z.id] = true
		_save_progress()
		_show_levels()
		_show_overlay(z.name, z.story, -1, [["Let's go", _hide_overlay]])
		_show_overlay_items(_zone_new_items(i))
		return
	_show_levels()


func _show_levels() -> void:
	screen = "levels"
	var z: Dictionary = zones[zone_i]
	levels_title.text = z.name.to_upper()
	levels_title.add_theme_color_override("font_color", z.color)
	levels_story.text = z.story.get_slice("\n", 0)
	for c in levels_grid.get_children():
		c.queue_free()
	var done := 0
	var current := _next_level()
	for i in z.levels.size():
		var id: String = z.levels[i].id
		if best.has(id):
			done += 1
		var open := _level_open(zone_i, i)
		var art := "level-unlocked"
		if not open:
			art = "level-locked"
		elif current == Vector2i(zone_i, i):
			art = "level-current"
		var b := _button("", _start_level.bind(zone_i, i))
		b.custom_minimum_size = Vector2(196, 190)
		b.disabled = not open
		var m := Vector4(48, 48, 48, 48)
		b.add_theme_stylebox_override("normal", UiArt.box(art, m))
		b.add_theme_stylebox_override("hover", UiArt.box(art, m, Vector4.ZERO, Color(1.12, 1.12, 1.15)))
		b.add_theme_stylebox_override("pressed", UiArt.box(art, m, Vector4.ZERO, Color(0.8, 0.8, 0.85)))
		b.add_theme_stylebox_override("disabled", UiArt.box(art, m))
		if open:
			var box := VBoxContainer.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.alignment = BoxContainer.ALIGNMENT_CENTER
			box.add_theme_constant_override("separation", -4)
			b.add_child(box)
			box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			box.offset_top = 10
			box.offset_bottom = -34
			box.add_child(_label(str(i + 1), 60, C_TEXT))
			box.add_child(_stars_view(best.get(id, 0), 18.0))
		levels_grid.add_child(b)
	levels_progress.set_meta("done", done)
	levels_progress.set_meta("total", z.levels.size())
	levels_progress.queue_redraw()
	_set_screen(levels_screen)


func _set_screen(c: Control) -> void:
	hold_dir = Vector2i.ZERO
	for s in [menu_screen, map_screen, levels_screen, play_hud]:
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
	tips_seen = cfg.get_value("progress", "tips_seen", {})
	tips_off = cfg.get_value("progress", "tips_off", false)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "intro_seen", intro_seen)
	cfg.set_value("progress", "tips_seen", tips_seen)
	cfg.set_value("progress", "tips_off", tips_off)
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
	_find_outer_walls()
	screen = "play"
	_set_screen(play_hud)
	_restart_attempt()
	_queue_tips()
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
	# A fresh attempt: the undo history is cleared, so Undo can't bring back
	# moves from before the restart.
	_restart_attempt()


## Restart asks first, so a stray tap doesn't throw away a long attempt.
func _ask_restart() -> void:
	if screen != "play" or overlay.visible:
		return
	if finished == "won":
		_restart_attempt()
		return
	if history.is_empty():
		return
	hold_dir = Vector2i.ZERO
	_show_overlay("Restart?", "Start this room over from the beginning?", -1,
			[["Cancel", _hide_overlay], ["Restart", _restart]])


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
	var before := state
	state = next
	hint_dir = Vector2i.ZERO
	_tip_after_move(before, next)
	var o := lv.outcome(state)
	if o == "won":
		_on_won()
	elif o != "":
		finished = o
		_on_failed(o)
	_update_hud()


func _on_won() -> void:
	finished = "won"
	tip_queue.clear()
	_hide_card()
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
	if not tips_off and not tips_seen.has("stars"):
		tips_seen["stars"] = true
		_save_progress()
		text += "\n\n3 stars: solve it in the best possible moves, with no tools. Replay any room to do better."
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
		if event.pressed and touch_index == -1 and _on_board(event.position):
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
				_ask_restart()
		KEY_H:
			if screen == "play":
				_on_booster("hint")
		KEY_ESCAPE:
			_back()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not overlay.visible and screen == "play" and tip_now != "" and card_ok.visible and not event.echo:
				_next_tip()
			elif overlay.visible and not event.echo:
				var bs := overlay_buttons.get_children()
				if not bs.is_empty():
					(bs[bs.size() - 1] as Button).pressed.emit()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Swipes only count when they start above the bottom controls, so pressing
## a d-pad arrow never also counts as a swipe.
func _on_board(pos: Vector2) -> bool:
	return screen != "play" or pos.y < get_viewport_rect().size.y - BOTTOM_BAR + 20.0


func _back() -> void:
	if overlay.visible and (screen != "play" or finished == ""):
		_hide_overlay()  # popups on the map, or the restart question
	elif screen == "play":
		_show_levels()
	elif screen == "levels":
		_show_map()
	elif screen == "map":
		_show_menu()


func _on_title_tapped() -> void:
	# Seven taps on the title unlock every zone, for testing.
	title_taps += 1
	if title_taps == 7:
		for z in zones:
			for l in z.levels:
				if not best.has(l.id):
					best[l.id] = 1
		_save_progress()
		_show_menu()


# --- Animation & drawing --------------------------------------------------------

func _process(delta: float) -> void:
	if screen == "menu":
		menu_t = fmod(menu_t + delta, HERO_LOOP)
		menu_hero.queue_redraw()
	if screen != "play":
		return
	clock += delta
	_update_ring()
	if hold_dir != Vector2i.ZERO:
		hold_t -= delta
		if hold_t <= 0.0:
			hold_t = HOLD_STEP
			_try_move(hold_dir)
	anim_t = minf(anim_t + delta / MOVE_TIME, 1.0)
	bump_t = minf(bump_t + delta / BUMP_TIME, 1.0)
	step_t = minf(step_t + delta / STEP_TIME, 1.0)
	queue_redraw()


func _start_animation(old: Dictionary, new: Dictionary) -> void:
	crate_moves.clear()
	player_from = Vector2(old.p)
	var gone: Array = old.boxes.keys().filter(func(p): return not new.boxes.has(p))
	var came: Array = new.boxes.keys().filter(func(p): return not old.boxes.has(p))
	if gone.size() == 1 and came.size() == 1 and _straight(gone[0], came[0]):
		crate_moves[came[0]] = Vector2(gone[0])
	anim_t = 0.0 if _straight(old.p, new.p) else 1.0
	if old.p != new.p and anim_t == 0.0:
		step_t = 0.0
		step_dir = Vector2(new.p - old.p).normalized()
		step_push = not crate_moves.is_empty()


func _straight(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x or a.y == b.y


func _snap() -> void:
	anim_t = 1.0
	bump_t = 1.0
	step_t = 1.0
	crate_moves.clear()
	queue_redraw()


func _bump(dir: Vector2i) -> void:
	bump_dir = Vector2(dir)
	bump_t = 0.0


func _layout() -> void:
	if lv == null:
		return
	var view := get_viewport_rect().size
	var top := TOP_BAR
	if card != null and card.visible:
		top = maxf(top, card.position.y + card.size.y + 12.0)
	var area := Rect2(Vector2(MARGIN, top), view - Vector2(MARGIN * 2.0, top + BOTTOM_BAR))
	var span := Vector2(core.size) + Vector2.ONE * RIM * 2.0
	cell = floorf(minf(minf(area.size.x / span.x, area.size.y / span.y), MAX_CELL))
	origin = (area.position + (area.size - span * cell) / 2.0 - (Vector2(core.position) - Vector2.ONE * RIM) * cell).floor()
	queue_redraw()


## Outer walls only frame the room, so they get a thin rim instead of a whole
## cell. A wall is outer when it touches the space outside the room, or when
## no floor is next to it at all. Outer walls can never be blasted.
func _find_outer_walls() -> void:
	outer.clear()
	var first := true
	for p: Vector2i in lv.walls:
		var near_floor := false
		var near_outside := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := p + Vector2i(dx, dy)
				if lv.inside.has(q):
					near_floor = true
				elif not lv.walls.has(q):
					near_outside = true
		if near_outside or not near_floor:
			outer[p] = true
	for p: Vector2i in lv.inside:
		core = Rect2i(p, Vector2i.ONE) if first else core.expand(p).expand(p + Vector2i.ONE)
		first = false
	for p: Vector2i in lv.walls:
		if not outer.has(p):
			core = core.expand(p).expand(p + Vector2i.ONE)


func _cell_rect(p: Vector2) -> Rect2:
	return Rect2(origin + p * cell, Vector2(cell, cell))


func _draw() -> void:
	if screen != "play" or lv == null:
		return
	var on := lv.hazards_on(state)
	for p in lv.inside:
		_draw_floor(p, on)
	_draw_walls()
	for p in lv.goals:
		if not state.boxes.has(p):
			_draw_target(p)

	var k := 1.0 - pow(1.0 - anim_t, 3.0)
	for p: Vector2i in state.boxes:
		var pos := Vector2(p)
		if crate_moves.has(p) and anim_t < 1.0:
			pos = crate_moves[p].lerp(pos, k)
		# Only the crate that is still sliding waits for the animation to end
		# before it lights up; crates already in place stay lit (no red flicker).
		var moving: bool = crate_moves.has(p) and anim_t < 1.0
		_draw_crate(pos, state.boxes[p], _crate_done(p) and not moving, lv.goals.has(p) and not moving)

	var ppos := player_from.lerp(Vector2(state.p), k) if anim_t < 1.0 else Vector2(state.p)
	if bump_t < 1.0:
		ppos += bump_dir * 0.12 * sin(bump_t * PI)
	_draw_robot(ppos)
	_draw_tip_marks()
	if hint_dir != Vector2i.ZERO:
		var c := _cell_rect(Vector2(state.p)).get_center()
		var d := Vector2(hint_dir)
		var tip := c + d * cell * (0.9 + 0.08 * sin(clock * 6.0))
		var side := Vector2(-d.y, d.x) * cell * 0.22
		var tri := PackedVector2Array([tip, tip - d * cell * 0.3 + side, tip - d * cell * 0.3 - side])
		draw_colored_polygon(tri, C_TEXT)
		draw_polyline(tri + PackedVector2Array([tip]), C_BG, cell * 0.03, true)


func _spr(sprite: String, r: Rect2, mod := Color.WHITE) -> void:
	var s: Array = Sprites.MAP[sprite]
	draw_texture_rect_region(Sprites.sheet(s[0]), r, Rect2(s[1] * 128, s[2] * 128, 128, 128), mod)


func _spr_rotated(sprite: String, r: Rect2, angle: float) -> void:
	draw_set_transform(r.get_center(), angle)
	_spr(sprite, Rect2(-r.size / 2.0, r.size))
	draw_set_transform(Vector2.ZERO)


func _flat_floor(r: Rect2) -> void:
	# Plain, low-contrast floor so it reads as background.
	draw_rect(r, C_FLOOR)
	draw_rect(r, C_FLOOR_LINE, false, maxf(1.0, cell * 0.015))


func _is_wall_at(p: Vector2i) -> bool:
	return lv.walls.has(p) and not state.blasted.has(p)


## Walls are drawn as one solid mass: a light top face, a darker front face
## where the wall meets open floor below, and a shadow cast onto the floor.
func _draw_walls() -> void:
	var side_h := cell * 0.2
	_draw_rim()
	for p: Vector2i in lv.walls:
		if not _is_wall_at(p) or outer.has(p):
			continue
		var below := p + Vector2i.DOWN
		var right := p + Vector2i.RIGHT
		if lv.inside.has(below) and not _is_wall_at(below):
			var fl := _cell_rect(Vector2(below))
			draw_rect(Rect2(fl.position, Vector2(cell, cell * 0.28)), Color(0, 0, 0, 0.35))
		if lv.inside.has(right) and not _is_wall_at(right):
			var fr := _cell_rect(Vector2(right))
			draw_rect(Rect2(fr.position, Vector2(cell * 0.14, cell)), Color(0, 0, 0, 0.22))
	for p: Vector2i in lv.walls:
		if not _is_wall_at(p) or outer.has(p):
			continue
		var r := _cell_rect(Vector2(p))
		var open_below := not _is_wall_at(p + Vector2i.DOWN)
		var top := r
		if open_below:
			top.size.y -= side_h
			draw_rect(Rect2(r.position.x, r.end.y - side_h, cell, side_h), C_WALL_SIDE)
			# Small orange lights on the front face, like the art's wall panels
			draw_rect(Rect2(r.position.x + cell * 0.38, r.end.y - side_h * 0.6, cell * 0.24, side_h * 0.22), Color("ff9a3c", 0.7))
		draw_rect(top.grow(0.5), C_WALL_TOP)
		var edge := maxf(1.5, cell * 0.035)
		if not _is_wall_at(p + Vector2i.UP):
			draw_line(top.position, Vector2(top.end.x, top.position.y), C_WALL_HI, edge)
		if not _is_wall_at(p + Vector2i.LEFT):
			draw_line(top.position, Vector2(top.position.x, r.end.y), C_WALL_EDGE, edge)
		if not _is_wall_at(p + Vector2i.RIGHT):
			draw_line(Vector2(top.end.x, top.position.y), Vector2(top.end.x, r.end.y), C_WALL_EDGE, edge)


## Floor or an inner wall: the part of the map the rim goes around.
func _in_room(q: Vector2i) -> bool:
	return lv.inside.has(q) or (lv.walls.has(q) and not outer.has(q))


## The room's border: a thin strip along every side where an outer wall
## meets the floor, plus small squares on the room's outside corners.
func _draw_rim() -> void:
	var t := cell * RIM
	var edge := maxf(1.5, cell * 0.035)
	for p: Vector2i in outer:
		var r := _cell_rect(Vector2(p))
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not _in_room(p + d):
				continue
			var strip: Rect2
			var face: PackedVector2Array  # the side that faces the floor
			match d:
				Vector2i.DOWN:
					strip = Rect2(r.position.x, r.end.y - t, cell, t)
					face = [strip.position + Vector2(0, t), strip.end]
					# shadow on the floor below
					draw_rect(Rect2(r.position.x, r.end.y, cell, cell * 0.12), Color(0, 0, 0, 0.3))
				Vector2i.UP:
					strip = Rect2(r.position.x, r.position.y, cell, t)
					face = [strip.position, strip.position + Vector2(cell, 0)]
				Vector2i.RIGHT:
					strip = Rect2(r.end.x - t, r.position.y, t, cell)
					face = [strip.position + Vector2(t, 0), strip.end]
				Vector2i.LEFT:
					strip = Rect2(r.position.x, r.position.y, t, cell)
					face = [strip.position, strip.position + Vector2(0, cell)]
			draw_rect(strip.grow(0.5), C_WALL_TOP)
			draw_line(face[0], face[1], C_WALL_HI, edge)
		for dx in [-1, 1]:
			for dy in [-1, 1]:
				var d := Vector2i(dx, dy)
				if _in_room(p + d) and not _in_room(p + Vector2i(dx, 0)) and not _in_room(p + Vector2i(0, dy)):
					var corner := Vector2(r.end.x - t if dx > 0 else r.position.x, r.end.y - t if dy > 0 else r.position.y)
					draw_rect(Rect2(corner, Vector2(t, t)).grow(0.5), C_WALL_TOP)


func _draw_target(p: Vector2i) -> void:
	var r := _cell_rect(Vector2(p))
	var col: Color = C_TARGET if lv.goals[p] == "" else TARGET_GLOW[lv.goals[p]]
	var pulse := 0.5 + 0.5 * sin(clock * 3.0 + p.x + p.y)
	draw_circle(r.get_center(), cell * (0.42 + 0.06 * pulse), Color(col, 0.12 + 0.18 * pulse), true, -1.0, true)
	_spr("target" if lv.goals[p] == "" else "target-" + CRATE_NAMES[lv.goals[p]], r.grow(-cell * (0.04 - 0.03 * pulse)))


func _crate_done(p: Vector2i) -> bool:
	if not lv.goals.has(p):
		return false
	return lv.goals[p] == "" or lv.goals[p] == state.boxes[p]


func _draw_floor(p: Vector2i, on: bool) -> void:
	var r := _cell_rect(Vector2(p))
	_flat_floor(r)
	if lv.walls.has(p):  # blasted wall: rubble marks
		for i in 3:
			draw_circle(r.position + Vector2(0.25 + 0.25 * i, 0.3 + 0.2 * (i % 2)) * cell, cell * 0.05, C_WALL_SIDE)
		return
	if lv.crumble.has(p):
		var st: String = state.crumbled.get(p, "")
		if st != "filled":
			_spr("broken-hole" if st == "pit" else "crumbling-floor", r)
		return
	if lv.ice.has(p):
		_spr("ice", r)
	elif lv.arrows.has(p):
		_spr_rotated("one-way-right", r, Vector2(lv.arrows[p]).angle())
	elif lv.plates.has(p):
		_spr("switch-pressed" if state.boxes.has(p) else "switch-up", r)
	elif lv.fire.has(p):
		_spr("fire-active" if on else "fire-off", r)
		if on:
			_draw_flame(r, p)
	elif lv.holes.has(p):
		if on:
			_spr_rotated("vortex", r, -clock * 1.5)
		else:
			_spr("vortex", r.grow(-cell * 0.2), Color(0.5, 0.5, 0.6, 0.35))
	elif lv.teleports.has(p):
		_spr(PAD_SPRITES[_pad_index(p)], r, Color(1, 1, 1, 0.85 + 0.15 * sin(clock * 4.0)))
	elif lv.doors.has(p):
		_spr("door-open" if state.open.has(p) else "door-closed", r)
	if lv.has_pickup(state, p):
		var bob := Vector2(0, sin(clock * 3.0 + p.x) * cell * 0.04)
		_spr("key-card" if lv.pickups[p] == "k" else "plus-five-moves", Rect2(r.position + bob, r.size).grow(-cell * 0.14))


## Living fire on top of the burner sprite: a flickering glow, a flame that
## sways and changes height, and sparks that float up. Each burner gets its own
## phase so a row of them doesn't move in step.
func _draw_flame(r: Rect2, p: Vector2i) -> void:
	var ph := float(p.x * 7 + p.y * 13)
	var f := 0.5 + 0.25 * sin(clock * 11.0 + ph) + 0.25 * sin(clock * 17.3 + ph * 2.0)
	var c := r.get_center()
	# Glow
	draw_circle(c, cell * (0.36 + 0.05 * f), Color(1.0, 0.45, 0.1, 0.10 + 0.10 * f), true, -1.0, true)
	# Flame: outer orange tongue, inner yellow core
	var sway := sin(clock * 5.0 + ph) * cell * 0.03
	_flame_shape(c + Vector2(0, cell * 0.17), cell * 0.15, cell * (0.30 + 0.08 * f), sway, Color(1.0, 0.5, 0.1, 0.55))
	_flame_shape(c + Vector2(0, cell * 0.18), cell * 0.08, cell * (0.17 + 0.06 * f), sway * 1.4, Color(1.0, 0.9, 0.4, 0.7))
	# Sparks
	for k in 3:
		var t := fmod(clock * 0.7 + k / 3.0 + ph * 0.13, 1.0)
		var pos := c + Vector2(sin(t * 6.0 + k * 2.0 + ph) * cell * 0.12, cell * 0.05 - t * cell * 0.55)
		draw_circle(pos, cell * 0.03 * (1.0 - t * 0.6), Color(1.0, 0.8, 0.35, 1.0 - t), true, -1.0, true)


## A teardrop: round bottom at base with radius w, pointed tip height h above.
func _flame_shape(base: Vector2, w: float, h: float, sway: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var a := PI * i / 8.0  # right side, round bottom, left side
		pts.append(base + Vector2(cos(a) * w, sin(a) * w * 0.8))
	pts.append(base + Vector2(-w * 0.7, -h * 0.45) + Vector2(sway * 0.5, 0))
	pts.append(base + Vector2(sway, -h))
	pts.append(base + Vector2(w * 0.7, -h * 0.45) + Vector2(sway * 0.5, 0))
	draw_colored_polygon(pts, col)


func _pad_index(p: Vector2i) -> int:
	# Pads of the same pair share a color; pairs are numbered in map order.
	var keys: Array = []
	for q: Vector2i in lv.teleports:
		var tw: Vector2i = lv.teleports[q]
		var k := mini(q.y * 1000 + q.x, tw.y * 1000 + tw.x)
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	var t: Vector2i = lv.teleports[p]
	return keys.find(mini(p.y * 1000 + p.x, t.y * 1000 + t.x)) % PAD_SPRITES.size()


func _draw_crate(pos: Vector2, kind: String, done: bool, on_goal: bool) -> void:
	var r := _cell_rect(pos).grow(-cell * 0.1)  # 80% of the tile, so the floor shows around it
	if done:
		draw_circle(r.get_center(), cell * 0.5, Color(C_TARGET, 0.3 + 0.12 * sin(clock * 3.0)), true, -1.0, true)
	# Drop shadow
	var sh := StyleBoxFlat.new()
	sh.bg_color = Color(0, 0, 0, 0.45)
	sh.set_corner_radius_all(int(cell * 0.12))
	draw_style_box(sh, Rect2(r.position + Vector2(0.05, 0.09) * cell, r.size))
	var sprite := "crate"
	if kind == "&":
		sprite = "heavy-crate"
	elif CRATE_NAMES.has(kind):
		sprite = "crate-" + CRATE_NAMES[kind]
	elif done:
		sprite = "crate-on-target"
	_spr(sprite, r)
	if on_goal and not done:
		draw_rect(r.grow(-cell * 0.1), Color(1, 0.3, 0.3, 0.7), false, cell * 0.04)


func _draw_robot(pos: Vector2) -> void:
	var r := _cell_rect(pos)
	var c := r.get_center()
	if armed != "":
		var glow := Color("ffd23f") if armed == "pull" else Color("ff5a36")
		draw_circle(c, cell * 0.5, Color(glow, 0.3 + 0.1 * sin(clock * 8.0)), true, -1.0, true)
	var name := "robot-down"
	match facing:
		Vector2i.UP: name = "robot-up"
		Vector2i.LEFT: name = "robot-left"
		Vector2i.RIGHT: name = "robot-right"

	# Idle: a slow hover. Each step: a small hop with squash and stretch,
	# a lean forward while pushing, and dust puffs left behind.
	var hop := 0.0
	var sx := 1.0 + 0.015 * sin(clock * 3.0)
	var sy := 1.0 - 0.015 * sin(clock * 3.0)
	var lean := 0.0
	if step_t < 1.0:
		var t := step_t
		hop = sin(minf(t * 1.6, 1.0) * PI) * 0.07
		# stretch while in the air, squash on landing, settle
		var w := sin(t * PI * 2.0) * (1.0 - t)
		sy += 0.10 * w
		sx -= 0.08 * w
		if step_push:
			lean = sin(minf(t * 1.3, 1.0) * PI) * 0.14
		_draw_dust(c, t)
	if bump_t < 1.0:
		lean += sin(bump_t * PI) * 0.08

	# soft shadow that shrinks as Kip hops
	var sh := cell * (0.30 - hop * 0.8)
	draw_set_transform(c + Vector2(0, cell * 0.36), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, sh, Color(0, 0, 0, 0.28), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)

	var dir := step_dir if step_t < 1.0 else bump_dir
	var ang := 0.0
	if dir.x != 0.0:
		ang = lean * signf(dir.x) * 0.9
	var off := dir * lean * cell * 0.35 + Vector2(0, -hop * cell)
	# scale around the robot's feet so a squash stays on the floor
	var feet := c + Vector2(0, cell * 0.4) + off
	draw_set_transform(feet, ang, Vector2(sx, sy))
	_spr(name, Rect2(Vector2(-cell / 2.0, -cell * 0.9), Vector2(cell, cell)))
	_draw_eye(name, step_t >= 1.0 and bump_t >= 1.0)
	draw_set_transform(Vector2.ZERO)


## Kip's lens: a soft glow, and while standing still a blink every few
## seconds (sometimes a double blink). Drawn in the robot's own transform.
const EYE := {"robot-up": Vector2(64, 33), "robot-down": Vector2(64, 98),
		"robot-left": Vector2(32, 62), "robot-right": Vector2(96, 62)}

func _draw_eye(name: String, idle: bool) -> void:
	var e: Vector2 = EYE[name] / 128.0 * cell - Vector2(cell / 2.0, cell * 0.9)
	draw_circle(e, cell * 0.11, Color(0.3, 1.0, 0.9, 0.12 + 0.08 * sin(clock * 4.0)), true, -1.0, true)
	if not idle:
		return
	var t := fmod(clock, 3.6)
	var cyc := int(clock / 3.6)
	var shut := 0.0
	if t < 0.16:
		shut = sin(t / 0.16 * PI)
	elif cyc % 3 == 2 and t > 0.24 and t < 0.40:
		shut = sin((t - 0.24) / 0.16 * PI)
	if shut <= 0.0:
		return
	var rad := cell * 0.075
	draw_circle(e, rad * shut, Color(0.12, 0.14, 0.2), true, -1.0, true)
	if shut > 0.6:
		var side := Vector2(rad, 0) if name == "robot-up" or name == "robot-down" else Vector2(0, rad)
		draw_line(e - side, e + side, Color(0.3, 1.0, 0.9), cell * 0.025, true)


func _draw_dust(c: Vector2, t: float) -> void:
	var back := -step_dir
	var side := Vector2(-step_dir.y, step_dir.x)
	var base := c + Vector2(0, cell * 0.3) + back * cell * 0.25
	var n := 4 if step_push else 3
	for i in n:
		var s := float(i) / float(n - 1) - 0.5
		var p := base + side * s * cell * 0.4 + back * t * cell * 0.25 + Vector2(0, -t * cell * 0.12)
		var rad := cell * (0.05 + 0.06 * t) * (1.2 if step_push else 1.0)
		draw_circle(p, rad, Color(0.75, 0.78, 0.9, 0.45 * (1.0 - t)), true, -1.0, true)



# --- Tip cards ------------------------------------------------------------------
# A card under the title explains the first room step by step, then each new
# tile, crate or tool the first time a room has it. See tutorials.gd.

func _queue_tips() -> void:
	tip_queue.clear()
	_hide_card()
	if tips_off:
		return
	if not tips_seen.has("move"):
		tip_queue.append("move")
	else:
		for t in Tutorials.topics_for(lv, uses.keys()):
			if not tips_seen.has(t):
				tip_queue.append(t)
	_next_tip()


func _next_tip() -> void:
	if tip_queue.is_empty():
		_hide_card()
		return
	_show_tip(tip_queue.pop_front())


func _show_tip(id: String) -> void:
	var t: Dictionary = Tutorials.TOPICS[id]
	tip_now = id
	tip_moves = 0
	# Marked as seen as soon as it shows, so it never comes back.
	tips_seen[id] = true
	if id == "move":
		for w in Tutorials.WALKTHROUGH:
			tips_seen[w] = true
	_save_progress()
	card_icon.texture = Sprites.icon(t.icon)
	card_title.text = t.title
	card_title.add_theme_color_override("font_color", zones[zone_i].color)
	card_text.text = t.text
	# Walkthrough steps move on when the player does the step.
	card_ok.visible = not Tutorials.WALKTHROUGH.has(id)
	card.offset_bottom = card.offset_top  # shrink to fit the new text
	card.show()
	_update_hud()
	_layout.call_deferred()


func _hide_card() -> void:
	tip_now = ""
	if card == null:
		return
	card.hide()
	for r in rings:
		r.hide()
	_update_hud()
	_layout.call_deferred()


func _tip_after_move(before: Dictionary, after: Dictionary) -> void:
	if tip_now == "":
		return
	var pushed: bool = before.boxes != after.boxes
	match tip_now:
		"move":
			_show_tip("goal" if pushed else "push")
		"push":
			if pushed:
				_show_tip("goal")
		"goal":
			pass
		_:
			# The card gets out of the way once the player is busy. Anything
			# still queued shows up in a later room.
			tip_moves += 1
			if tip_moves >= 6:
				tip_queue.clear()
				_hide_card()


func _skip_tips() -> void:
	tips_off = true
	_save_progress()
	tip_queue.clear()
	_hide_card()
	_toast("Tips off. Turn them on again from the main menu.")


func _toggle_tips() -> void:
	tips_off = not tips_off
	if not tips_off:
		tips_seen.clear()  # turning tips back on shows every card again
	_save_progress()
	_show_menu()


## HUD controls the current card points at with a ring.
func _ring_targets() -> Array:
	match tip_now:
		"move":
			return [dpad]
		"undo":
			return [undo_button, restart_button]
		"limit":
			return [info_label]
	if tip_now.begins_with("tool-"):
		return [booster_buttons.get(tip_now.substr(5))]
	return []


func _update_ring() -> void:
	var targets := _ring_targets()
	for i in rings.size():
		var ring := rings[i]
		var target: Control = targets[i] if i < targets.size() else null
		ring.visible = target != null and target.is_visible_in_tree()
		if ring.visible:
			var r := target.get_global_rect().grow(8)
			ring.global_position = r.position
			ring.size = r.size
			ring.modulate.a = 0.55 + 0.45 * sin(clock * 5.0)


## Pulsing outlines on the cells the card talks about, and in the first step a
## sliding arrow that shows which way to swipe.
func _draw_tip_marks() -> void:
	if tip_now == "":
		return
	var pulse := 0.5 + 0.5 * sin(clock * 5.0)
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = Color(C_ORANGE, 0.5 + 0.5 * pulse)
	sb.set_border_width_all(int(maxf(3.0, cell * 0.05)))
	sb.set_corner_radius_all(int(cell * 0.18))
	for p: Vector2i in Tutorials.cells_for(tip_now, lv, state):
		draw_style_box(sb, _cell_rect(Vector2(p)).grow(-cell * 0.03))
	if tip_now == "move" and anim_t >= 1.0 and not state.boxes.is_empty():
		var to: Vector2i = state.boxes.keys()[0] - state.p
		var d := Vector2(signf(to.x), 0) if absi(to.x) >= absi(to.y) else Vector2(0, signf(to.y))
		var c := _cell_rect(Vector2(state.p)).get_center()
		var t := fmod(clock * 1.1, 1.0)
		var tip := c + d * cell * (0.7 + 0.9 * t)
		var side := Vector2(-d.y, d.x) * cell * 0.2
		var back := tip - d * cell * 0.25
		var col := Color(C_TEXT, 1.0 - t)
		draw_polyline(PackedVector2Array([back + side, tip, back - side]), col, maxf(3.0, cell * 0.07), true)


func _build_card() -> void:
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel",
			UiArt.box("panel-frame", Vector4(44, 44, 44, 44), Vector4(30, 22, 30, 20)))
	play_hud.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cap_width(card, 16, 688)
	card.offset_top = 132
	card.offset_bottom = 132
	card.resized.connect(_layout)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	card_icon = TextureRect.new()
	card_icon.custom_minimum_size = Vector2(92, 92)
	card_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card_icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	row.add_child(texts)
	card_title = _label("", 32, C_GOAL)
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(card_title)
	card_text = _label("", 25, C_TEXT)
	card_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	texts.add_child(card_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	var skip := _button("Skip tips", _skip_tips)
	skip.custom_minimum_size = Vector2(0, 72)
	skip.add_theme_font_size_override("font_size", 24)
	skip.add_theme_color_override("font_color", C_DIM)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed"]:
		skip.add_theme_stylebox_override(st, empty)
	buttons.add_child(skip)
	card_ok = _primary_button("Got it", _next_tip)
	card_ok.custom_minimum_size = Vector2(190, 76)
	card_ok.add_theme_font_size_override("font_size", 30)
	buttons.add_child(card_ok)
	card.hide()

	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = C_ORANGE
	rs.set_border_width_all(5)
	rs.set_corner_radius_all(22)
	for i in 2:
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.add_theme_stylebox_override("panel", rs)
		play_hud.add_child(ring)
		ring.hide()
		rings.append(ring)


# --- HUD ------------------------------------------------------------------------

func _update_hud() -> void:
	if lv == null or screen != "play":
		return
	var z: Dictionary = zones[zone_i]
	title_label.text = "%d-%d  ·  %s" % [zone_i + 1, level_i + 1, lv.title]
	var info := "Moves %d" % state.moves
	if lv.limit > 0:
		info = "Moves %d/%d" % [state.moves, lv.budget(state)]
	if lv.par > 0:
		info += "  Best %d" % lv.par
	var placed := 0
	for g in lv.goals:
		if state.boxes.has(g) and _crate_done(g):
			placed += 1
	info += "  Charged %d/%d" % [placed, lv.goals.size()]
	if state.keys > 0:
		info += "  Keys %d" % state.keys
	info_label.text = info
	tip_label.text = lv.tip
	tip_label.visible = lv.tip != "" and state.moves < 6 and tip_now == ""
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
	_build_menu()
	_build_map()
	_build_levels()
	_build_play()
	_build_card()
	_build_overlay()


func _build_menu() -> void:
	menu_screen = _full_rect(ui)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 26)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_screen.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cap_width(col, 60, 600)
	col.offset_top = 100
	col.offset_bottom = -40
	var logo := _ui_rect("logo", Vector2(460, 380))
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_STOP
	logo.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_on_title_tapped())
	col.add_child(logo)
	# Kip pushing a crate onto a charger, on a loop, with the game's own sprites.
	menu_hero = Control.new()
	menu_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_hero.custom_minimum_size = Vector2(HERO_CELL * 4.0, HERO_CELL)
	menu_hero.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_hero.draw.connect(_draw_menu_hero)
	col.add_child(menu_hero)
	col.add_child(_label("Kip the cargo robot is restarting a dark space station, one battery crate at a time.", 26, C_DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 20)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var play := _primary_button("Play", _show_map)
	play.custom_minimum_size = Vector2(0, 140)
	play.add_theme_font_size_override("font_size", 56)
	col.add_child(play)
	continue_button = _button("Continue", _continue)
	continue_button.custom_minimum_size = Vector2(0, 118)
	col.add_child(continue_button)
	var count := HBoxContainer.new()
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.alignment = BoxContainer.ALIGNMENT_CENTER
	count.add_theme_constant_override("separation", 10)
	count.add_child(_ui_rect("star-filled", Vector2(44, 44)))
	menu_stars = _label("", 30, C_STAR)
	menu_stars.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.add_child(menu_stars)
	col.add_child(count)
	# Tips toggle in the top-right corner, so it is never pushed off a short
	# screen by the Continue button.
	tips_button = _button("", _toggle_tips)
	tips_button.custom_minimum_size = Vector2(200, 80)
	tips_button.add_theme_font_size_override("font_size", 26)
	menu_screen.add_child(tips_button)
	tips_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tips_button.offset_left = -224
	tips_button.offset_right = -24
	tips_button.offset_top = 24
	tips_button.offset_bottom = 104


## The menu's little scene: Kip walks right, pushes the crate two cells onto
## the charger, the crate lights up, then everything fades and starts again.
func _draw_menu_hero() -> void:
	var t := menu_t
	var smooth := func(a: float, b: float) -> float:
		var k := clampf((t - a) / (b - a), 0.0, 1.0)
		return k * k * (3.0 - 2.0 * k)
	# Kip goes cell 0 -> 1 -> 2, the crate 1 -> 2 -> 3 (the charger).
	var step: float = smooth.call(0.7, 1.15) + smooth.call(1.5, 1.95)
	var done := t >= 1.95
	var fade: float = 1.0 - smooth.call(3.6, 4.0) + smooth.call(4.05, HERO_LOOP)
	if t < 3.6:
		fade = 1.0
	if t >= 4.0:  # faded out: fade back in on the starting picture
		step = 0.0
		done = false
	var c := HERO_CELL
	var mod := Color(1, 1, 1, fade)
	var cell_rect := func(x: float) -> Rect2:
		return Rect2(Vector2(x * c, 0), Vector2(c, c))
	var spr := func(name: String, r: Rect2) -> void:
		var m: Array = Sprites.MAP[name]
		menu_hero.draw_texture_rect_region(Sprites.sheet(m[0]), r, Rect2(m[1] * 128, m[2] * 128, 128, 128), mod)
	# A strip of floor under the scene
	var floor := Rect2(Vector2(0, c * 0.08), Vector2(c * 4.0, c * 0.84))
	menu_hero.draw_rect(floor, Color(C_FLOOR, 0.9))
	for i in range(1, 4):
		menu_hero.draw_line(Vector2(i * c, floor.position.y), Vector2(i * c, floor.end.y), C_FLOOR_LINE, 2.0)
	if not done:
		spr.call("target", cell_rect.call(3.0))
	var box: Rect2 = cell_rect.call(1.0 + step).grow(-c * 0.1)
	if done:
		var glow := 0.3 + 0.15 * sin(menu_t * 6.0)
		menu_hero.draw_circle(box.get_center(), c * 0.5, Color(C_TARGET, glow * fade), true, -1.0, true)
	spr.call("crate-on-target" if done else "crate", box)
	# Kip leans in a little while pushing.
	var push := 0.0
	if t > 0.55 and t < 2.05:
		push = 0.06
	spr.call("robot-right", cell_rect.call(step + push))


func _build_map() -> void:
	map_screen = _full_rect(ui)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 18)
	map_screen.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cap_width(col, 28, 664)
	col.offset_top = 40
	col.offset_bottom = -30
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	top.add_child(_back_button(_show_menu))
	var title := _label("STATION MAP", 44, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var count := HBoxContainer.new()
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.add_theme_constant_override("separation", 4)
	count.custom_minimum_size = Vector2(96, 0)
	count.add_child(_ui_rect("star-filled", Vector2(34, 34)))
	map_stars = _label("", 24, C_STAR)
	map_stars.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.add_child(map_stars)
	top.add_child(count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	zone_list = VBoxContainer.new()
	zone_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone_list.add_theme_constant_override("separation", 12)
	scroll.add_child(zone_list)


func _build_levels() -> void:
	levels_screen = _full_rect(ui)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 22)
	levels_screen.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cap_width(col, 32, 656)
	col.offset_top = 40
	col.offset_bottom = -40
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	top.add_child(_back_button(_show_map))
	levels_title = _label("", 46, C_TEXT)
	levels_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(levels_title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(96, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	levels_story = _label("", 26, C_DIM)
	col.add_child(levels_story)
	levels_progress = Control.new()
	levels_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	levels_progress.custom_minimum_size = Vector2(0, 52)
	levels_progress.set_meta("done", 0)
	levels_progress.set_meta("total", 1)
	var font := ThemeDB.fallback_font
	levels_progress.draw.connect(func() -> void:
		var done: int = levels_progress.get_meta("done")
		var total: int = maxi(1, levels_progress.get_meta("total"))
		var r := Rect2(Vector2.ZERO, levels_progress.size)
		var back := StyleBoxFlat.new()
		back.bg_color = Color("10131f")
		back.border_color = Color("59628f")
		back.set_border_width_all(3)
		back.set_corner_radius_all(26)
		levels_progress.draw_style_box(back, r)
		if done > 0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = C_STAR
			fill.set_corner_radius_all(20)
			var inner := r.grow(-7)
			inner.size.x = maxf(inner.size.y, inner.size.x * done / total)
			levels_progress.draw_style_box(fill, inner)
		var text := "%d / %d COMPLETE" % [done, total]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var pos := Vector2(r.size.x - w - 26, r.size.y / 2 + 9)
		levels_progress.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, C_INK)
		levels_progress.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_TEXT))
	col.add_child(levels_progress)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	levels_grid = GridContainer.new()
	levels_grid.columns = 3
	levels_grid.add_theme_constant_override("h_separation", 26)
	levels_grid.add_theme_constant_override("v_separation", 22)
	center.add_child(levels_grid)


func _build_play() -> void:
	play_hud = _full_rect(ui)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_hud.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cap_width(top, 16, 688)
	top.offset_top = 36
	top.offset_bottom = 136
	top.add_child(_back_button(_show_levels))
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(titles)
	title_label = _label("", 34, C_TEXT)
	titles.add_child(title_label)
	info_label = _label("", 22, C_DIM)
	titles.add_child(info_label)
	# Undo and Restart sit up here, away from the arrows, so a missed tap on
	# the d-pad can't hit them.
	undo_button = _icon_button("undo", _undo)
	top.add_child(undo_button)
	restart_button = _icon_button("restart", _ask_restart)
	top.add_child(restart_button)

	tip_label = _label("", 26, C_DIM)
	play_hud.add_child(tip_label)
	tip_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_cap_width(tip_label, 30, 660)
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
	_cap_width(bottom, 24, 672)
	bottom.offset_top = -BOTTOM_BAR + 20
	bottom.offset_bottom = -36
	bottom.alignment = BoxContainer.ALIGNMENT_END
	booster_row = HBoxContainer.new()
	booster_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	booster_row.add_theme_constant_override("separation", 10)
	booster_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(booster_row)
	for b in BOOSTERS:
		var btn := _button(BOOSTERS[b].label, _on_booster.bind(b))
		btn.icon = Sprites.icon(BOOSTERS[b].icon)
		# Compact, fixed-size tool buttons, centered in their row
		btn.custom_minimum_size = Vector2(156, 64)
		btn.add_theme_font_size_override("font_size", 24)
		btn.add_theme_constant_override("icon_max_width", 34)
		_flat_style(btn)
		booster_row.add_child(btn)
		booster_buttons[b] = btn
	dpad = _build_dpad()
	dpad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(dpad)


## Small square icon button for the top bar.
func _icon_button(icon: String, action: Callable) -> Button:
	var b := _button("", action)
	b.custom_minimum_size = Vector2(100, 96)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon = Sprites.icon(icon)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 52)
	_flat_style(b)
	return b


## Plain flat look for the in-game controls: one fill, a thin border, no
## highlights or shadows. Pressed turns the border orange.
func _flat_style(b: Button) -> void:
	var make := func(bg: Color, border: Color) -> StyleBoxFlat:
		var st := StyleBoxFlat.new()
		st.bg_color = bg
		st.border_color = border
		st.set_border_width_all(2)
		st.set_corner_radius_all(20)
		st.set_content_margin_all(10)
		st.anti_aliasing = true
		return st
	b.add_theme_stylebox_override("normal", make.call(Color("2a2f4a"), Color("454c78")))
	b.add_theme_stylebox_override("hover", make.call(Color("323858"), Color("59628f")))
	b.add_theme_stylebox_override("pressed", make.call(Color("232740"), C_ORANGE))
	b.add_theme_stylebox_override("disabled", make.call(Color("2a2f4a", 0.45), Color("454c78", 0.45)))
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))


## On-screen arrows. Tap to step, hold to keep walking.
func _build_dpad() -> Control:
	var pad := Control.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.custom_minimum_size = Vector2.ONE * PAD_CELL * 3.0
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.position = (Vector2(d) + Vector2.ONE) * PAD_CELL + Vector2.ONE * 4.0
		b.size = Vector2.ONE * (PAD_CELL - 8.0)
		_flat_style(b)
		b.button_down.connect(_pad_down.bind(d))
		b.button_up.connect(_pad_up.bind(d))
		b.draw.connect(func() -> void:
			var c := b.size / 2.0
			var v := Vector2(d)
			var side := Vector2(-v.y, v.x) * PAD_CELL * 0.2
			var tip := c + v * PAD_CELL * 0.17
			var tri := PackedVector2Array([tip, tip - v * PAD_CELL * 0.3 + side, tip - v * PAD_CELL * 0.3 - side])
			b.draw_colored_polygon(tri, C_ORANGE if b.is_pressed() else C_TEXT))
		pad.add_child(b)
	return pad


func _pad_down(d: Vector2i) -> void:
	hold_dir = d
	hold_t = HOLD_DELAY
	_try_move(d)


func _pad_up(d: Vector2i) -> void:
	if hold_dir == d:
		hold_dir = Vector2i.ZERO


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
	_cap_width(box, 50, 620)
	overlay_title = _label("", 64, C_GOAL)
	box.add_child(overlay_title)
	overlay_stars = _stars_view(0, 48.0)
	box.add_child(overlay_stars)
	overlay_text = _label("", 30, C_TEXT)
	box.add_child(overlay_text)
	overlay_items = GridContainer.new()
	overlay_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_items.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	overlay_items.add_theme_constant_override("h_separation", 22)
	overlay_items.add_theme_constant_override("v_separation", 16)
	box.add_child(overlay_items)
	overlay_items.hide()
	overlay_buttons = HBoxContainer.new()
	overlay_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_buttons.add_theme_constant_override("separation", 20)
	box.add_child(overlay_buttons)
	overlay.hide()


## buttons: [[label, callable], ...]; the last one is the default (Enter).
func _show_overlay(title: String, text: String, stars: int, buttons: Array) -> void:
	overlay_items.hide()
	overlay_title.text = title
	overlay_text.text = text
	overlay_stars.visible = stars >= 0
	overlay_stars.set_meta("stars", maxi(stars, 0))
	overlay_stars.queue_redraw()
	for c in overlay_buttons.get_children():
		c.queue_free()
	for k in buttons.size():
		var b: Array = buttons[k]
		var btn := _primary_button(b[0], b[1]) if k == buttons.size() - 1 else _button(b[0], b[1])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 104)
		overlay_buttons.add_child(btn)
	overlay.show()


## What a zone brings that earlier zones didn't: [[sprite, name], ...].
## The first zone shows the basics instead.
func _zone_new_items(zi: int) -> Array:
	if zi == 0:
		return [["robot-right", "Kip"], ["crate", "Crate"], ["target", "Charger"]]
	var seen := {}
	var order: Array[String] = []
	for z in zones.size():
		if z > zi:
			break
		for l in zones[z].levels:
			for t in Tutorials.topics_for(l.rules, _boosters_for(z)):
				if z < zi:
					seen[t] = true
				elif not seen.has(t) and not order.has(t) and t != "undo":
					order.append(t)
	# New tiles first, then the new tool.
	var tiles := order.filter(func(t: String) -> bool: return not t.begins_with("tool-"))
	var tools := order.filter(func(t: String) -> bool: return t.begins_with("tool-"))
	var out := []
	for t in tiles + tools:
		var info: Dictionary = Tutorials.TOPICS[t]
		out.append([info.icon, info.title.trim_prefix("New tool: ")])
	return out


## Icons with captions under the popup text, e.g. a new zone's new tiles.
func _show_overlay_items(items: Array) -> void:
	for c in overlay_items.get_children():
		c.queue_free()
	overlay_items.columns = clampi(items.size(), 1, 4)
	for it in items:
		var cell := VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 4)
		cell.custom_minimum_size = Vector2(130, 0)
		var pic := TextureRect.new()
		pic.texture = Sprites.icon(it[0])
		pic.custom_minimum_size = Vector2(100, 100)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(pic)
		cell.add_child(_label(it[1], 22, C_GOAL))
		overlay_items.add_child(cell)
	overlay_items.visible = not items.is_empty()


func _hide_overlay() -> void:
	overlay.hide()


## Keeps c centered and at most max_w wide, with at least margin on each side,
## so menus don't stretch across wide (desktop) screens.
func _cap_width(c: Control, margin: float, max_w: float) -> void:
	var fit := func() -> void:
		var side := margin + maxf(0.0, (ui.size.x - 2.0 * margin - max_w) / 2.0)
		c.offset_left = side
		c.offset_right = -side
	fit.call()
	ui.resized.connect(fit)


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
			var sz := Vector2.ONE * radius * 2.4
			c.draw_texture_rect_region(UiArt.SHEET, Rect2(center - sz / 2.0, sz),
					UiArt.MAP["star-filled" if i < got else "star-empty"]))
	return c


func _ui_rect(name: String, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = UiArt.tex(name)
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


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


## The orange arrow from the UI sheet, with no button frame around it.
func _back_button(action: Callable) -> Button:
	var b := _button("", action)
	b.custom_minimum_size = Vector2(96, 96)
	b.icon = UiArt.tex("back")
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 84)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_color_override("icon_hover_color", Color(1.2, 1.2, 1.2))
	b.add_theme_color_override("icon_pressed_color", Color(0.75, 0.75, 0.75))
	return b


func _primary_button(text: String, action: Callable) -> Button:
	var b := _button(text, action)
	var m := Vector4(56, 44, 56, 50)
	var c := Vector4(30, 6, 30, 14)
	b.add_theme_stylebox_override("normal", UiArt.box("primary-normal", m, c))
	b.add_theme_stylebox_override("hover", UiArt.box("primary-normal", m, c, Color(1.1, 1.1, 1.1)))
	b.add_theme_stylebox_override("pressed", UiArt.box("primary-pressed", m, c))
	b.add_theme_color_override("font_pressed_color", C_TEXT)
	return b


func _make_theme() -> Theme:
	var t := Theme.new()
	t.set_constant("icon_max_width", "Button", 48)
	t.set_font_size("font_size", "Button", 38)
	var m := Vector4(50, 40, 50, 46)
	var c := Vector4(20, 4, 20, 10)
	t.set_stylebox("normal", "Button", UiArt.box("secondary", m, c))
	t.set_stylebox("hover", "Button", UiArt.box("secondary", m, c, Color(1.1, 1.1, 1.15)))
	t.set_stylebox("pressed", "Button", UiArt.box("secondary", m, c, Color(0.78, 0.78, 0.85)))
	t.set_stylebox("disabled", "Button", UiArt.box("secondary", m, c, Color(0.55, 0.55, 0.6, 0.6)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", C_GOAL)
	t.set_color("font_disabled_color", "Button", Color(C_DIM, 0.6))
	t.set_color("font_outline_color", "Button", C_INK)
	t.set_constant("outline_size", "Button", 10)
	t.set_color("font_outline_color", "Label", C_INK)
	t.set_constant("outline_size", "Label", 8)
	return t
