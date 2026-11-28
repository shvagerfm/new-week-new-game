extends Node
## Deck the Tree: screens and flow. The level itself is Game (game.gd).
##   title -> level map -> play (HUD) -> win / fail panel -> next level
## All UI is built in code with one shared Theme.

const INTROS := {0: "tap_to_throw", 4: "intro_candies", 20: "intro_ice", 30: "intro_stars",
	31: "intro_move", 40: "intro_pulse"}

var save := Save.new()
var game: Game
var sfx: Sfx
var ui: CanvasLayer
var theme_ui: Theme
var current := 0
var screen := ""

# screens
var title_screen: Control
var map_screen: Control
var hud: Control
var panel_layer: Control
# hud parts
var hud_level: Label
var hud_time: Label
var hud_boss: ProgressBar
var hud_boss_name: Label
var hud_quiver: Control
var pause_btn: Button
var booster_btns := {}
var popup_label: Label
var intro_label: Label
var map_grid: VBoxContainer
var _last_reward := ""


func _ready() -> void:
	save.load_file()
	if save.lang == "":
		save.lang = "uk" if OS.get_locale_language() in ["uk", "ru", "be"] else "en"
	Loc.lang = save.lang
	sfx = Sfx.new()
	add_child(sfx)
	sfx.muted = save.muted
	game = Game.new()
	add_child(game)
	game.won.connect(_on_won)
	game.failed.connect(_on_failed)
	game.changed.connect(_refresh_hud)
	game.popup.connect(_popup)
	game.sound.connect(func(n): sfx.play(n))
	ui = CanvasLayer.new()
	add_child(ui)
	theme_ui = _make_theme()
	Ads.availability_changed.connect(func(_r): _refresh_hud())
	_build_all()
	_show_title()


func _build_all() -> void:
	for c in ui.get_children():
		c.queue_free()
	title_screen = _build_title()
	map_screen = _build_map()
	hud = _build_hud()
	panel_layer = _full_control()
	panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [title_screen, map_screen, hud, panel_layer]:
		ui.add_child(c)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if screen != "play":
		return
	if event is InputEventScreenTouch and event.pressed:
		if not panel_layer.get_children().is_empty() or _on_button(event.position):
			return
		game.throw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_UP, KEY_W:
				if panel_layer.get_children().is_empty():
					game.throw()
			KEY_ESCAPE, KEY_P:
				_toggle_pause()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var k: String = Save.BOOSTERS[event.keycode - KEY_1]
				_on_booster(k)


func _on_button(pos: Vector2) -> bool:
	var btns: Array = booster_btns.values() + [pause_btn]
	for b in btns:
		if b.is_visible_in_tree() and b.get_global_rect().grow(6).has_point(pos):
			return true
	return false


# ------------------------------------------------------------------ title

func _build_title() -> Control:
	var root := _full_control()
	var tree_view := TreeView.new()
	tree_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	tree_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_view.title_mode = true
	root.add_child(tree_view)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 22)
	box.alignment = BoxContainer.ALIGNMENT_END
	box.offset_bottom = -90
	box.offset_left = 120
	box.offset_right = -120
	root.add_child(box)
	var title := _label(Loc.t("title"), 72)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 70
	title.offset_bottom = 190
	title.add_theme_color_override("font_outline_color", Color("1b2a1d"))
	title.add_theme_constant_override("outline_size", 14)
	root.add_child(title)
	var play := _button(Loc.t("play"), 48)
	play.custom_minimum_size.y = 120
	play.pressed.connect(func(): _start_level(mini(save.unlocked - 1, Levels.COUNT - 1)))
	box.add_child(play)
	var lv := _button(Loc.t("levels"), 38)
	lv.pressed.connect(_show_map)
	box.add_child(lv)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	var snd := _button(Loc.t("sound_off") if save.muted else Loc.t("sound_on"), 34)
	snd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	snd.pressed.connect(func():
		_set_muted(not save.muted)
		snd.text = Loc.t("sound_off") if save.muted else Loc.t("sound_on"))
	row.add_child(snd)
	var lang := _button(Loc.t("lang"), 34)
	lang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang.pressed.connect(func():
		save.lang = "en" if save.lang == "uk" else "uk"
		Loc.lang = save.lang
		save.save_file()
		_build_all()
		_show_title())
	row.add_child(lang)
	return root


