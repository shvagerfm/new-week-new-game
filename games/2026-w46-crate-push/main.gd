extends Node2D
## Crate Push: push every crate onto a ring.
##
## Levels are plain-text files in res://levels/, played in file-name order.
## See README.md in this folder for the map format.

const LEVEL_DIR := "res://levels"
const SAVE_PATH := "user://progress.cfg"

const TOP_BAR := 170.0
const BOTTOM_BAR := 200.0
const MARGIN := 20.0
const MAX_CELL := 120.0
const SWIPE_MIN := 36.0
const MOVE_TIME := 0.09
const BUMP_TIME := 0.12

const C_FLOOR := Color("232740")
const C_WALL := Color("3b4170")
const C_WALL_EDGE := Color("2b3055")
const C_GOAL := Color("ffb347")
const C_BOX := Color("c98a4b")
const C_BOX_EDGE := Color("8f5a2b")
const C_BOX_DONE := Color("6fd08c")
const C_BOX_DONE_EDGE := Color("3f9460")
const C_PLAYER := Color("6ec3ff")
const C_EYE := Color("171a29")
const C_TEXT := Color("eeeeff")
const C_DIM := Color("9aa0c0")
const C_BUTTON := Color("2d3252")
const C_BUTTON_HOVER := Color("3a4068")

## Each level: {title: String, rows: PackedStringArray}
var levels: Array[Dictionary] = []
var level_index := 0
var unlocked := 0  # highest level index the player may open

# Board state
var grid_size := Vector2i.ONE
var walls := {}
var floor_cells := {}
var goals := {}
var boxes: Array[Vector2i] = []
var player := Vector2i.ZERO
var facing := Vector2i.DOWN
var moves := 0
var history: Array[Dictionary] = []
var solved := false

# Animation
var anim_t := 1.0
var player_from := Vector2.ZERO
var box_moving := -1
var box_from := Vector2.ZERO
var bump_t := 1.0
var bump_dir := Vector2.ZERO

# Layout
var cell := 64.0
var origin := Vector2.ZERO

# Touch
var touch_index := -1
var swipe_start := Vector2.ZERO

# HUD
var title_label: Label
var moves_label: Label
var hint_label: Label
var prev_button: Button
var next_button: Button
var undo_button: Button
var overlay: Control
var overlay_title: Label
var overlay_text: Label
var overlay_button: Button

var wall_style := StyleBoxFlat.new()
var box_style := StyleBoxFlat.new()
var box_done_style := StyleBoxFlat.new()


func _ready() -> void:
	_load_levels()
	_build_hud()
	_load_progress()
	get_viewport().size_changed.connect(_layout)
	if levels.is_empty():
		title_label.text = "No levels found in levels/"
		return
	_start_level(level_index)


# --- Levels -----------------------------------------------------------------

func _load_levels() -> void:
	var names := Array(DirAccess.get_files_at(LEVEL_DIR)).filter(
			func(f: String) -> bool: return f.get_extension() == "txt")
	names.sort()
	for f: String in names:
		var text := FileAccess.get_file_as_string(LEVEL_DIR.path_join(f))
		_parse_file(text, f.get_basename())


## A file holds one or more maps separated by blank lines. A line starting
## with ";" is a comment; the first comment above a map is its title.
func _parse_file(text: String, fallback_title: String) -> void:
	var title := ""
	var rows := PackedStringArray()
	for raw in (text.replace("\r", "") + "\n\n").split("\n"):
		var line := raw.rstrip(" \t")
		if line.strip_edges().begins_with(";"):
			if title.is_empty():
				title = line.strip_edges().trim_prefix(";").strip_edges()
		elif line.strip_edges().is_empty():
			if not rows.is_empty():
				var lvl_name := title if not title.is_empty() else fallback_title
				if _is_valid(rows, lvl_name):
					levels.append({"title": lvl_name, "rows": rows})
				rows = PackedStringArray()
				title = ""
		else:
			rows.append(line)


