class_name Rules
extends RefCounted
## Level data and game rules for Crate Push, with no drawing or input.
## The game, the hint booster and the level checker (tests/check_levels.gd)
## all use this one implementation, so they always agree.
##
## Map characters (see README.md for the full table):
##   # wall    @ robot   + robot on target   $ crate   . target   * crate on target
##   a b c  colored crates      A B C  colored targets
##   &  heavy crate             ~  fire       O  black hole     _  pressure plate
##   =  ice                     > < ^ v  one-way arrows         1-9  teleporter pairs
##   %  crumbling floor         k  key        D  door           t  clock (+5 moves)

const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const DIR_CHARS := {Vector2i.UP: "u", Vector2i.DOWN: "d", Vector2i.LEFT: "l", Vector2i.RIGHT: "r"}
const ARROWS := {">": Vector2i.RIGHT, "<": Vector2i.LEFT, "^": Vector2i.UP, "v": Vector2i.DOWN}
const CLOCK_BONUS := 5

# --- Static level data --------------------------------------------------------
var title := ""
var tip := ""
var limit := 0   # 0 = no move limit
var par := 0     # fewest moves, written by the level checker; 0 = unknown
var size := Vector2i.ONE
var walls := {}
var inside := {}   # every non-wall cell inside the outer walls
var goals := {}    # pos -> "" (any crate) or "a"/"b"/"c"
var fire := {}
var holes := {}
var plates := {}
var ice := {}
var arrows := {}   # pos -> Vector2i
var teleports := {}  # pos -> twin pos
var crumble := {}
var doors := {}
var pickups := {}  # pos -> "k" key or "t" clock
var start := {}
var error := ""


## Parses one map. Directives in comments: "; tip ...", "; limit N", "; par N".
## The first other comment line is the title.
static func parse(lines: PackedStringArray, fallback_title: String) -> Rules:
	var lv := Rules.new()
	var rows := PackedStringArray()
	for raw in lines:
		var s := raw.strip_edges()
		if s.begins_with(";"):
			s = s.trim_prefix(";").strip_edges()
			var word := s.get_slice(" ", 0).to_lower()
			var rest := s.substr(word.length()).strip_edges()
			if word == "tip":
				lv.tip = rest
			elif word == "limit":
				lv.limit = rest.to_int()
			elif word == "par":
				lv.par = rest.to_int()
			elif lv.title.is_empty():
				lv.title = s
		elif not s.is_empty():
			rows.append(raw.rstrip(" \t"))
	if lv.title.is_empty():
		lv.title = fallback_title
	lv._build(rows)
	return lv


func _build(rows: PackedStringArray) -> void:
	var player := Vector2i(-1, -1)
	var boxes := {}
	var pads := {}  # digit -> [pos, ...]
	size = Vector2i(1, rows.size())
	for y in rows.size():
		size.x = maxi(size.x, rows[y].length())
		for x in rows[y].length():
			var p := Vector2i(x, y)
			var c := rows[y][x]
			match c:
				"#": walls[p] = true
				".": goals[p] = ""
				"A", "B", "C": goals[p] = c.to_lower()
				"$", "&", "a", "b", "c": boxes[p] = c
				"*":
					boxes[p] = "$"
					goals[p] = ""
				"@": player = p
				"+":
					player = p
					goals[p] = ""
				"~": fire[p] = true
				"O": holes[p] = true
				"_": plates[p] = true
				"=": ice[p] = true
				">", "<", "^", "v": arrows[p] = ARROWS[c]
				"%": crumble[p] = true
				"D": doors[p] = true
				"k", "t": pickups[p] = c
				_:
					if c >= "1" and c <= "9":
						if not pads.has(c):
							pads[c] = []
						pads[c].append(p)
	for d in pads:
		if pads[d].size() != 2:
			error = "teleporter %s needs exactly two pads" % d
			return
		teleports[pads[d][0]] = pads[d][1]
		teleports[pads[d][1]] = pads[d][0]
	if player.x < 0:
		error = "no robot (@)"
		return
	if goals.is_empty():
		error = "no targets"
		return
	_fill_inside()
	start = {
		"p": player, "boxes": boxes, "keys": 0, "picked": {}, "open": {},
		"crumbled": {}, "blasted": {}, "moves": 0, "bonus": 0, "dead": "",
	}
	if is_lost(start):
		error = "not enough crates for the targets"


