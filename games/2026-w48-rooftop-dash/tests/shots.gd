extends SceneTree
## Plays the real game scene with the autopilot and saves screenshots.
##   xvfb-run godot --path . --rendering-driver opengl3 --script tests/shots.gd -- \
##       --out=/some/dir --seed=3 --every=2.0 --until=60 [--crash-at=40]
## Needs a display (xvfb-run on a server). --crash-at stops pressing at that
## second so the run ends and the results screen is captured too.

const Autopilot := preload("res://tests/autopilot.gd")

var o := {"out": "user://shots", "seed": "3", "every": "2.0", "until": "40", "crash-at": "-1",
	"w": "1280", "h": "720", "early": "4"}
var main
var ap
var crash_at := -1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			o[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(o.out)
	DisplayServer.window_set_size(Vector2i(int(o.w), int(o.h)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rooftop_dash.cfg"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.5)
	main.sfx.muted = true
	main.music.volume_db = -80.0
	await _shot("00-title")
	var w := World.new(int(o.seed))
	main.world = w
	ap = Autopilot.new()
	ap.early = int(o.early)
	var probe := World.new(int(o.seed))
	probe.start()
	ap.solve(probe, 3000.0)
	main.best_m = 260.0
	main.best_score = 400
	main._start_run()
	crash_at = float(o["crash-at"])
	physics_frame.connect(_drive)
	var t := 0.0
	var i := 1
	var every := float(o.every)
	while t < float(o.until):
		await _wait(every)
		t += every
		await _shot("%02d-run-%dm" % [i, int(main.world.meters())])
		i += 1
		if main.state == main.State.OVER:
			await _wait(1.0)
			await _shot("%02d-over" % i)
			break
	quit()


func _drive() -> void:
	if main.state != main.State.RUN:
		return
	var tick := roundi(main.world.t / World.DT)
	var held: bool = ap.held_at(tick)
	if crash_at >= 0.0 and main.world.t > crash_at:
		held = false
	main.key_down = held


func _wait(s: float) -> void:
	await create_timer(s, true, true).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(o.out.path_join(name + ".png"))
	print("saved ", name)
