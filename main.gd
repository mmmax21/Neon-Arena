extends Node2D
## Neon Arena — top-down arena shooter. Owns game state, waves, upgrades, collisions.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const FxScript := preload("res://scripts/fx.gd")
const HudScript := preload("res://scripts/hud.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const I18n := preload("res://scripts/i18n.gd")
const FONT_ZH := preload("res://fonts/NotoSansSC-Medium.subset.otf")

const W := 1280.0
const H := 720.0
const ARENA := Rect2(30, 30, 1220, 660)
const VERSION := "2.0"
## v1 stored its best score in user://best.save; v2 keeps its own so the two web builds don't mix scores.
const SAVE_PATH := "user://best_v2.save"
const SETTINGS_PATH := "user://settings.cfg"
const LANGS := ["en", "zh"]
## An upgrade card is offered after every this many cleared waves.
const UPGRADE_EVERY := 3
const SEG_RADIUS := 11.0

# Order matters: hud.gd mirrors these values.
enum State { TITLE, PLAYING, PAUSED, GAMEOVER, SELECT, UPGRADE }

const WEAPON_ORDER := ["pulse", "scatter", "laser"]
const WEAPONS := {
	"pulse": {"color": Color(1, 0.95, 0.45)},
	"scatter": {"color": Color(1, 0.72, 0.35)},
	"laser": {"color": Color(0.55, 1, 1)},
}

## Names and descriptions live in i18n.gd ("up_<id>", "up_<id>_d").
## cat: fire / ballistic / dash / survival. no: weapons that can't roll it.
const UPGRADES := {
	"rapid": {"max": 5, "cat": "fire"},
	"multi": {"max": 3, "cat": "fire"},
	"power": {"max": 5, "cat": "fire"},
	"crit": {"max": 3, "cat": "fire"},
	"pierce": {"max": 3, "cat": "ballistic", "no": ["laser"]},
	"bounce": {"max": 3, "cat": "ballistic", "no": ["laser"]},
	"homing": {"max": 1, "cat": "ballistic", "no": ["laser"]},
	"split": {"max": 1, "cat": "ballistic"},
	"trail": {"max": 1, "cat": "dash"},
	"shock": {"max": 2, "cat": "dash"},
	"quick": {"max": 3, "cat": "dash"},
	"vital": {"max": 4, "cat": "survival"},
	"shield": {"max": 1, "cat": "survival"},
	"magnet": {"max": 2, "cat": "survival"},
}
const CAT_ORDER := ["fire", "ballistic", "dash", "survival"]
const CAT_COLORS := {"fire": Color(1, 0.5, 0.3), "ballistic": Color(1, 0.9, 0.35),
	"dash": Color(0.35, 0.9, 1), "survival": Color(0.45, 1, 0.55), "bonus": Color(1, 0.5, 0.8)}

## type, first wave, weight
const ENEMY_TABLE := [
	["chaser", 1, 10], ["shooter", 2, 4], ["splitter", 3, 3], ["tank", 3, 2],
	["dodger", 4, 3], ["sentry", 5, 2], ["layer", 6, 2], ["snake", 7, 1],
]
const ELITE_TYPES := ["chaser", "shooter", "tank", "splitter", "dodger", "sentry", "layer"]
const ELITE_AFFIXES := ["shield", "haste", "volatile"]

var state: int = State.TITLE
var player: Node2D = null
var weapon := "pulse"
var enemies: Array = []
var bullets: Array = []
var pickups: Array = []
var new_enemies: Array = []
var new_bullets: Array = []
var hazards: Array = []  # {p, life, tick}
var obstacles: Array[Vector3] = []  # x, y, radius
var spawn_queue: Array[String] = []
var spawn_markers: Array = []  # {p: Vector2, type: String, t: float, elite: String}
var spawn_timer := 0.0
var spawn_interval := 0.8
var wave := 0
var intermission := 0.0
var clear_timer := 0.0
var offer: Array[String] = []
var card_lock := 0.0
var score := 0
var best := 0
var kills := 0
var combo := 0
var combo_timer := 0.0
var shake := 0.0
var gameover_timer := 0.0
var time_alive := 0.0
var boss: Node2D = null
var waves_since_upgrade := 0
var lang := "en"

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
	load_settings()
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

func open_select() -> void:
	state = State.SELECT
	card_lock = 0.3


func start_game() -> void:
	for layer in [layer_pickups, layer_enemies, layer_player, layer_bullets]:
		for c in layer.get_children():
			c.queue_free()
	enemies.clear()
	bullets.clear()
	pickups.clear()
	new_enemies.clear()
	new_bullets.clear()
	hazards.clear()
	spawn_queue.clear()
	spawn_markers.clear()
	offer.clear()
	fx.clear()
	player = PlayerScript.new()
	player.main = self
	player.weapon = weapon
	player.position = Vector2(W / 2, H / 2)
	layer_player.add_child(player)
	score = 0
	kills = 0
	wave = 0
	combo = 0
	combo_timer = 0.0
	time_alive = 0.0
	clear_timer = 0.0
	waves_since_upgrade = 0
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
	var pick := -1
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm = true
		pick = hud.card_at(hud.get_local_mouse_position())
		if state == State.PLAYING and player:
			player.fire_queued = true
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			confirm = true
		if k >= KEY_1 and k <= KEY_3:
			pick = k - KEY_1
		elif k >= KEY_KP_1 and k <= KEY_KP_3:
			pick = k - KEY_KP_1
		if k == KEY_P or k == KEY_ESCAPE:
			if state == State.PLAYING:
				state = State.PAUSED
				return
			elif state == State.PAUSED:
				state = State.PLAYING
				return
			elif state == State.SELECT and k == KEY_ESCAPE:
				state = State.TITLE
				return
		if k == KEY_L:
			set_lang(LANGS[(LANGS.find(lang) + 1) % LANGS.size()])
			return
		if k == KEY_R and state == State.GAMEOVER and gameover_timer > 0.6:
			start_game()
			return
	match state:
		State.TITLE:
			if event is InputEventMouseButton and confirm:
				var l: String = hud.lang_at(hud.get_local_mouse_position())
				if l != "":
					set_lang(l)
					return
			if confirm:
				open_select()
		State.SELECT:
			if pick >= 0 and card_lock <= 0:
				weapon = WEAPON_ORDER[pick]
				start_game()
		State.UPGRADE:
			if pick >= 0 and pick < offer.size() and card_lock <= 0:
				choose_upgrade(pick)
		State.GAMEOVER:
			if confirm and gameover_timer > 0.8:
				open_select()
		State.PAUSED:
			if confirm:
				state = State.PLAYING


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING:
		state = State.PAUSED


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	card_lock -= delta
	match state:
		State.PLAYING:
			update_game(delta)
		State.GAMEOVER:
			gameover_timer += delta
			_update_bullets(delta)
			_sweep()
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
	_update_hazards(delta)
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
	var caps := {"tank": 2 + wave / 3, "sentry": 1 + wave / 5, "layer": 1 + wave / 6, "snake": 1 + wave / 8}
	var counts := {}
	var list: Array[String] = []
	for i in n:
		var t := _roll_enemy()
		if caps.has(t) and int(counts.get(t, 0)) >= int(caps[t]):
			t = "chaser"
		counts[t] = int(counts.get(t, 0)) + 1
		list.append(t)
	list.shuffle()
	if wave % 5 == 0:
		var bt: String = ["boss", "boss2"][(wave / 5 - 1) % 2]
		list.push_front(bt)
		hud.announce(t("wave_boss") % [wave, t("boss_" + bt)], Color(1, 0.3, 0.6))
	else:
		hud.announce(t("wave") % wave, Color(0.4, 0.95, 1))
	spawn_queue = list
	spawn_interval = maxf(0.22, 0.85 - wave * 0.05)
	spawn_timer = 0.3


func _roll_enemy() -> String:
	var total := 0
	for row in ENEMY_TABLE:
		if wave >= row[1]:
			total += row[2]
	var r := randi() % total
	for row in ENEMY_TABLE:
		if wave >= row[1]:
			r -= row[2]
			if r < 0:
				return row[0]
	return "chaser"


func _roll_elite(t: String) -> String:
	if wave < 7 or not ELITE_TYPES.has(t):
		return ""
	if randf() < minf(0.05 * (wave - 6), 0.35):
		return ELITE_AFFIXES[randi() % ELITE_AFFIXES.size()]
	return ""


func _update_waves(delta: float) -> void:
	if clear_timer > 0:
		clear_timer -= delta
		if clear_timer <= 0:
			open_upgrade()
		return
	if intermission > 0:
		intermission -= delta
		if intermission <= 0:
			begin_wave()
		return
	spawn_timer -= delta
	if spawn_timer <= 0 and not spawn_queue.is_empty():
		spawn_timer = spawn_interval
		var t: String = spawn_queue.pop_front()
		spawn_marker(t, _find_spawn_point(), 1.4 if t.begins_with("boss") else 0.9)
		sfx.play("spawn")
	for m in spawn_markers:
		m["t"] -= delta
		if m["t"] <= 0:
			var e := _spawn_enemy(m["type"], m["p"])
			if m["elite"] != "":
				e.make_elite(m["elite"], wave)
	spawn_markers = spawn_markers.filter(func(m): return m["t"] > 0)
	if spawn_queue.is_empty() and spawn_markers.is_empty() and not _blocking_enemies_left():
		_on_wave_clear()


func _blocking_enemies_left() -> bool:
	for e in enemies:
		if not e.dead and not e.no_clear:
			return true
	for e in new_enemies:
		if not e.no_clear:
			return true
	return false


func _on_wave_clear() -> void:
	var bonus := wave * 100
	score += bonus
	hud.announce(t("wave_clear") % bonus, Color(0.5, 1, 0.6))
	sfx.play("clear")
	for e in enemies:
		if not e.dead and e.type == "mine":
			fizzle(e)
	for b in bullets:
		if not b.from_player and not b.dead:
			b.dead = true
			fx.burst(b.position, b.color, 3, 90, 2.0, 0.25)
	waves_since_upgrade += 1
	if waves_since_upgrade >= UPGRADE_EVERY:
		clear_timer = 1.1
	else:
		intermission = 2.6


func spawn_marker(t: String, p: Vector2, delay: float) -> void:
	spawn_markers.append({"p": p, "type": t, "t": delay, "elite": _roll_elite(t)})


func _find_spawn_point() -> Vector2:
	var best_p := Vector2(ARENA.position.x + 60, ARENA.position.y + 60)
	for i in 30:
		var p := Vector2(
			randf_range(ARENA.position.x + 50, ARENA.end.x - 50),
			randf_range(ARENA.position.y + 50, ARENA.end.y - 50))
		if p.distance_to(player.position) < 300:
			continue
		if _clear_of_obstacles(p, 60):
			return p
		best_p = p
	return best_p


func random_point_near_player(min_d: float, max_d: float) -> Vector2:
	var p := player.position
	for i in 20:
		var c: Vector2 = player.position + Vector2.from_angle(randf() * TAU) * randf_range(min_d, max_d)
		if ARENA.grow(-50).has_point(c) and _clear_of_obstacles(c, 30):
			return c
		p = c
	return resolve_static(p, 20)


func _clear_of_obstacles(p: Vector2, margin: float) -> bool:
	for o in obstacles:
		if p.distance_to(Vector2(o.x, o.y)) < o.z + margin:
			return false
	return true


func _spawn_enemy(t: String, p: Vector2) -> Node2D:
	var e := EnemyScript.new()
	e.main = self
	e.position = p
	e.setup(t, wave)
	layer_enemies.add_child(e)
	new_enemies.append(e)
	if t != "mine" and t != "mini":
		fx.ring(p, 140 if e.is_boss else 50, e.color, 0.4)
	if e.is_boss:
		boss = e
		add_shake(14)
	return e


## Spawns immediately (no warning marker); used for mines and splitter fragments.
func spawn_enemy_now(t: String, p: Vector2) -> Node2D:
	return _spawn_enemy(t, p)


func count_type(t: String) -> int:
	var n := 0
	for e in enemies:
		if not e.dead and e.type == t:
			n += 1
	for e in new_enemies:
		if e.type == t:
			n += 1
	for m in spawn_markers:
		if m["type"] == t:
			n += 1
	return n


# ---------------------------------------------------------------- upgrades

func open_upgrade() -> void:
	offer = _roll_offer()
	waves_since_upgrade = 0
	state = State.UPGRADE
	card_lock = 0.5
	sfx.play("card")


func _roll_offer() -> Array[String]:
	var pool: Array[String] = []
	for id in UPGRADES:
		var d: Dictionary = UPGRADES[id]
		if player.level(id) >= int(d["max"]):
			continue
		if d.has("no") and (d["no"] as Array).has(player.weapon):
			continue
		pool.append(id)
	pool.shuffle()
	var out: Array[String] = pool.slice(0, 3)
	var hurt: bool = player.hp < player.max_hp
	if hurt and (player.hp * 2 <= player.max_hp or randf() < 0.25 or out.size() < 3):
		if out.size() >= 3:
			out[2] = "repair"
		else:
			out.append("repair")
	while out.size() < 3:
		out.append("bonus")
	return out


func choose_upgrade(i: int) -> void:
	var id: String = offer[i]
	var info := card_info(id)
	if id == "bonus":
		score += 500 * wave
	else:
		player.add_upgrade(id)
	fx.ring(player.position, 80, info["color"], 0.4)
	fx.text(player.position, info["name"], info["color"])
	hud.announce(info["name"], info["color"])
	sfx.play("pickup")
	offer.clear()
	state = State.PLAYING
	intermission = 1.4


## Display data for an upgrade card.
func card_info(id: String) -> Dictionary:
	if id == "repair":
		return {"icon": id, "name": t("up_repair"), "desc": t("up_repair_d"), "tag": t("cat_survival"), "color": CAT_COLORS["survival"], "level": ""}
	if id == "bonus":
		return {"icon": id, "name": t("up_bonus"), "desc": t("up_bonus_d") % (500 * wave), "tag": t("cat_bonus"), "color": CAT_COLORS["bonus"], "level": ""}
	var d: Dictionary = UPGRADES[id]
	var cur: int = player.level(id) if player else 0
	var lvl := t("lv_new") if cur == 0 else t("lv_up") % [cur, cur + 1]
	if int(d["max"]) == 1:
		lvl = t("lv_unique")
	return {"icon": id, "name": t("up_" + id), "desc": t("up_" + id + "_d"), "tag": t("cat_" + d["cat"]),
		"color": CAT_COLORS[d["cat"]], "level": lvl}


func weapon_info(id: String) -> Dictionary:
	return {"icon": id, "name": t("w_" + id), "desc": t("w_" + id + "_d"), "tag": t("w_" + id + "_tag"),
		"color": WEAPONS[id]["color"], "level": ""}


func current_cards() -> Array:
	var out: Array = []
	if state == State.SELECT:
		for id in WEAPON_ORDER:
			out.append(weapon_info(id))
	elif state == State.UPGRADE:
		for id in offer:
			out.append(card_info(id))
	return out


## Owned upgrades as [id, level], grouped by category, for the HUD and results screen.
func owned_upgrades() -> Array:
	var out: Array = []
	if player == null:
		return out
	for cat in CAT_ORDER:
		for id in UPGRADES:
			if UPGRADES[id]["cat"] == cat and player.level(id) > 0:
				out.append([id, player.level(id)])
	return out


# ---------------------------------------------------------------- language

func t(key: String) -> String:
	var row = I18n.TEXT.get(key)
	if row == null:
		return key
	return row[1] if lang == "zh" else row[0]


func ui_font() -> Font:
	return FONT_ZH if lang == "zh" else ThemeDB.fallback_font


func set_lang(l: String) -> void:
	if l == lang or not LANGS.has(l):
		return
	lang = l
	sfx.play("card")
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "lang", lang)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var default_lang := "zh" if OS.get_locale_language() == "zh" else "en"
	if cfg.load(SETTINGS_PATH) == OK:
		lang = String(cfg.get_value("ui", "lang", default_lang))
	else:
		lang = default_lang
	if not LANGS.has(lang):
		lang = "en"


