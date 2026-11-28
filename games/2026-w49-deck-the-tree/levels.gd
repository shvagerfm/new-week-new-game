class_name Levels
extends RefCounted
## All 50 levels: 5 worlds of 10, every 10th level is a boss.
## The elf decorates a Christmas tree tier by tier: each tier spins, the elf throws
## ornaments at it, and when the tier has all its ornaments it rises onto the tree.
##
## A table entry (describes the top tier, see get_level for the lower ones):
##   n        ornaments to throw (for a boss's top tier: its HP)
##   pre      angles (degrees, in the tier's own frame) of ornaments already hanging at the start
##   rot      rotation program, see Rotor
##   candies  optional bonus candies on the rim: hit them all for the second star
##   stars    golden stars on the rim: all of them must be hit to win
##   ice      ice plates [center_deg, width_deg]: an ornament that lands there shatters (= fail)
##   move     the tier sways left and right by this many pixels
##   pulse    the tier breathes: radius changes by this fraction
##   phases   boss only: Array of dicts that replace the fields above when the boss's HP
##            drops to "at"; all hanging ornaments fall off at each phase change
##
## Angles: 0 = right, 90 = down (where ornaments land when the tier is centered).

const WORLDS := [
	{"key": "world_1", "target": "forest", "boss": "boss_1"},
	{"key": "world_2", "target": "gingerbread", "boss": "boss_2"},
	{"key": "world_3", "target": "ice", "boss": "boss_3"},
	{"key": "world_4", "target": "workshop", "boss": "boss_4"},
	{"key": "world_5", "target": "square", "boss": "boss_5"},
]
const COUNT := 50


static func world_of(index: int) -> int:
	return index / 10


static func is_boss(index: int) -> bool:
	return index % 10 == 9


## Evenly spaced angles: k of them, starting at offset.
static func even(k: int, offset := 0.0) -> Array:
	var out := []
	for i in k:
		out.append(fposmod(offset + 360.0 * i / k, 360.0))
	return out


static func plates(k: int, width: float, offset := 0.0) -> Array:
	var out := []
	for a in even(k, offset):
		out.append([a, width])
	return out


static func c(s: float) -> Dictionary:
	return {"m": "const", "s": s}


static func flip(s: float, every: float) -> Dictionary:
	return {"m": "flip", "s": s, "every": every}


static func pulse(s: float, amp: float, period: float) -> Dictionary:
	return {"m": "pulse", "s": s, "amp": amp, "period": period}


static func rnd(lo: float, hi: float, rev := 0.4, t0 := 1.0, t1 := 2.4) -> Dictionary:
	return {"m": "random", "min": lo, "max": hi, "rev": rev, "t0": t0, "t1": t1}


## Tiers per level: the tree grows from 1 tier to 5 over the game.
const TIERS := [
	1, 1, 1, 2, 2, 2, 2, 3, 3, 3,
	2, 2, 3, 3, 3, 3, 3, 3, 3, 4,
	3, 3, 3, 3, 3, 4, 4, 4, 4, 4,
	3, 3, 4, 4, 4, 4, 4, 4, 4, 5,
	4, 4, 4, 4, 5, 5, 5, 5, 5, 5,
]
const BASE_RADIUS := 165.0  # the bottom tier; each tier above is a bit smaller
const RADIUS_STEP := 8.0


## A level is a list of tiers, played bottom to top. The table entry describes the
## top (hardest) tier; lower tiers get fewer ornaments and spin slower.
## Candies and golden stars sit on the top tier only. A boss's top tier is the
## tree-top star with phases.
static func get_level(index: int) -> Dictionary:
	var d: Dictionary = _table()[index].duplicate(true)
	var w: Dictionary = WORLDS[world_of(index)]
	var count: int = TIERS[index]
	var tiers := []
	for j in count:
		var top := j == count - 1
		var t := {}
		var f := 1.0 if count == 1 else (0.75 if count == 2 else 0.6)
		var sf := 1.0 if count == 1 else 0.8 + 0.2 * j / (count - 1)
		t["n"] = d.n if top else clampi(roundi(d.n * f) - (count - 2 - j), 4, 12)
		t["rot"] = _scaled(d.rot, sf if not top else 1.0)
		t["pre"] = d.get("pre", []) if top else _rotate(d.get("pre", []).slice(0, mini(d.get("pre", []).size(), 2 + j)), 37.0 * (j + 1))
		t["ice"] = d.get("ice", []) if top else _rotate_plates(d.get("ice", []).slice(0, maxi(1, d.get("ice", []).size() - 1)), 23.0 * (j + 1))
		t["candies"] = d.get("candies", []) if top else []
		t["stars"] = d.get("stars", []) if top else []
		t["move"] = d.get("move", 0.0)
		t["pulse"] = d.get("pulse", 0.0)
		t["radius"] = BASE_RADIUS - RADIUS_STEP * j
		if top and d.has("phases"):
			t["phases"] = d.phases
			t["radius"] = BASE_RADIUS + 10.0
		tiers.append(t)
	return {
		"index": index, "world": world_of(index), "theme": w.target,
		"boss": is_boss(index), "boss_name": w.boss if is_boss(index) else "",
		"tiers": tiers,
	}


