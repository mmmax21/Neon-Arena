extends Node2D
## All enemy types.
## Regular: chaser, shooter, tank, splitter, mini, dodger, sentry, layer, mine, snake.
## Bosses: boss (CORE WARDEN), boss2 (VOID WEAVER).
## Elites carry one affix: shield, haste or volatile.

const SEG_RADIUS := 11.0
const SEG_SPACING := 21.0
const SEG_COUNT := 7
const MINE_BLAST := 80.0
const BOSS_NAMES := {"boss": "CORE WARDEN", "boss2": "VOID WEAVER"}

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
var is_boss := false
var display_name := ""
var no_clear := false  # mines don't block wave clear
var knock_scale := 1.0
# Elite
var elite := ""
var shield := 0.0
var shield_max := 0.0
# Dodger
var dodge_cd := 0.0
# Sentry / VOID WEAVER beams; mine arming
var phase := ""
var phase_t := 0.0
var beam_dir := Vector2.RIGHT
var beam_len := 0.0
var move_target := Vector2.ZERO
var beams: Array[float] = []
var beam_lens: Array[float] = []
var beam_spin_dir := 1.0
# Mine
var fuse := -1.0
# Snake body, head first
var segs: Array[Vector2] = []


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
			knock_scale = 2.4
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
		"splitter":
			hp = 4 + floorf(wave / 5.0)
			radius = 19
			speed = 85
			color = Color(0.6, 1, 0.3)
			score_value = 150
		"mini":
			hp = 1
			radius = 9
			speed = 210 + minf(wave * 3, 60)
			color = Color(0.7, 1, 0.45)
			score_value = 40
			knock_scale = 2.4
		"dodger":
			hp = 2 + floorf(wave / 6.0)
			radius = 13
			speed = 165
			color = Color(0.4, 0.62, 1)
			score_value = 200
			knock_scale = 1.8
		"sentry":
			hp = 5 + floorf(wave / 4.0)
			radius = 16
			speed = 150
			color = Color(1, 0.42, 0.82)
			score_value = 250
			phase = "move"
			phase_t = randf_range(0.6, 1.2)
			move_target = position
		"layer":
			hp = 4 + floorf(wave / 5.0)
			radius = 15
			speed = 125
			color = Color(0.92, 0.92, 0.85)
			score_value = 200
			fire_cd = randf_range(1.0, 1.8)
		"mine":
			hp = 1
			radius = 9
			speed = 0
			color = Color(0.95, 0.95, 0.88)
			score_value = 20
			no_clear = true
			knock_scale = 0.0
			phase_t = 0.6  # arming time
			fire_cd = 14.0  # lifetime
		"snake":
			hp = 8 + floorf(wave * 0.6)
			radius = 14
			speed = 150
			color = Color(1, 0.85, 0.25)
			score_value = 500
			knock_scale = 0.3
			for i in SEG_COUNT:
				segs.append(position)
		"boss":
			hp = 90 + wave * 14
			radius = 48
			speed = 55
			color = Color(1, 0.25, 0.65)
			score_value = 3000
			fire_cd = 2.0
			is_boss = true
			knock_scale = 0.1
		"boss2":
			hp = 100 + wave * 12
			radius = 46
			speed = 45
			color = Color(0.55, 0.45, 1)
			score_value = 4000
			phase = "idle"
			phase_t = 1.5
			is_boss = true
			knock_scale = 0.1
	if is_boss:
		display_name = BOSS_NAMES[kind]
	max_hp = hp


func make_elite(affix: String, wave: int) -> void:
	elite = affix
	hp *= 1.5
	max_hp = hp
	score_value *= 2
	match affix:
		"shield":
			shield_max = 3 + floorf(wave / 3.0)
			shield = shield_max
		"haste":
			speed *= 1.45


func elite_color() -> Color:
	match elite:
		"shield":
			return Color(0.55, 0.85, 1)
		"haste":
			return Color(1, 0.95, 0.35)
		"volatile":
			return Color(1, 0.5, 0.2)
	return Color.WHITE