# ---------------------------------------------------------------- combat

func spawn_bullet(p: Vector2, v: Vector2, from_player: bool, dmg: float, r: float, c: Color) -> Node2D:
	var b := BulletScript.new()
	b.position = p
	b.vel = v
	b.from_player = from_player
	b.damage = dmg
	b.radius = r
	b.color = c
	b.life = 1.4 if from_player else 6.0
	layer_bullets.add_child(b)
	new_bullets.append(b)
	return b


func spawn_player_bullet(p: Vector2, v: Vector2, dmg: float, r: float, life: float, c: Color) -> void:
	var b := spawn_bullet(p, v, true, dmg, r, c)
	b.life = life
	b.pierce = player.level("pierce")
	b.bounce = player.level("bounce")
	b.homing = player.level("homing") > 0
	b.split = player.level("split") > 0


func _spawn_shards(p: Vector2, dir: Vector2, dmg: float, c: Color, hit_id: int) -> void:
	for s in [-0.7, 0.7]:
		var b := spawn_bullet(p, dir.rotated(s) * 620.0, true, dmg * 0.5, 3.5, c)
		b.life = 0.35
		b.shard = true
		b.hit_ids.append(hit_id)


func _update_bullets(delta: float) -> void:
	for b in bullets:
		if b.dead:
			continue
		if b.homing:
			_steer_homing(b, delta)
		b.step(delta)
		var p: Vector2 = b.position
		if b.life <= 0:
			b.dead = true
			continue
		if not ARENA.grow(4).has_point(p):
			if b.from_player and b.bounce > 0:
				_bounce_wall(b)
			else:
				b.dead = true
			continue
		var ob := _obstacle_at(p, b.radius)
		if ob.z > 0:
			if b.from_player and b.bounce > 0:
				_bounce_off(b, Vector2(ob.x, ob.y), ob.z + b.radius)
			else:
				b.dead = true
				fx.burst(p, b.color, 5, 160, 2.5, 0.25)
			continue
		if b.from_player:
			_player_bullet_hits(b, p)
		elif state == State.PLAYING and not player.dead:
			var rr2: float = player.radius * 0.7 + b.radius
			if p.distance_squared_to(player.position) < rr2 * rr2:
				if player.hurt(1):
					b.dead = true


