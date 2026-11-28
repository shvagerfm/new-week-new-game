extends SceneTree
## Runs the real game and saves screenshots of the main screens.
##   xvfb-run godot --path . --rendering-driver opengl3 --script tests/shots.gd -- --out=/some/dir
## The bot from tests/sim.gd plays; shots are taken mid-level, on the win and fail panels.

var o := {"out": "user://shots", "w": "720", "h": "1280"}
var main


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			o[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(o.out)
	DisplayServer.window_set_size(Vector2i(int(o.w), int(o.h)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	main.sfx.muted = true
	main.save.unlocked = 50
	for i in 37:
		main.save.stars[i] = [3, 2, 1][i % 3]
	await _wait(0.6)
	await _shot("01-title")
	main._show_map()
	await _wait(0.3)
	await _shot("02-levels")
	await _play_shot(4, 2.5, "03-level5-candies")
	await _play_shot(9, 9.5, "04-boss1")
	await _play_shot(26, 5.0, "05-ice")
	await _play_shot(36, 5.0, "06-workshop-stars")
	await _play_shot(46, 6.0, "07-new-year")
	# a fail: throw without looking until something clashes
	main._start_level(7)
	await _wait(0.3)
	main.game.use_booster("aim")
	for k in 40:
		main.game.throw()
		await _wait(0.05)
		if main.game.state != Game.PLAYING:
			break
	await _wait(1.3)
	await _shot("08-fail")
	# Continue through the mock rewarded ad
	var cont: Button = _find_button(main.panel_layer, Loc.t("continue_ad"))
	cont.pressed.emit()
	await _wait(3.4)
	await _shot("10-test-ad")
	var close: Button = _find_button(root.get_node("Ads"), "Close ✓")
	close.pressed.emit()
	await _wait(0.5)
	print("after continue: state ", main.game.state, " shield ", main.game.shield, " panels ", main.panel_layer.get_child_count())
	await _shot("11-continued")
	# a win
	main._start_level(6)
	while main.game.state != Game.WON:
		_bot()
		await process_frame
	await _wait(1.4)
	await _shot("09-win")
	quit()


func _play_shot(level: int, secs: float, name: String) -> void:
	main._start_level(level)
	var t := 0.0
	while t < secs:
		_bot()
		await process_frame
		t += 1.0 / 60.0
	await _shot(name)


var _wait_t := 0.0


func _bot() -> void:
	var g: Game = main.game
	_wait_t -= 1.0 / 60.0
	if g.state == Game.PLAYING and _wait_t <= 0.0 and g.flying.is_empty() and g.aim_safe():
		if g.stars.is_empty() or g.left > g.stars.size() + 1 or _on_star(g):
			g.throw()
			_wait_t = 0.3


func _on_star(g: Game) -> bool:
	var a := g.predict_landing()
	for st in g.stars:
		if Game._ang_diff(a, st) < Game.HIT_ARC * 0.7:
			return true
	return false


func _find_button(n: Node, text: String) -> Button:
	for c in n.find_children("*", "Button", true, false):
		if c.text == text:
			return c
	return null


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(o.out.path_join(name + ".png"))
	print("shot ", name)
