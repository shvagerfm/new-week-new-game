class_name TreeArt
extends RefCounted
## The tree seen from the side, built from the tiers finished so far.
## Used for the small preview during play and the big tree on the win panel.


## rect: where the whole tree (trunk to star) fits. done: per finished tier, the
## colors of its ornaments. current: the tier being played (outlined), -1 for none.
static func draw_tree(ci: CanvasItem, rect: Rect2, total: int, done: Array, theme: Dictionary,
		with_star: bool, current: int, t: float) -> void:
	var cols: Array = theme.tier
	var trunk_h := rect.size.y * 0.1
	var star_h := rect.size.y * 0.14
	var body := Rect2(rect.position.x, rect.position.y + star_h, rect.size.x, rect.size.y - star_h - trunk_h)
	var cx := rect.get_center().x
	ci.draw_rect(Rect2(cx - rect.size.x * 0.08, body.end.y - 2, rect.size.x * 0.16, trunk_h), Color("6b4428"))
	var tier_h := body.size.y / maxf(total, 1)
	for i in total:
		# tier 0 is the bottom, widest
		var bottom := body.end.y - tier_h * i
		var top := bottom - tier_h * 1.45
		var half := rect.size.x * 0.5 * (1.0 - 0.6 * i / maxf(total, 1))
		var pts := PackedVector2Array([Vector2(cx - half, bottom), Vector2(cx + half, bottom), Vector2(cx, top)])
		if i < done.size():
			ci.draw_colored_polygon(pts, cols[1])
			ci.draw_colored_polygon(PackedVector2Array([Vector2(cx - half, bottom), Vector2(cx, bottom), Vector2(cx, top)]), cols[0])
			ci.draw_line(Vector2(cx - half, bottom), Vector2(cx + half, bottom), cols[2], 2.0)
			var colors: Array = done[i]
			var rng := RandomNumberGenerator.new()
			rng.seed = 97 + i * 13
			for k in colors.size():
				var v := rng.randf_range(0.15, 0.95)
				var y := lerpf(top, bottom, v)
				var w := half * v * 0.85
				var p := Vector2(cx + rng.randf_range(-w, w), y)
				ci.draw_circle(p, maxf(rect.size.x * 0.028, 2.5), colors[k])
		else:
			var a := 0.25
			if i == current:
				a = 0.45 + 0.3 * sin(t * 6.0)
			ci.draw_colored_polygon(pts, Color(1, 1, 1, 0.08))
			ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(1, 1, 1, a), 2.0)
	var top_y := body.end.y - tier_h * (total - 1) - tier_h * 1.45
	if with_star:
		var c := Vector2(cx, top_y - star_h * 0.25)
		var pts := PackedVector2Array()
		for i in 10:
			var rr := star_h * (0.6 if i % 2 == 0 else 0.27)
			pts.append(c + Vector2.from_angle(-PI * 0.5 + TAU * i / 10.0) * rr)
		ci.draw_colored_polygon(pts, Color("ffd84a"))
		ci.draw_circle(c, star_h * (0.9 + 0.1 * sin(t * 4.0)), Color(1.0, 0.9, 0.4, 0.18))