func _player_bullet_hits(b: Node2D, p: Vector2) -> void:
	for e in enemies:
		if e.dead:
			continue
		var id: int = e.get_instance_id()
		if b.hit_ids.has(id):
			continue
		var rr: float = e.radius + b.radius
		if p.distance_squared_to(e.position) < rr * rr:
			var dir: Vector2 = b.vel.normalized()
			hit_enemy(e, b.damage, dir)
			if b.split and not b.shard:
				_spawn_shards(p, dir, b.damage, b.color, id)
			if b.pierce > 0:
				b.pierce -= 1
				b.hit_ids.append(id)
			else:
				b.dead = true
			return
	# Snake bodies are armoured: they stop (or deflect) shots.
	for e in enemies:
		if e.dead or e.type != "snake":
			continue
		for s in e.segs:
			var sr: float = SEG_RADIUS + b.radius
			if p.distance_squared_to(s) < sr * sr:
				fx.burst(p, Color(1, 0.95, 0.7), 4, 160, 2.0, 0.2)
				if b.bounce > 0:
					_bounce_off(b, s, sr)
				else:
					b.dead = true
				return


func _steer_homing(b: Node2D, delta: float) -> void:
	var target: Node2D = null
	var best_d := 320.0 * 320.0
	for e in enemies:
		if e.dead or e.type == "mine":
			continue
		var d: float = b.position.distance_squared_to(e.position)
		if d < best_d:
			best_d = d
			target = e
	if target:
		var want: float = (target.position - b.position).angle()
		var cur: float = b.vel.angle()
		var diff := wrapf(want - cur, -PI, PI)
		b.vel = b.vel.rotated(clampf(diff, -6.0 * delta, 6.0 * delta))


