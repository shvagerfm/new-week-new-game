extends SceneTree
## Saves store-page screenshots and GIF frames from the real game scene.
##   godot --path . --rendering-driver opengl3 --script tests/store_shots.gd -- --out=/some/dir
## Needs a display (use xvfb-run on a server). Resets the save file first.

const D := {"u": Vector2i.UP, "d": Vector2i.DOWN, "l": Vector2i.LEFT, "r": Vector2i.RIGHT}
var out := "user://shots"
var main


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(720, 1280)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.3)
	main.sound_on = false
	main.tips_off = true
	for z in main.zones.size():
		main.intro_seen[main.zones[z].id] = true
	# A run partway through: the first four zones solved, mixed stars.
	var n := 0
	for z in 4:
		for l in main.zones[z].levels:
			main.best[l.id] = [3, 3, 2, 3, 1][n % 5]
			n += 1
	main._show_menu()
	await _shot("1-menu", 1.2)
	main._show_map()
	await _shot("2-map", 0.6)
	main._open_zone(4)
	await _shot("3-levels", 0.6)
	await _play_shot("4-ice", 1, 1, 2)
	await _play_shot("5-fire", 2, 6, 5)
	await _play_shot("6-security", 3, 4, 6)
	await _play_shot("7-teleport", 5, 3, 4)
	await _play_shot("8-core", 6, 7, 6)
	# GIF frames: a whole room, from the first step to "Charged!".
	await _gif("gif-ice", 1, 1)
	await _gif("gif-teleport", 5, 1)
	# The ending after a full run.
	for z in main.zones.size():
		for l in main.zones[z].levels:
			main.best[l.id] = 3 if l.id.hash() % 4 else 2
	main._show_ending()
	for k in 60:
		main._ending_tick(0.1)
	await _shot("9-ending", 0.5)
	quit()


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String, t: float) -> void:
	await _wait(t)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


## Starts a room and plays the first `steps` moves of the solution.
func _play_shot(name: String, z: int, i: int, steps: int) -> void:
	main._start_level(z, i)
	await _wait(0.3)
	var sol: String = await main.lv.solve(main.lv.start, 600000)
	for c in sol.substr(0, steps):
		main._try_move(D[c])
		await _wait(0.35)
	await _shot(name, 1.0)


func _gif(name: String, z: int, i: int) -> void:
	main._start_level(z, i)
	await _wait(0.3)
	var sol: String = await main.lv.solve(main.lv.start, 600000)
	var dir := out.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := 0
	for k in 6:
		await _frame(dir, f); f += 1
	for c in sol:
		main._try_move(D[c])
		for k in 5:
			await _frame(dir, f); f += 1
	for k in 25:
		await _frame(dir, f); f += 1


func _frame(dir: String, f: int) -> void:
	await _wait(0.06)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(dir.path_join("%04d.png" % f))
