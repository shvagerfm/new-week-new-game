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
const MOCK := 720.0 / 1080.0  # menu mockups (1080 x 1920) -> stage pixels
const STAGE := Vector2(720, 1280)
const END_FIRST := 0.9    # ending: when the first zone module lights up
const END_GAP := 0.42     # ending: seconds between zone modules
const END_CORE := 0.5     # ending: pause before the core lights after the last module
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
## The station map's rooms in mockup pixels, bottom (Warehouse) to top (Core).
const MAP_ROOMS := [
	Rect2(110, 1525, 865, 195), Rect2(110, 1295, 865, 205), Rect2(110, 1090, 865, 175),
	Rect2(110, 895, 865, 170), Rect2(110, 700, 865, 165), Rect2(110, 495, 865, 175),
	Rect2(110, 265, 865, 200),
]
const MAP_NODE_X := 845.0  # the route line, in mockup pixels
const TARGET_GLOW := {"a": Color("ff6b6b"), "b": Color("5aa9ff"), "c": Color("6fd08c")}

var zones: Array[Dictionary] = []
var best := {}        # level id -> stars (1..3)
var intro_seen := {}  # zone id -> true
var tips_seen := {}   # tip card id -> true (see tutorials.gd)
var tips_off := false
var sound_on := true
var sfx: Sfx

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
var still_since := 0.0  # clock time of Kip's last step or bump
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
var menu_t := 0.0
var continue_button: Button
var map_screen: Control
var zone_list: Control  # the map's rooms, drawn route and nodes
var levels_screen: Control
var ending_screen: Control
var ending_art: Control
var ending_text: Control
var ending_stars: Label
var ending_note: Label
var ending_t := 0.0
var ending_lit := 0  # zone modules lit so far (the core counts as one more)
var levels_title: Label
var levels_story: Label
var levels_progress: Control
var levels_grid: Control
var levels_bg: Texture2D
var levels_current_tile: Button
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
var settings_open := false
var settings_panel: Control
var settings_sound: Button
var settings_tips: Button

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
	sfx = Sfx.new()
	add_child(sfx)
	_load_progress()
	sfx.muted = not sound_on
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_show_menu()


# --- Screens --------------------------------------------------------------------

func _show_menu() -> void:
	screen = "menu"
	# Once every room is solved, Continue becomes a way to watch the ending again.
	var all_done := not best.is_empty() and _next_level() == Vector2i(-1, -1)
	continue_button.disabled = best.is_empty()
	continue_button.set_meta("text", "The End" if all_done else "Continue")
	continue_button.queue_redraw()
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
	else:
		_show_ending()


func _show_settings() -> void:
	settings_sound.set_meta("text", "Sound: On" if sound_on else "Sound: Off")
	settings_tips.set_meta("text", "Tips: Off" if tips_off else "Tips: On")
	settings_sound.queue_redraw()
	settings_tips.queue_redraw()
	settings_panel.show()
	settings_open = true


func _hide_settings() -> void:
	settings_panel.hide()
	settings_open = false


func _show_map() -> void:
	screen = "map"
	for c in zone_list.get_children():
		c.queue_free()
	for i in mini(zones.size(), MAP_ROOMS.size()):
		var r := _mock_r(MAP_ROOMS[i])
		var b := _button("", _on_room.bind(i), false)
		_flat(b)
		b.position = r.position
		b.size = r.size
		zone_list.add_child(b)
		var name := _menu_label(zones[i].name, 68, Color.WHITE)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.autowrap_mode = TextServer.AUTOWRAP_WORD
		var n := _mock_r(Rect2(150, MAP_ROOMS[i].position.y - 6, 460, MAP_ROOMS[i].size.y))
		name.position = n.position
		name.size = n.size
		if not _zone_open(i):
			name.modulate = Color(0.9, 0.92, 0.96)
		zone_list.add_child(name)
	_set_screen(map_screen)


func _on_room(i: int) -> void:
	if _zone_open(i):
		sfx.play("click", 0.04)
		_open_zone(i)
	else:
		sfx.play("bump", 0.05)


func _zone_done(i: int) -> bool:
	var ls: Array = zones[i].levels
	return best.has(ls[ls.size() - 1].id)