func _bounce_wall(b: Node2D) -> void:
	var p: Vector2 = b.position
	if p.x < ARENA.position.x or p.x > ARENA.end.x:
		b.vel.x = -b.vel.x
	if p.y < ARENA.position.y or p.y > ARENA.end.y:
		b.vel.y = -b.vel.y
	b.position = Vector2(clampf(p.x, ARENA.position.x, ARENA.end.x), clampf(p.y, ARENA.position.y, ARENA.end.y))
	_after_bounce(b)


func _bounce_off(b: Node2D, c: Vector2, min_d: float) -> void:
	var n: Vector2 = (b.position - c).normalized()
	if n == Vector2.ZERO:
		n = -b.vel.normalized()
	b.vel = b.vel.bounce(n)
	b.position = c + n * (min_d + 1.0)
	_after_bounce(b)


func _after_bounce(b: Node2D) -> void:
	b.bounce -= 1
	b.life = maxf(b.life, 0.5)
	b.hit_ids.clear()
	fx.burst(b.position, b.color, 3, 120, 2.0, 0.2)


## Hitscan laser: pierces every enemy up to the first pillar, wall or snake body.
func fire_laser(o: Vector2, d: Vector2, dmg: float, c: Color) -> void:
	var length := cast_ray(o, d, 1600.0)
	for e in enemies:
		if e.dead or e.type != "snake":
			continue
		for s in e.segs:
			var tt := _ray_circle(o, d, s, SEG_RADIUS)
			if tt >= 0.0 and tt < length:
				length = tt
	var end := o + d * length
	for e in enemies:
		if e.dead:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(e.position, o, end)
		if cp.distance_to(e.position) < e.radius + 6.0:
			hit_enemy(e, dmg, d)
			if player.level("split") > 0:
				_spawn_shards(cp, d, dmg, c, e.get_instance_id())
	fx.beam(o, end, c, 7.0, 0.14)
	fx.burst(end, c, 6, 200, 2.5, 0.25)


