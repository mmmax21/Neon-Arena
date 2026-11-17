extends Node2D
## Player ship: WASD move, mouse aim, hold LMB to fire, Space/Shift/RMB to dash.

const DASH_CD := 1.0
const DASH_TIME := 0.16
const DASH_SPEED := 860.0
const BULLET_SPEED := 780.0
const COLOR := Color(0.25, 0.9, 1.0)

var main: Node2D
var radius := 15.0
var speed := 290.0
var max_hp := 6
var hp := 6
var aim := Vector2.RIGHT
var vel := Vector2.ZERO
var fire_cd := 0.0
var rapid := 0.0
var invuln := 0.0
var dash_t := 0.0
var dash_cd := 0.0
var dash_cd_max := DASH_CD
var dash_dir := Vector2.RIGHT
var dash_held := false
var ghost_t := 0.0
var dead := false
var anim := 0.0


func move_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	return v.normalized()


func update(delta: float) -> void:
	anim += delta
	invuln = maxf(0.0, invuln - delta)
	rapid = maxf(0.0, rapid - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	fire_cd -= delta
	var mv := move_input()
	var to_mouse := get_global_mouse_position() - position
	if to_mouse.length() > 4:
		aim = to_mouse.normalized()

	var dash_now := Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SHIFT) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if dash_now and not dash_held and dash_cd <= 0 and dash_t <= 0:
		dash_dir = mv if mv != Vector2.ZERO else aim
		dash_t = DASH_TIME
		dash_cd = DASH_CD
		invuln = maxf(invuln, DASH_TIME + 0.08)
		main.sfx.play("dash")
		main.fx.ring(position, 40, COLOR, 0.25)
	dash_held = dash_now

	if dash_t > 0:
		dash_t -= delta
		vel = dash_dir * DASH_SPEED
		ghost_t -= delta
		if ghost_t <= 0:
			ghost_t = 0.018
			main.fx.ghost(position, COLOR, radius)
		if dash_t <= 0:
			vel = dash_dir * speed
	else:
		vel = vel.lerp(mv * speed, clampf(delta * 12.0, 0, 1))

	position = main.resolve_static(position + vel * delta, radius)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and fire_cd <= 0:
		shoot()
	queue_redraw()


func shoot() -> void:
	var muzzle := position + aim * (radius + 10)
	var col := Color(1.0, 0.95, 0.45)
	if rapid > 0:
		fire_cd = 0.075
		for a in [-0.13, 0.0, 0.13]:
			main.spawn_bullet(muzzle, aim.rotated(a + randf_range(-0.03, 0.03)) * BULLET_SPEED, true, 1.0, 5.0, col)
	else:
		fire_cd = 0.13
		main.spawn_bullet(muzzle, aim.rotated(randf_range(-0.045, 0.045)) * BULLET_SPEED, true, 1.0, 5.0, col)
	main.fx.muzzle(muzzle, aim, col)
	main.sfx.play("shoot")
	vel -= aim * 18.0
	main.add_shake(1.2)


## Returns true if the hit landed.
func hurt(dmg: int) -> bool:
	if invuln > 0 or dead:
		return false
	hp -= dmg
	invuln = 1.1
	main.combo = 0
	main.add_shake(12)
	main.fx.burst(position, Color(1, 0.35, 0.4), 22, 280, 3.5, 0.5)
	main.sfx.play("hurt")
	if hp <= 0:
		dead = true
		main.on_player_dead()
	return true


func _draw() -> void:
	if invuln > 0 and dash_t <= 0 and int(invuln * 18) % 2 == 0:
		return
	var body := COLOR
	if rapid > 0:
		body = body.lerp(Color(1, 0.9, 0.3), 0.5 + 0.5 * sin(anim * 14))
	draw_circle(Vector2.ZERO, radius + 9, Color(body, 0.10))
	draw_circle(Vector2.ZERO, radius + 4, Color(body, 0.18))
	# Hull: arrow shape pointing to aim
	var a := aim.angle()
	var pts := PackedVector2Array([
		Vector2(radius + 6, 0), Vector2(-radius * 0.7, radius * 0.95),
		Vector2(-radius * 0.35, 0), Vector2(-radius * 0.7, -radius * 0.95)])
	for i in pts.size():
		pts[i] = pts[i].rotated(a)
	draw_colored_polygon(pts, Color(0.06, 0.12, 0.2))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, body, 3.0, true)
	draw_circle(Vector2.ZERO, 4.5, Color(0.9, 1, 1))
	# Dash-ready indicator
	if dash_cd <= 0:
		draw_arc(Vector2.ZERO, radius + 13, 0, TAU, 32, Color(body, 0.35), 1.5, true)
	else:
		draw_arc(Vector2.ZERO, radius + 13, -PI / 2, -PI / 2 + TAU * (1.0 - dash_cd / DASH_CD), 32, Color(body, 0.25), 1.5, true)