func _show_title() -> void:
	screen = "title"
	game.state = Game.READY
	game.level = Levels.get_level(mini(save.unlocked - 1, Levels.COUNT - 1))
	_clear_panels()
	title_screen.show()
	map_screen.hide()
	hud.hide()


# ------------------------------------------------------------------ map

func _build_map() -> Control:
	var root := _full_control()
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.12, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 40
	top.offset_bottom = 130
	top.offset_left = 30
	top.offset_right = -30
	root.add_child(top)
	var back := _button("←", 40)
	back.custom_minimum_size = Vector2(100, 88)
	back.pressed.connect(_show_title)
	top.add_child(back)
	var t := _label(Loc.t("levels"), 48)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var stars_lbl := _label("", 34)
	stars_lbl.name = "Stars"
	stars_lbl.custom_minimum_size.x = 140
	top.add_child(stars_lbl)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 150
	scroll.offset_left = 30
	scroll.offset_right = -30
	scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	map_grid = VBoxContainer.new()
	map_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_grid.add_theme_constant_override("separation", 14)
	scroll.add_child(map_grid)
	return root


func _fill_map() -> void:
	for c in map_grid.get_children():
		c.queue_free()
	(map_screen.find_child("Stars", true, false) as Label).text = "★ %d" % save.total_stars()
	for w in Levels.WORLDS.size():
		var head := _label(Loc.t(Levels.WORLDS[w].key), 36)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_theme_color_override("font_color", Color("ffd25e"))
		map_grid.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		map_grid.add_child(grid)
		for k in 10:
			var i := w * 10 + k
			var open := i < save.unlocked
			var s: int = save.stars.get(i, 0)
			var txt := "%d" % (i + 1)
			if Levels.is_boss(i):
				txt = "★%d" % (i + 1)
			txt += "\n" + ("·  ·  ·" if not open else "★".repeat(s) + "☆".repeat(3 - s))
			var b := _button(txt, 26)
			b.custom_minimum_size = Vector2(118, 110)
			b.disabled = not open
			if Levels.is_boss(i):
				b.add_theme_color_override("font_color", Color("ffd25e"))
			b.pressed.connect(_start_level.bind(i))
			grid.add_child(b)


func _show_map() -> void:
	screen = "map"
	_clear_panels()
	_fill_map()
	title_screen.hide()
	hud.hide()
	map_screen.show()


# ------------------------------------------------------------------ hud

func _build_hud() -> Control:
	var root := _full_control()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_btn = _button("❚❚", 34)
	pause_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pause_btn.position = Vector2(24, 40)
	pause_btn.size = Vector2(88, 88)
	pause_btn.pressed.connect(_toggle_pause)
	root.add_child(pause_btn)
	hud_level = _label("", 36)
	hud_level.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud_level.offset_top = 40
	hud_level.offset_bottom = 90
	hud_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_level)
	hud_time = _label("", 28)
	hud_time.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud_time.offset_top = 88
	hud_time.offset_bottom = 128
	hud_time.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	root.add_child(hud_time)
	hud_boss_name = _label("", 26)
	hud_boss_name.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud_boss_name.offset_top = 134
	hud_boss_name.offset_bottom = 168
	hud_boss_name.add_theme_color_override("font_color", Color("ffd25e"))
	root.add_child(hud_boss_name)
	hud_boss = ProgressBar.new()
	hud_boss.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hud_boss.offset_top = 170
	hud_boss.offset_bottom = 194
	hud_boss.offset_left = 180
	hud_boss.offset_right = -180
	hud_boss.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ff5a4e")
	fill.set_corner_radius_all(10)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0, 0, 0, 0.45)
	bgs.set_corner_radius_all(10)
	hud_boss.add_theme_stylebox_override("fill", fill)
	hud_boss.add_theme_stylebox_override("background", bgs)
	root.add_child(hud_boss)
	hud_quiver = QuiverView.new()
	hud_quiver.game = game
	hud_quiver.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_quiver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud_quiver)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -104
	bar.offset_bottom = -16
	bar.offset_left = 14
	bar.offset_right = -14
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	for k in Save.BOOSTERS:
		var b := _button("", 21)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = Loc.t("tip_" + k)
		b.pressed.connect(_on_booster.bind(k))
		bar.add_child(b)
		booster_btns[k] = b
	popup_label = _label("", 64)
	popup_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	popup_label.custom_minimum_size = Vector2(700, 120)
	popup_label.position = Vector2(-350, -360)
	popup_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	popup_label.add_theme_constant_override("outline_size", 12)
	popup_label.modulate.a = 0.0
	root.add_child(popup_label)
	intro_label = _label("", 34)
	intro_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	intro_label.offset_top = -420
	intro_label.offset_bottom = -330
	intro_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	intro_label.add_theme_constant_override("outline_size", 10)
	intro_label.modulate.a = 0.0
	root.add_child(intro_label)
	return root