## Cells reachable from beyond the map edge without crossing a wall are
## outside; everything else that is not a wall is inside.
func _fill_inside() -> void:
	var outside := {}
	var bounds := Rect2i(Vector2i(-1, -1), size + Vector2i(2, 2))
	var stack: Array[Vector2i] = [Vector2i(-1, -1)]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if outside.has(p) or walls.has(p) or not bounds.has_point(p):
			continue
		outside[p] = true
		for d in DIRS:
			stack.append(p + d)
	for y in size.y:
		for x in size.x:
			var p := Vector2i(x, y)
			if not walls.has(p) and not outside.has(p):
				inside[p] = true


# --- Queries ------------------------------------------------------------------

func hazards_on(s: Dictionary) -> bool:
	if plates.is_empty():
		return true
	for p in plates:
		if not s.boxes.has(p):
			return true
	return false


func is_wall(s: Dictionary, p: Vector2i) -> bool:
	return (walls.has(p) and not s.blasted.has(p)) or not (inside.has(p) or s.blasted.has(p))


func is_locked_door(s: Dictionary, p: Vector2i) -> bool:
	return doors.has(p) and not s.open.has(p)


func is_pit(s: Dictionary, p: Vector2i) -> bool:
	return s.crumbled.get(p, "") == "pit"


func has_pickup(s: Dictionary, p: Vector2i) -> bool:
	return pickups.has(p) and not s.picked.has(p)


func is_won(s: Dictionary) -> bool:
	if s.dead != "":
		return false
	for g in goals:
		if not s.boxes.has(g):
			return false
		if goals[g] != "" and s.boxes[g] != goals[g]:
			return false
	return true


func is_lost(s: Dictionary) -> bool:
	var need := {"": 0, "a": 0, "b": 0, "c": 0}
	var have := {"": 0, "a": 0, "b": 0, "c": 0}
	for g in goals:
		need[goals[g]] += 1
	for b in s.boxes:
		var kind: String = s.boxes[b]
		if have.has(kind):
			have[kind] += 1
	var total_have: int = s.boxes.size()
	var total_need: int = goals.size()
	if total_have < total_need:
		return true
	for k in ["a", "b", "c"]:
		if have[k] < need[k]:
			return true
	return false


func budget(s: Dictionary) -> int:
	return limit + s.bonus if limit > 0 else 0


func blastable(s: Dictionary, dir: Vector2i) -> bool:
	var w: Vector2i = s.p + dir
	return walls.has(w) and not s.blasted.has(w) and inside.has(w + dir)


# --- Moves --------------------------------------------------------------------

func _player_can_enter(s: Dictionary, p: Vector2i, dir: Vector2i) -> bool:
	if is_wall(s, p) or is_pit(s, p):
		return false
	if is_locked_door(s, p) and s.keys <= 0:
		return false
	if arrows.has(p) and arrows[p] != dir:
		return false
	if fire.has(p) and hazards_on(s):
		return false
	return true


func _crate_can_enter(s: Dictionary, p: Vector2i, dir: Vector2i) -> bool:
	if is_wall(s, p) or is_locked_door(s, p) or s.boxes.has(p) or has_pickup(s, p) or s.p == p:
		return false
	if arrows.has(p) and arrows[p] != dir:
		return false
	return true


## Returns the state after moving one step in dir, or {} if the robot can't
## move. pull drags a crate behind the robot along with it.
func step(s: Dictionary, dir: Vector2i, pull := false) -> Dictionary:
	if s.dead != "":
		return {}
	var from: Vector2i = s.p
	var n := from + dir
	if not _player_can_enter(s, n, dir):
		return {}
	var t := s.duplicate(true)
	var vacated: Array[Vector2i] = [from]
	if t.boxes.has(n):
		if not _crate_can_enter(t, n + dir, dir):
			return {}
		var kind: String = t.boxes[n]
		t.boxes.erase(n)
		_place_crate(t, n + dir, dir, kind)
	var behind := from - dir
	if pull and t.boxes.has(behind):
		t.boxes[from] = t.boxes[behind]
		t.boxes.erase(behind)
		vacated = [behind]
	t.p = n
	_arrive(t, dir, vacated)
	_resolve(t, vacated)
	t.moves += 1
	return t