func _is_valid(rows: PackedStringArray, name: String) -> bool:
	var text := "".join(rows)
	var players := text.count("@") + text.count("+")
	var box_count := text.count("$") + text.count("*")
	var goal_count := text.count(".") + text.count("*") + text.count("+")
	if players != 1 or goal_count == 0 or box_count < goal_count:
		push_warning("Skipping level \"%s\": needs one player, at least one goal, and a crate for every goal" % name)
		return false
	return true


func _start_level(index: int) -> void:
	level_index = clampi(index, 0, levels.size() - 1)
	history.clear()
	_reset_board()
	_layout()
	_save_progress()


func _reset_board() -> void:
	var rows: PackedStringArray = levels[level_index].rows
	walls.clear()
	goals.clear()
	floor_cells.clear()
	boxes.clear()
	grid_size = Vector2i(1, rows.size())
	for y in rows.size():
		var row := rows[y]
		grid_size.x = maxi(grid_size.x, row.length())
		for x in row.length():
			var p := Vector2i(x, y)
			match row[x]:
				"#":
					walls[p] = true
				".":
					goals[p] = true
				"$":
					boxes.append(p)
				"*":
					boxes.append(p)
					goals[p] = true
				"@":
					player = p
				"+":
					player = p
					goals[p] = true
	_fill_floor()
	facing = Vector2i.DOWN
	moves = 0
	solved = false
	overlay.hide()
	_snap_animation()
	_update_hud()


## Floor is everything the player could ever walk on, found by flood fill, so
## the empty space outside the walls stays blank.
func _fill_floor() -> void:
	var stack: Array[Vector2i] = [player]
	var bounds := Rect2i(Vector2i.ZERO, grid_size)
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if floor_cells.has(p) or walls.has(p) or not bounds.has_point(p):
			continue
		floor_cells[p] = true
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			stack.append(p + d)
	for p in goals:
		floor_cells[p] = true
	for p in boxes:
		floor_cells[p] = true


# --- Moves ------------------------------------------------------------------

func _try_move(dir: Vector2i) -> void:
	if solved or levels.is_empty():
		return
	_snap_animation()
	facing = dir
	var next := player + dir
	var pushed := boxes.find(next)
	if walls.has(next) or not floor_cells.has(next):
		_bump(dir)
		return
	if pushed != -1:
		var beyond := next + dir
		if walls.has(beyond) or boxes.has(beyond) or not floor_cells.has(beyond):
			_bump(dir)
			return
	_push_history()
	if pushed != -1:
		box_from = Vector2(next)
		boxes[pushed] = next + dir
	box_moving = pushed
	player_from = Vector2(player)
	player = next
	moves += 1
	anim_t = 0.0
	_update_hud()
	if _is_solved():
		_on_solved()


func _is_solved() -> bool:
	for g in goals:
		if not boxes.has(g):
			return false
	return true


func _on_solved() -> void:
	solved = true
	unlocked = clampi(maxi(unlocked, level_index + 1), 0, levels.size() - 1)
	_save_progress()
	_update_hud()
	await get_tree().create_timer(0.45).timeout
	if not solved:
		return
	var last := level_index == levels.size() - 1
	overlay_title.text = "All done!" if last else "Solved!"
	overlay_text.text = "%s in %d moves" % [levels[level_index].title, moves]
	if last:
		overlay_text.text += "\n\nThat was the last level.\nAdd more in levels/."
	overlay_button.text = "Play level 1" if last else "Next level"
	overlay.show()


func _continue_after_solve() -> void:
	if level_index == levels.size() - 1:
		_start_level(0)
	else:
		_start_level(level_index + 1)


func _push_history() -> void:
	history.append({"player": player, "boxes": boxes.duplicate(), "facing": facing, "moves": moves})


