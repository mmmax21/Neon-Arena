extends Node2D
## Neon Arena — top-down arena shooter. Owns game state, waves, collisions.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const FxScript := preload("res://scripts/fx.gd")
const HudScript := preload("res://scripts/hud.gd")
const SfxScript := preload("res://scripts/sfx.gd")

const W := 1280.0
const H := 720.0
const ARENA := Rect2(30, 30, 1220, 660)
const SAVE_PATH := "user://best.save"

enum State { TITLE, PLAYING, PAUSED, GAMEOVER }

var state: int = State.TITLE
var player: Node2D = null
var enemies: Array = []
var bullets: Array = []
var pickups: Array = []
var obstacles: Array[Vector3] = []  # x, y, radius
var spawn_queue: Array[String] = []
var spawn_markers: Array = []  # {p: Vector2, type: String, t: float}
var spawn_timer := 0.0
var spawn_interval := 0.8
var wave := 0
var intermission := 0.0
var score := 0
var best := 0
var kills := 0
var combo := 0
var combo_timer := 0.0
var shake := 0.0
var gameover_timer := 0.0
var time_alive := 0.0
var boss: Node2D = null

var layer_pickups: Node2D
var layer_enemies: Node2D
var layer_bullets: Node2D
var layer_player: Node2D
var fx: Node2D
var hud: Control
var sfx: Node
var camera: Camera2D


func _ready() -> void:
	randomize()
	load_best()
	camera = Camera2D.new()
	camera.position = Vector2(W / 2, H / 2)
	add_child(camera)
	camera.make_current()
	layer_pickups = _make_layer("Pickups")
	layer_enemies = _make_layer("Enemies")
	layer_player = _make_layer("Player")
	layer_bullets = _make_layer("Bullets")
	fx = FxScript.new()
	fx.main = self
	add_child(fx)
	sfx = SfxScript.new()
	add_child(sfx)
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = HudScript.new()
	hud.main = self
	cl.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	build_obstacles()
	queue_redraw()


func _make_layer(n: String) -> Node2D:
	var l := Node2D.new()
	l.name = n
	add_child(l)
	return l


func build_obstacles() -> void:
	obstacles.clear()
	obstacles.append(Vector3(300, 210, 42))
	obstacles.append(Vector3(980, 210, 42))
	obstacles.append(Vector3(300, 510, 42))
	obstacles.append(Vector3(980, 510, 42))
	obstacles.append(Vector3(640, 140, 28))
	obstacles.append(Vector3(640, 580, 28))


# ---------------------------------------------------------------- flow

func start_game() -> void:
	for layer in [layer_pickups, layer_enemies, layer_player, layer_bullets]:
		for c in layer.get_children():
			c.queue_free()
	enemies.clear()
	bullets.clear()
	pickups.clear()
	spawn_queue.clear()
	spawn_markers.clear()
	fx.clear()
	player = PlayerScript.new()
	player.main = self
	player.position = Vector2(W / 2, H / 2)
	layer_player.add_child(player)
	score = 0
	kills = 0
	wave = 0
	combo = 0
	combo_timer = 0.0
	time_alive = 0.0
	boss = null
	intermission = 1.2
	state = State.PLAYING
	sfx.play("pickup")


func on_player_dead() -> void:
	state = State.GAMEOVER
	gameover_timer = 0.0
	fx.burst(player.position, Color(0.3, 0.9, 1.0), 80, 420, 5, 1.1)
	fx.ring(player.position, 220, Color(0.3, 0.9, 1.0), 0.7)
	add_shake(22)
	sfx.play("explode_big")
	player.visible = false
	if score > best:
		best = score
		save_best()


