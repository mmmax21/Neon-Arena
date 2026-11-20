extends Node2D
## Player ship: WASD move, mouse aim, hold LMB to fire, Space/Shift/RMB to dash.
## On touch screens touch.gd supplies movement, aim, firing and dash instead.
## Holds the chosen weapon and upgrade levels; main.gd applies them to shots and hits.

const DASH_CD := 1.0
const DASH_TIME := 0.16
const DASH_SPEED := 860.0
const COLOR := Color(0.25, 0.9, 1.0)
const SHIELD_CD := 15.0
const SHIELD_CD_REACTIVE := 9.0
## Pulse MULTISHOT: the aimed shot keeps full damage, extra shots deal this fraction.
const PULSE_SIDE_DAMAGE := 0.5
## Light costs on firepower cards (per level).
const POWER_SLOW := 0.03     # move speed -3%
const MULTI_SLOW_FIRE := 0.05  # fire interval +5%
const RAPID_SPREAD := 0.02   # extra aim jitter, radians
const PHASE_DASH_DAMAGE := 4.0
const FIRE_INTERVAL := {"pulse": 0.13, "scatter": 0.5, "laser": 0.38}

var main: Node2D
var weapon := "pulse"
var lv := {}  # upgrade id -> level
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
var trail_t := 0.0
var shield_up := false
var shield_cd := 0.0
var side_flip := 1.0  # alternates odd pulse side shots left/right
var dash_hits: Array = []  # enemy ids already struck by this PHASE DASH
var fire_queued := false  # a click shorter than one frame still fires
var dead := false
var anim := 0.0
# Online co-op
var slot := 0
var remote := false   # host-side copy of a guest's ship: driven by net_in, not local input
var client := false   # a guest's own ship: moves locally (prediction), the host fires for it
var net_in := {"mv": Vector2.ZERO, "aim": Vector2.RIGHT, "fire": false, "dash": 0, "pos": Vector2.ZERO}
var dash_seq := 0      # client: dashes started; remote: last dash seen
var want_fire := false # client: fire button state sent to the host


func is_local() -> bool:
	return main.player == self and not remote


## Color of this ship: the host is cyan, the guest magenta.
func ship_color() -> Color:
	return COLOR if slot == 0 else Color(1, 0.45, 0.85)


func level(id: String) -> int:
	return int(lv.get(id, 0))


func add_upgrade(id: String) -> void:
	if id == "repair":
		hp = mini(hp + 3, max_hp)
		return
	lv[id] = level(id) + 1
	match id:
		"vital":
			max_hp += 1
			hp = mini(hp + 1, max_hp)
		"quick":
			dash_cd_max = DASH_CD * pow(0.8, level("quick"))
		"shield":
			shield_up = true
		"reactive":
			if not shield_up:
				shield_cd = minf(shield_cd, SHIELD_CD_REACTIVE)


func damage_mult() -> float:
	return 1.0 + 0.25 * level("power")


func crit_chance() -> float:
	return 0.15 * level("crit")


func move_speed() -> float:
	return speed * (1.0 - POWER_SLOW * level("power"))


func pickup_range() -> float:
	return 130.0 * (1.0 + 0.75 * level("magnet"))


func drop_mult() -> float:
	return 1.0 + 0.3 * level("magnet") + 0.2 * level("storm")


func fire_interval() -> float:
	var f: float = FIRE_INTERVAL[weapon] * pow(0.83, level("rapid")) * (1.0 + MULTI_SLOW_FIRE * level("multi"))
	return f * (0.5 if rapid > 0 else 1.0)


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
	if level("shield") > 0 and not shield_up:
		shield_cd -= delta
		if shield_cd <= 0:
			shield_up = true
			main.fx.ring(position, 50, Color(0.6, 0.95, 1), 0.35)
			main.sfx.play("pickup")
	var mv := Vector2.ZERO
	var touch = main.touch
	var touch_fire := false
	if remote:
		mv = net_in["mv"]
		if (net_in["aim"] as Vector2).length() > 0.1:
			aim = (net_in["aim"] as Vector2).normalized()
		touch_fire = net_in["fire"]
		if int(net_in["dash"]) != dash_seq:
			dash_seq = int(net_in["dash"])
			if dash_t <= 0:
				start_dash(mv.normalized() if mv != Vector2.ZERO else aim)
	else:
		mv = move_input()
		if touch.active:
			var tm: Vector2 = touch.move_vector()
			if tm != Vector2.ZERO:
				mv = tm
			touch_fire = touch.steer(self, delta)
		else:
			var to_mouse := get_global_mouse_position() - position
			if to_mouse.length() > 4:
				aim = to_mouse.normalized()

		var dash_now: bool = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_SHIFT) \
			or (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not touch.active)
		if ((dash_now and not dash_held) or touch.dash_buf > 0) and dash_cd <= 0 and dash_t <= 0:
			touch.dash_buf = 0.0
			start_dash(mv.normalized() if mv != Vector2.ZERO else aim)
			dash_seq += 1
		dash_held = dash_now

	if dash_t > 0:
		dash_t -= delta
		vel = dash_dir * DASH_SPEED
		ghost_t -= delta
		if ghost_t <= 0:
			ghost_t = 0.018
			main.fx.ghost(position, ship_color(), radius)
		if level("trail") > 0 and not client:
			trail_t -= delta
			if trail_t <= 0:
				trail_t = 0.02
				main.add_hazard(position)
		if level("phase") > 0 and not client:
			_phase_hits()
		if dash_t <= 0:
			vel = dash_dir * move_speed()
			if level("shock") > 0 and not client:
				main.shockwave(position, level("shock"))
	else:
		vel = vel.lerp(mv * move_speed(), clampf(delta * 12.0, 0, 1))

	if remote:
		# The guest predicts its own movement; follow its reported position.
		var target: Vector2 = main.resolve_static(net_in["pos"], radius)
		position = position.lerp(target, clampf(delta * 20.0, 0, 1))
	else:
		position = main.resolve_static(position + vel * delta, radius)

	var mouse_fire: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not touch.active and not remote
	if client:
		want_fire = mouse_fire or fire_queued or touch_fire
		if want_fire:
			fire_queued = false
	elif (mouse_fire or fire_queued or touch_fire) and fire_cd <= 0:
		fire_queued = false
		shoot()
	queue_redraw()


