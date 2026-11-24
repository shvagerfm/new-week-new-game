extends SceneTree
## Prints how much plain running a course has: the share of roofs with no
## obstacle, and the plain stretches (no obstacle, no gap) in seconds.
## godot --headless --path . --script tests/density.gd
func _initialize() -> void:
	var bare := 0
	var roofs_n := 0
	var segs := []
	var longest := []
	var pieces := 0
	for sd in range(1, 21):
		var w := World.new(sd)
		w.start()
		while w.roofs.back().x1 < w.start_x + 3000.0 * World.PX_PER_M:
			w._gen_roof()
		var worst := 0.0
		for r in w.roofs:
			var m: float = (r.x0 - w.start_x) / World.PX_PER_M
			if m < 60.0 or r.crumble:
				continue
			# Puzzle points build their own roofs and keep them clear.
			if w.obstacles.any(func(o): return o.get("grab", false) and absf(o.x0 - r.x0) < 2500.0):
				continue
			var obs := w.obstacles.filter(func(o): return o.get("roof", -1) == r.id)
			obs.sort_custom(func(a, b): return a.x0 < b.x0)
			roofs_n += 1
			if obs.is_empty():
				bare += 1
			var x: float = r.x0
			var v := w.speed_at(r.x0)
			for o in obs + [{"x0": r.x1, "x1": r.x1}]:
				var s: float = (o.x0 - x) / v
				segs.append(s)
				worst = maxf(worst, s)
				x = o.x1
		longest.append(worst)
		for o in w.obstacles:
			if o.get("grab", false) or o.kind in World.PIECES:
				pieces += 1
	segs.sort()
	print("roofs %d, bare %d%%" % [roofs_n, 100 * bare / roofs_n])
	print("plain stretch s: median %.2f  p90 %.2f  max %.2f" % [segs[segs.size() / 2], segs[int(segs.size() * 0.9)], segs.back()])
	print("longest per seed: ", longest.map(func(s): return snappedf(s, 0.1)))
	print("piece objects per 3000 m: %.1f" % (pieces / 20.0))
	quit()
