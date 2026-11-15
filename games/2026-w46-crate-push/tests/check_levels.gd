extends SceneTree
## Solves every level with the game's own rules and reports the fewest moves.
##   godot --headless --path games/<this game> --script tests/check_levels.gd
## Add "-- --write-par" to store each result as "; par N" in its level file,
## which is what the star rating compares against. Add "-- --only=<text>" to
## check just the levels whose id contains <text>.

const MAX_STATES := 600000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var write := args.has("--write-par")
	var only := ""
	for a in args:
		if a.begins_with("--only="):
			only = a.substr(7)
	var failed := 0
	var count := 0
	for zone in Campaign.load_zones():
		print("== ", zone.name)
		for lvl in zone.levels:
			if only != "" and not lvl.id.contains(only):
				continue
			count += 1
			var rules: Rules = lvl.rules
			var t := Time.get_ticks_msec()
			var sol = await rules.solve(rules.start, MAX_STATES)
			var ms := Time.get_ticks_msec() - t
			if sol == null:
				failed += 1
				print("  FAIL  %s  (no solution in %d states, %d ms)" % [lvl.id, MAX_STATES, ms])
				continue
			var note := ""
			if rules.limit > 0:
				note = "  limit %d" % rules.limit
			print("  ok  %-40s %3d moves  %5d ms%s  %s" % [lvl.id, sol.length(), ms, note, sol])
			if write and rules.par != sol.length():
				_write_par(lvl.path, sol.length())
	print("%d levels, %d failed" % [count, failed])
	quit(1 if failed > 0 else 0)


func _write_par(path: String, par: int) -> void:
	var lines := FileAccess.get_file_as_string(path).replace("\r", "").split("\n")
	var out := PackedStringArray()
	for l in lines:
		if l.strip_edges().begins_with("; par "):
			continue
		out.append(l)
	# Insert after the leading comment block.
	var i := 0
	while i < out.size() and out[i].strip_edges().begins_with(";"):
		i += 1
	out.insert(i, "; par %d" % par)
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string("\n".join(out))