func update(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta)
	if type == "mine":
		_update_mine(delta)
		queue_redraw()
		return
	var pl: Node2D = main.player
	var to_p: Vector2 = pl.position - position
	var dist := maxf(to_p.length(), 0.001)
	var dir := to_p / dist
	facing = lerp_angle(facing, dir.angle(), clampf(delta * 8.0, 0, 1))
	var desired := Vector2.ZERO
	match type:
		"chaser", "mini":
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
		"splitter":
			desired = dir.rotated(sin(t * 1.7) * 0.3) * speed
		"dodger":
			desired = dir.rotated(sin(t * 2.0) * 0.5) * speed
			dodge_cd -= delta
			if dodge_cd <= 0:
				_try_dodge()
		"sentry":
			desired = _update_sentry(delta, dir)
		"layer":
			var tang := Vector2(-dir.y, dir.x) * strafe
			if dist > 360:
				desired = dir * speed
			elif dist < 240:
				desired = -dir * speed
			desired += tang * speed * 0.8
			if randf() < delta * 0.3:
				strafe = -strafe
			fire_cd -= delta
			if fire_cd <= 0:
				fire_cd = randf_range(1.6, 2.4)
				if main.count_type("mine") < 14:
					main.spawn_enemy_now("mine", position)
		"snake":
			desired = dir.rotated(sin(t * 2.2) * 0.8) * speed
		"boss":
			spin += delta * (1.2 if hp > max_hp * 0.5 else 2.2)
			desired = dir * speed if dist > 220 else -dir * speed * 0.3
			fire_cd -= delta
			if fire_cd <= 0:
				_boss_fire(dir)
		"boss2":
			desired = _update_boss2(delta, dir, dist)

	# Separation from other enemies
	for o in main.enemies:
		if o == self or o.dead or o.type == "mine":
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
	if type == "snake":
		_update_segs()

	# Contact damage
	var cr: float = radius + pl.radius * 0.7
	if dist < cr:
		if pl.hurt(2 if is_boss else 1):
			knock -= dir * 200.0
	elif type == "snake":
		var sr: float = SEG_RADIUS + pl.radius * 0.7
		for s in segs:
			if pl.position.distance_squared_to(s) < sr * sr:
				pl.hurt(1)
				break
	queue_redraw()


func _try_dodge() -> void:
	for b in main.bullets:
		if b.dead or not b.from_player:
			continue
		var bl: float = b.vel.length()
		if bl < 1.0:
			continue
		var bd: Vector2 = b.vel / bl
		var rel: Vector2 = position - b.position
		var along := rel.dot(bd)
		if along < 0.0 or along > 140.0:
			continue
		var lateral := rel - bd * along
		if lateral.length() < radius + 12.0:
			var side := lateral.normalized() if lateral.length() > 0.5 else Vector2(-bd.y, bd.x) * strafe
			knock += side * 560.0
			dodge_cd = 0.5 if elite == "haste" else 0.75
			main.fx.ghost(position, color, radius)
			return


func _update_sentry(delta: float, dir: Vector2) -> Vector2:
	phase_t -= delta
	match phase:
		"move":
			if phase_t <= 0 or position.distance_to(move_target) < 12:
				phase = "aim"
				phase_t = 1.0
				beam_dir = dir
				main.sfx.play("charge")
				return Vector2.ZERO
			return (move_target - position).normalized() * speed
		"aim":
			if phase_t > 0.3:
				beam_dir = beam_dir.slerp(dir, clampf(delta * 6.0, 0, 1)).normalized()
			beam_len = main.cast_ray(position, beam_dir, 2000.0)
			if phase_t <= 0:
				phase = "fire"
				phase_t = 0.3
				main.sfx.play("beam")
				main.add_shake(3)
		"fire":
			beam_len = main.cast_ray(position, beam_dir, 2000.0)
			_beam_hits_player(position, beam_dir, beam_len)
			if phase_t <= 0:
				phase = "move"
				phase_t = randf_range(1.6, 2.6)
				move_target = main.random_point_near_player(240.0, 420.0)
	return Vector2.ZERO


