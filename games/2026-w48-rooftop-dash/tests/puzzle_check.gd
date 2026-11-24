extends SceneTree
## Proves each puzzle point needs its trick: with grabbing turned off for one
## kind (bat or laundry), the autopilot must get stuck right at the first one
## of that kind, and not before.
##   godot --headless --path . --script tests/puzzle_check.gd -- --seeds=8

const Autopilot := preload("res://tests/autopilot.gd")


func _initialize() -> void:
	var seeds := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = a.get_slice("=", 1).to_int()
	var fails := 0
	for kind in World.PIECES:
		if kind == "balcony":
			continue  # plain (hard) jumping, no trick to turn off
		for s in range(1, seeds + 1):
			var first := _first(s, kind)
			if first == INF:
				print("%-7s seed %2d  none in the first 4000 m" % [kind, s])
				continue
			var w := World.new(s)
			w.start()
			w.no_grab = [kind]
			var ap := Autopilot.new()
			ap.max_tries = 3000
			var ok := ap.solve(w, (first - w.start_x) / World.PX_PER_M + 60.0)
			var at := ap.best * World.PX_PER_M + w.start_x
			var good := not ok and at > first - 900.0
			if not good:
				fails += 1
			print("%-7s seed %2d  first at %4d m   without the trick: %s at %4d m  %s" % [kind, s,
				int((first - w.start_x) / World.PX_PER_M), "got past" if ok else "stuck", int(ap.best),
				"ok" if good else "FAIL"])
	print("%d puzzle checks failed" % fails)
	quit(1 if fails > 0 else 0)


## World x of the first puzzle point of this kind in a seed.
func _first(s: int, kind: String) -> float:
	var probe := World.new(s)
	while probe.x < 200000.0:
		for o in probe.obstacles:
			if o.kind == kind:
				return o.x0
		probe.x += 2000.0
		probe._ensure_generated()
	return INF