func _undo() -> void:
	if history.is_empty() or solved:
		return
	var s: Dictionary = history.pop_back()
	player = s.player
	boxes.assign(s.boxes)
	facing = s.facing
	moves = s.moves
	_snap_animation()
	_update_hud()


## Restart can be undone too: it is pushed onto the history like a move.
func _restart() -> void:
	if moves == 0 and history.is_empty():
		return
	if solved:
		_start_level(level_index)
		return
	_push_history()
	var keep := history
	_reset_board()
	history = keep
	_update_hud()


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			swipe_start = event.position
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
	elif event is InputEventScreenDrag and event.index == touch_index:
		# Keep dragging to keep walking: every swipe-length moves one cell.
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
			_undo()
		KEY_R:
			if not event.echo:
				_restart()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if overlay.visible and not event.echo:
				_continue_after_solve()
		KEY_PAGEUP, KEY_BRACKETLEFT:
			_go_level(-1)
		KEY_PAGEDOWN, KEY_BRACKETRIGHT:
			_go_level(1)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _go_level(step: int) -> void:
	var target := level_index + step
	if target < 0 or target > unlocked or target >= levels.size():
		return
	_start_level(target)


# --- Animation & drawing ----------------------------------------------------

func _process(delta: float) -> void:
	if anim_t < 1.0 or bump_t < 1.0:
		anim_t = minf(anim_t + delta / MOVE_TIME, 1.0)
		bump_t = minf(bump_t + delta / BUMP_TIME, 1.0)
		queue_redraw()


func _snap_animation() -> void:
	anim_t = 1.0
	bump_t = 1.0
	box_moving = -1
	queue_redraw()


func _bump(dir: Vector2i) -> void:
	bump_dir = Vector2(dir)
	bump_t = 0.0
	queue_redraw()


func _layout() -> void:
	var view := get_viewport_rect().size
	var area := Rect2(Vector2(MARGIN, TOP_BAR), view - Vector2(MARGIN * 2.0, TOP_BAR + BOTTOM_BAR))
	cell = floorf(minf(minf(area.size.x / grid_size.x, area.size.y / grid_size.y), MAX_CELL))
	origin = (area.position + (area.size - Vector2(grid_size) * cell) / 2.0).floor()
	wall_style.bg_color = C_WALL
	wall_style.border_color = C_WALL_EDGE
	wall_style.border_width_bottom = int(cell * 0.12)
	wall_style.set_corner_radius_all(int(cell * 0.12))
	for s: StyleBoxFlat in [box_style, box_done_style]:
		s.set_corner_radius_all(int(cell * 0.14))
		s.set_border_width_all(int(cell * 0.08))
	box_style.bg_color = C_BOX
	box_style.border_color = C_BOX_EDGE
	box_done_style.bg_color = C_BOX_DONE
	box_done_style.border_color = C_BOX_DONE_EDGE
	queue_redraw()


func _to_screen(p: Vector2) -> Vector2:
	return origin + p * cell


func _draw() -> void:
	if levels.is_empty():
		return
	var c := Vector2(cell, cell)
	for p in floor_cells:
		draw_rect(Rect2(_to_screen(Vector2(p)), c), C_FLOOR)
	for p in walls:
		draw_style_box(wall_style, Rect2(_to_screen(Vector2(p)) + c * 0.02, c * 0.96))
	for p in goals:
		draw_arc(_to_screen(Vector2(p)) + c / 2.0, cell * 0.2, 0.0, TAU, 32, C_GOAL, cell * 0.07, true)

	var k := 1.0 - pow(1.0 - anim_t, 3.0)
	for i in boxes.size():
		var pos := Vector2(boxes[i])
		if i == box_moving:
			pos = box_from.lerp(pos, k)
		var done := goals.has(boxes[i]) and (i != box_moving or anim_t >= 1.0)
		var r := Rect2(_to_screen(pos) + c * 0.08, c * 0.84)
		draw_style_box(box_done_style if done else box_style, r)
		var inner := r.grow(-cell * 0.2)
		draw_line(inner.position, inner.end, Color(0, 0, 0, 0.18), cell * 0.06, true)
		draw_line(Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), Color(0, 0, 0, 0.18), cell * 0.06, true)

	var ppos := player_from.lerp(Vector2(player), k) if anim_t < 1.0 else Vector2(player)
	ppos += bump_dir * 0.12 * sin(bump_t * PI) if bump_t < 1.0 else Vector2.ZERO
	var center := _to_screen(ppos) + c / 2.0
	draw_circle(center, cell * 0.36, C_PLAYER, true, -1.0, true)
	var look := Vector2(facing) * cell * 0.1
	var side := Vector2(-facing.y, facing.x) * cell * 0.13
	for s in [-1.0, 1.0]:
		draw_circle(center + look + side * s, cell * 0.06, C_EYE, true, -1.0, true)


