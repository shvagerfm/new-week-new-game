class_name Sprites
extends RefCounted
## Where each sprite sits in the art sheets (128 px tiles, 4 x 3 per sheet).
## Mirrors art/source/atlas.json.

const SHEETS := [
	preload("res://art/source/sheet-1-core.png"),
	preload("res://art/source/sheet-2-hazards.png"),
	preload("res://art/source/sheet-3-objects.png"),
	preload("res://art/source/sheet-4-ui.png"),
]

## name -> [sheet, column, row]
const MAP := {
	"robot-up": [0, 0, 0], "robot-down": [0, 1, 0], "robot-left": [0, 2, 0], "robot-right": [0, 3, 0],
	"floor": [0, 0, 1], "wall": [0, 1, 1], "crate": [0, 2, 1], "target": [0, 3, 1],
	"crate-on-target": [0, 0, 2],
	"ice": [1, 0, 0], "one-way-right": [1, 1, 0], "fire-active": [1, 2, 0], "fire-off": [1, 3, 0],
	"switch-up": [1, 0, 1], "switch-pressed": [1, 1, 1], "vortex": [1, 2, 1], "teleport-blue": [1, 3, 1],
	"teleport-purple": [1, 0, 2], "crumbling-floor": [1, 1, 2], "broken-hole": [1, 2, 2],
	"key-card": [2, 0, 0], "door-closed": [2, 1, 0], "door-open": [2, 2, 0], "crate-red": [2, 3, 0],
	"crate-blue": [2, 0, 1], "crate-green": [2, 1, 1], "crate-yellow": [2, 2, 1], "target-red": [2, 3, 1],
	"target-blue": [2, 0, 2], "target-green": [2, 1, 2], "target-yellow": [2, 2, 2], "heavy-crate": [2, 3, 2],
	"pull": [3, 0, 0], "wall-blast": [3, 1, 0], "plus-five-moves": [3, 2, 0], "hint": [3, 3, 0],
	"star-filled": [3, 0, 1], "star-empty": [3, 1, 1], "undo": [3, 2, 1], "restart": [3, 3, 1],
	"menu": [3, 0, 2],
}


static func sheet(i: int) -> Texture2D:
	return SHEETS[i]


static func icon(name: String) -> AtlasTexture:
	var s: Array = MAP[name]
	var t := AtlasTexture.new()
	t.atlas = SHEETS[s[0]]
	t.region = Rect2(s[1] * 128, s[2] * 128, 128, 128)
	return t
