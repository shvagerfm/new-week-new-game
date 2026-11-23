extends SceneTree
## Screenshots of the menus in the same states as the mockups in art/source/ui/,
## to compare them side by side.
##   xvfb-run godot --path . --rendering-driver opengl3 --script tests/menu_shots.gd -- --out=/some/dir [--size=720x1280]

var out := "user://menu_shots"
var main


func _initialize() -> void:
	var size := Vector2i(720, 1280)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--size="):
			var wh := a.substr(7).split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(out)
	root.size = size
	DisplayServer.window_set_size(size)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.3)
	main.sfx.muted = true  # not sound_on: that would be saved
	main.best = {}
	main._show_menu()
	await _shot("1-menu-new", 0.4)
	# The mockups' state: the Warehouse done (first four with stars, as drawn), Cold Storage next.
	var stars := [3, 3, 2, 1, 2, 3, 3, 1, 2, 3]
	var ws: Array = main.zones[0].levels
	for i in ws.size():
		main.best[ws[i].id] = stars[i]
	for z in main.zones.size():
		main.intro_seen[main.zones[z].id] = true
	main._show_menu()
	await _shot("2-menu", 0.4)
	main._show_settings()
	await _shot("3-settings", 0.3)
	main._hide_overlay()
	main._show_map()
	await _shot("4-map", 0.5)
	# Level select as in the mockup: 4 of 10 solved, the 5th is next.
	var keep := {}
	for i in 4:
		keep[ws[i].id] = stars[i]
	main.best = keep
	main._open_zone(0)
	await _shot("5-levels", 0.5)
	main.best = {}
	main._show_map()
	await _shot("6-map-new", 0.4)
	for z in main.zones.size():
		for l in main.zones[z].levels:
			main.best[l.id] = 3
	main._show_map()
	await _shot("7-map-done", 0.4)
	main._open_zone(1)
	await _shot("8-levels-cold", 0.4)
	quit()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String, t: float) -> void:
	await _wait(t)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