func _place_crate(t: Dictionary, p: Vector2i, dir: Vector2i, kind: String) -> void:
	while true:
		if is_pit(t, p):
			t.crumbled[p] = "filled"  # the crate drops in and becomes floor
			return
		if kind == "&" and crumble.has(p) and not t.crumbled.has(p):
			t.crumbled[p] = "filled"  # too heavy: breaks through and fills it
			return
		if teleports.has(p):
			var twin: Vector2i = teleports[p]
			if not t.boxes.has(twin) and t.p != twin:
				p = twin
			break
		if ice.has(p) and kind != "&" and _crate_can_enter(t, p + dir, dir):
			p += dir
			continue
		break
	t.boxes[p] = kind


func _arrive(t: Dictionary, dir: Vector2i, vacated: Array[Vector2i]) -> void:
	var teleported := false
	while true:
		var p: Vector2i = t.p
		if has_pickup(t, p):
			t.picked[p] = true
			if pickups[p] == "k":
				t.keys += 1
			else:
				t.bonus += CLOCK_BONUS
		if is_locked_door(t, p):
			t.open[p] = true
			t.keys -= 1
		if teleports.has(p) and not teleported:
			var twin: Vector2i = teleports[p]
			if not t.boxes.has(twin):
				vacated.append(p)
				t.p = twin
				teleported = true
				continue
		if ice.has(p) and not teleported:
			var nxt := p + dir
			if _player_can_enter(t, nxt, dir) and not t.boxes.has(nxt):
				vacated.append(p)
				t.p = nxt
				continue
		break


func _resolve(t: Dictionary, vacated: Array[Vector2i]) -> void:
	for c in vacated:
		if crumble.has(c) and not t.crumbled.has(c) and not t.boxes.has(c) and t.p != c:
			t.crumbled[c] = "pit"
	if hazards_on(t):
		for b in t.boxes.keys():
			if fire.has(b) or holes.has(b):
				t.boxes.erase(b)
		if fire.has(t.p):
			t.dead = "The robot overheated."
		elif holes.has(t.p):
			t.dead = "The black hole swallowed the robot."


## Rule checks after a step that aren't about the board itself.
func outcome(s: Dictionary) -> String:
	if s.dead != "":
		return s.dead
	if is_won(s):
		return "won"
	if is_lost(s):
		return "A crate was lost. Undo or restart."
	if limit > 0 and s.moves >= budget(s):
		return "Out of moves."
	return ""


func blast(s: Dictionary, dir: Vector2i) -> Dictionary:
	if not blastable(s, dir):
		return {}
	var t := s.duplicate(true)
	t.blasted[s.p + dir] = true
	return t


# --- Solver -------------------------------------------------------------------

static func key(s: Dictionary) -> String:
	var parts := PackedStringArray([str(s.p), str(s.keys), str(s.bonus)])
	var bk: Array = s.boxes.keys()
	bk.sort()
	for b in bk:
		parts.append("%d,%d%s" % [b.x, b.y, s.boxes[b]])
	for d in ["picked", "open", "crumbled", "blasted"]:
		var ks: Array = s[d].keys()
		if ks.is_empty():
			continue
		ks.sort()
		var cells := PackedStringArray()
		for c in ks:
			cells.append("%d,%d%s" % [c.x, c.y, s[d][c] if d == "crumbled" else ""])
		parts.append(d[0] + ";".join(cells))
	return "|".join(parts)


## Breadth-first search for the fewest moves (no boosters). Returns a string
## of u/d/l/r, "" if already solved, or null if not found within max_states.
## With a tree, it yields a frame every few thousand states so the game
## stays responsive.
func solve(from: Dictionary, max_states := 200000, tree: SceneTree = null) -> Variant:
	if is_won(from):
		return ""
	var seen := {key(from): ""}
	var queue: Array[Dictionary] = [from]
	var paths: Array[String] = [""]
	var head := 0
	while head < queue.size():
		var s := queue[head]
		var path := paths[head]
		head += 1
		if tree != null and head % 2000 == 0:
			await tree.process_frame
		for d in DIRS:
			var t := step(s, d)
			if t.is_empty():
				continue
			var k := key(t)
			if seen.has(k):
				continue
			seen[k] = true
			var o := outcome(t)
			if o == "won":
				return path + DIR_CHARS[d]
			if o != "":
				continue
			queue.append(t)
			paths.append(path + DIR_CHARS[d])
			if seen.size() > max_states:
				return null
	return null
