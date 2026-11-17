extends RefCounted
## Procedural neon icons for weapons and upgrades (no image files).
## draw(ci, id, center, half_size, color) draws into any CanvasItem's _draw().


static func draw(ci: CanvasItem, id: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(1.5, s * 0.16)
	match id:
		"pulse":
			var head := c + Vector2(s * 0.35, -s * 0.35)
			ci.draw_line(c + Vector2(-s * 0.85, s * 0.85), head, Color(col, 0.35), w * 2.2, true)
			ci.draw_line(c + Vector2(-s * 0.4, s * 0.4), head, col, w, true)
			ci.draw_circle(head, s * 0.32, col)
			ci.draw_circle(head, s * 0.14, Color.WHITE)
		"scatter":
			var o := c + Vector2(-s * 0.8, 0)
			for a in [-0.55, -0.27, 0.0, 0.27, 0.55]:
				var d := Vector2.from_angle(a)
				ci.draw_line(o + d * s * 0.3, o + d * s * 1.4, Color(col, 0.6), w * 0.8, true)
				ci.draw_circle(o + d * s * 1.55, w * 0.95, col)
		"laser":
			var a := c + Vector2(-s * 0.9, s * 0.5)
			var b := c + Vector2(s * 0.95, -s * 0.55)
			ci.draw_line(a, b, Color(col, 0.3), w * 3.2, true)
			ci.draw_line(a, b, col, w * 1.3, true)
			ci.draw_line(a, b, Color.WHITE, w * 0.5, true)
			ci.draw_circle(a, s * 0.24, col)
		"rapid":
			for k in 2:
				var x := -s * 0.6 + k * s * 0.6
				ci.draw_polyline(PackedVector2Array([c + Vector2(x, -s * 0.6), c + Vector2(x + s * 0.5, 0), c + Vector2(x, s * 0.6)]), col, w * 1.2, true)
		"multi":
			var base := c + Vector2(0, s * 0.8)
			for a in [-0.5, 0.0, 0.5]:
				var tip := base + Vector2.from_angle(-PI / 2 + a) * s * 1.45
				ci.draw_line(base, tip, Color(col, 0.7), w, true)
				ci.draw_circle(tip, w * 1.15, col)
		"power":
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8 + PI / 8)
				ci.draw_line(c + d * s * 0.45, c + d * s * (0.95 if i % 2 == 0 else 0.72), col, w, true)
			ci.draw_circle(c, s * 0.3, col)
		"crit":
			ci.draw_arc(c, s * 0.6, 0, TAU, 24, col, w, true)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				ci.draw_line(c + d * s * 0.32, c + d * s * 0.95, col, w, true)
			ci.draw_circle(c, w * 0.9, Color.WHITE)
		"pierce":
			ci.draw_arc(c, s * 0.42, 0, TAU, 20, Color(col, 0.55), w, true)
			ci.draw_line(c + Vector2(-s * 0.95, 0), c + Vector2(s * 0.85, 0), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.5, -s * 0.35), c + Vector2(s * 0.92, 0), c + Vector2(s * 0.5, s * 0.35)]), col, w, true)
		"bounce":
			ci.draw_line(c + Vector2(s * 0.8, -s * 0.9), c + Vector2(s * 0.8, s * 0.9), Color(col, 0.5), w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.85, -s * 0.7), c + Vector2(s * 0.62, 0), c + Vector2(-s * 0.85, s * 0.7)]), col, w, true)
			ci.draw_circle(c + Vector2(-s * 0.85, s * 0.7), w * 1.15, col)
		"homing":
			var ctr := c + Vector2(-s * 0.1, s * 0.35)
			var r := s * 0.7
			var end_a := TAU * 0.96
			ci.draw_arc(ctr, r, PI, end_a, 20, col, w, true)
			var tip := ctr + Vector2.from_angle(end_a) * r
			var dir := Vector2.from_angle(end_a + PI / 2)
			ci.draw_line(tip, tip - dir.rotated(0.6) * s * 0.4, col, w, true)
			ci.draw_line(tip, tip - dir.rotated(-0.6) * s * 0.4, col, w, true)
			ci.draw_circle(c + Vector2(s * 0.7, s * 0.7), s * 0.18, Color(col, 0.7))
		"split":
			ci.draw_line(c + Vector2(-s * 0.9, 0), c, col, w, true)
			for sy in [-1.0, 1.0]:
				var e := c + Vector2(s * 0.85, s * 0.6 * sy)
				ci.draw_line(c, e, col, w, true)
				ci.draw_circle(e, w * 1.1, col)
			ci.draw_circle(c, w * 1.2, Color.WHITE)
		"trail":
			var pts := PackedVector2Array([Vector2(0, -0.95), Vector2(0.55, -0.1), Vector2(0.5, 0.45), Vector2(0, 0.85), Vector2(-0.5, 0.45), Vector2(-0.55, -0.1)])
			for i in pts.size():
				pts[i] = c + pts[i] * s
			ci.draw_colored_polygon(pts, Color(col, 0.3))
			var o := pts.duplicate()
			o.append(pts[0])
			ci.draw_polyline(o, col, w, true)
			ci.draw_circle(c + Vector2(0, s * 0.35), s * 0.24, col)
		"shock":
			ci.draw_circle(c, s * 0.18, col)
			for rr in [0.5, 0.88]:
				ci.draw_arc(c, s * rr, -0.8, 0.8, 12, col, w, true)
				ci.draw_arc(c, s * rr, PI - 0.8, PI + 0.8, 12, col, w, true)
		"quick":
			ci.draw_polyline(PackedVector2Array([c + Vector2(s * 0.05, -s * 0.6), c + Vector2(s * 0.75, 0), c + Vector2(s * 0.05, s * 0.6)]), col, w * 1.2, true)
			ci.draw_line(c + Vector2(-s * 0.9, -s * 0.38), c + Vector2(-s * 0.15, -s * 0.38), Color(col, 0.6), w, true)
			ci.draw_line(c + Vector2(-s * 0.7, 0), c + Vector2(s * 0.55, 0), col, w, true)
			ci.draw_line(c + Vector2(-s * 0.9, s * 0.38), c + Vector2(-s * 0.15, s * 0.38), Color(col, 0.6), w, true)
		"vital":
			var heart := PackedVector2Array()
			for i in 32:
				var tt := TAU * i / 32
				var x := 16.0 * pow(sin(tt), 3)
				var y := -(13.0 * cos(tt) - 5.0 * cos(2 * tt) - 2.0 * cos(3 * tt) - cos(4 * tt))
				heart.append(c + Vector2(x, y + 2.0) * s / 17.0)
			ci.draw_colored_polygon(heart, Color(col, 0.35))
			heart.append(heart[0])
			ci.draw_polyline(heart, col, w, true)
		"shield":
			var hex := PackedVector2Array()
			var inner := PackedVector2Array()
			for i in 7:
				var d := Vector2.from_angle(-PI / 2 + TAU * i / 6)
				hex.append(c + d * s * 0.9)
				inner.append(c + d * s * 0.5)
			ci.draw_polyline(hex, col, w, true)
			ci.draw_polyline(inner, Color(col, 0.5), w * 0.8, true)
		"magnet":
			var top := -s * 0.65
			var mid := c + Vector2(0, s * 0.05)
			ci.draw_arc(mid, s * 0.58, 0, PI, 16, col, w * 1.7, true)
			for sx in [-1.0, 1.0]:
				ci.draw_line(mid + Vector2(s * 0.58 * sx, 0), c + Vector2(s * 0.58 * sx, top), col, w * 1.7, true)
				ci.draw_line(c + Vector2(s * 0.58 * sx, top), c + Vector2(s * 0.58 * sx, top - s * 0.3), Color.WHITE, w * 1.7, true)
		"repair":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.75), Vector2(s * 0.4, s * 1.5)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.75, -s * 0.2), Vector2(s * 1.5, s * 0.4)), col)
		"bonus":
			var star := PackedVector2Array()
			for i in 10:
				star.append(c + Vector2.from_angle(-PI / 2 + TAU * i / 10) * s * (0.95 if i % 2 == 0 else 0.42))
			ci.draw_colored_polygon(star, Color(col, 0.35))
			star.append(star[0])
			ci.draw_polyline(star, col, w, true)
		_:
			ci.draw_circle(c, s * 0.5, col)
