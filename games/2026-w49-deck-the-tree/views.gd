class_name TreeView
extends Control
## Draws a whole tree: on the win panel (the tree just decorated, with its star)
## and behind the title (a finished demo tree).

var level: Dictionary = {}
var done: Array = []
var title_mode := false
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var theme: Dictionary = Game.THEMES.get(level.get("theme", "forest"), Game.THEMES.forest)
	if title_mode:
		var tiers := 5
		var demo := []
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in tiers:
			var c := []
			for k in 10 - i:
				c.append(Game.ORNAMENT_COLORS[rng.randi() % Game.ORNAMENT_COLORS.size()])
			demo.append(c)
		var w := minf(size.x * 0.75, 520.0)
		var h := w * 1.35
		var r := Rect2((size.x - w) * 0.5, 230.0, w, minf(h, size.y - 600.0))
		TreeArt.draw_tree(self, r, tiers, demo, theme, true, -1, _t)
		return
	var total: int = level.get("tiers", []).size()
	var h2 := size.y - 40.0
	var w2 := h2 * 0.72
	TreeArt.draw_tree(self, Rect2((size.x - w2) * 0.5, 40.0, w2, h2), total, done, theme, true, -1, _t)