func _process(_delta: float) -> void:
	if screen == "play" and hud_time:
		hud_time.text = Loc.t("time") % game.elapsed


func _refresh_hud() -> void:
	if screen != "play" or game.level.is_empty():
		return
	var lv: Dictionary = game.level
	var txt := Loc.t("level_n") % (lv.index + 1)
	if lv.tiers.size() > 1:
		txt += "  ·  " + Loc.t("tier") % [mini(game.tier_index + 1, lv.tiers.size()), lv.tiers.size()]
	hud_level.text = txt
	var boss := game.is_boss_tier()
	hud_boss.visible = boss
	hud_boss_name.visible = boss
	if boss:
		hud_boss_name.text = Loc.t("boss") + " · " + Loc.t(lv.boss_name)
		hud_boss.max_value = game.hp_max
		hud_boss.value = game.left
	for k in Save.BOOSTERS:
		var b: Button = booster_btns[k]
		var count: int = save.boosters.get(k, 0)
		var used: bool = game.used_boosters.has(k)
		var active: bool = (k == "shield" and game.shield) or (k == "fire" and game.fire_next) \
			or (k == "slow" and game.slow_t > 0.0) or (k == "aim" and game.aim_t > 0.0)
		b.text = "%s\n%s" % [Loc.t(k), ("✓" if active else ("×%d" % count if count > 0 else "▶"))]
		b.disabled = used or game.state != Game.PLAYING or (count <= 0 and not Ads.is_rewarded_ready())
		b.modulate = Color(1, 1, 1, 1) if not active else Color(0.7, 1.0, 0.7)
	hud_quiver.queue_redraw()


func _on_booster(k: String) -> void:
	if screen != "play" or game.state != Game.PLAYING or game.used_boosters.has(k):
		return
	if save.boosters.get(k, 0) > 0:
		if game.use_booster(k):
			save.boosters[k] -= 1
			save.save_file()
			_popup(Loc.t(k) + "!", Color("bfe8ff"))
	elif Ads.is_rewarded_ready():
		if await Ads.show_rewarded("booster_" + k):
			if game.use_booster(k):
				_popup(Loc.t(k) + "!", Color("bfe8ff"))
	_refresh_hud()


