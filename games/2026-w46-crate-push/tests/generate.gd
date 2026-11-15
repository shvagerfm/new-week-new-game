extends SceneTree
## Level idea generator: makes random rooms with the given features, solves
## them with the game's rules, and prints the most interesting ones. Results
## still need a human look before they go into levels/.
##   godot --headless --path . --script tests/generate.gd -- \
##       --features=ice,arrows --crates=2 --w=7 --h=6 --tries=3000 --seed=1
## Features: ice arrows fire holes crumble heavy keys colors teleport

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var o := {"features": "", "crates": "2", "w": "7", "h": "6", "tries": "2000", "seed": "1", "walls": "0.18", "top": "4", "max": "60"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			o[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	rng.seed = o.seed.to_int()
	var feats := PackedStringArray(o.features.split(",", false))
	var found: Array = []
	for i in o.tries.to_int():
		var rows := _room(o.w.to_int(), o.h.to_int(), o.crates.to_int(), feats, o.walls.to_float())
		var lv := Rules.parse(rows, "gen")
		if lv.error != "":
			continue
		var sol = await lv.solve(lv.start, 40000)
		if sol == null or sol.length() < 8 or sol.length() > o.max.to_int():
			continue
		var plain := Rules.parse(_strip(rows, feats), "plain")
		var psol = null if plain.error != "" else await plain.solve(plain.start, 40000)
		var gain: int = 99 if psol == null else sol.length() - psol.length()
		if gain < 4:
			continue
		var score: int = sol.length() + _turns(sol) * 2 + mini(gain, 20)
		found.append({"score": score, "rows": rows, "sol": sol, "gain": gain})
	found.sort_custom(func(a, b): return a.score > b.score)
	for f in found.slice(0, o.top.to_int()):
		print("; score %d  moves %d  gain %d  %s" % [f.score, f.sol.length(), f.gain, f.sol])
		print("\n".join(f.rows))
		print()
	print("%d candidates" % found.size())
	quit()


func _turns(sol: String) -> int:
	var n := 0
	for i in range(1, sol.length()):
		if sol[i] != sol[i - 1]:
			n += 1
	return n


func _strip(rows: PackedStringArray, feats: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		var s := r
		for c in ["=", ">", "<", "^", "v", "%", "D", "k", "1", "2", "3"]:
			s = s.replace(c, " ")
		s = s.replace("&", "$").replace("a", "$").replace("b", "$").replace("A", ".").replace("B", ".")
		out.append(s)
	return out


func _room(w: int, h: int, crates: int, feats: PackedStringArray, wall_rate: float) -> PackedStringArray:
	var g := []
	for y in h:
		var row := []
		for x in w:
			var border := x == 0 or y == 0 or x == w - 1 or y == h - 1
			row.append("#" if border or rng.randf() < wall_rate else " ")
		g.append(row)
	var free := func() -> Vector2i:
		for _i in 200:
			var p := Vector2i(rng.randi_range(1, w - 2), rng.randi_range(1, h - 2))
			if g[p.y][p.x] == " ":
				return p
		return Vector2i(-1, -1)
	var put := func(c: String) -> bool:
		var p: Vector2i = free.call()
		if p.x < 0:
			return false
		g[p.y][p.x] = c
		return true
	if feats.has("ice"):
		for _i in rng.randi_range(4, 9):
			put.call("=")
	if feats.has("arrows"):
		for _i in rng.randi_range(1, 3):
			put.call([">", "<", "^", "v"][rng.randi() % 4])
	if feats.has("crumble"):
		for _i in rng.randi_range(2, 5):
			put.call("%")
	if feats.has("teleport"):
		put.call("1")
		put.call("1")
	if feats.has("split"):
		# A wall across the room with one door in it.
		var sx := rng.randi_range(3, w - 4)
		for y in range(1, h - 1):
			g[y][sx] = "#"
		g[rng.randi_range(1, h - 2)][sx] = "D"
		put.call("k")
	if feats.has("keys"):
		for _i in rng.randi_range(1, 2):
			put.call("D")
			put.call("k")
	for i in crates:
		var kind := "$"
		var goal := "."
		if feats.has("colors") and i < 2:
			kind = ["a", "b"][i]
			goal = kind.to_upper()
		if feats.has("heavy") and i == crates - 1:
			kind = "&"
		put.call(kind)
		put.call(goal)
	put.call("@")
	var rows := PackedStringArray()
	for row in g:
		rows.append("".join(row))
	return rows
