extends SceneTree
## Plays a short trailer through the real game scene, for Godot's movie maker:
##   xvfb-run godot --path . --rendering-driver opengl3 --resolution 720x1280 \
##       --fixed-fps 30 --write-movie /tmp/trailer.avi --script tests/trailer.gd
## with window_width_override=1080 / window_height_override=1920 in a temporary override.cfg,
## then: ffmpeg -ss 0.1 -i trailer.avi -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac trailer.mp4

const D := {"u": Vector2i.UP, "d": Vector2i.DOWN, "l": Vector2i.LEFT, "r": Vector2i.RIGHT}
const STEP := 0.17  # seconds between moves

## [zone, room, caption]
const CLIPS := [
	[0, 2, "Push every crate\nonto a charger"],
	[1, 1, "Slide across ice"],
	[2, 0, "Find a way past the fire"],
	[3, 0, "Grab keys, open doors"],
	[4, 0, "Floors crumble behind you"],
	[5, 1, "Teleport crates\nacross the room"],
	[6, 0, "Steer clear of black holes"],
]

var main
var caption: Label
var banner: Panel


func _initialize() -> void:
	root.size = Vector2i(720, 1280)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.1)
	main.sound_on = true
	main.sfx.muted = false
	main.tips_off = true
	for z in main.zones.size():
		main.intro_seen[main.zones[z].id] = true
	_make_caption()
	# Solve every room first; the video is trimmed to start at the menu.
	var sols := []
	for c in CLIPS:
		main._start_level(c[0], c[1])
		sols.append(await main.lv.solve(main.lv.start, 600000))
	main._show_menu()
	print("TRAILER_START ", Engine.get_frames_drawn())
	await _wait(2.8)
	for k in CLIPS.size():
		await _clip(CLIPS[k][0], CLIPS[k][1], CLIPS[k][2], sols[k])
	# The ending after a perfect run.
	for z in main.zones.size():
		for l in main.zones[z].levels:
			main.best[l.id] = 3
	_say("")
	main._show_ending()
	await _wait(7.0)
	# Back to the title.
	main._show_menu()
	main.continue_button.hide()
	_say("60 rooms · 7 zones\nNow on itch.io")
	await _wait(4.0)
	quit()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _clip(z: int, i: int, text: String, sol: String) -> void:
	main._start_level(z, i)
	_say(text)
	await _wait(0.6)
	for c in sol:
		main._try_move(D[c])
		await _wait(STEP)
	await _wait(1.1)


func _make_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	banner = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.88)
	sb.border_color = Color("ff8a1f")
	sb.border_width_bottom = 4
	banner.add_theme_stylebox_override("panel", sb)
	banner.position = Vector2(0, 0)
	banner.size = Vector2(720, 212)
	layer.add_child(banner)
	caption = Label.new()
	caption.theme = main.ui.theme
	caption.add_theme_font_size_override("font_size", 46)
	caption.add_theme_color_override("font_color", Color("ffb347"))
	caption.add_theme_color_override("font_outline_color", Color("0d0f1a"))
	caption.add_theme_constant_override("outline_size", 10)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.position = Vector2(20, 0)
	caption.size = Vector2(680, 208)
	banner.add_child(caption)
	banner.hide()


func _say(text: String) -> void:
	caption.text = text
	banner.visible = text != ""