func _popup(text: String, color: Color) -> void:
	popup_label.text = text
	popup_label.add_theme_color_override("font_color", color)
	popup_label.modulate.a = 1.0
	popup_label.scale = Vector2.ONE
	popup_label.pivot_offset = popup_label.size * 0.5
	var tw := create_tween()
	tw.tween_property(popup_label, "scale", Vector2.ONE * 1.15, 0.12)
	tw.tween_property(popup_label, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(0.5)
	tw.tween_property(popup_label, "modulate:a", 0.0, 0.4)


# ------------------------------------------------------------------ flow

func _start_level(i: int) -> void:
	current = i
	screen = "play"
	_clear_panels()
	title_screen.hide()
	map_screen.hide()
	hud.show()
	game.start(i)
	_refresh_hud()
	sfx.play("click")
	var intro := ""
	if INTROS.has(i):
		intro = Loc.t(INTROS[i])
	if Levels.is_boss(i):
		_popup(Loc.t("boss") + "!", Color("ff7a6e"))
	if intro != "":
		intro_label.text = intro
		intro_label.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(2.6)
		tw.tween_property(intro_label, "modulate:a", 0.0, 0.6)


func _on_won(time: float, all_candies: bool) -> void:
	var i := current
	var par: float = Levels.total_ornaments(i) * 0.9 + game.level.tiers.size() * 1.5 + 2.0
	if Levels.is_boss(i):
		par *= 1.2
	var s := 1 + int(all_candies) + int(time <= par)
	var first := i >= save.unlocked - 1 and not save.stars.has(i)
	save.stars[i] = maxi(save.stars.get(i, 0), s)
	var prev_best: float = save.best.get(i, 1e9)
	save.best[i] = minf(prev_best, time)
	save.unlocked = clampi(maxi(save.unlocked, i + 2), 1, Levels.COUNT)
	_last_reward = ""
	if first:
		_last_reward = Save.BOOSTERS[randi() % Save.BOOSTERS.size()]
		save.boosters[_last_reward] += 2 if Levels.is_boss(i) else 1
	save.save_file()
	_show_win(s, time, prev_best)


func _show_win(s: int, time: float, prev_best: float) -> void:
	var p := _panel()
	var box: VBoxContainer = p.get_meta("box")
	box.add_child(_label(Loc.t("win"), 46))
	var tv := TreeView.new()
	tv.custom_minimum_size = Vector2(0, 390)
	tv.level = game.level
	tv.done = game.done_tiers
	box.add_child(tv)
	var st := _label("★".repeat(s) + "☆".repeat(3 - s), 64)
	st.add_theme_color_override("font_color", Color("ffd84a"))
	box.add_child(st)
	var tl := Loc.t("time") % time
	if prev_best < 1e8:
		tl += "   " + Loc.t("best") % minf(prev_best, time)
	box.add_child(_label(tl, 28))
	if _last_reward != "":
		var amount := 2 if Levels.is_boss(current) else 1
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 16)
		var rl := _label("%s %s +%d" % [Loc.t("reward"), Loc.t(_last_reward), amount], 30)
		row.add_child(rl)
		if Ads.is_rewarded_ready():
			var dbl := _button(Loc.t("double_ad"), 28)
			var reward := _last_reward
			dbl.pressed.connect(func():
				dbl.disabled = true
				if await Ads.show_rewarded("double_reward"):
					save.boosters[reward] += amount
					save.save_file()
					rl.text = "%s %s +%d" % [Loc.t("reward"), Loc.t(reward), amount * 2]
					dbl.queue_free()
				else:
					dbl.disabled = false)
			row.add_child(dbl)
		box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	box.add_child(row2)
	var menu := _button(Loc.t("menu"), 30)
	menu.pressed.connect(_show_map)
	var retry := _button(Loc.t("retry"), 30)
	retry.pressed.connect(_start_level.bind(current))
	for b in [menu, retry]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(b)
	if current + 1 < Levels.COUNT:
		var nxt := _button(Loc.t("next"), 40)
		nxt.custom_minimum_size.y = 104
		nxt.pressed.connect(_start_level.bind(current + 1))
		box.add_child(nxt)
	_refresh_hud()