func _beam_hits_player(from: Vector2, d: Vector2, length: float) -> void:
	var pl: Node2D = main.player
	var cp := Geometry2D.get_closest_point_to_segment(pl.position, from, from + d * length)
	if cp.distance_to(pl.position) < 9.0 + pl.radius * 0.6:
		pl.hurt(1)


func _update_mine(delta: float) -> void:
	phase_t -= delta
	fire_cd -= delta
	if fire_cd <= 0:
		main.fizzle(self)
		return
	var pd: float = position.distance_to(main.player.position)
	if fuse < 0:
		if phase_t <= 0 and pd < 70:
			fuse = 0.45
			main.sfx.play("beep")
	else:
		fuse -= delta
		if fuse <= 0:
			dead = true
			main.explode(position, MINE_BLAST, 3.0, true)


func _update_segs() -> void:
	var prev := position
	for i in segs.size():
		var d := segs[i] - prev
		if d.length() > SEG_SPACING:
			segs[i] = prev + d.normalized() * SEG_SPACING
		prev = segs[i]


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


func _update_boss2(delta: float, dir: Vector2, dist: float) -> Vector2:
	var enraged := hp < max_hp * 0.5
	spin += delta * (1.4 if enraged else 0.9)
	var desired := dir * speed if dist > 300 else -dir * speed * 0.5
	phase_t -= delta
	match phase:
		"idle":
			if phase_t <= 0:
				pattern = (pattern + 1) % 3
				match pattern:
					0:
						phase = "beam_aim"
						phase_t = 1.1
						beams.clear()
						var n := 4 if enraged else 3
						var base := dir.angle() + PI / n
						for i in n:
							beams.append(base + TAU * i / n)
						beam_spin_dir = -beam_spin_dir
						main.sfx.play("charge")
					1:
						phase = "spiral"
						phase_t = 2.2
						fire_cd = 0.0
					2:
						if main.count_type("mini") < 10:
							for i in (6 if enraged else 4):
								var off := Vector2.from_angle(TAU * i / (6 if enraged else 4) + spin) * (radius + 40)
								main.spawn_marker("mini", main.resolve_static(position + off, 12), 0.6)
						phase = "idle"
						phase_t = 1.2
		"beam_aim":
			desired = Vector2.ZERO
			_update_beam_lens()
			if phase_t <= 0:
				phase = "beam"
				phase_t = 2.6
				main.sfx.play("beam")
				main.add_shake(6)
		"beam":
			desired = Vector2.ZERO
			var rot := (1.0 if enraged else 0.7) * beam_spin_dir * delta
			for i in beams.size():
				beams[i] += rot
			_update_beam_lens()
			for i in beams.size():
				_beam_hits_player(position, Vector2.from_angle(beams[i]), beam_lens[i])
			if phase_t <= 0:
				phase = "idle"
				phase_t = 0.9
				beams.clear()
		"spiral":
			fire_cd -= delta
			if fire_cd <= 0:
				fire_cd = 0.06 if enraged else 0.08
				var arms := 3 if enraged else 2
				for k in arms:
					var a := spin * 2.6 + TAU * k / arms
					main.spawn_bullet(position + Vector2.from_angle(a) * radius, Vector2.from_angle(a) * 220.0, false, 1, 7, Color(0.65, 0.55, 1))
				main.sfx.play("enemy_shoot")
			if phase_t <= 0:
				phase = "idle"
				phase_t = 0.8
	return desired


func _update_beam_lens() -> void:
	beam_lens.resize(beams.size())
	for i in beams.size():
		beam_lens[i] = main.cast_ray(position, Vector2.from_angle(beams[i]), 2000.0)


# ---------------------------------------------------------------- drawing

func _poly(n: int, r: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2.from_angle(rot + TAU * i / n) * r)
	return pts


