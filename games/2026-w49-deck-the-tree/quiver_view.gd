class_name QuiverView
extends Control
## Right edge of the HUD: one ball per ornament still to throw on this tier.

var game: Game


func _draw() -> void:
	if game == null or game.level.is_empty() or game.state == Game.READY:
		return
	var n := game.left - game.flying.size()
	var x := size.x - 46.0
	var y0 := size.y - 300.0
	var step := minf(34.0, 560.0 / maxf(n, 1))
	for i in n:
		var p := Vector2(x, y0 - i * step)
		draw_line(p + Vector2(0, -12), p + Vector2(0, -26), Color("d8c27a"), 3.0)
		draw_circle(p, 11.0, Color(0, 0, 0, 0.3))
		draw_circle(p, 9.0, Color("f6c343") if i > 0 else Color("ffe680"))
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(x - 40, y0 + 46), "%d" % n, HORIZONTAL_ALIGNMENT_CENTER, 80, 30, Color.WHITE)