## Room shading, the route, the nodes and Kip's pin, over the map background.
func _draw_map() -> void:
	var c := zone_list
	var n := mini(zones.size(), MAP_ROOMS.size())
	if n == 0:
		return
	var cur := _next_level().x
	var pin := cur if cur >= 0 else n - 1
	var pulse := 0.5 + 0.5 * sin(menu_t * 3.0)
	for i in n:
		if not _zone_open(i):
			c.draw_colored_polygon(_chamfer(_mock_r(MAP_ROOMS[i]), 16.0), Color(0.03, 0.04, 0.1, 0.42))
	if cur >= 0:
		var ring := _chamfer(_mock_r(MAP_ROOMS[cur]).grow(5.0), 20.0)
		ring.append(ring[0])
		c.draw_polyline(ring, Color(C_ORANGE, 0.18 + 0.2 * pulse), 16.0, true)
		c.draw_polyline(ring, C_ORANGE, 6.0, true)
	var x := MAP_NODE_X * MOCK
	var ys: Array[float] = []
	for i in n:
		ys.append(_mock_r(MAP_ROOMS[i]).get_center().y)
	c.draw_line(Vector2(x, ys[0]), Vector2(x, ys[n - 1]), Color("8e9bab"), 9.0)
	c.draw_line(Vector2(x, ys[0]), Vector2(x, ys[pin]), Color(C_TARGET, 0.3), 22.0)
	c.draw_line(Vector2(x, ys[0]), Vector2(x, ys[pin]), Color("3ff5e0"), 9.0)
	var node := 68.0
	for i in n:
		if i == pin:
			continue
		var tex := MenuArt.tex("map-node-check" if _zone_done(i) else "map-node-lock")
		if tex:
			c.draw_texture_rect(tex, Rect2(Vector2(x, ys[i]) - Vector2.ONE * node / 2.0, Vector2.ONE * node), false)
	var pin_tex := MenuArt.tex("kip-pin")
	if pin_tex:
		# The pin's round head sits on the node; its tip points down the route.
		var sz := Vector2(87, 120)
		var head := Vector2(43, 47)
		var bob := sin(menu_t * 2.6) * 4.0
		c.draw_texture_rect(pin_tex, Rect2(Vector2(x, ys[pin] + bob) - head, sz), false)


## A rect with its corners cut off, like the station's rooms.
func _chamfer(r: Rect2, k: float) -> PackedVector2Array:
	return PackedVector2Array([
		r.position + Vector2(k, 0), Vector2(r.end.x - k, r.position.y), r.position + Vector2(r.size.x, k),
		r.end - Vector2(0, k), r.end - Vector2(k, 0), Vector2(r.position.x + k, r.end.y),
		Vector2(r.position.x, r.end.y - k), r.position + Vector2(0, k)])


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
	var key: String = z.id.substr(z.id.find("-") + 1)
	levels_bg = MenuArt.tex("levels-bg-" + key) if MenuArt.drawn("levels-bg-" + key) else MenuArt.tex("levels-bg")
	levels_screen.get_child(0).queue_redraw()
	levels_title.text = z.name.to_upper()
	levels_story.text = z.tagline if z.tagline != "" else z.story.get_slice(". ", 0)
	for c in levels_grid.get_children():
		c.queue_free()
	levels_current_tile = null
	var done := 0
	var current := _next_level()
	var count: int = z.levels.size()
	# Two columns like the mockup; rows get closer only past five.
	var rows := ceili(count / 2.0)
	var pitch := minf(274.0, (1800.0 - 438.0 - 244.0) / maxf(1.0, rows - 1))
	for i in count:
		var id: String = z.levels[i].id
		if best.has(id):
			done += 1
		var b := _button("", _start_level.bind(zone_i, i))
		_flat(b)
		b.disabled = not _level_open(zone_i, i)
		var r := _mock_r(Rect2(127.0 + 436.0 * (i % 2), 438.0 + pitch * (i / 2), 390, 244))
		b.position = r.position
		b.size = r.size
		b.set_meta("n", i + 1)
		b.set_meta("stars", best.get(id, 0))
		b.set_meta("current", current == Vector2i(zone_i, i))
		if current == Vector2i(zone_i, i):
			levels_current_tile = b
		b.draw.connect(_draw_tile.bind(b))
		levels_grid.add_child(b)
	levels_progress.set_meta("done", done)
	levels_progress.set_meta("total", count)
	levels_progress.queue_redraw()
	_set_screen(levels_screen)


