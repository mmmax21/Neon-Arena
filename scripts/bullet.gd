extends Node2D

var vel := Vector2.ZERO
var radius := 5.0
var damage := 1.0
var from_player := true
var life := 1.4
var color := Color(1, 0.95, 0.45)
var dead := false
# Player upgrades
var pierce := 0
var bounce := 0
var homing := false
var split := false
var shard := false
var hit_ids: Array[int] = []


func step(delta: float) -> void:
	position += vel * delta
	life -= delta
	queue_redraw()


func _draw() -> void:
	if from_player:
		var tail := -vel.normalized() * (10.0 if shard else 16.0)
		draw_line(tail, Vector2.ZERO, Color(color, 0.35), radius * 1.6, true)
		draw_line(tail * 0.5, Vector2.ZERO, color, radius, true)
		draw_circle(Vector2.ZERO, radius * 0.6, Color(1, 1, 0.9))
	else:
		draw_circle(Vector2.ZERO, radius + 4, Color(color, 0.18))
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 1, 1, 0.9))
