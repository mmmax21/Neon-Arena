extends Node2D
## Enemy with four behaviours: chaser, shooter, tank, boss.

var main: Node2D
var type := "chaser"
var hp := 1.0
var max_hp := 1.0
var radius := 14.0
var speed := 120.0
var color := Color(1, 0.3, 0.35)
var score_value := 100
var flash := 0.0
var fire_cd := 0.0
var t := 0.0
var dead := false
var vel := Vector2.ZERO
var knock := Vector2.ZERO
var facing := 0.0
var strafe := 1.0
var pattern := 0
var spin := 0.0


func setup(kind: String, wave: int) -> void:
	type = kind
	t = randf() * 10.0
	strafe = 1.0 if randf() < 0.5 else -1.0
	match kind:
		"chaser":
			hp = 2 + floorf(wave / 6.0)
			radius = 13
			speed = minf(140 + wave * 6, 240)
			color = Color(1, 0.3, 0.38)
			score_value = 100
		"shooter":
			hp = 3 + floorf(wave / 5.0)
			radius = 15
			speed = 115
			color = Color(0.75, 0.45, 1)
			score_value = 150
			fire_cd = randf_range(1.0, 2.0)
		"tank":
			hp = 10 + wave
			radius = 25
			speed = 62
			color = Color(1, 0.62, 0.2)
			score_value = 300
		"boss":
			hp = 90 + wave * 14
			radius = 48
			speed = 55
			color = Color(1, 0.25, 0.65)
			score_value = 3000
			fire_cd = 2.0
	max_hp = hp


func update(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta)
	var p: Vector2 = main.player.position
	var to_p := p - position
	var dist := maxf(to_p.length(), 0.001)
	var dir := to_p / dist
	facing = lerp_angle(facing, dir.angle(), clampf(delta * 8.0, 0, 1))
	var desired := Vector2.ZERO
	match type:
		"chaser":
			desired = dir.rotated(sin(t * 3.0) * 0.4) * speed
		"shooter":
			var tang := Vector2(-dir.y, dir.x) * strafe
			if dist > 330:
				desired = dir * speed
			elif dist < 210:
				desired = -dir * speed
			desired += tang * speed * 0.6
			if randf() < delta * 0.4:
				strafe = -strafe
			fire_cd -= delta
			if fire_cd <= 0 and dist < 650:
				fire_cd = maxf(1.0, 2.2 - main.wave * 0.06)
				main.spawn_bullet(position + dir * radius, dir * 270.0, false, 1, 7, Color(0.85, 0.55, 1))
				main.sfx.play("enemy_shoot")
		"tank":
			desired = dir * speed
		"boss":
			spin += delta * (1.2 if hp > max_hp * 0.5 else 2.2)
			desired = dir * speed if dist > 220 else -dir * speed * 0.3
			fire_cd -= delta
			if fire_cd <= 0:
				_boss_fire(dir)

	# Separation from other enemies
	for o in main.enemies:
		if o == self or o.dead:
			continue
		var d: Vector2 = position - o.position
		var min_d: float = radius + o.radius
		var l2 := d.length_squared()
		if l2 < min_d * min_d and l2 > 0.01:
			var l := sqrt(l2)
			desired += d / l * (min_d - l) * 10.0

	vel = vel.lerp(desired, clampf(delta * 6.0, 0, 1))
	position = main.resolve_static(position + (vel + knock) * delta, radius)
	knock = knock.lerp(Vector2.ZERO, clampf(delta * 9.0, 0, 1))

	# Contact damage
	var cr: float = radius + main.player.radius * 0.7
	if dist < cr:
		if main.player.hurt(2 if type == "boss" else 1):
			knock -= dir * 200.0
	queue_redraw()


func _boss_fire(dir: Vector2) -> void:
	var enraged := hp < max_hp * 0.5
	var bc := Color(1, 0.4, 0.75)
	pattern = (pattern + 1) % 3
	if pattern == 0 or pattern == 2:
		var n := 22 if enraged else 16
		for i in n:
			var a := spin + TAU * i / n
			main.spawn_bullet(position + Vector2.from_angle(a) * radius, Vector2.from_angle(a) * 210.0, false, 1, 8, bc)
		fire_cd = 1.1 if enraged else 1.5
	else:
		for i in range(-3, 4):
			var v := dir.rotated(i * 0.14) * 330.0
			main.spawn_bullet(position + dir * radius, v, false, 1, 7, Color(1, 0.7, 0.3))
		fire_cd = 0.8 if enraged else 1.1
	main.sfx.play("enemy_shoot")


func _poly(n: int, r: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.from_angle(rot + TAU * i / n) * r)
	return pts


func _outline(pts: PackedVector2Array, c: Color, w: float) -> void:
	var o := pts.duplicate()
	o.append(pts[0])
	draw_polyline(o, c, w, true)


func _draw() -> void:
	var c := Color.WHITE if flash > 0 else color
	var fill := Color(c.r * 0.18, c.g * 0.18, c.b * 0.18) if flash <= 0 else Color(1, 1, 1, 0.9)
	draw_circle(Vector2.ZERO, radius + 7, Color(c, 0.09))
	match type:
		"chaser":
			var pts := PackedVector2Array([Vector2(radius + 3, 0), Vector2(-radius, radius * 0.85), Vector2(-radius * 0.5, 0), Vector2(-radius, -radius * 0.85)])
			for i in pts.size():
				pts[i] = pts[i].rotated(facing)
			draw_colored_polygon(pts, fill)
			_outline(pts, c, 2.5)
		"shooter":
			var pts := _poly(6, radius, t * 1.5)
			draw_colored_polygon(pts, fill)
			_outline(pts, c, 2.5)
			draw_circle(Vector2.from_angle(facing) * radius * 0.35, 4.5, c)
		"tank":
			var pts := _poly(4, radius * 1.15, t * 0.6 + PI / 4)
			draw_colored_polygon(pts, fill)
			_outline(pts, c, 4.0)
			_outline(_poly(4, radius * 0.6, -t * 0.9), Color(c, 0.6), 2.0)
		"boss":
			var spikes := PackedVector2Array()
			for i in 16:
				var rr := radius * (1.25 if i % 2 == 0 else 0.95)
				spikes.append(Vector2.from_angle(spin + TAU * i / 16) * rr)
			draw_colored_polygon(spikes, fill)
			_outline(spikes, c, 3.5)
			_outline(_poly(8, radius * 0.6, -spin * 0.7), Color(c, 0.7), 2.5)
			draw_circle(Vector2.from_angle(facing) * radius * 0.25, 9, c)
	# Health bar for durable enemies
	if type != "boss" and hp < max_hp and max_hp > 2:
		var w := radius * 2.0
		var y := -radius - 12
		draw_rect(Rect2(-w / 2, y, w, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2, y, w * hp / max_hp, 4), color)
