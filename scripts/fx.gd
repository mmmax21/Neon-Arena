extends Node2D
## Lightweight particle / ring / floating-text effects, plus spawn warnings.

const MAX_PARTS := 900
const MAX_PARTS_TOUCH := 500  # phones get a lower cap

var main: Node2D
var parts: Array = []   # {p, v, life, m, c, s, drag}
var rings: Array = []   # {p, r, life, m, c}
var texts: Array = []   # {p, s, life, c}
var beams: Array = []   # {a, b, c, w, life, m}
var t := 0.0


func clear() -> void:
	parts.clear()
	rings.clear()
	texts.clear()
	beams.clear()


func _add(d: Dictionary) -> void:
	if parts.size() >= (MAX_PARTS_TOUCH if main.touch and main.touch.active else MAX_PARTS):
		parts.pop_front()
	parts.append(d)


func burst(p: Vector2, c: Color, count: int, spd: float, size: float = 3.0, life: float = 0.5) -> void:
	for i in count:
		var l := life * randf_range(0.5, 1.2)
		_add({"p": p, "v": Vector2.from_angle(randf() * TAU) * spd * randf_range(0.2, 1.0),
			"life": l, "m": l, "c": c, "s": size * randf_range(0.6, 1.3), "drag": 4.0})


func muzzle(p: Vector2, dir: Vector2, c: Color) -> void:
	for i in 3:
		var l := randf_range(0.06, 0.12)
		_add({"p": p, "v": dir.rotated(randf_range(-0.5, 0.5)) * randf_range(150, 320),
			"life": l, "m": l, "c": c, "s": randf_range(2, 3.5), "drag": 8.0})


func ghost(p: Vector2, c: Color, r: float) -> void:
	_add({"p": p, "v": Vector2.ZERO, "life": 0.22, "m": 0.22, "c": Color(c, 0.5), "s": r, "drag": 0.0})


func ring(p: Vector2, r: float, c: Color, life: float) -> void:
	rings.append({"p": p, "r": r, "life": life, "m": life, "c": c})


func beam(a: Vector2, b: Vector2, c: Color, w: float, life: float) -> void:
	beams.append({"a": a, "b": b, "c": c, "w": w, "life": life, "m": life})


func text(p: Vector2, s: String, c: Color) -> void:
	var f: Font = main.ui_font() if main else ThemeDB.fallback_font
	texts.append({"p": p + Vector2(0, -10), "s": s, "life": 0.9, "c": c, "f": f})


func update(delta: float) -> void:
	t += delta
	for d in parts:
		d["life"] -= delta
		d["p"] += d["v"] * delta
		d["v"] *= maxf(0.0, 1.0 - d["drag"] * delta)
	parts = parts.filter(func(d): return d["life"] > 0)
	for d in rings:
		d["life"] -= delta
	rings = rings.filter(func(d): return d["life"] > 0)
	for d in texts:
		d["life"] -= delta
		d["p"] += Vector2(0, -40) * delta
	texts = texts.filter(func(d): return d["life"] > 0)
	for d in beams:
		d["life"] -= delta
	beams = beams.filter(func(d): return d["life"] > 0)
	queue_redraw()


func _draw() -> void:
	if main:
		for h in main.hazards:
			var hk: float = clampf(h["life"] / 1.4, 0, 1)
			var hp: Vector2 = h["p"]
			var fl := 0.8 + 0.2 * sin(t * 30.0 + hp.x)
			draw_circle(hp, 20.0 * hk * fl, Color(1, 0.45, 0.15, 0.18 * hk))
			draw_circle(hp, 10.0 * hk * fl, Color(1, 0.75, 0.3, 0.45 * hk))
	for d in parts:
		var k: float = d["life"] / d["m"]
		var c: Color = d["c"]
		draw_circle(d["p"], maxf(0.5, d["s"] * k), Color(c, c.a * k))
	for d in rings:
		var k: float = d["life"] / d["m"]
		var c: Color = d["c"]
		draw_arc(d["p"], d["r"] * (1.0 - k * k), 0, TAU, 48, Color(c, k), 3.0 * k + 1.0, true)
	for d in beams:
		var k: float = d["life"] / d["m"]
		var c: Color = d["c"]
		var w: float = d["w"]
		draw_line(d["a"], d["b"], Color(c, 0.25 * k), w * 2.6 * k + 1.0, true)
		draw_line(d["a"], d["b"], Color(c, 0.9 * k), w * k + 1.0, true)
		draw_line(d["a"], d["b"], Color(1, 1, 1, k), w * 0.35 * k + 0.5, true)
	if main:
		for m in main.spawn_markers:
			var p: Vector2 = m["p"]
			var big: bool = String(m["type"]).begins_with("boss")
			var r := 54.0 if big else 22.0
			var pulse := 0.5 + 0.5 * sin(t * 18.0)
			var c := Color(1, 0.25, 0.4, 0.4 + pulse * 0.5)
			if m["elite"] != "":
				c = Color(1, 0.85, 0.3, 0.4 + pulse * 0.5)
			draw_arc(p, r, 0, TAU, 40, c, 2.0, true)
			draw_arc(p, r * (0.4 + 0.6 * fmod(t * 2.0, 1.0)), 0, TAU, 40, Color(c, 0.4), 1.5, true)
			draw_line(p + Vector2(-r * 0.4, 0), p + Vector2(r * 0.4, 0), c, 2.0)
			draw_line(p + Vector2(0, -r * 0.4), p + Vector2(0, r * 0.4), c, 2.0)
	for d in texts:
		var k: float = clampf(d["life"] / 0.9 * 2.0, 0, 1)
		var c: Color = d["c"]
		draw_string(d["f"], d["p"] + Vector2(-60, 0), d["s"], HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(c, k))