func _unhandled_input(event: InputEvent) -> void:
	var confirm := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm = true
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			confirm = true
		if k == KEY_P or k == KEY_ESCAPE:
			if state == State.PLAYING:
				state = State.PAUSED
			elif state == State.PAUSED:
				state = State.PLAYING
		if k == KEY_R and state == State.GAMEOVER and gameover_timer > 0.6:
			start_game()
			return
	if confirm:
		if state == State.TITLE:
			start_game()
		elif state == State.GAMEOVER and gameover_timer > 0.8:
			start_game()
		elif state == State.PAUSED:
			state = State.PLAYING


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING:
		state = State.PAUSED


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	match state:
		State.PLAYING:
			update_game(delta)
		State.GAMEOVER:
			gameover_timer += delta
			_update_bullets(delta)
	if state != State.PAUSED:
		fx.update(delta)
	shake = maxf(0.0, shake - delta * 40.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	hud.queue_redraw()


func update_game(delta: float) -> void:
	time_alive += delta
	player.update(delta)
	_update_waves(delta)
	for e in enemies:
		if not e.dead:
			e.update(delta)
	_update_bullets(delta)
	_update_pickups(delta)
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0
	_sweep()


# ---------------------------------------------------------------- waves

func begin_wave() -> void:
	wave += 1
	spawn_queue.clear()
	var n := 4 + wave * 2
	var list: Array[String] = []
	for i in n:
		var r := randf()
		var t := "chaser"
		if wave >= 2 and r < 0.22 + minf(wave * 0.02, 0.16):
			t = "shooter"
		elif wave >= 3 and r > 0.88 - minf(wave * 0.01, 0.1):
			t = "tank"
		list.append(t)
	list.shuffle()
	if wave % 5 == 0:
		list.push_front("boss")
		hud.announce("WAVE %d  —  BOSS" % wave, Color(1, 0.3, 0.6))
	else:
		hud.announce("WAVE %d" % wave, Color(0.4, 0.95, 1))
	spawn_queue = list
	spawn_interval = maxf(0.22, 0.85 - wave * 0.05)
	spawn_timer = 0.3


func _update_waves(delta: float) -> void:
	if intermission > 0:
		intermission -= delta
		if intermission <= 0:
			begin_wave()
		return
	spawn_timer -= delta
	if spawn_timer <= 0 and not spawn_queue.is_empty():
		spawn_timer = spawn_interval
		var t: String = spawn_queue.pop_front()
		spawn_markers.append({"p": _find_spawn_point(), "type": t, "t": 1.4 if t == "boss" else 0.9})
		sfx.play("spawn")
	for m in spawn_markers:
		m["t"] -= delta
		if m["t"] <= 0:
			_spawn_enemy(m["type"], m["p"])
	spawn_markers = spawn_markers.filter(func(m): return m["t"] > 0)
	if spawn_queue.is_empty() and spawn_markers.is_empty() and enemies.is_empty():
		var bonus := wave * 100
		score += bonus
		hud.announce("WAVE CLEAR  +%d" % bonus, Color(0.5, 1, 0.6))
		sfx.play("clear")
		intermission = 2.6


func _find_spawn_point() -> Vector2:
	var best_p := Vector2(ARENA.position.x + 60, ARENA.position.y + 60)
	for i in 30:
		var p := Vector2(
			randf_range(ARENA.position.x + 50, ARENA.end.x - 50),
			randf_range(ARENA.position.y + 50, ARENA.end.y - 50))
		if p.distance_to(player.position) < 300:
			continue
		var ok := true
		for o in obstacles:
			if p.distance_to(Vector2(o.x, o.y)) < o.z + 60:
				ok = false
				break
		if ok:
			return p
		best_p = p
	return best_p


func _spawn_enemy(t: String, p: Vector2) -> void:
	var e := EnemyScript.new()
	e.main = self
	e.position = p
	e.setup(t, wave)
	layer_enemies.add_child(e)
	enemies.append(e)
	fx.ring(p, 50 if t != "boss" else 140, e.color, 0.4)
	if t == "boss":
		boss = e
		add_shake(14)


# ---------------------------------------------------------------- combat

func spawn_bullet(p: Vector2, v: Vector2, from_player: bool, dmg: float, r: float, c: Color) -> void:
	var b := BulletScript.new()
	b.position = p
	b.vel = v
	b.from_player = from_player
	b.damage = dmg
	b.radius = r
	b.color = c
	b.life = 1.4 if from_player else 6.0
	layer_bullets.add_child(b)
	bullets.append(b)


func _update_bullets(delta: float) -> void:
	for b in bullets:
		if b.dead:
			continue
		b.step(delta)
		var p: Vector2 = b.position
		if b.life <= 0 or not ARENA.grow(10).has_point(p):
			b.dead = true
			continue
		if _point_in_obstacle(p, b.radius):
			b.dead = true
			fx.burst(p, b.color, 5, 160, 2.5, 0.25)
			continue
		if b.from_player:
			for e in enemies:
				if e.dead:
					continue
				var rr: float = e.radius + b.radius
				if p.distance_squared_to(e.position) < rr * rr:
					b.dead = true
					damage_enemy(e, b.damage, b.vel.normalized())
					break
		elif state == State.PLAYING and not player.dead:
			var rr2: float = player.radius * 0.7 + b.radius
			if p.distance_squared_to(player.position) < rr2 * rr2:
				if player.hurt(1):
					b.dead = true


func damage_enemy(e: Node2D, dmg: float, dir: Vector2) -> void:
	e.hp -= dmg
	e.flash = 0.08
	e.knock += dir * (220.0 if e.type == "chaser" else 90.0 if e.type != "boss" else 10.0)
	fx.burst(e.position - dir * e.radius * 0.5, e.color, 4, 200, 2.5, 0.25)
	sfx.play("hit")
	if e.hp <= 0 and not e.dead:
		kill_enemy(e)


func kill_enemy(e: Node2D) -> void:
	e.dead = true
	kills += 1
	combo += 1
	combo_timer = 2.5
	var mult := 1.0 + minf(combo - 1, 20) * 0.1
	var gained := int(e.score_value * mult)
	score += gained
	var big: bool = e.type == "boss"
	fx.burst(e.position, e.color, 60 if big else 18 + int(e.radius), 520 if big else 300, 6 if big else 3.5, 1.2 if big else 0.6)
	fx.ring(e.position, e.radius * 4, e.color, 0.45)
	fx.text(e.position, "+%d" % gained, e.color)
	add_shake(20 if big else 4 + e.radius * 0.12)
	sfx.play("explode_big" if big or e.type == "tank" else "explode")
	if big:
		boss = null
		_drop(e.position + Vector2(-30, 0), "heal")
		_drop(e.position + Vector2(30, 0), "rapid")
	else:
		var r := randf()
		if r < 0.07:
			_drop(e.position, "heal")
		elif r < 0.13:
			_drop(e.position, "rapid")


func _drop(p: Vector2, t: String) -> void:
	var pk := PickupScript.new()
	pk.type = t
	pk.position = resolve_static(p, 14)
	layer_pickups.add_child(pk)
	pickups.append(pk)


func _update_pickups(delta: float) -> void:
	for pk in pickups:
		if pk.dead:
			continue
		pk.step(delta)
		var d: float = pk.position.distance_to(player.position)
		if d < 130:
			pk.position = pk.position.move_toward(player.position, delta * (520 - d * 2.5))
		if d < player.radius + 16:
			pk.dead = true
			if pk.type == "heal":
				player.hp = mini(player.hp + 2, player.max_hp)
				fx.text(pk.position, "+HP", Color(0.4, 1, 0.5))
			else:
				player.rapid = 7.0
				fx.text(pk.position, "RAPID FIRE", Color(1, 0.9, 0.3))
			fx.ring(pk.position, 60, pk.get_color(), 0.35)
			sfx.play("pickup")
		elif pk.life <= 0:
			pk.dead = true


func _sweep() -> void:
	bullets = _sweep_list(bullets)
	enemies = _sweep_list(enemies)
	pickups = _sweep_list(pickups)


func _sweep_list(list: Array) -> Array:
	var out: Array = []
	for n in list:
		if n.dead:
			n.queue_free()
		else:
			out.append(n)
	return out


# ---------------------------------------------------------------- helpers

func resolve_static(p: Vector2, r: float) -> Vector2:
	for o in obstacles:
		var c := Vector2(o.x, o.y)
		var d := p - c
		var min_d: float = o.z + r
		if d.length_squared() < min_d * min_d:
			var l := d.length()
			if l < 0.001:
				d = Vector2.RIGHT
				l = 1.0
			p = c + d / l * min_d
	p.x = clampf(p.x, ARENA.position.x + r, ARENA.end.x - r)
	p.y = clampf(p.y, ARENA.position.y + r, ARENA.end.y - r)
	return p


func _point_in_obstacle(p: Vector2, r: float) -> bool:
	for o in obstacles:
		var rr: float = o.z + r * 0.5
		if p.distance_squared_to(Vector2(o.x, o.y)) < rr * rr:
			return true
	return false


func add_shake(amount: float) -> void:
	shake = minf(maxf(shake, amount), 26.0)


func load_best() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			best = int(f.get_line())


func save_best() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_line(str(best))


# ---------------------------------------------------------------- arena drawing

func _draw() -> void:
	draw_rect(Rect2(-200, -200, W + 400, H + 400), Color(0.02, 0.02, 0.05))
	draw_rect(ARENA, Color(0.04, 0.045, 0.09))
	var grid := Color(0.25, 0.3, 0.6, 0.12)
	var x := ARENA.position.x
	while x <= ARENA.end.x:
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), grid, 1.0)
		x += 40
	var y := ARENA.position.y
	while y <= ARENA.end.y:
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), grid, 1.0)
		y += 40
	for i in 4:
		draw_rect(ARENA.grow(i * 2.0), Color(0.3, 0.6, 1.0, 0.35 - i * 0.08), false, 2.0)
	for o in obstacles:
		var c := Vector2(o.x, o.y)
		draw_circle(c, o.z + 8, Color(0.5, 0.3, 1.0, 0.08))
		draw_circle(c, o.z, Color(0.09, 0.08, 0.18))
		draw_arc(c, o.z, 0, TAU, 48, Color(0.6, 0.45, 1.0, 0.9), 3.0, true)
		draw_arc(c, o.z * 0.6, 0, TAU, 32, Color(0.6, 0.45, 1.0, 0.25), 2.0, true)