## Distance along a ray to a circle, or -1 if it misses.
func _ray_circle(o: Vector2, d: Vector2, c: Vector2, r: float) -> float:
	var m := o - c
	var b := m.dot(d)
	var cc := m.length_squared() - r * r
	if cc > 0.0 and b > 0.0:
		return -1.0
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	return maxf(-b - sqrt(disc), 0.0)


## Distance from o along unit direction d to the first pillar or arena wall.
func cast_ray(o: Vector2, d: Vector2, max_len: float) -> float:
	var best_t := max_len
	if d.x > 0.0001:
		best_t = minf(best_t, (ARENA.end.x - o.x) / d.x)
	elif d.x < -0.0001:
		best_t = minf(best_t, (ARENA.position.x - o.x) / d.x)
	if d.y > 0.0001:
		best_t = minf(best_t, (ARENA.end.y - o.y) / d.y)
	elif d.y < -0.0001:
		best_t = minf(best_t, (ARENA.position.y - o.y) / d.y)
	for ob in obstacles:
		var tt := _ray_circle(o, d, Vector2(ob.x, ob.y), ob.z)
		if tt > 0.0 and tt < best_t:
			best_t = tt
	return maxf(best_t, 0.0)


## Player damage on an enemy, with crits.
func hit_enemy(e: Node2D, dmg: float, dir: Vector2) -> void:
	if randf() < player.crit_chance():
		dmg *= 2.0
		fx.ring(e.position, e.radius * 2.5, Color(1, 1, 0.6), 0.2)
	damage_enemy(e, dmg, dir)