func _draw_tile(b: Button) -> void:
	var locked := b.disabled
	var mode := b.get_draw_mode()
	var mod := Color.WHITE
	var push := Vector2.ZERO
	if mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED:
		mod = Color(0.82, 0.84, 0.9)
		push = Vector2(0, 3)
	elif mode == BaseButton.DRAW_HOVER:
		mod = Color(1.1, 1.1, 1.14)
	var r := Rect2(push, b.size)
	if b.get_meta("current"):
		var glow := StyleBoxFlat.new()
		glow.draw_center = false
		glow.border_color = Color(C_ORANGE, 0.2 + 0.2 * sin(menu_t * 3.0))
		glow.set_border_width_all(14)
		glow.set_corner_radius_all(36)
		b.draw_style_box(glow, r.grow(12))
	var tex := MenuArt.tex("level-tile-locked" if locked else "level-tile")
	if tex:
		b.draw_texture_rect(tex, r, false, mod)
	if b.get_meta("current"):
		var ring := StyleBoxFlat.new()
		ring.draw_center = false
		ring.border_color = C_ORANGE
		ring.set_border_width_all(6)
		ring.set_corner_radius_all(30)
		b.draw_style_box(ring, r.grow(7))
	var font := MenuArt.font()
	var num := str(b.get_meta("n"))
	var fs := 86
	var w := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2((r.size.x - w) / 2.0, push.y + 86.0)
	b.draw_string(font, base + Vector2(0, 4), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.02, 0.04, 0.1, 0.55))
	b.draw_string(font, base, num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("c9ced8") if locked else Color.WHITE)
	var cy := push.y + 117.0
	if locked:
		var lock := Rect2(Vector2(r.size.x / 2.0 - 25.0, cy - 30.0), Vector2(50, 60))
		b.draw_texture_rect_region(UiArt.SHEET, lock, UiArt.MAP["padlock"], Color(0.85, 0.87, 0.9))
		return
	var got: int = b.get_meta("stars")
	for k in 3:
		var c := Vector2(r.size.x / 2.0 + (k - 1) * 55.0, cy)
		var sz := Vector2(52, 50)
		b.draw_texture_rect_region(UiArt.SHEET, Rect2(c - sz / 2.0, sz),
				UiArt.MAP["star-filled" if k < got else "star-empty"])


func _set_screen(c: Control) -> void:
	hold_dir = Vector2i.ZERO
	for s in [menu_screen, map_screen, levels_screen, play_hud, ending_screen]:
		s.visible = s == c
	_hide_overlay()
	_hide_settings()
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
	sound_on = cfg.get_value("settings", "sound", true)


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "intro_seen", intro_seen)
	cfg.set_value("progress", "tips_seen", tips_seen)
	cfg.set_value("progress", "tips_off", tips_off)
	cfg.set_value("settings", "sound", sound_on)
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


# --- Ending ---------------------------------------------------------------------

## The last room is solved: the zones light up one by one around the core,
## then the core, then the totals and credits fade in.
func _show_ending() -> void:
	screen = "ending"
	ending_t = 0.0
	ending_lit = 0
	var got := 0
	var total := 0
	var solved := 0
	var rooms := 0
	for z in zones:
		for l in z.levels:
			got += best.get(l.id, 0)
			total += 3
			rooms += 1
			if best.has(l.id):
				solved += 1
	ending_stars.text = "%d / %d" % [got, total]
	if got == total:
		ending_note.text = "Every room in the fewest moves. A perfect station!"
	elif solved < rooms:
		ending_note.text = "%d of %d rooms charged. The rest are still waiting in the dark." % [solved, rooms]
	else:
		ending_note.text = "All %d rooms charged. Replay rooms for 3 stars to make it perfect." % rooms
	ending_text.modulate.a = 0.0
	_set_screen(ending_screen)


func _ending_core_time() -> float:
	return END_FIRST + END_GAP * (zones.size() - 1) + END_CORE


func _ending_tick(delta: float) -> void:
	ending_t += delta
	# One rising chime per zone module, then the finale for the core.
	while ending_lit < zones.size() and ending_t >= END_FIRST + END_GAP * ending_lit:
		sfx.play("charge", 0.0, -3.0, pow(2.0, ending_lit * 2.0 / 12.0))
		ending_lit += 1
	if ending_lit == zones.size() and ending_t >= _ending_core_time():
		sfx.play("finale")
		ending_lit += 1
	var show := clampf((ending_t - _ending_core_time() - 0.6) / 0.8, 0.0, 1.0)
	ending_text.modulate.a = show
	ending_art.queue_redraw()


## Tap anywhere during the light-up to skip to the end of it.
func _skip_ending_intro(e: InputEvent) -> void:
	if screen != "ending" or ending_t >= _ending_core_time() + 0.6:
		return
	if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
		while ending_lit < zones.size():
			ending_lit += 1  # skipped modules light up silently
		ending_t = _ending_core_time() - 0.01


