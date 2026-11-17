extends Node2D

var type := "heal"
var life := 10.0
var t := 0.0
var dead := false


func get_color() -> Color:
	return Color(0.4, 1, 0.5) if type == "heal" else Color(1, 0.88, 0.3)


func step(delta: float) -> void:
	life -= delta
	t += delta
	queue_redraw()


func _draw() -> void:
	if life < 3.0 and int(life * 8) % 2 == 0:
		return
	var c := get_color()
	var bob := sin(t * 4.0) * 3.0
	var o := Vector2(0, bob)
	draw_circle(o, 20 + sin(t * 6) * 2, Color(c, 0.12))
	draw_arc(o, 13, 0, TAU, 32, c, 2.5, true)
	if type == "heal":
		draw_rect(Rect2(o + Vector2(-2.5, -7), Vector2(5, 14)), c)
		draw_rect(Rect2(o + Vector2(-7, -2.5), Vector2(14, 5)), c)
	else:
		var bolt := PackedVector2Array([
			Vector2(2, -9), Vector2(-5, 1), Vector2(-0.5, 1),
			Vector2(-2, 9), Vector2(5, -1), Vector2(0.5, -1)])
		for i in bolt.size():
			bolt[i] += o
		draw_colored_polygon(bolt, c)
