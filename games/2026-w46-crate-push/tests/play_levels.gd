extends SceneTree
## Plays every level through the real game scene using the solver's moves,
## and checks that each one ends on the "Charged!" screen with 3 stars.
##   godot --headless --path . --script tests/play_levels.gd

const D := {"u": Vector2i.UP, "d": Vector2i.DOWN, "l": Vector2i.LEFT, "r": Vector2i.RIGHT}


func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var bad := 0
	for z in main.zones.size():
		for i in main.zones[z].levels.size():
			main._start_level(z, i)
			var lv: Rules = main.lv
			var sol = await lv.solve(lv.start, 600000)
			for c in sol:
				main._try_move(D[c])
			var stars: int = main._stars_for(main.state.moves, lv.par, main.booster_used)
			if main.finished != "won" or stars != 3:
				bad += 1
				print("FAIL ", main.zones[z].levels[i].id, " finished=", main.finished, " stars=", stars)
	# Restart starts over cleanly: Undo can't bring back moves from before it.
	main._start_level(2, 1)
	main._try_move(Vector2i.RIGHT)
	main._restart()
	main._undo()
	if main.state.moves != 0 or not main.history.is_empty():
		bad += 1
		print("FAIL undo after restart brought back old moves")
	# Every game event made its sound somewhere along the way.
	for snd in ["step", "push", "charge", "undo", "teleport", "pickup", "door", "crumble"]:
		if not main.sfx._last.has(snd):
			bad += 1
			print("FAIL sound never played: ", snd)
	print("play test: %d failures" % bad)
	quit(1 if bad else 0)
