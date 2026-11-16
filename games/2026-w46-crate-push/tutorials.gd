class_name Tutorials
extends RefCounted
## Tip cards: the first-room walkthrough and a short card the first time a
## room has a new tile, crate or tool. Each card is shown once (main.gd keeps
## the seen list in the save file).

## The walkthrough in the first room. Each step moves on when the player does
## the thing it asks for, not with a button.
const WALKTHROUGH := ["move", "push", "goal"]

## id -> title, text, icon (a sprite from sprites.gd)
const TOPICS := {
	"move": {
		"title": "Move Kip",
		"text": "Tap the arrows at the bottom, or swipe on the board. Hold to keep walking. Keyboard: arrows or WASD.",
		"icon": "robot-right",
	},
	"push": {
		"title": "Push the crate",
		"text": "Walk into a crate to push it. Kip can't pull, so don't trap a crate in a corner.",
		"icon": "crate",
	},
	"goal": {
		"title": "Charge it",
		"text": "Push the crate onto the glowing charger. A room is done when every charger has a crate.",
		"icon": "target",
	},
	"undo": {
		"title": "Undo and Restart",
		"text": "Stuck? Undo takes back a move. Restart puts the room back as it was, and can be undone too.",
		"icon": "undo",
	},
	"ice": {
		"title": "Ice",
		"text": "Kip and crates slide across ice until they hit something or reach plain floor.",
		"icon": "ice",
	},
	"arrows": {
		"title": "One-way arrows",
		"text": "Kip and crates can only move onto an arrow in the direction it points.",
		"icon": "one-way-right",
	},
	"fire": {
		"title": "Fire",
		"text": "Fire blocks Kip and burns any crate pushed into it.",
		"icon": "fire-active",
	},
	"plates": {
		"title": "Pressure plates",
		"text": "While every plate holds a crate, fire and black holes switch off. Move the crate away and they come back.",
		"icon": "switch-up",
	},
	"keys": {
		"title": "Keys and doors",
		"text": "Walk over a key to pick it up. Each key opens one door. Crates can't open doors.",
		"icon": "key-card",
	},
	"colors": {
		"title": "Colored crates",
		"text": "A colored crate only charges on a bay of its own color. Plain chargers take any crate.",
		"icon": "crate-red",
	},
	"crumble": {
		"title": "Cracked floor",
		"text": "It falls in once Kip steps off it, and Kip can't cross a hole. Push a crate in to fill it.",
		"icon": "crumbling-floor",
	},
	"heavy": {
		"title": "Heavy crates",
		"text": "Heavy crates don't slide on ice. They crash through cracked floor and fill the hole.",
		"icon": "heavy-crate",
	},
	"teleport": {
		"title": "Teleporters",
		"text": "Step on a pad to come out of its twin. Crates pushed onto a pad teleport too.",
		"icon": "teleport-blue",
	},
	"holes": {
		"title": "Black holes",
		"text": "A black hole swallows any crate pushed into it, and Kip too. Plates switch them off.",
		"icon": "vortex",
	},
	"limit": {
		"title": "Move limit",
		"text": "Power is low: this room only allows so many moves. Watch the counter at the top.",
		"icon": "restart",
	},
	"clock": {
		"title": "Clocks",
		"text": "Walk over a clock to get 5 extra moves.",
		"icon": "plus-five-moves",
	},
	"tool-hint": {
		"title": "New tool: Hint",
		"text": "Tap Hint (or press H) and an arrow shows a good next move. Any tool caps the room at 2 stars.",
		"icon": "hint",
	},
	"tool-pull": {
		"title": "New tool: Pull",
		"text": "Tap Pull, then step away from a crate to drag it one step behind Kip.",
		"icon": "pull",
	},
	"tool-blast": {
		"title": "New tool: Blast",
		"text": "Tap Blast, then swipe toward an inner wall to remove it. Outer walls can't be blasted.",
		"icon": "wall-blast",
	},
	"tool-moves": {
		"title": "New tool: +5 moves",
		"text": "Running out of moves? Tap +5 for five more, once per try.",
		"icon": "plus-five-moves",
	},
}


## Cards that fit this room, in the order to show them: anything new on the
## board first, then the tools. boosters: the tools available in this room.
static func topics_for(lv: Rules, boosters: Array) -> Array[String]:
	var out: Array[String] = ["undo"]
	var kinds: Array = lv.start.boxes.values()
	var colored := false
	for g in lv.goals:
		colored = colored or lv.goals[g] != ""
	var checks := [
		["ice", not lv.ice.is_empty()],
		["arrows", not lv.arrows.is_empty()],
		["fire", not lv.fire.is_empty()],
		["plates", not lv.plates.is_empty()],
		["keys", not lv.doors.is_empty() or lv.pickups.values().has("k")],
		["colors", colored],
		["crumble", not lv.crumble.is_empty()],
		["heavy", kinds.has("&")],
		["teleport", not lv.teleports.is_empty()],
		["holes", not lv.holes.is_empty()],
		["limit", lv.limit > 0],
		["clock", lv.pickups.values().has("t")],
	]
	for c in checks:
		if c[1]:
			out.append(c[0])
	for b in ["hint", "pull", "blast", "moves"]:
		# +5 only matters (and only works) in a room with a move limit.
		if boosters.has(b) and (b != "moves" or lv.limit > 0):
			out.append("tool-" + b)
	return out


## Board cells to point at while a card is up.
static func cells_for(id: String, lv: Rules, s: Dictionary) -> Array:
	match id:
		"move":
			return [s.p]
		"push", "heavy":
			return s.boxes.keys().filter(func(p): return id == "push" or s.boxes[p] == "&")
		"goal":
			return lv.goals.keys()
		"ice":
			return lv.ice.keys()
		"arrows":
			return lv.arrows.keys()
		"fire":
			return lv.fire.keys()
		"plates":
			return lv.plates.keys()
		"keys":
			return lv.doors.keys() + lv.pickups.keys().filter(func(p): return lv.pickups[p] == "k")
		"colors":
			return lv.goals.keys().filter(func(p): return lv.goals[p] != "") \
					+ s.boxes.keys().filter(func(p): return "abc".contains(s.boxes[p]))
		"crumble":
			return lv.crumble.keys()
		"teleport":
			return lv.teleports.keys()
		"holes":
			return lv.holes.keys()
		"clock":
			return lv.pickups.keys().filter(func(p): return lv.pickups[p] == "t")
	return []