func _build_ending() -> void:
	ending_screen = _full_rect(ui)
	ending_art = _full_rect(ending_screen)
	ending_art.mouse_filter = Control.MOUSE_FILTER_STOP
	ending_art.gui_input.connect(_skip_ending_intro)
	ending_art.draw.connect(_draw_ending)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_END
	ending_screen.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cap_width(col, 40, 620)
	col.offset_top = 640
	col.offset_bottom = -40
	ending_text = col
	col.add_child(_label("STATION ONLINE", 58, C_GOAL))
	col.add_child(_label("Every zone has power again. The lights are back on, and Kip can finally rest.", 28, C_TEXT))
	var count := HBoxContainer.new()
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.alignment = BoxContainer.ALIGNMENT_CENTER
	count.add_theme_constant_override("separation", 10)
	count.add_child(_ui_rect("star-filled", Vector2(52, 52)))
	ending_stars = _label("", 40, C_STAR)
	ending_stars.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.add_child(ending_stars)
	col.add_child(count)
	ending_note = _label("", 24, C_DIM)
	col.add_child(ending_note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	col.add_child(_label("CRATE PUSH", 30, C_TEXT))
	col.add_child(_label("Made by Dima for New Week, New Game\nArt made with AI image generation · Sounds made in code\nBuilt with Godot", 22, C_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 110)
	col.add_child(row)
	var menu := _button("Menu", _show_menu)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(menu)
	var map := _primary_button("Map", _show_map)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(map)


## The station: seven zone modules in a ring around the core, joined by
## struts. Each module lights up in its zone's color, then power flows along
## the struts and the core lights up with Kip inside.
func _draw_ending() -> void:
	var c := ending_art
	var size := c.size
	var t := ending_t
	var smooth := func(a: float, b: float) -> float:
		var k := clampf((t - a) / (b - a), 0.0, 1.0)
		return k * k * (3.0 - 2.0 * k)
	var core_t := _ending_core_time()
	var core_on: float = smooth.call(core_t, core_t + 0.7)
	# Starfield, brighter once the station is on.
	for i in 90:
		var h := hash(i * 7919)
		var p := Vector2(float(h % 1000) / 1000.0 * size.x, float((h / 1000) % 1000) / 1000.0 * size.y)
		var tw := 0.5 + 0.5 * sin(t * (1.0 + float(i % 5) * 0.4) + float(i))
		c.draw_circle(p, 1.2 + float(i % 3) * 0.6, Color(1, 1, 1, (0.15 + 0.35 * tw) * (0.6 + 0.4 * core_on)))
	var center := Vector2(size.x / 2.0, 330.0)
	var ring := minf(230.0, size.x * 0.34)
	var n := zones.size()
	# A soft glow behind the station once the core is on.
	for k in 6:
		c.draw_circle(center, ring * (1.6 - k * 0.2), Color(C_GOAL, 0.025 * core_on))
	var mods: Array[Vector2] = []
	for i in n:
		var a := -PI / 2.0 + TAU * i / n
		mods.append(center + Vector2(cos(a), sin(a)) * ring)
	# Struts, with a pulse of power running from each lit module to the core.
	for i in n:
		var on: float = smooth.call(END_FIRST + END_GAP * i, END_FIRST + END_GAP * i + 0.3)
		var col: Color = zones[i].color
		var from := mods[i]
		c.draw_line(from, center, Color("2b3055"), 14.0, true)
		if on > 0.0:
			c.draw_line(from, center, Color(col, 0.55 * on), 6.0, true)
			var f := fmod(t * 0.9 + i * 0.13, 1.0)
			c.draw_circle(from.lerp(center, f), 6.0, Color(col.lightened(0.4), on), true, -1.0, true)
	# Modules
	var box := 112.0
	for i in n:
		var on: float = smooth.call(END_FIRST + END_GAP * i, END_FIRST + END_GAP * i + 0.3)
		var col: Color = zones[i].color
		var r := Rect2(mods[i] - Vector2.ONE * box / 2.0, Vector2.ONE * box)
		if on > 0.0:
			var pulse := 0.5 + 0.5 * sin(t * 3.0 + i)
			c.draw_circle(mods[i], box * (0.75 + 0.06 * pulse), Color(col, 0.18 * on), true, -1.0, true)
		var st := StyleBoxFlat.new()
		st.bg_color = Color("1d2034").lerp(col.darkened(0.55), on)
		st.border_color = Color("3b4170").lerp(col, on)
		st.set_border_width_all(4)
		st.set_corner_radius_all(26)
		st.anti_aliasing = true
		c.draw_style_box(st, r)
		var icon := UiArt.tex(UiArt.zone_icon(zones[i].id))
		var isz := icon.get_size()
		var fit := (box - 30.0) / maxf(isz.x, isz.y)
		var ir := Rect2(mods[i] - isz * fit / 2.0, isz * fit)
		var shade := Color(0.25, 0.27, 0.35).lerp(Color.WHITE, on)
		c.draw_texture_rect(icon, ir, false, shade)
	# Core with Kip inside.
	var core_r := 92.0
	for k in 4:
		c.draw_circle(center, core_r * (1.0 + 0.25 * k) * (1.0 + 0.04 * sin(t * 2.5)),
				Color(C_GOAL, 0.12 * core_on), true, -1.0, true)
	c.draw_circle(center, core_r, Color("1d2034").lerp(Color("4a3420"), core_on), true, -1.0, true)
	c.draw_circle(center, core_r, Color("3b4170").lerp(C_GOAL, core_on), false, 6.0, true)
	# Kip dozes with its eye shut in the dark core and wakes up when it lights.
	var kip := Kip.idle_frame(t - core_t) if core_on > 0.0 else Kip.FRAMES.get_frame_texture(&"idle", 4)
	var ks := core_r * 1.3
	c.draw_texture_rect(kip, Rect2(center - Vector2.ONE * ks / 2.0, Vector2.ONE * ks), false,
			Color(0.45, 0.47, 0.55).lerp(Color.WHITE, core_on))


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
	sfx.play("undo", 0.0, -2.0)
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
	sfx.play("undo", 0.05)
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
			sfx.play("bump")
			_toast("No inner wall there to blast.")
		else:
			sfx.play("crumble", 0.0, 3.0)
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
	_move_sounds(before, next)
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
		text += "\n\nThe core is back online."
		buttons.append(["Power up", _show_ending])
	await get_tree().create_timer(0.45).timeout
	if finished == "won" and screen == "play":
		sfx.play("win")
		_show_overlay("Charged!", text, stars, buttons)


func _go_next_zone() -> void:
	_show_map()
	_open_zone(zone_i + 1)


func _on_failed(reason: String) -> void:
	sfx.play("fail")
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
			sfx.play("tool" if armed != "" else "click")
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
			sfx.play("tool")
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
	sfx.play("tool")
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
		KEY_M:
			if not event.echo:
				_toggle_sound()
		KEY_ESCAPE:
			_back()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if not overlay.visible and screen == "play" and tip_now != "" and card_ok.visible and not event.echo:
				_next_tip()
			elif settings_open and not event.echo:
				_hide_settings()
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
	if settings_open:
		_hide_settings()
	elif overlay.visible and (screen != "play" or finished == ""):
		_hide_overlay()  # popups on the map, or the restart question
	elif screen == "play":
		_show_levels()
	elif screen == "ending":
		_show_menu()
	elif screen == "levels":
		_show_map()
	elif screen == "map":
		_show_menu()


func _on_title_tapped() -> void:
	# Seven taps on the title unlock every zone, for testing.
	# Only in debug builds (editor runs, debug exports): never in a release.
	if not OS.is_debug_build():
		return
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
	# The map's pin bobs and the current room and level glow.
	menu_t = fmod(menu_t + delta, TAU * 10.0)
	if screen == "map":
		zone_list.queue_redraw()
	elif screen == "levels" and levels_current_tile:
		levels_current_tile.queue_redraw()
	if screen == "ending":
		_ending_tick(delta)
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
		still_since = clock


func _straight(a: Vector2i, b: Vector2i) -> bool:
	return a.x == b.x or a.y == b.y


func _snap() -> void:
	anim_t = 1.0
	bump_t = 1.0
	step_t = 1.0
	crate_moves.clear()
	queue_redraw()


func _bump(dir: Vector2i) -> void:
	sfx.play("bump", 0.06)
	bump_dir = Vector2(dir)
	bump_t = 0.0
	still_since = clock


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

	# Frames from the sprite sheet: drive or push while stepping (the clock
	# keeps the wheels turning across held steps), push while bumping into
	# something, and idle / look around while standing still.
	var tex: Texture2D
	if step_t < 1.0:
		tex = Kip.frame(&"push" if step_push else &"drive", clock)
	elif bump_t < 1.0:
		tex = Kip.frame(&"push", clock)
	else:
		tex = Kip.idle_frame(maxf(clock - still_since - STEP_TIME, 0.0))

	# On top of the frames, each step is a small hop with squash and stretch
	# and a lean forward while pushing.
	var hop := 0.0
	var sx := 1.0
	var sy := 1.0
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
	# scale around the robot's feet so a squash stays on the floor, then turn
	# the down-facing frame toward where Kip faces
	var feet := c + Vector2(0, cell * 0.4) + off
	var body := Transform2D(ang, Vector2(sx, sy), 0.0, feet)
	draw_set_transform_matrix(body * Transform2D(Kip.angle(facing), Vector2(0, -cell * 0.4)))
	draw_texture_rect(tex, Rect2(-cell / 2.0, -cell / 2.0, cell, cell), false)
	draw_set_transform(Vector2.ZERO)



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
	_toast("Tips off. Turn them on again in Settings on the main menu.")


func _toggle_tips() -> void:
	tips_off = not tips_off
	if not tips_off:
		tips_seen.clear()  # turning tips back on shows every card again
	_save_progress()
	if settings_open:
		_show_settings()


func _toggle_sound() -> void:
	sound_on = not sound_on
	sfx.muted = not sound_on
	sfx.play("click")
	_save_progress()
	if settings_open:
		_show_settings()
	elif screen == "play":
		_toast("Sound on" if sound_on else "Sound off")


## One sound for what Kip did this step, plus one for anything it set off.
func _move_sounds(before: Dictionary, after: Dictionary) -> void:
	sfx.play("push" if before.boxes != after.boxes else "step", 0.08)
	if _charged(after) > _charged(before):
		sfx.play("charge")
	if after.picked.size() > before.picked.size() or after.bonus > before.bonus:
		sfx.play("pickup")
	if after.open.size() > before.open.size():
		sfx.play("door")
	if after.crumbled.size() > before.crumbled.size():
		sfx.play("crumble")
	if lv.teleports.has(after.p) and after.p != before.p \
			and absi(after.p.x - before.p.x) + absi(after.p.y - before.p.y) > 1:
		sfx.play("teleport")


## Crates sitting on a charger that takes them.
func _charged(s: Dictionary) -> int:
	var n := 0
	for g in lv.goals:
		if s.boxes.has(g) and (lv.goals[g] == "" or s.boxes[g] == lv.goals[g]):
			n += 1
	return n


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
	_build_ending()
	_build_play()
	_build_card()
	_build_overlay()


# --- Menu screens ---------------------------------------------------------------
# Laid out like the mockups in art/source/ui/: positions are in mockup pixels
# (1080 x 1920), scaled by MOCK onto a 720 x 1280 stage that sits in the middle
# of any screen. The art comes from MenuArt (art/menu/).

func _mock(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x * MOCK, y * MOCK, w * MOCK, h * MOCK)


func _mock_r(r: Rect2) -> Rect2:
	return Rect2(r.position * MOCK, r.size * MOCK)


## A full-window screen with its background, and the 720 x 1280 stage in its
## middle. Returns the stage; the screen is its parent.
func _menu_stage(bg: Callable) -> Control:
	var s := _full_rect(ui)
	var back := _full_rect(s)
	back.draw.connect(func() -> void: _draw_backdrop(back, bg.call()))
	var stage := Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = STAGE
	s.add_child(stage)
	var fit := func() -> void:
		stage.position = ((s.size - STAGE) / 2.0).floor()
		back.queue_redraw()
	s.resized.connect(fit)
	fit.call_deferred()
	return stage


## The background at full brightness behind the stage, and a dimmed copy
## filling the rest of a screen that is wider or taller than 9:16.
func _draw_backdrop(c: Control, tex: Texture2D) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), C_BG)
	if tex == null:
		return
	var ts := tex.get_size()
	var stage := Rect2(((c.size - STAGE) / 2.0).floor(), STAGE)
	var k := maxf(c.size.x / ts.x, c.size.y / ts.y)
	var cover := Rect2((c.size - ts * k) / 2.0, ts * k)
	if not cover.is_equal_approx(stage):
		c.draw_texture_rect(tex, cover, false, Color(0.3, 0.32, 0.4))
	c.draw_texture_rect(tex, stage, false)