func start_dash(dir: Vector2) -> void:
	dash_dir = dir
	dash_t = DASH_TIME
	dash_cd = dash_cd_max
	trail_t = 0.0
	dash_hits.clear()
	invuln = maxf(invuln, DASH_TIME + 0.08)
	main.sfx.play("dash")
	main.fx.ring(position, 40, ship_color(), 0.25)


## PHASE DASH evolution: the dash itself cuts through enemies; a kill refunds the cooldown.
func _phase_hits() -> void:
	for e in main.enemies:
		if e.dead or e.type == "mine":
			continue
		var id: int = e.get_instance_id()
		if dash_hits.has(id):
			continue
		if position.distance_to(e.position) < radius + e.radius + 8.0:
			dash_hits.append(id)
			main.hit_enemy(e, PHASE_DASH_DAMAGE * damage_mult(), dash_dir)
			main.fx.burst(e.position, COLOR, 8, 260, 2.5, 0.3)
			if e.dead:
				dash_cd = 0.0


func shoot() -> void:
	var muzzle := position + aim * (radius + 10)
	var m := level("multi")
	var dmg := damage_mult()
	var jit := RAPID_SPREAD * level("rapid")
	var col: Color = main.WEAPONS[weapon]["color"]
	fire_cd = fire_interval()
	match weapon:
		"scatter":
			var n := 5 + m * 2
			var spread := 0.5 + m * 0.08
			for i in n:
				var a := lerpf(-spread / 2, spread / 2, float(i) / (n - 1)) + randf_range(-0.05 - jit, 0.05 + jit)
				main.spawn_player_bullet(muzzle, aim.rotated(a) * randf_range(620, 760), dmg, 4.5, 0.5, col)
			main.sfx.play("shotgun")
			vel -= aim * 90.0
			if is_local():
				main.add_shake(4.0)
		"laser":
			var n := 1 + m
			for i in n:
				main.fire_laser(position + aim * 4.0, aim.rotated((i - (n - 1) / 2.0) * 0.09 + randf_range(-jit, jit)), 2.2 * dmg, col)
			main.sfx.play("laser")
			vel -= aim * 40.0
			if is_local():
				main.add_shake(2.5)
		_:
			# Aimed shot at full damage; MULTISHOT adds weaker side shots (odd levels alternate sides).
			var shots: Array = [[0.0, dmg]]
			var side := dmg * PULSE_SIDE_DAMAGE
			if m >= 2:
				shots.append([-0.11, side])
				shots.append([0.11, side])
			if m % 2 == 1:
				side_flip = -side_flip
				shots.append([(0.11 if m == 1 else 0.22) * side_flip, side])
			for sh in shots:
				var a: float = sh[0] + randf_range(-0.04 - jit, 0.04 + jit)
				main.spawn_player_bullet(muzzle, aim.rotated(a) * 780.0, sh[1], 5.0 if sh[0] == 0.0 else 4.0, 1.4, col)
			main.sfx.play("shoot")
			vel -= aim * 18.0
			if is_local():
				main.add_shake(1.2)
	main.fx.muzzle(muzzle, aim, col)


## Returns true if the hit landed (or was absorbed by the barrier).
func hurt(dmg: int) -> bool:
	if invuln > 0 or dead:
		return false
	if shield_up:
		shield_up = false
		shield_cd = SHIELD_CD_REACTIVE if level("reactive") > 0 else SHIELD_CD
		if level("reactive") > 0:
			main.reactive_blast(position)
		invuln = 0.8
		if is_local():
			main.add_shake(6)
		main.fx.ring(position, 70, Color(0.6, 0.95, 1), 0.4)
		main.fx.burst(position, Color(0.6, 0.95, 1), 18, 260, 3.0, 0.4)
		main.sfx.play("shield")
		return true
	hp -= dmg
	invuln = 1.1
	main.combo = 0
	if is_local():
		main.add_shake(12)
	main.fx.burst(position, Color(1, 0.35, 0.4), 22, 280, 3.5, 0.5)
	main.sfx.play("hurt")
	if hp <= 0:
		dead = true
		main.on_player_dead(self)
	return true


func _draw() -> void:
	if invuln > 0 and dash_t <= 0 and int(invuln * 18) % 2 == 0:
		return
	var body := ship_color()
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
	# Barrier: hexagon around the ship while charged
	if shield_up:
		var hex := PackedVector2Array()
		for i in 7:
			hex.append(Vector2.from_angle(anim * 1.5 + TAU * i / 6) * (radius + 19))
		draw_polyline(hex, Color(0.6, 0.95, 1, 0.55 + 0.2 * sin(anim * 5)), 2.0, true)
	# Dash-ready indicator
	if dash_cd <= 0:
		draw_arc(Vector2.ZERO, radius + 13, 0, TAU, 32, Color(body, 0.35), 1.5, true)
	else:
		draw_arc(Vector2.ZERO, radius + 13, -PI / 2, -PI / 2 + TAU * (1.0 - dash_cd / dash_cd_max), 32, Color(body, 0.25), 1.5, true)