func damage_enemy(e: Node2D, dmg: float, dir: Vector2, quiet := false) -> void:
	if e.dead:
		return
	e.flash = 0.08
	if e.shield > 0:
		e.shield -= dmg
		e.knock += dir * 30.0
		fx.burst(e.position - dir * e.radius, e.elite_color(), 3, 160, 2.0, 0.2)
		if e.shield <= 0:
			fx.ring(e.position, e.radius * 3, e.elite_color(), 0.35)
			sfx.play("shield")
		elif not quiet:
			sfx.play("hit")
		return
	e.hp -= dmg
	e.knock += dir * 90.0 * e.knock_scale
	if not quiet:
		fx.burst(e.position - dir * e.radius * 0.5, e.color, 4, 200, 2.5, 0.25)
		sfx.play("hit")
	if e.hp <= 0:
		kill_enemy(e)


func kill_enemy(e: Node2D) -> void:
	if e.dead:
		return
	e.dead = true
	kills += 1
	combo += 1
	combo_timer = 2.5
	var mult := 1.0 + minf(combo - 1, 20) * 0.1
	var gained := int(e.score_value * mult)
	score += gained
	var big: bool = e.is_boss
	fx.burst(e.position, e.color, 60 if big else 18 + int(e.radius), 520 if big else 300, 6 if big else 3.5, 1.2 if big else 0.6)
	fx.ring(e.position, e.radius * 4, e.color, 0.45)
	fx.text(e.position, "+%d" % gained, e.color)
	add_shake(20 if big else 4 + e.radius * 0.12)
	sfx.play("explode_big" if big or e.type == "tank" else "explode")
	match e.type:
		"splitter":
			for i in 3:
				var off := Vector2.from_angle(TAU * i / 3 + randf())
				var m := spawn_enemy_now("mini", resolve_static(e.position + off * 14, 9))
				m.knock = off * 260.0
		"snake":
			for s in e.segs:
				fx.burst(s, e.color, 8, 220, 3.0, 0.5)
		"mine":
			explode(e.position, EnemyScript.MINE_BLAST, 3.0, true)
	if e.elite == "volatile":
		for i in 10:
			var a := TAU * i / 10.0
			spawn_bullet(e.position, Vector2.from_angle(a) * 200.0, false, 1, 7, e.elite_color())
	if big:
		boss = null
		_drop(e.position + Vector2(-30, 0), "heal")
		_drop(e.position + Vector2(30, 0), "rapid")
	elif e.type != "mine":
		var dm: float = player.drop_mult()
		var r := randf()
		if e.elite != "":
			dm *= 4.0
		elif e.type == "mini":
			dm *= 0.3
		if r < 0.07 * dm:
			_drop(e.position, "heal")
		elif r < 0.13 * dm:
			_drop(e.position, "rapid")


