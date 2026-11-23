extends SceneTree
## Proves the generated city can be run: tests/autopilot.gd searches for
## button presses that get through the first N metres of several seeds, using
## the game's own World rules. A seed it can't finish means the generator
## made an unfair jump.
##   godot --headless --path . --script tests/bot.gd -- --seeds=20 --meters=2000

const Autopilot := preload("res://tests/autopilot.gd")


func _initialize() -> void:
	var o := {"seeds": "20", "meters": "2000", "first": "1"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			o[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	var goal: float = (o.meters as String).to_float()
	var first: int = (o.first as String).to_int()
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for s in range(first, first + (o.seeds as String).to_int()):
		var w := World.new(s)
		w.start()
		var ap := Autopilot.new()
		var ok := ap.solve(w, goal)
		if not ok:
			failed += 1
		var st: Dictionary = ap.stats
		print("seed %3d  %s  reached %5d m  (%d tries)  ac %d  antennas %d  skylights %d  bats %d  laundry %d  wires %d  crumbling %d" % [
			s, "ok  " if ok else "FAIL", int(ap.best), ap.tried, st.ac, st.antenna, st.skylight, st.bat,
			st.laundry, st.wire, st.crumble])
	print("%d seeds failed, %.1f s" % [failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)
