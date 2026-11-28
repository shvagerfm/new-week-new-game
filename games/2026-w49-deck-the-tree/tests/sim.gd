extends SceneTree
## Plays every level with a simple bot and prints how often it wins.
## The bot throws only when Game.aim_safe() says the throw is clear and waits a
## little between throws, like a careful player. A level the bot never beats is
## probably unfair.
##   godot --headless --path . --script tests/sim.gd -- [--tries=10] [--from=0] [--to=49]

var o := {"tries": "8", "from": "0", "to": "49"}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			o[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	_run.call_deferred()


func _run() -> void:
	var g := Game.new()
	root.add_child(g)
	g.set_process(false)
	var all_ok := true
	for i in range(int(o.from), int(o.to) + 1):
		var wins := 0
		var fails := {}
		var times := []
		for k in int(o.tries):
			seed(1000 * i + k)
			var res := _play(g, i)
			if res[0] == "won":
				wins += 1
				times.append(res[1])
			else:
				fails[res[0]] = fails.get(res[0], 0) + 1
		var avg := 0.0
		for tt in times:
			avg += tt
		avg = avg / maxf(times.size(), 1)
		var tiers: int = Levels.get_level(i).tiers.size()
		print("L%02d %s tiers=%d orn=%3d  wins %d/%d  avg %.1fs  %s" % [i + 1, "BOSS" if Levels.is_boss(i) else "    ",
			tiers, Levels.total_ornaments(i), wins, int(o.tries), avg, str(fails)])
		if wins == 0:
			all_ok = false
	print("ALL BEATABLE" if all_ok else "SOME LEVELS NEVER WON")
	quit()


func _play(g: Game, i: int) -> Array:
	g.start(i)
	var result := [""]
	var on_won := func(tm, _c): result[0] = "won"; result.append(tm)
	var on_fail := func(r): result[0] = r
	g.won.connect(on_won)
	g.failed.connect(on_fail)
	var dt := 1.0 / 60.0
	var wait := 0.0
	var frames := 0
	while result[0] == "" and frames < 60 * 240:
		g._process(dt)
		frames += 1
		wait -= dt
		if g.state == Game.PLAYING and wait <= 0.0 and g.flying.is_empty() and g.aim_safe() and _star_ok(g):
			g.throw()
			wait = 0.25
	g.won.disconnect(on_won)
	g.failed.disconnect(on_fail)
	if result[0] == "":
		result[0] = "timeout"
	if OS.get_environment("SIM_DEBUG") != "":
		print("  ", result[0], " tier ", g.tier_index, " left ", g.left, " stuck ", g.stuck.size(), " stars ", g.stars.size())
	if result.size() < 2:
		result.append(0.0)
	return result


## With golden stars left, save the last throws for them.
func _star_ok(g: Game) -> bool:
	if g.stars.is_empty():
		return true
	var a := g.predict_landing()
	for st in g.stars:
		if Game._ang_diff(a, st) < Game.HIT_ARC * 0.9:
			return true
	# don't crowd a star that is still to be hit
	for st in g.stars:
		if Game._ang_diff(a, st) < 0.6:
			return false
	return g.left > g.stars.size() + 1