## Removes an enemy with no score (expired mines, leftovers at wave end).
func fizzle(e: Node2D) -> void:
	e.dead = true
	fx.burst(e.position, e.color, 6, 120, 2.0, 0.3)


## Area blast: hurts enemies inside (chains into other mines) and optionally the player.
func explode(p: Vector2, r: float, enemy_dmg: float, hurt_player: bool) -> void:
	fx.burst(p, Color(1, 0.55, 0.3), 30, 380, 4.0, 0.5)
	fx.ring(p, r * 1.2, Color(1, 0.45, 0.3), 0.4)
	sfx.play("explode")
	add_shake(9)
	for e in enemies:
		if e.dead:
			continue
		var d: Vector2 = e.position - p
		if d.length() < r + e.radius:
			damage_enemy(e, enemy_dmg, d.normalized(), true)
	if hurt_player and state == State.PLAYING and not player.dead:
		if player.position.distance_to(p) < r + player.radius * 0.5:
			player.hurt(1)


## SHOCKWAVE upgrade: fires when a dash ends.
func shockwave(p: Vector2, lvl: int) -> void:
	var r := 110.0 + 35.0 * (lvl - 1)
	var dmg: float = (3.0 + 2.0 * (lvl - 1)) * player.damage_mult()
	fx.ring(p, r * 1.15, Color(0.4, 0.95, 1), 0.35)
	fx.burst(p, Color(0.4, 0.95, 1), 20, 360, 3.0, 0.35)
	sfx.play("shock")
	add_shake(6)
	for e in enemies:
		if e.dead:
			continue
		var d: Vector2 = e.position - p
		if d.length() < r + e.radius:
			var n := d.normalized()
			e.knock += n * 320.0 * minf(e.knock_scale, 1.0)
			damage_enemy(e, dmg, n, true)
	for b in bullets:
		if not b.from_player and not b.dead and b.position.distance_to(p) < r:
			b.dead = true
			fx.burst(b.position, b.color, 3, 90, 2.0, 0.2)