func _menu_label(text: String, mock_size: float, color: Color) -> Label:
	var l := _label(text, roundi(mock_size * MOCK), color)
	l.add_theme_font_override("font", MenuArt.font())
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.1, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("line_spacing", -8)
	return l


func _flat(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)


## A title plate (drawn art if there is any; the placeholder backgrounds have
## the plate painted in) with its text. Returns the label.
func _menu_title(stage: Control, plate: Rect2, text_rect: Rect2, mock_size: float) -> Label:
	if MenuArt.drawn("header-plate"):
		var t := TextureRect.new()
		t.texture = MenuArt.tex("header-plate")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.position = plate.position
		t.size = plate.size
		stage.add_child(t)
	var l := _menu_label("", mock_size, Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.position = text_rect.position
	l.size = text_rect.size
	stage.add_child(l)
	return l


## The orange square back button of the mockups.
func _menu_back(stage: Control, r: Rect2, action: Callable) -> void:
	var b := _button("", action)
	_flat(b)
	b.position = r.position
	b.size = r.size
	b.draw.connect(func() -> void:
		var mode := b.get_draw_mode()
		var pressed := mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED
		var mod := Color(0.82, 0.82, 0.86) if pressed else (Color(1.1, 1.1, 1.1) if mode == BaseButton.DRAW_HOVER else Color.WHITE)
		var tex := MenuArt.tex("back-button")
		if tex:
			b.draw_texture_rect(tex, Rect2(Vector2(0, 3 if pressed else 0), b.size), false, mod))
	stage.add_child(b)


## A menu button drawn from its art, with an icon ("play", "gear" or "") and
## its label (meta "text") on top.
func _art_button(art: String, text: String, icon: String, mock_size: float, r: Rect2, action: Callable) -> Button:
	var b := _button("", action)
	_flat(b)
	b.position = r.position
	b.size = r.size
	b.set_meta("text", text)
	b.draw.connect(func() -> void:
		var mode := b.get_draw_mode()
		var mod := Color.WHITE
		var push := Vector2.ZERO
		if mode == BaseButton.DRAW_DISABLED:
			mod = Color(0.6, 0.62, 0.68, 0.8)
		elif mode == BaseButton.DRAW_PRESSED or mode == BaseButton.DRAW_HOVER_PRESSED:
			mod = Color(0.85, 0.85, 0.88)
			push = Vector2(0, 4)
		elif mode == BaseButton.DRAW_HOVER:
			mod = Color(1.08, 1.08, 1.1)
		var tex := MenuArt.tex(art)
		if tex:
			b.draw_texture_rect(tex, Rect2(push, b.size), false, mod)
		var font := MenuArt.font()
		var fs := roundi(mock_size * MOCK)
		var label: String = b.get_meta("text")
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var iw := 0.0
		if icon == "play":
			iw = 70.0
		elif icon == "gear":
			iw = 76.0
		var gap := 52.0 if icon != "" else 0.0
		var x := (b.size.x - iw - gap - tw) / 2.0
		# The art has a raised bottom edge, so the face is a little above center.
		var mid := push.y + b.size.y * 0.47
		var ink := Color(1, 1, 1, mod.a)
		var shade := Color(0.05, 0.05, 0.12, 0.3 * mod.a)
		if icon == "play":
			var tri := PackedVector2Array([Vector2(x, mid - 38), Vector2(x + iw, mid), Vector2(x, mid + 38)])
			b.draw_colored_polygon(tri, ink)
		elif icon == "gear":
			_draw_gear(b, Vector2(x + iw / 2.0, mid), iw / 2.0, ink, Color(Color("4b5873"), mod.a))
		var base := Vector2(x + iw + gap, mid + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0 - 2.0)
		b.draw_string(font, base + Vector2(0, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, shade)
		b.draw_string(font, base, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink))
	return b


## A solid gear: eight teeth around a disc, with a hole in the hole color.
func _draw_gear(c: CanvasItem, center: Vector2, r: float, ink: Color, hole: Color) -> void:
	for k in 8:
		var a := TAU * k / 8.0
		var d := Vector2.from_angle(a)
		var side := d.orthogonal() * r * 0.2
		var root := center + d * r * 0.62
		var tip := center + d * r
		c.draw_colored_polygon(PackedVector2Array([root - side * 1.15, tip - side * 0.85, tip + side * 0.85, root + side * 1.15]), ink)
	c.draw_circle(center, r * 0.74, ink, true, -1.0, true)
	c.draw_circle(center, r * 0.32, hole, true, -1.0, true)


func _build_menu() -> void:
	var stage := _menu_stage(func() -> Texture2D: return MenuArt.tex("menu-bg"))
	menu_screen = stage.get_parent()
	# Drawn layers; the placeholder background has the logo and Kip painted in.
	for layer in [["kip-crate", _mock(140, 590, 820, 540)], ["logo", _mock(100, 95, 880, 500)]]:
		if MenuArt.drawn(layer[0]):
			var t := TextureRect.new()
			t.texture = MenuArt.tex(layer[0])
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.position = layer[1].position
			t.size = layer[1].size
			stage.add_child(t)
	var logo_tap := Control.new()
	logo_tap.position = _mock(110, 100, 860, 480).position
	logo_tap.size = _mock(110, 100, 860, 480).size
	logo_tap.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_on_title_tapped())
	stage.add_child(logo_tap)
	stage.add_child(_art_button("button-play", "Play", "play", 128, _mock(92, 1185, 894, 217), _show_map))
	continue_button = _art_button("button-continue", "Continue", "", 104, _mock(95, 1433, 887, 184), _continue)
	stage.add_child(continue_button)
	stage.add_child(_art_button("button-settings", "Settings", "gear", 100, _mock(95, 1648, 887, 184), _show_settings))
	# Settings: a popup over the menu with the same buttons.
	settings_panel = ColorRect.new()
	(settings_panel as ColorRect).color = Color(0.03, 0.04, 0.09, 0.82)
	menu_screen.add_child(settings_panel)
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = STAGE
	settings_panel.add_child(box)
	var fit := func() -> void: box.position = ((settings_panel.size - STAGE) / 2.0).floor()
	settings_panel.resized.connect(fit)
	fit.call_deferred()
	var title := _menu_label("SETTINGS", 96, Color.WHITE)
	var tr := _mock(90, 560, 900, 140)
	title.position = tr.position
	title.size = tr.size
	box.add_child(title)
	settings_sound = _art_button("button-settings", "", "", 92, _mock(95, 760, 887, 184), _toggle_sound)
	box.add_child(settings_sound)
	settings_tips = _art_button("button-settings", "", "", 92, _mock(95, 975, 887, 184), _toggle_tips)
	box.add_child(settings_tips)
	box.add_child(_art_button("button-play", "Done", "", 110, _mock(92, 1225, 894, 217), _hide_settings))
	settings_panel.hide()


func _build_map() -> void:
	var stage := _menu_stage(func() -> Texture2D: return MenuArt.tex("map-bg"))
	map_screen = stage.get_parent()
	zone_list = Control.new()
	zone_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone_list.size = STAGE
	zone_list.draw.connect(_draw_map)
	stage.add_child(zone_list)
	_menu_title(stage, _mock(220, 15, 640, 135), _mock(230, 25, 620, 112), 80).text = "STATION MAP"
	_menu_back(stage, _mock(19, 24, 148, 123), _show_menu)


func _build_levels() -> void:
	var stage := _menu_stage(func() -> Texture2D: return levels_bg)
	levels_screen = stage.get_parent()
	levels_title = _menu_title(stage, _mock(195, 15, 745, 175), _mock(215, 40, 700, 120), 96)
	_menu_back(stage, _mock(35, 40, 153, 138), _show_map)
	levels_story = _menu_label("", 58, Color.WHITE)
	var sr := _mock(50, 200, 980, 90)
	levels_story.position = sr.position
	levels_story.size = sr.size
	stage.add_child(levels_story)
	levels_progress = Control.new()
	levels_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pr := _mock(95, 300, 895, 88)
	levels_progress.position = pr.position
	levels_progress.size = pr.size
	levels_progress.set_meta("done", 0)
	levels_progress.set_meta("total", 1)
	levels_progress.draw.connect(func() -> void:
		var done: int = levels_progress.get_meta("done")
		var total: int = maxi(1, levels_progress.get_meta("total"))
		var r := Rect2(Vector2.ZERO, levels_progress.size)
		var back := StyleBoxFlat.new()
		back.bg_color = Color("0a1220")
		back.border_color = Color("63738f")
		back.set_border_width_all(4)
		back.set_corner_radius_all(int(r.size.y / 2.0))
		back.anti_aliasing = true
		levels_progress.draw_style_box(back, r)
		if done > 0:
			var inner := r.grow(-10)
			inner.size.x = maxf(inner.size.y * 1.4, inner.size.x * done / total)
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color("1de9c8")
			fill.set_corner_radius_all(int(inner.size.y / 2.0))
			levels_progress.draw_style_box(fill, inner)
			var shine := StyleBoxFlat.new()
			shine.bg_color = Color(1, 1, 1, 0.18)
			shine.set_corner_radius_all(int(inner.size.y / 4.0))
			levels_progress.draw_style_box(shine, Rect2(inner.position + Vector2(10, 4), Vector2(inner.size.x - 20, inner.size.y * 0.3)))
		var font := MenuArt.font()
		var text := "%d / %d COMPLETE" % [done, total]
		var fs := 32
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(r.size.x - w - 24, r.size.y / 2.0 + 11)
		var on_fill := done > 0 and r.grow(-10).position.x + maxf(r.size.y, (r.size.x - 20) * done / total) > pos.x
		levels_progress.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("06302c") if on_fill else Color("4ff2dc")))
	stage.add_child(levels_progress)
	levels_grid = Control.new()
	levels_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	levels_grid.size = STAGE
	stage.add_child(levels_grid)


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
		var btn := _button(BOOSTERS[b].label, _on_booster.bind(b), false)
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
	var b := _button("", action, false)
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


## click: play the click sound. Off for buttons that make their own sound.
func _button(text: String, action: Callable, click := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for walking
	if click:
		b.pressed.connect(func() -> void: sfx.play("click", 0.04))
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