func _on_failed(reason: String) -> void:
	var p := _panel()
	var box: VBoxContainer = p.get_meta("box")
	var key := "fail"
	if reason == "ice":
		key = "fail_ice"
	elif reason == "stars":
		key = "fail_stars"
	box.add_child(_label(Loc.t(key), 40))
	box.add_child(_label(Loc.t("level_n") % (current + 1) + "  ·  " + Loc.t("tier") % [game.tier_index + 1, game.level.tiers.size()], 30))
	if not game.continued and Ads.is_rewarded_ready():
		var cont := _button(Loc.t("continue_ad"), 40)
		cont.custom_minimum_size.y = 104
		cont.pressed.connect(func():
			cont.disabled = true
			if await Ads.show_rewarded("continue"):
				_clear_panels()
				game.continue_after_fail()
			else:
				cont.disabled = false)
		box.add_child(cont)
	var retry := _button(Loc.t("retry"), 36)
	retry.custom_minimum_size.y = 96
	retry.pressed.connect(_start_level.bind(current))
	box.add_child(retry)
	var menu := _button(Loc.t("menu"), 30)
	menu.pressed.connect(_show_map)
	box.add_child(menu)


func _toggle_pause() -> void:
	if screen != "play":
		return
	if get_tree().paused:
		_clear_panels()
		get_tree().paused = false
		return
	if not panel_layer.get_children().is_empty() or game.state != Game.PLAYING:
		return
	get_tree().paused = true
	var p := _panel()
	var box: VBoxContainer = p.get_meta("box")
	box.add_child(_label(Loc.t("paused"), 48))
	var resume := _button(Loc.t("resume"), 40)
	resume.custom_minimum_size.y = 104
	resume.pressed.connect(_toggle_pause)
	box.add_child(resume)
	var retry := _button(Loc.t("retry"), 32)
	retry.pressed.connect(func():
		get_tree().paused = false
		_start_level(current))
	box.add_child(retry)
	var snd := _button(Loc.t("sound_off") if save.muted else Loc.t("sound_on"), 32)
	snd.pressed.connect(func():
		_set_muted(not save.muted)
		snd.text = Loc.t("sound_off") if save.muted else Loc.t("sound_on"))
	box.add_child(snd)
	var menu := _button(Loc.t("menu"), 32)
	menu.pressed.connect(func():
		get_tree().paused = false
		_show_map())
	box.add_child(menu)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "play" and not get_tree().paused \
			and not Ads.showing:
		_toggle_pause()


func _set_muted(m: bool) -> void:
	save.muted = m
	sfx.muted = m
	save.save_file()
	sfx.play("click")


# ------------------------------------------------------------------ helpers

func _panel() -> Control:
	_clear_panels()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_layer.add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(600, 0)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	pc.add_child(box)
	dim.set_meta("box", box)
	pc.scale = Vector2.ONE * 0.9
	pc.modulate.a = 0.0
	var tw := dim.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(pc, "scale", Vector2.ONE, 0.18)
	pc.resized.connect(func(): pc.pivot_offset = pc.size * 0.5)
	return dim


func _clear_panels() -> void:
	for c in panel_layer.get_children():
		panel_layer.remove_child(c)
		c.queue_free()


func _full_control() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.theme = theme_ui
	c.process_mode = Node.PROCESS_MODE_ALWAYS
	return c


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 84)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): sfx.play("click"))
	return b


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 30
	var mk := func(c: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = c
		s.set_corner_radius_all(22)
		s.border_color = border
		s.set_border_width_all(0)
		s.border_width_bottom = 6
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		return s
	th.set_stylebox("normal", "Button", mk.call(Color("c8333a"), Color("8a1f25")))
	th.set_stylebox("hover", "Button", mk.call(Color("d9454b"), Color("8a1f25")))
	th.set_stylebox("pressed", "Button", mk.call(Color("a8262d"), Color("6d161b")))
	th.set_stylebox("disabled", "Button", mk.call(Color(0.35, 0.35, 0.4, 0.8), Color(0.2, 0.2, 0.25, 0.8)))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color("fff7ec"))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.45))
	th.set_color("font_hover_color", "Button", Color("ffffff"))
	th.set_color("font_pressed_color", "Button", Color("ffe9c9"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("13263a")
	panel.set_corner_radius_all(30)
	panel.border_color = Color("ffd25e")
	panel.set_border_width_all(4)
	panel.content_margin_left = 34
	panel.content_margin_right = 34
	panel.content_margin_top = 30
	panel.content_margin_bottom = 30
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_color("font_color", "Label", Color("fff7ec"))
	return th