func _outline(pts: PackedVector2Array, c: Color, w: float) -> void:
	var o := pts.duplicate()
	o.append(pts[0])
	draw_polyline(o, c, w, true)


func _shape(pts: PackedVector2Array, fill: Color, c: Color, w: float) -> void:
	draw_colored_polygon(pts, fill)
	_outline(pts, c, w)


func _rotated(pts: PackedVector2Array, a: float) -> PackedVector2Array:
	for i in pts.size():
		pts[i] = pts[i].rotated(a)
	return pts


func _draw_beam(d: Vector2, length: float, c: Color, charging: bool, k: float) -> void:
	var a := d * (radius * 0.8)
	var b := d * length
	if charging:
		var flick := 0.25 + 0.5 * k + 0.2 * sin(t * 40.0)
		draw_line(a, b, Color(c, flick), 1.5 + k * 2.0, true)
	else:
		draw_line(a, b, Color(c, 0.25), 22.0, true)
		draw_line(a, b, Color(c, 0.85), 10.0, true)
		draw_line(a, b, Color(1, 1, 1, 0.95), 4.0, true)


func _draw() -> void:
	var c := Color.WHITE if flash > 0 else color
	var fill := Color(c.r * 0.18, c.g * 0.18, c.b * 0.18) if flash <= 0 else Color(1, 1, 1, 0.9)
	if type != "mine":
		draw_circle(Vector2.ZERO, radius + 7, Color(c, 0.09))
	match type:
		"chaser", "mini":
			var pts := PackedVector2Array([Vector2(radius + 3, 0), Vector2(-radius, radius * 0.85), Vector2(-radius * 0.5, 0), Vector2(-radius, -radius * 0.85)])
			_shape(_rotated(pts, facing), fill, c, 2.5 if type == "chaser" else 2.0)
		"shooter":
			_shape(_poly(6, radius, t * 1.5), fill, c, 2.5)
			draw_circle(Vector2.from_angle(facing) * radius * 0.35, 4.5, c)
		"tank":
			_shape(_poly(4, radius * 1.15, t * 0.6 + PI / 4), fill, c, 4.0)
			_outline(_poly(4, radius * 0.6, -t * 0.9), Color(c, 0.6), 2.0)
		"splitter":
			_shape(_poly(5, radius, t * 0.8), fill, c, 3.0)
			for i in 3:
				draw_circle(Vector2.from_angle(-t * 1.6 + TAU * i / 3) * radius * 0.45, 3.5, c)
		"dodger":
			var pts := PackedVector2Array([Vector2(radius + 5, 0), Vector2(0, radius * 0.7), Vector2(-radius - 5, 0), Vector2(0, -radius * 0.7)])
			_shape(_rotated(pts, facing), fill, c, 2.5)
			draw_line(Vector2.from_angle(facing) * -radius, Vector2.from_angle(facing) * radius, Color(c, 0.6), 1.5, true)
		"sentry":
			if phase == "aim":
				_draw_beam(beam_dir, beam_len, color, true, 1.0 - clampf(phase_t, 0, 1))
			elif phase == "fire":
				_draw_beam(beam_dir, beam_len, color, false, 1.0)
			_shape(_poly(3, radius * 1.15, beam_dir.angle()), fill, c, 3.0)
			draw_circle(Vector2.ZERO, 5.0 if phase != "aim" else 5.0 + sin(t * 30.0) * 2.0, c)
		"layer":
			var arm := radius * 1.05
			var wdt := radius * 0.42
			var rot := t * 1.2
			for k in 2:
				var pts := PackedVector2Array([Vector2(-arm, -wdt), Vector2(arm, -wdt), Vector2(arm, wdt), Vector2(-arm, wdt)])
				_shape(_rotated(pts, rot + k * PI / 2), fill, c, 2.0)
			draw_circle(Vector2.ZERO, 4.0, c)
		"mine":
			var armed := phase_t <= 0
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8 + t * 0.5)
				draw_line(d * radius * 0.8, d * (radius + 5), Color(c, 0.8), 2.0, true)
			draw_circle(Vector2.ZERO, radius, fill)
			draw_arc(Vector2.ZERO, radius, 0, TAU, 24, c, 2.0, true)
			var blink := armed and int(t * (12.0 if fuse >= 0 else 3.0)) % 2 == 0
			draw_circle(Vector2.ZERO, 3.5, Color(1, 0.25, 0.3) if blink else Color(c, 0.4))
			if fuse >= 0:
				var k := 1.0 - fuse / 0.45
				draw_circle(Vector2.ZERO, MINE_BLAST, Color(1, 0.3, 0.3, 0.08 + 0.1 * k))
				draw_arc(Vector2.ZERO, MINE_BLAST, 0, TAU, 48, Color(1, 0.3, 0.3, 0.5 + 0.4 * k), 2.0, true)
		"snake":
			for i in range(segs.size() - 1, -1, -1):
				var p := segs[i] - position
				var r := SEG_RADIUS * (1.0 - i * 0.05)
				draw_circle(p, r + 4, Color(color, 0.08))
				draw_circle(p, r, Color(color.r * 0.15, color.g * 0.15, color.b * 0.15))
				draw_arc(p, r, 0, TAU, 20, Color(color, 0.75), 2.0, true)
			var head := PackedVector2Array([Vector2(radius + 4, 0), Vector2(radius * 0.2, radius), Vector2(-radius, radius * 0.6), Vector2(-radius, -radius * 0.6), Vector2(radius * 0.2, -radius)])
			_shape(_rotated(head, facing), fill, c, 3.0)
			for s in [-1.0, 1.0]:
				draw_circle(Vector2(radius * 0.25, s * radius * 0.4).rotated(facing), 2.5, c)
		"boss":
			var spikes := PackedVector2Array()
			for i in 16:
				var rr := radius * (1.25 if i % 2 == 0 else 0.95)
				spikes.append(Vector2.from_angle(spin + TAU * i / 16) * rr)
			_shape(spikes, fill, c, 3.5)
			_outline(_poly(8, radius * 0.6, -spin * 0.7), Color(c, 0.7), 2.5)
			draw_circle(Vector2.from_angle(facing) * radius * 0.25, 9, c)
		"boss2":
			for i in beams.size():
				if i < beam_lens.size():
					_draw_beam(Vector2.from_angle(beams[i]), beam_lens[i], color, phase == "beam_aim", 1.0 - clampf(phase_t / 1.1, 0, 1))
			draw_circle(Vector2.ZERO, radius, fill)
			for i in 4:
				var a0 := spin + TAU * i / 4
				draw_arc(Vector2.ZERO, radius, a0, a0 + TAU / 4 - 0.35, 16, c, 4.0, true)
				draw_arc(Vector2.ZERO, radius * 1.22, -a0 * 0.7, -a0 * 0.7 + 0.5, 8, Color(c, 0.6), 2.5, true)
			_shape(_poly(4, radius * 0.55, -spin * 1.3), Color(c, 0.15), c, 2.5)
			draw_circle(Vector2.from_angle(facing) * radius * 0.2, 8, c)
	# Elite aura
	if elite != "":
		var ec := elite_color()
		var pulse := 0.6 + 0.4 * sin(t * 6.0)
		draw_arc(Vector2.ZERO, radius + 10, t * 2.0, t * 2.0 + TAU * 0.8, 32, Color(ec, 0.5 * pulse), 2.0, true)
		if elite == "shield" and shield > 0:
			draw_arc(Vector2.ZERO, radius + 5, -PI / 2, -PI / 2 + TAU * shield / shield_max, 32, Color(ec, 0.9), 3.0, true)
	# Health bar for durable enemies
	if not is_boss and hp < max_hp and max_hp > 2:
		var w := radius * 2.0
		var y := -radius - 14
		draw_rect(Rect2(-w / 2, y, w, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2, y, w * hp / max_hp, 4), color)