# --- HUD --------------------------------------------------------------------

func _update_hud() -> void:
	if levels.is_empty():
		return
	title_label.text = "%d / %d  ·  %s" % [level_index + 1, levels.size(), levels[level_index].title]
	var placed := 0
	for b in boxes:
		if goals.has(b):
			placed += 1
	moves_label.text = "Moves %d    Crates %d / %d" % [moves, placed, goals.size()]
	prev_button.disabled = level_index == 0
	next_button.disabled = level_index >= unlocked or level_index >= levels.size() - 1
	undo_button.disabled = history.is_empty()
	hint_label.visible = level_index == 0
	queue_redraw()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 40
	top.offset_bottom = 140
	prev_button = _button("<", func() -> void: _go_level(-1))
	prev_button.custom_minimum_size = Vector2(96, 96)
	top.add_child(prev_button)
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(titles)
	title_label = _label("", 36, C_TEXT)
	titles.add_child(title_label)
	moves_label = _label("", 26, C_DIM)
	titles.add_child(moves_label)
	next_button = _button(">", func() -> void: _go_level(1))
	next_button.custom_minimum_size = Vector2(96, 96)
	top.add_child(next_button)

	hint_label = _label("Swipe or use the arrow keys.\nPush every crate onto a ring.", 28, C_DIM)
	root.add_child(hint_label)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -BOTTOM_BAR - 70
	hint_label.offset_bottom = -BOTTOM_BAR + 10

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 20)
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -160
	bottom.offset_bottom = -48
	undo_button = _button("Undo", _undo)
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(undo_button)
	var restart_button := _button("Restart", _restart)
	restart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(restart_button)

	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0.05, 0.06, 0.1, 0.78)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	overlay.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 60
	box.offset_right = -60
	overlay_title = _label("", 72, C_GOAL)
	box.add_child(overlay_title)
	overlay_text = _label("", 32, C_TEXT)
	box.add_child(overlay_text)
	overlay_button = _button("Next level", _continue_after_solve)
	overlay_button.custom_minimum_size = Vector2(0, 110)
	box.add_child(overlay_button)
	overlay.hide()


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
	t.set_font_size("font_size", "Button", 40)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = C_BUTTON_HOVER if state == "hover" or state == "pressed" else C_BUTTON
		if state == "disabled":
			s.bg_color.a = 0.45
		s.set_corner_radius_all(22)
		s.content_margin_left = 16
		s.content_margin_right = 16
		t.set_stylebox(state, "Button", s)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", C_GOAL)
	t.set_color("font_disabled_color", "Button", Color(C_DIM, 0.5))
	return t


# --- Progress ---------------------------------------------------------------

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or levels.is_empty():
		return
	unlocked = clampi(cfg.get_value("progress", "unlocked", 0), 0, levels.size() - 1)
	level_index = clampi(cfg.get_value("progress", "current", unlocked), 0, unlocked)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("progress", "current", level_index)
	cfg.save(SAVE_PATH)