static func total_ornaments(index: int) -> int:
	var sum := 0
	for t in get_level(index).tiers:
		sum += t.n
	return sum


static func _scaled(rot: Dictionary, f: float) -> Dictionary:
	var r := rot.duplicate()
	for k in ["s", "min", "max"]:
		if r.has(k):
			r[k] = r[k] * f
	return r


static func _rotate(angles: Array, by: float) -> Array:
	var out := []
	for a in angles:
		out.append(fposmod(a + by, 360.0))
	return out


static func _rotate_plates(p: Array, by: float) -> Array:
	var out := []
	for pl in p:
		out.append([fposmod(pl[0] + by, 360.0), pl[1]])
	return out


static func _table() -> Array:
	return [
		# --- World 1: the Christmas tree. Steady spin, then reversals, then candies.
		{"n": 5, "rot": c(70)},
		{"n": 6, "rot": c(85), "pre": [270]},
		{"n": 7, "rot": c(-95), "pre": even(2, 0)},
		{"n": 8, "rot": c(110), "pre": even(3, 45)},
		{"n": 8, "rot": flip(110, 3.0), "candies": even(3, 30)},
		{"n": 9, "rot": c(-130), "pre": even(3, 0), "candies": [60, 300]},
		{"n": 9, "rot": flip(130, 2.2), "pre": [20, 200]},
		{"n": 10, "rot": pulse(110, 0.6, 3.0), "pre": even(4, 10), "candies": [135, 315]},
		{"n": 11, "rot": flip(150, 1.8), "pre": even(3, 70), "candies": [10, 250]},
		{"n": 15, "rot": c(100), "pre": even(2, 0), "phases": [
			{"at": 10, "rot": flip(150, 2.0), "pre": even(3, 30)},
			{"at": 5, "rot": rnd(80, 220, 0.5), "pre": even(4, 0)},
		]},
		# --- World 2: the gingerbread house. Speed that changes on its own.
		{"n": 9, "rot": pulse(120, 0.9, 2.5), "pre": even(2, 90)},
		{"n": 10, "rot": rnd(60, 180, 0.3), "pre": even(2, 0)},
		{"n": 10, "rot": rnd(80, 200, 0.5), "pre": even(3, 20), "candies": [100, 280]},
		{"n": 11, "rot": pulse(140, 1.3, 3.0), "pre": even(2, 45)},
		{"n": 11, "rot": rnd(60, 240, 0.5, 0.8, 2.0), "pre": even(4, 0), "candies": even(3, 60)},
		{"n": 12, "rot": flip(170, 1.5), "pre": even(3, 0)},
		{"n": 12, "rot": rnd(90, 260, 0.4), "pre": even(4, 45), "candies": [0, 180]},
		{"n": 12, "rot": pulse(160, 1.1, 2.0), "pre": even(5, 0)},
		{"n": 13, "rot": rnd(100, 280, 0.6), "pre": even(4, 20), "candies": even(3, 0)},
		{"n": 18, "rot": c(130), "pre": even(3, 0), "phases": [
			{"at": 12, "rot": rnd(80, 240, 0.5), "pre": even(4, 45)},
			{"at": 6, "rot": pulse(180, 1.2, 2.2), "pre": even(5, 0)},
		]},
		# --- World 3: the frozen lake. Ice plates shatter ornaments.
		{"n": 8, "rot": c(100), "ice": plates(1, 40, 270)},
		{"n": 9, "rot": c(-120), "ice": plates(2, 30, 0)},
		{"n": 10, "rot": flip(130, 2.0), "ice": plates(1, 50, 90), "pre": [0, 180]},
		{"n": 10, "rot": rnd(80, 200), "ice": plates(2, 30, 45), "pre": [135, 315], "candies": [0, 180]},
		{"n": 11, "rot": pulse(140, 0.8, 2.5), "ice": plates(3, 25, 0), "pre": even(3, 60)},
		{"n": 11, "rot": c(180), "ice": plates(2, 60, 0), "pre": [90, 270]},
		{"n": 12, "rot": rnd(100, 240, 0.5), "ice": plates(2, 40, 90), "pre": even(3, 0), "candies": [45, 225]},
		{"n": 10, "rot": flip(180, 1.4), "ice": plates(3, 24, 30), "pre": even(3, 90)},
		{"n": 13, "rot": rnd(100, 280), "ice": plates(4, 25, 0), "pre": even(3, 45), "candies": [100, 280]},
		{"n": 20, "rot": c(120), "ice": plates(1, 40, 0), "phases": [
			{"at": 14, "rot": flip(160, 1.8), "ice": plates(2, 40, 0), "pre": even(2, 90)},
			{"at": 7, "rot": rnd(100, 260, 0.5), "ice": plates(3, 35, 0), "pre": even(3, 60)},
		]},
		# --- World 4: Santa's workshop. Golden stars to hit, a target that sways.
		{"n": 9, "rot": c(110), "stars": even(3, 0)},
		{"n": 9, "rot": c(100), "move": 50.0},
		{"n": 10, "rot": flip(140, 2.0), "stars": even(3, 30), "pre": [90, 210]},
		{"n": 10, "rot": rnd(80, 200), "move": 70.0, "pre": [0, 180]},
		{"n": 11, "rot": c(150), "move": 60.0, "stars": even(3, 90), "pre": [0, 180]},
		{"n": 11, "rot": pulse(150, 1.0, 2.5), "stars": even(4, 45), "ice": plates(2, 25, 0)},
		{"n": 12, "rot": rnd(100, 240), "move": 80.0, "stars": [90, 270], "pre": even(3, 0)},
		{"n": 12, "rot": flip(180, 1.6), "move": 60.0, "ice": plates(2, 30, 90), "pre": even(3, 0)},
		{"n": 13, "rot": rnd(100, 260), "move": 80.0, "stars": even(3, 60), "pre": even(3, 0), "candies": [30, 210]},
		{"n": 22, "rot": c(130), "move": 40.0, "stars": even(2, 0), "phases": [
			{"at": 15, "rot": flip(170, 1.6), "move": 70.0, "pre": even(3, 0)},
			{"at": 8, "rot": rnd(100, 260, 0.5), "move": 90.0, "ice": plates(2, 30, 45), "pre": even(3, 90)},
		]},
		# --- World 5: New Year's night. The target breathes; everything together.
		{"n": 10, "rot": c(130), "pulse": 0.1},
		{"n": 10, "rot": rnd(100, 220), "pulse": 0.1, "pre": even(3, 0)},
		{"n": 11, "rot": flip(170, 1.5), "pulse": 0.12, "ice": plates(2, 30, 0), "pre": [90, 270]},
		{"n": 11, "rot": rnd(100, 260), "move": 70.0, "stars": even(3, 0)},
		{"n": 12, "rot": pulse(170, 1.2, 2.4), "pulse": 0.12, "pre": even(4, 45), "candies": even(3, 0)},
		{"n": 12, "rot": rnd(120, 280, 0.6), "ice": plates(3, 30, 0), "pre": even(3, 60)},
		{"n": 13, "rot": flip(200, 1.3), "move": 60.0, "stars": even(3, 90), "pre": even(3, 30)},
		{"n": 13, "rot": rnd(120, 300), "pulse": 0.12, "ice": plates(2, 35, 0), "pre": even(4, 45)},
		{"n": 14, "rot": rnd(140, 300, 0.6), "move": 80.0, "stars": even(4, 0), "pre": even(4, 45), "candies": [20, 200]},
		{"n": 25, "rot": c(140), "pulse": 0.08, "phases": [
			{"at": 19, "rot": flip(180, 1.5), "pulse": 0.1, "ice": plates(2, 30, 0), "pre": even(2, 90)},
			{"at": 12, "rot": rnd(120, 280, 0.5), "move": 70.0, "pre": even(4, 45)},
			{"at": 6, "rot": rnd(160, 320, 0.6, 0.6, 1.6), "move": 90.0, "pulse": 0.12, "ice": plates(3, 25, 30)},
		]},
	]