## FLAME DASH upgrade: burning points left along the dash path.
func add_hazard(p: Vector2) -> void:
	hazards.append({"p": p, "life": 1.4, "tick": 0.0})


func _update_hazards(delta: float) -> void:
	if hazards.is_empty():
		return
	var dmg: float = 1.0 * player.damage_mult()
	for h in hazards:
		h["life"] -= delta
		h["tick"] -= delta
		if h["tick"] <= 0:
			h["tick"] = 0.25
			var hp: Vector2 = h["p"]
			for e in enemies:
				if not e.dead and hp.distance_to(e.position) < 22.0 + e.radius:
					damage_enemy(e, dmg, Vector2.ZERO, true)
	hazards = hazards.filter(func(h): return h["life"] > 0)


func _drop(p: Vector2, t: String) -> void:
	var pk := PickupScript.new()
	pk.type = t
	pk.position = resolve_static(p, 14)
	layer_pickups.add_child(pk)
	pickups.append(pk)


func _update_pickups(delta: float) -> void:
	var reach: float = player.pickup_range()
	for pk in pickups:
		if pk.dead:
			continue
		pk.step(delta)
		var d: float = pk.position.distance_to(player.position)
		if d < reach:
			pk.position = pk.position.move_toward(player.position, delta * maxf(520.0 - d * 2.5, 260.0))
		if d < player.radius + 16:
			pk.dead = true
			if pk.type == "heal":
				player.hp = mini(player.hp + 2, player.max_hp)
				fx.text(pk.position, "+HP", Color(0.4, 1, 0.5))
			else:
				player.rapid = 7.0
				fx.text(pk.position, t("overdrive"), Color(1, 0.9, 0.3))
			fx.ring(pk.position, 60, pk.get_color(), 0.35)
			sfx.play("pickup")
		elif pk.life <= 0:
			pk.dead = true


func _sweep() -> void:
	bullets = _sweep_list(bullets)
	enemies = _sweep_list(enemies)
	pickups = _sweep_list(pickups)
	if not new_bullets.is_empty():
		bullets.append_array(new_bullets)
		new_bullets.clear()
	if not new_enemies.is_empty():
		enemies.append_array(new_enemies)
		new_enemies.clear()


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


## Returns the pillar (x, y, radius) a point overlaps, or Vector3.ZERO.
func _obstacle_at(p: Vector2, r: float) -> Vector3:
	for o in obstacles:
		var rr: float = o.z + r * 0.5
		if p.distance_squared_to(Vector2(o.x, o.y)) < rr * rr:
			return o
	return Vector3.ZERO


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
