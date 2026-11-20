extends Node2D
## Neon Arena — top-down arena shooter. Owns game state, waves, upgrades, collisions.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const PickupScript := preload("res://scripts/pickup.gd")
const FxScript := preload("res://scripts/fx.gd")
const HudScript := preload("res://scripts/hud.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const ArenaScript := preload("res://scripts/arena.gd")
const TouchScript := preload("res://scripts/touch.gd")
const NetScript := preload("res://scripts/net.gd")
const CoopScript := preload("res://scripts/coop.gd")
const I18n := preload("res://scripts/i18n.gd")
const FONT_ZH := preload("res://fonts/NotoSansSC-Medium.subset.otf")

const W := 1280.0
const H := 720.0
## W×H is the screen frame the HUD is laid out in. The arena is 1.4× larger than that frame
## and the camera follows the player, leading toward the aim (Nuclear Throne-style).
const ARENA := Rect2(30, 30, 1708, 924)
const WORLD := Vector2(1768, 984)
const CAM_LEAD := 90.0      # px the camera looks ahead along the aim
const CAM_FOLLOW := 7.0     # higher = snappier
const CAM_EDGE := 40.0      # how much outside the arena wall the view may show
const VERSION := "2.3"
## v1 stored its best score in user://best.save; v2 keeps its own so the two web builds don't mix scores.
const SAVE_PATH := "user://best_v2.save"
## Best scores per control category. The single score in SAVE_PATH is migrated to "kbm" once.
const BEST_PATH := "user://best_v2_modes.cfg"
## Score categories, from least to most aim assistance. A run counts in the most assisted
## category used at any point during it.
const CAT_RANK := {"kbm": 0, "twin": 1, "hybrid": 2, "auto": 3}
const SETTINGS_PATH := "user://settings.cfg"
const LANGS := ["en", "zh"]
## An upgrade card is offered after every this many cleared waves.
const UPGRADE_EVERY := 3

# Order matters: hud.gd mirrors these values.
enum State { TITLE, PLAYING, PAUSED, GAMEOVER, SELECT, UPGRADE, BOARD, LOBBY }

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
	# Evolutions: offered (and always offered) once every requirement is owned at the given level.
	"phase": {"max": 1, "cat": "evo", "req": {"quick": 3, "shock": 1}},
	"reactive": {"max": 1, "cat": "evo", "req": {"shield": 1, "vital": 2}},
	"inferno": {"max": 1, "cat": "evo", "req": {"trail": 1, "quick": 1}},
	"storm": {"max": 1, "cat": "evo", "req": {"magnet": 2, "vital": 1}},
}
const CAT_ORDER := ["fire", "ballistic", "dash", "survival", "evo"]
const CAT_COLORS := {"fire": Color(1, 0.5, 0.3), "ballistic": Color(1, 0.9, 0.35),
	"dash": Color(0.35, 0.9, 1), "survival": Color(0.45, 1, 0.55), "bonus": Color(1, 0.5, 0.8),
	"evo": Color(1, 0.45, 1)}
const INFERNO_LIFE := 2.8
const STORM_RADIUS := 160.0
const REACTIVE_RADIUS := 150.0

## type, first wave, weight
const ENEMY_TABLE := [
	["chaser", 1, 10], ["shooter", 2, 4], ["splitter", 3, 3], ["tank", 3, 2],
	["dodger", 4, 3], ["sentry", 5, 2], ["layer", 6, 2], ["snake", 7, 1],
]
## Waves stop growing in head count here; later waves get harder through HP, elites and mixes.
const MAX_WAVE_ENEMIES := 24
## At most this many enemies (plus warning markers) on the field; the rest of the wave waits
## in the queue and walks in as earlier ones die (Brotato-style trickle instead of a flood).
const MAX_ALIVE := 22
const MAX_ALIVE_TOUCH := 18
## Enemies push each other apart so packs read as individuals, not one blob.
const SEPARATION := 0.55
## From this wave on, each arena layout favours enemies that play off its mechanism.
const ARENA_MIX_WAVE := 10
const ARENA_MIX := {
	"classic": {"splitter": 2.0, "shooter": 1.5},
	"cross": {"snake": 3.0, "tank": 1.5},       # snakes thread the corridors
	"ring": {"dodger": 2.5, "chaser": 1.5},     # dodgers sidestep into live fences
	"fortress": {"layer": 3.0, "shooter": 1.5}, # belts carry the mines around
	"portals": {"shooter": 2.0, "dodger": 1.5}, # shots arrive through the other gate
	"open": {"sentry": 2.5, "shooter": 1.5},    # no cover from sentry beams
}
## Extra per-wave caps on top of the normal ones while a mix is active.
const ARENA_MIX_CAPS := {"cross": {"snake": 1}, "fortress": {"layer": 2}, "open": {"sentry": 1}}
## Spike waves: a themed roster replaces the usual mix. count/interval scale the normal values;
## fill replaces anything over its cap.
const SPIKE_WAVES := {
	"swarm": {"types": {"chaser": 1.0}, "count": 1.5, "interval": 0.5, "fill": "chaser"},
	"siege": {"types": {"shooter": 3.0, "sentry": 2.0, "layer": 2.0}, "count": 0.7, "interval": 1.0, "fill": "shooter"},
	"heavy": {"types": {"tank": 2.0, "splitter": 3.0}, "count": 0.55, "interval": 1.2, "fill": "splitter"},
}
const SPIKE_FROM := 8
const SPIKE_CHANCE := 0.3
## Breather waves shrink the roster: right after a boss, and on the first wave of a new layout.
const BREATHER_AFTER_BOSS := 0.6
const BREATHER_NEW_ARENA := 0.8
## Card offers: an eligible upgrade that wasn't shown gains this much weight per offer (capped).
const PITY_STEP := 0.5
const PITY_MAX := 4
const ELITE_TYPES := ["chaser", "shooter", "tank", "splitter", "dodger", "sentry", "layer"]
const ELITE_AFFIXES := ["shield", "haste", "volatile"]

var state: int = State.TITLE
var player: Node2D = null  # the ship this device controls
var players: Array = []  # every ship in the run (index = co-op slot)
var coop: Node
var weapon := "pulse"
var enemies: Array = []
var bullets: Array = []
var pickups: Array = []
var new_enemies: Array = []
var new_bullets: Array = []
var hazards: Array = []  # {p, life, tick}
var obstacles: Array[Vector3] = []  # x, y, radius; rebuilt by arena.gd from solid pillars / crystals
var ray_hit := -1  # obstacle index hit by the last cast_ray, or -1
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
var bests := {"kbm": 0, "twin": 0, "hybrid": 0, "auto": 0}
var run_cat := "kbm"
## Best score of the category on screen: this run's during play, the current input's on the title.
var best: int:
	get:
		return int(bests.get(score_cat(), 0))
# Flow field toward the player on a coarse grid, for enemies that got stuck behind walls.
const FLOW_CELL := 40.0
const FLOW_CLEAR := 18.0
const FLOW_CLEAR_BIG := 28.0
const FLOW_EVERY := 0.4
var flow := PackedInt32Array()
## Same field with extra clearance, for bodies wider than FLOW_CLEAR (tanks).
var flow_big := PackedInt32Array()
var flow_w := 0
var flow_h := 0
var flow_t := 0.0
var boss_shift_t := 0.0  # countdown to switching to the coming boss's arena
## Boss entrance: WARNING, then 3-2-1 over the spot where it will land.
const BOSS_INTRO := 3.6
const BOSS_TYPES := ["boss", "boss2", "boss3", "boss4", "boss5"]
var boss_intro_t := 0.0
var boss_intro_type := ""
var boss_intro_p := Vector2.ZERO
var boss_order: Array[String] = []  # shuffled per run; wave 5k fights boss_order[k - 1]
var wave_kind := ""  # "", "breather", or a SPIKE_WAVES key
var last_spike := -10
var offer_misses := {}  # upgrade id -> offers in a row it was eligible but not shown
var kills := 0
var combo := 0
var combo_timer := 0.0
var shake := 0.0
var shake_t := 0.0
var shake_setting := "full"  # full / low / off
const SHAKE_LEVELS := ["full", "low", "off"]
const SHAKE_SCALE := {"full": 1.0, "low": 0.35, "off": 0.0}
const SHAKE_TOUCH := 0.6  # small screens: the same pixel shake reads much stronger
const SHAKE_DECAY := 6.5  # per second, exponential: instant kick, smooth tail
var gameover_timer := 0.0
var time_alive := 0.0
var boss: Node2D = null
var waves_since_upgrade := 0
var lang := "en"
var muted := false
# Fullscreen: the browser's Fullscreen API on the web (not available on iPhone Safari),
# the window mode elsewhere.
var pointer_override = null  # Vector2 in HUD space, or null for the real pointer
## Co-op room codes (must match server/src/room.js); typed on an in-game keypad.
const ROOM_ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LEN := 4
var entering_code := false
var code_entry := ""
var fs_supported := true
var fs_on := false
var fs_poll := 0.0
var ios_browser := false
var touch_mode_setting := "hybrid"

var arena: Node2D
var net: Node
# Leaderboard screen
var board_platform := "pc"
var board_mode := "kbm"
var board_period := "all"
var board_back: int = State.TITLE
var board_refresh := 0.0
const BOARD_REFRESH := 15.0
var layer_pickups: Node2D
var layer_enemies: Node2D
var layer_bullets: Node2D
var layer_player: Node2D
var fx: Node2D
var hud: Control
var touch: Control
var sfx: Node
var camera: Camera2D


func _ready() -> void:
	randomize()
	# Chinese player names show up in English mode too (leaderboard, co-op lobby)
	var base_font := ThemeDB.fallback_font
	if FONT_ZH not in base_font.fallbacks:
		base_font.fallbacks = base_font.fallbacks + [FONT_ZH]
	load_best()
	load_settings()
	if OS.has_feature("web"):
		fs_supported = bool(JavaScriptBridge.eval("!!(document.fullscreenEnabled || document.webkitFullscreenEnabled)", true))
		ios_browser = bool(JavaScriptBridge.eval("/iPhone|iPod/.test(navigator.userAgent) && !navigator.standalone", true))
	camera = Camera2D.new()
	camera.position = ARENA.get_center()
	add_child(camera)
	camera.make_current()
	arena = ArenaScript.new()
	arena.main = self
	add_child(arena)  # first child: drawn above the floor, below everything else
	layer_pickups = _make_layer("Pickups")
	layer_enemies = _make_layer("Enemies")
	layer_player = _make_layer("Player")
	layer_bullets = _make_layer("Bullets")
	fx = FxScript.new()
	fx.main = self
	add_child(fx)
	sfx = SfxScript.new()
	add_child(sfx)
	net = NetScript.new()
	net.main = self
	add_child(net)
	coop = CoopScript.new()
	coop.main = self
	add_child(coop)
	var cl := CanvasLayer.new()
	add_child(cl)
	hud = HudScript.new()
	hud.main = self
	cl.add_child(hud)
	touch = TouchScript.new()
	touch.main = self
	cl.add_child(touch)
	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)
	touch.set_mode(touch_mode_setting)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	arena.reset()
	queue_redraw()


func _make_layer(n: String) -> Node2D:
	var l := Node2D.new()
	l.name = n
	add_child(l)
	return l


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
	arena.reset()
	touch.reset()
	players.clear()
	player = _make_ship(0, weapon, ARENA.get_center())
	if coop.is_host() and coop.peer_here:
		var rp := _make_ship(1, coop.peer_weapon, ARENA.get_center() + Vector2(60, 0))
		rp.remote = true
		rp.net_in["pos"] = rp.position
		player.position += Vector2(-60, 0)
	fx.record = coop.is_host()
	sfx.record = coop.is_host()
	fx.events.clear()
	sfx.events.clear()
	coop.local_picked = false
	coop.peer_picked = true
	score = 0
	kills = 0
	wave = 0
	combo = 0
	combo_timer = 0.0
	time_alive = 0.0
	clear_timer = 0.0
	waves_since_upgrade = 0
	boss_shift_t = 0.0
	boss_intro_t = 0.0
	boss_order.clear()
	wave_kind = ""
	last_spike = -10
	offer_misses.clear()
	run_cat = input_cat()
	if not coop.active():
		net.start_run()
	boss = null
	intermission = 1.2
	state = State.PLAYING
	snap_camera()
	sfx.play("pickup")


func _make_ship(slot: int, w: String, pos: Vector2) -> Node2D:
	var p := PlayerScript.new()
	p.main = self
	p.slot = slot
	p.weapon = w
	p.position = pos
	layer_player.add_child(p)
	players.append(p)
	return p


# ---------------------------------------------------------------- co-op

func is_guest() -> bool:
	return coop != null and coop.is_guest()


func is_host() -> bool:
	return coop != null and coop.is_host()


## Ships that enemies, bullets and hazards can hurt. On a guest nothing is hurt locally:
## the host decides and sends the result.
func hurtable_players() -> Array:
	if is_guest():
		return []
	return players.filter(func(p): return is_instance_valid(p) and not p.dead)


## Closest living ship (enemies chase it); falls back to our own ship.
func nearest_player(p: Vector2) -> Node2D:
	var best: Node2D = player
	var best_d := INF
	for s in players:
		if is_instance_valid(s) and not s.dead:
			var d := p.distance_squared_to(s.position)
			if d < best_d:
				best_d = d
				best = s
	return best


func remote_player() -> Node2D:
	for p in players:
		if is_instance_valid(p) and p.remote:
			return p
	return null


func player_by_slot(slot: int) -> Node2D:
	for p in players:
		if is_instance_valid(p) and p.slot == slot:
			return p
	return null


func open_lobby() -> void:
	state = State.LOBBY
	entering_code = false
	card_lock = 0.3


## Host: the guest left mid-run. Their ship disappears and the run goes on.
func drop_remote() -> void:
	var rp := remote_player()
	if rp:
		fx.burst(rp.position, rp.ship_color(), 30, 260, 3.0, 0.6)
		players.erase(rp)
		rp.queue_free()
		hud.announce(t("coop_peer_left"), Color(1, 0.6, 0.4))
		if not coop.peer_picked:
			remote_pick(-1)
		if state == State.PLAYING and hurtable_players().is_empty():
			on_player_dead(player)


## Guest: the host is gone; leave the run.
func coop_ended(key: String) -> void:
	for layer in [layer_pickups, layer_enemies, layer_player, layer_bullets]:
		for c in layer.get_children():
			c.queue_free()
	enemies.clear()
	bullets.clear()
	pickups.clear()
	players.clear()
	player = null
	boss = null
	boss_intro_t = 0.0
	spawn_markers.clear()
	hazards.clear()
	offer.clear()
	state = State.LOBBY
	hud.announce(t(key), Color(1, 0.5, 0.4))


## Guest: the host started a run. Our ship is slot 1 and moves locally.
func start_client_game(my_weapon: String, host_weapon: String) -> void:
	for layer in [layer_pickups, layer_enemies, layer_player, layer_bullets]:
		for c in layer.get_children():
			c.queue_free()
	enemies.clear()
	bullets.clear()
	pickups.clear()
	new_enemies.clear()
	new_bullets.clear()
	hazards.clear()
	spawn_markers.clear()
	offer.clear()
	fx.clear()
	coop._clear_guest_world()
	touch.reset()
	players.clear()
	_make_ship(0, host_weapon, ARENA.get_center() + Vector2(-60, 0))
	player = _make_ship(1, my_weapon, ARENA.get_center() + Vector2(60, 0))
	player.client = true
	weapon = my_weapon
	score = 0
	kills = 0
	wave = 0
	combo = 0
	time_alive = 0.0
	boss = null
	boss_intro_t = 0.0
	run_cat = input_cat()
	state = State.PLAYING
	snap_camera()
	sfx.play("pickup")


func update_client(delta: float) -> void:
	if player and not player.dead:
		player.update(delta)
	arena.update(delta)
	coop.guest_step(delta)


func on_player_dead(who: Node2D = null) -> void:
	if who and who != player or (who == player and players.size() > 1):
		# Co-op: a ship is down; the run ends only when nobody is left.
		if who:
			fx.burst(who.position, who.ship_color(), 50, 360, 4, 0.9)
			fx.ring(who.position, 160, who.ship_color(), 0.6)
			who.visible = false
			sfx.play("explode_big")
		if not hurtable_players().is_empty():
			hud.announce(t("coop_down"), Color(1, 0.5, 0.6))
			return
	state = State.GAMEOVER
	gameover_timer = 0.0
	fx.burst(player.position, Color(0.3, 0.9, 1.0), 80, 420, 5, 1.1)
	fx.ring(player.position, 220, Color(0.3, 0.9, 1.0), 0.7)
	add_shake(22)
	sfx.play("explode_big")
	player.visible = false
	if coop.active():
		return  # co-op runs don't go on the solo leaderboards
	if score > int(bests.get(run_cat, 0)):
		bests[run_cat] = score
		save_best()
	net.submit_run(run_cat, score, wave, kills, int(time_alive), weapon)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press_at(hud.get_local_mouse_position())
		return
	var confirm := false
	var pick := -1
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			confirm = true
		if k >= KEY_1 and k <= KEY_3:
			pick = k - KEY_1
		elif k >= KEY_KP_1 and k <= KEY_KP_3:
			pick = k - KEY_KP_1
		if state == State.LOBBY and entering_code:
			_code_key(k)
			return
		if (k == KEY_P or k == KEY_ESCAPE) and state == State.LOBBY:
			coop.leave()
			state = State.TITLE
			return
		if (k == KEY_P or k == KEY_ESCAPE) and coop.in_game:
			return  # no pausing a shared run
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
			elif state == State.BOARD:
				close_board()
				return
		if k == KEY_M:
			set_muted(not muted)
			return
		if k == KEY_F and fs_supported:
			toggle_fullscreen()
			return
		if k == KEY_K:
			cycle_shake()
			return
		if k == KEY_L:
			set_lang(LANGS[(LANGS.find(lang) + 1) % LANGS.size()])
			return
		if k == KEY_R and state == State.GAMEOVER and gameover_timer > 0.6 and not coop.in_game:
			start_game()
			return
	match state:
		State.TITLE:
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
				_after_gameover()
		State.PAUSED:
			if confirm:
				state = State.PLAYING
		State.BOARD:
			if confirm:
				close_board()


## A left click, or a touch tap outside play (touch.gd sends those on release).
func press_at(pos: Vector2) -> void:
	if hud.mute_at(pos):
		set_muted(not muted)
		return
	if hud.fs_at(pos):
		toggle_fullscreen()
		return
	if touch.active and hud.ctrl_at(pos):
		touch.cycle_mode()
		return
	if hud.shake_at(pos):
		cycle_shake()
		return
	var pick: int = hud.card_at(pos)
	if (state == State.TITLE or state == State.GAMEOVER) and not coop.in_game and hud.board_button_at(pos):
		open_board()
		return
	if state == State.TITLE and hud.coop_button_at(pos):
		open_lobby()
		return
	match state:
		State.LOBBY:
			_lobby_press(pos)
		State.BOARD:
			_board_press(pos)
		State.TITLE:
			var l: String = hud.lang_at(pos)
			if l != "":
				set_lang(l)
			else:
				open_select()
		State.SELECT:
			if pick >= 0 and card_lock <= 0:
				weapon = WEAPON_ORDER[pick]
				start_game()
		State.UPGRADE:
			if pick >= 0 and pick < offer.size() and card_lock <= 0:
				choose_upgrade(pick)
		State.GAMEOVER:
			if gameover_timer > 0.8:
				_after_gameover()
		State.PAUSED:
			state = State.PLAYING
		State.PLAYING:
			if player:
				player.fire_queued = true


func _after_gameover() -> void:
	if coop.active():
		coop.in_game = false
		fx.record = false
		sfx.record = false
		open_lobby()
	else:
		open_select()


func _lobby_press(pos: Vector2) -> void:
	if card_lock > 0:
		return
	if entering_code:
		for b in hud.keypad_buttons():
			if (b["rect"] as Rect2).has_point(pos):
				match b["kind"]:
					"key":
						_code_add(b["value"])
					"del":
						code_entry = code_entry.left(-1)
						sfx.play("beep")
					"cancel":
						entering_code = false
					"join":
						_code_submit()
				return
		return
	for b in hud.lobby_buttons():
		if not (b["rect"] as Rect2).has_point(pos) or not b.get("on", true):
			continue
		match b["kind"]:
			"create":
				coop.create_room()
			"join":
				# On-screen keypad: works where prompt() doesn't (in-app browsers) and on phones.
				entering_code = true
				code_entry = ""
				sfx.play("card")
			"start":
				coop.host_start()
			"leave":
				coop.leave()
			"back":
				coop.leave()
				state = State.TITLE
			"weapon":
				weapon = b["value"]
				coop.send_weapon()
				sfx.play("card")
		return


func _code_add(c: String) -> void:
	if code_entry.length() >= ROOM_CODE_LEN or not ROOM_ALPHABET.contains(c):
		return
	code_entry += c
	sfx.play("beep")
	if code_entry.length() == ROOM_CODE_LEN:
		_code_submit()


func _code_submit() -> void:
	if code_entry.length() < ROOM_CODE_LEN:
		return
	entering_code = false
	coop.join_room(code_entry)


## Physical keyboard while the keypad is open: letters and digits, Backspace, Enter, Esc.
func _code_key(k: int) -> void:
	if k == KEY_ESCAPE:
		entering_code = false
	elif k == KEY_BACKSPACE:
		code_entry = code_entry.left(-1)
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		_code_submit()
	elif k >= KEY_A and k <= KEY_Z:
		_code_add(char(k))
	elif k >= KEY_0 and k <= KEY_9:
		_code_add(char(k))
	elif k >= KEY_KP_0 and k <= KEY_KP_9:
		_code_add(str(k - KEY_KP_0))


## Where the HUD treats the pointer as being: the mouse, or a held touch in touch mode.
func pointer_pos() -> Vector2:
	if pointer_override != null:
		return pointer_override  # scripted captures (store video / screenshots) aim the crosshair
	if touch and touch.active:
		return touch.hover_pos()
	return hud.get_local_mouse_position()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING and not coop.in_game:
		state = State.PAUSED


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	card_lock -= delta
	fs_poll -= delta
	if fs_poll <= 0:
		fs_poll = 0.4
		fs_on = _query_fullscreen()
	match state:
		State.PLAYING:
			update_game(delta)
		State.BOARD:
			board_refresh -= delta
			if board_refresh <= 0:
				_fetch_board()
		State.GAMEOVER:
			gameover_timer += delta
			if is_guest():
				coop.guest_step(delta)
			else:
				_update_bullets(delta)
				_sweep()
		State.UPGRADE:
			if is_guest():
				coop.guest_step(delta)
	if state != State.PAUSED:
		fx.update(delta)
	# Smooth shake: the kick lands at once and dies away exponentially; the offset follows
	# layered sine waves instead of per-frame random jumps, so it reads as a jolt, not jitter.
	shake *= exp(-SHAKE_DECAY * delta)
	if shake < 0.3:
		shake = 0.0
	shake_t += delta
	var wob := Vector2(sin(shake_t * 47.0) + 0.5 * sin(shake_t * 83.0 + 1.3),
		sin(shake_t * 53.0 + 2.1) + 0.5 * sin(shake_t * 71.0 + 0.4)) / 1.5
	camera.offset = wob * shake
	_update_camera(delta)
	hud.queue_redraw()


func _camera_target() -> Vector2:
	if player == null or not is_instance_valid(player):
		return ARENA.get_center()
	if player.dead and players.size() > 1:
		var mate := nearest_player(player.position)
		return mate.position
	return player.position + player.aim * CAM_LEAD


## Keeps the view inside the arena (plus a thin border); if the screen is wider/taller than
## the arena on an axis, centres on it instead.
func _clamp_camera(c: Vector2) -> Vector2:
	var half := get_viewport_rect().size / 2.0
	var lo := ARENA.position - Vector2(CAM_EDGE, CAM_EDGE) + half
	var hi := ARENA.end + Vector2(CAM_EDGE, CAM_EDGE) - half
	var mid := ARENA.get_center()
	c.x = mid.x if lo.x > hi.x else clampf(c.x, lo.x, hi.x)
	c.y = mid.y if lo.y > hi.y else clampf(c.y, lo.y, hi.y)
	return c


func _update_camera(delta: float) -> void:
	if state == State.PLAYING:
		var k := 1.0 - exp(-CAM_FOLLOW * delta)
		camera.position = _clamp_camera(camera.position.lerp(_camera_target(), k))
	elif state == State.TITLE or state == State.SELECT:
		camera.position = _clamp_camera(ARENA.get_center())
	else:
		camera.position = _clamp_camera(camera.position)


func snap_camera() -> void:
	camera.position = _clamp_camera(_camera_target())


## World point -> HUD/touch layer coordinates (those layers sit at view_offset()).
func world_to_hud(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p - view_offset()


## Visible world rectangle (without shake).
func view_rect() -> Rect2:
	var sz := get_viewport_rect().size
	return Rect2(camera.position - sz / 2.0, sz)


# ---------------------------------------------------------------- leaderboard screen

func open_board() -> void:
	net.notice = ""
	board_back = state
	board_platform = net.platform
	board_mode = run_cat if state == State.GAMEOVER else input_cat()
	board_period = "all"
	state = State.BOARD
	card_lock = 0.3
	_fetch_board()


func close_board() -> void:
	state = board_back


func _fetch_board() -> void:
	board_refresh = BOARD_REFRESH
	net.fetch_board(board_platform, board_mode, board_period)


func _board_press(pos: Vector2) -> void:
	if card_lock > 0:
		return
	for b in hud.board_buttons():
		if not (b["rect"] as Rect2).has_point(pos):
			continue
		match b["kind"]:
			"platform":
				board_platform = b["value"]
			"mode":
				board_mode = b["value"]
			"period":
				board_period = b["value"]
			"back":
				close_board()
				return
			"rename":
				var n: String = net.ask_name()
				if n.strip_edges() != "":
					net.rename(n, _fetch_board)
				return
		_fetch_board()
		return


# ---------------------------------------------------------------- screen layout

## The stretch mode is "expand": the 1280×720 play frame stays centred and wider or taller
## screens show extra margin around it. HUD and touch layers cover exactly the play frame,
## so their layout code works in frame coordinates; margins are negative x / x > W.
const SIDE_HUD_MIN := 110.0


func _layout_ui() -> void:
	var off := view_offset()
	for c in [hud, touch]:
		c.position = off
		c.size = Vector2(W, H)


func view_offset() -> Vector2:
	return ((get_viewport_rect().size - Vector2(W, H)) / 2.0).floor()


## Width of the empty margin left and right of the play frame.
func side_margin() -> float:
	return maxf(view_offset().x, 0.0)


## Phones in landscape have wide side margins: HUD and touch buttons move there so
## thumbs and readouts stop covering the arena.
func side_hud() -> bool:
	return touch != null and touch.active and side_margin() >= SIDE_HUD_MIN


## Control category of the input in use right now.
func input_cat() -> String:
	return String(touch.mode) if touch and touch.active else "kbm"


## Category whose best score applies to what's on screen.
func score_cat() -> String:
	return input_cat() if state == State.TITLE or state == State.SELECT else run_cat


func update_game(delta: float) -> void:
	if is_guest():
		update_client(delta)
		return
	time_alive += delta
	var c := input_cat()
	if int(CAT_RANK.get(c, 0)) > int(CAT_RANK.get(run_cat, 0)):
		run_cat = c
	var me := player
	for p in players.duplicate():
		if is_instance_valid(p) and not p.dead:
			player = p  # upgrades, shots and hits below belong to this ship
			p.update(delta)
	player = me
	arena.update(delta)
	flow_t -= delta
	if flow_t <= 0:
		flow_t = FLOW_EVERY
		_update_flow()
	_update_waves(delta)
	for e in enemies:
		if not e.dead:
			e.update(delta)
	_separate_enemies(delta)
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
	var is_boss := wave % 5 == 0
	wave_kind = _pick_wave_kind(is_boss)
	var n := mini(4 + wave * 2, MAX_WAVE_ENEMIES)
	var caps := {"tank": 2 + wave / 3, "sentry": 1 + wave / 5, "layer": 1 + wave / 6, "snake": 1 + wave / 8}
	var weights := _wave_weights()
	var fill := "chaser"
	var interval := maxf(0.22, 0.85 - wave * 0.05)
	if SPIKE_WAVES.has(wave_kind):
		var s: Dictionary = SPIKE_WAVES[wave_kind]
		weights = s["types"]
		fill = s["fill"]
		n = roundi(n * float(s["count"]))
		interval *= float(s["interval"])
		for k in caps:
			caps[k] = ceili(int(caps[k]) * 1.5)
	elif wave_kind == "breather":
		n = roundi(n * (BREATHER_AFTER_BOSS if (wave - 1) % 5 == 0 else BREATHER_NEW_ARENA))
	elif wave >= ARENA_MIX_WAVE:
		var extra: Dictionary = ARENA_MIX_CAPS.get(arena.layout, {})
		for k in extra:
			caps[k] = int(caps[k]) + int(extra[k])
	var counts := {}
	var list: Array[String] = []
	for i in n:
		var t := _roll_from(weights)
		if caps.has(t) and int(counts.get(t, 0)) >= int(caps[t]):
			t = fill
		counts[t] = int(counts.get(t, 0)) + 1
		list.append(t)
	list.shuffle()
	if is_boss:
		# The boss lands after a countdown (see _update_waves); its escorts follow it in.
		boss_intro_type = boss_type(wave)
		boss_intro_p = _boss_spawn_point()
		boss_intro_t = BOSS_INTRO
		hud.announce_t = 0.0
		sfx.play("siren")
	elif SPIKE_WAVES.has(wave_kind):
		hud.announce(t("wave_spike") % [wave, t("spike_" + wave_kind)], Color(1, 0.6, 0.2))
		sfx.play("charge")
	else:
		hud.announce(t("wave") % wave, Color(0.4, 0.95, 1))
	spawn_queue = list
	spawn_interval = interval
	spawn_timer = 0.3


## Tension and release: breathers after a boss and on a fresh layout, occasional spike waves.
func _pick_wave_kind(is_boss: bool) -> String:
	if is_boss:
		return ""
	if wave > 5 and (wave - 1) % 5 == 0:
		return "breather"
	if wave > UPGRADE_EVERY and waves_since_upgrade == 0:
		return "breather"
	if wave >= SPIKE_FROM and wave - last_spike >= 3 and randf() < SPIKE_CHANCE:
		last_spike = wave
		var kinds := SPIKE_WAVES.keys()
		return kinds[randi() % kinds.size()]
	return ""


## Spawn weights for the current wave: unlocked enemies, scaled by the layout's mix late on.
func _wave_weights() -> Dictionary:
	var mix: Dictionary = ARENA_MIX.get(arena.layout, {}) if wave >= ARENA_MIX_WAVE else {}
	var out := {}
	for row in ENEMY_TABLE:
		if wave >= row[1]:
			out[row[0]] = float(row[2]) * float(mix.get(row[0], 1.0))
	return out


func _roll_from(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := randf() * total
	for k in weights:
		r -= float(weights[k])
		if r < 0:
			return k
	return weights.keys()[0]


func _update_flow() -> void:
	flow_w = int(ceil(ARENA.size.x / FLOW_CELL))
	flow_h = int(ceil(ARENA.size.y / FLOW_CELL))
	flow = _build_flow(FLOW_CLEAR)
	flow_big = _build_flow(FLOW_CLEAR_BIG)


func _build_flow(clear: float) -> PackedInt32Array:
	var flow := PackedInt32Array()
	flow.resize(flow_w * flow_h)
	flow.fill(-1)
	var blocked := PackedByteArray()
	blocked.resize(flow_w * flow_h)
	blocked.fill(0)  # resize() leaves new bytes uninitialised
	for y in flow_h:
		for x in flow_w:
			var c := _flow_center(x, y)
			for ob in obstacles:
				if c.distance_to(Vector2(ob.x, ob.y)) < ob.z + clear:
					blocked[y * flow_w + x] = 1
					break
	var queue: Array[Vector2i] = []
	for s in hurtable_players() if not hurtable_players().is_empty() else [player]:
		var st := _flow_start(blocked, _flow_cell(s.position))
		if st.x >= 0 and flow[st.y * flow_w + st.x] != 0:
			flow[st.y * flow_w + st.x] = 0
			queue.append(st)
	if queue.is_empty():
		return flow
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d := flow[c.y * flow_w + c.x]
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= flow_w or n.y >= flow_h:
				continue
			var i := n.y * flow_w + n.x
			if flow[i] != -1 or blocked[i] == 1:
				continue
			flow[i] = d + 1
			queue.append(n)
	return flow


## BFS origin for a ship's cell (multi-source: every living ship is a target).
func _flow_start(blocked: PackedByteArray, player_cell: Vector2i) -> Vector2i:
	if player_cell.x < 0:
		return Vector2i(-1, -1)
	# The player can stand in a cell marked blocked when the coarse grid overlaps
	# a nearby pillar. Starting BFS there would strand the whole field because
	# every adjacent cell may also be blocked. Snap the origin to the nearest
	# walkable cell so enemies can still route around the obstacle.
	var start := Vector2i(-1, -1)
	var start_dist := 1 << 30
	for y in flow_h:
		for x in flow_w:
			var i := y * flow_w + x
			if blocked[i] == 1:
				continue
			var d := Vector2i(x, y).distance_squared_to(player_cell)
			if d < start_dist:
				start_dist = d
				start = Vector2i(x, y)
	return start


func _flow_center(x: int, y: int) -> Vector2:
	return ARENA.position + Vector2((x + 0.5) * FLOW_CELL, (y + 0.5) * FLOW_CELL)


func _flow_cell(p: Vector2) -> Vector2i:
	var x := int((p.x - ARENA.position.x) / FLOW_CELL)
	var y := int((p.y - ARENA.position.y) / FLOW_CELL)
	if x < 0 or y < 0 or x >= flow_w or y >= flow_h:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


## Direction to walk from p to reach the player around obstacles (ZERO if unknown).
func flow_dir(p: Vector2, big := false) -> Vector2:
	var flow := flow_big if big and not flow_big.is_empty() else self.flow
	if flow.is_empty():
		return Vector2.ZERO
	var c := _flow_cell(p)
	if c.x < 0:
		return Vector2.ZERO
	var here := flow[c.y * flow_w + c.x]
	# Wedged against pillars, the own cell and its ring may all be blocked: widen the search.
	for reach in [1, 2, 3]:
		var best := Vector2i(-1, -1)
		var best_d := here if here >= 0 else 1 << 30
		for oy in range(-reach, reach + 1):
			for ox in range(-reach, reach + 1):
				var n := c + Vector2i(ox, oy)
				if (ox == 0 and oy == 0) or n.x < 0 or n.y < 0 or n.x >= flow_w or n.y >= flow_h:
					continue
				var d := flow[n.y * flow_w + n.x]
				if d >= 0 and d < best_d:
					best_d = d
					best = n
		if best.x >= 0:
			return (_flow_center(best.x, best.y) - p).normalized()
	return Vector2.ZERO


## Every run meets the bosses in a fresh shuffled order; a cycle never starts with the boss
## that ended the previous one.
func boss_type(w: int) -> String:
	var i := maxi(w / 5 - 1, 0)
	while boss_order.size() <= i:
		var bag: Array[String] = []
		bag.assign(BOSS_TYPES)
		bag.shuffle()
		if not boss_order.is_empty() and bag[0] == boss_order[boss_order.size() - 1]:
			bag.reverse()
		boss_order.append_array(bag)
	return boss_order[i]


## Where the boss lands: on screen (near enough to watch the countdown), clear of cover.
func _boss_spawn_point() -> Vector2:
	var pp: Vector2 = player.position if player else ARENA.get_center()
	for i in 60:
		var p := pp + Vector2.from_angle(randf() * TAU) * randf_range(330.0, 470.0)
		if ARENA.grow(-90).has_point(p) and _clear_of_obstacles(p, 80) and not arena.near_portal(p, 90):
			return p
	return _find_spawn_point()


## Countdown beats: each number lands with a thud, a growing shake and a ring on the spot.
func _boss_intro_beats(prev: float, cur: float) -> void:
	for n in [3, 2, 1]:
		if prev > n and cur <= n:
			sfx.play("count")
			add_shake(3.0 + (3 - n) * 3.0)
			fx.ring(boss_intro_p, 200.0 - n * 30.0, Color(1, 0.25, 0.4), 0.55)


func _boss_arrive() -> void:
	boss_intro_t = 0.0
	for s in hurtable_players():
		var away: Vector2 = s.position - boss_intro_p
		if away.length() < 150.0:
			var n := away.normalized() if away.length() > 1.0 else Vector2.RIGHT
			s.vel = n * 700.0
			s.position = resolve_static(boss_intro_p + n * 150.0, s.radius)
	var e := _spawn_enemy(boss_intro_type, boss_intro_p)
	fx.ring(boss_intro_p, 380, Color(1, 1, 1), 0.7)
	fx.burst(boss_intro_p, e.color, 70, 560, 6.0, 1.0)
	add_shake(24)
	sfx.play("slam")
	sfx.play("explode_big")
	hud.announce(t("boss_" + e.type), e.color.lightened(0.2))
	spawn_timer = 1.6


## Each boss fights on the layout built for it: CORE WARDEN pulls the player in on the open
## field; VOID WEAVER's sweeping beams are blocked by the classic layout's pillars.
func _shift_to_boss_arena(w: int) -> void:
	if arena.shift_to(arena.BOSS_LAYOUTS[boss_type(w)]):
		hud.announce(t("arena_boss") % arena.display_name(), Color(1, 0.4, 0.65))
		sfx.play("charge")


func _roll_elite(t: String) -> String:
	if wave_kind == "breather":
		return ""
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
		if boss_shift_t > 0:
			boss_shift_t -= delta
			if boss_shift_t <= 0:
				_shift_to_boss_arena(wave + 1)
		intermission -= delta
		if intermission <= 0:
			begin_wave()
		return
	if boss_intro_t > 0:
		var prev := boss_intro_t
		boss_intro_t -= delta
		_boss_intro_beats(prev, boss_intro_t)
		if boss_intro_t <= 0:
			_boss_arrive()
		return
	spawn_timer -= delta
	if spawn_timer <= 0 and not spawn_queue.is_empty() and (spawn_queue[0].begins_with("boss") or field_count() < alive_cap()):
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


func alive_cap() -> int:
	return MAX_ALIVE_TOUCH if touch and touch.active else MAX_ALIVE


## Enemies on the field plus pending warning markers; mines and boss minis don't count.
func field_count() -> int:
	var n := spawn_markers.size()
	for list in [enemies, new_enemies]:
		for e in list:
			if not e.dead and e.type != "mine" and e.type != "mini" and not e.is_boss:
				n += 1
	return n


## Soft circle-vs-circle push between enemies on a coarse spatial hash. Bosses are immovable
## anchors; mines and turrets that sit still are skipped.
func _separate_enemies(delta: float) -> void:
	var cell := 64.0
	var grid := {}
	var movers: Array = []
	for e in enemies:
		if e.dead or e.type == "mine":
			continue
		movers.append(e)
		var k := Vector2i(floori(e.position.x / cell), floori(e.position.y / cell))
		if not grid.has(k):
			grid[k] = []
		grid[k].append(e)
	var k_push := minf(1.0, SEPARATION * delta * 60.0)
	for a in movers:
		var ka := Vector2i(floori(a.position.x / cell), floori(a.position.y / cell))
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var bucket = grid.get(ka + Vector2i(ox, oy))
				if bucket == null:
					continue
				for b in bucket:
					if b.get_instance_id() <= a.get_instance_id():
						continue
					var d: Vector2 = b.position - a.position
					var min_d: float = (a.radius + b.radius) * 0.9
					var l2 := d.length_squared()
					if l2 >= min_d * min_d:
						continue
					var l := sqrt(l2)
					var n: Vector2 = d / l if l > 0.01 else Vector2.from_angle(randf() * TAU)
					var push: float = (min_d - l) * 0.5 * k_push
					var wa := 0.0 if a.is_boss or a.type == "sentry" else 1.0
					var wb := 0.0 if b.is_boss or b.type == "sentry" else 1.0
					if wa + wb == 0.0:
						continue
					var s2 := 2.0 / (wa + wb)
					a.position = resolve_static(a.position - n * push * wa * s2, a.radius)
					b.position = resolve_static(b.position + n * push * wb * s2, b.radius)


func _blocking_enemies_left() -> bool:
	for e in enemies:
		if not e.dead and not e.no_clear:
			return true
	for e in new_enemies:
		if not e.no_clear:
			return true
	return false


func _on_wave_clear() -> void:
	for s in players:
		if is_instance_valid(s) and s.dead:
			# Co-op: downed ships return at the end of the wave beside a teammate.
			s.dead = false
			s.visible = true
			s.hp = maxi(2, s.max_hp / 2)
			s.invuln = 2.0
			var mate := nearest_player(s.position)
			s.position = resolve_static(mate.position + Vector2(50, 0), s.radius)
			s.net_in["pos"] = s.position
			fx.ring(s.position, 90, s.ship_color(), 0.5)
			hud.announce(t("coop_revive"), s.ship_color())
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
		# The next wave is a boss: move to its arena once the clear banner has been read.
		if (wave + 1) % 5 == 0 and arena.layout != arena.BOSS_LAYOUTS[boss_type(wave + 1)]:
			boss_shift_t = 0.8


func spawn_marker(t: String, p: Vector2, delay: float) -> void:
	spawn_markers.append({"p": p, "type": t, "t": delay, "elite": _roll_elite(t)})


func _find_spawn_point() -> Vector2:
	var best_p := Vector2(ARENA.position.x + 60, ARENA.position.y + 60)
	for i in 40:
		var p := Vector2(
			randf_range(ARENA.position.x + 50, ARENA.end.x - 50),
			randf_range(ARENA.position.y + 50, ARENA.end.y - 50))
		var dp := p.distance_to(nearest_player(p).position)
		# Not on top of the player, and (mostly) not in the far corner of the bigger arena.
		if dp < 300 or (dp > 950 and i < 30) or arena.near_portal(p, 50):
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
	coop.local_picked = false
	coop.peer_picked = true
	var rp := remote_player()
	if is_host() and rp:
		var me := player
		player = rp
		coop.peer_offer = _roll_offer()
		player = me
		coop.peer_picked = false
		coop.send_offer(coop.peer_offer)
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
		if d["cat"] == "evo":
			continue
		pool.append(id)
	var eligible := pool.duplicate()
	# Bad-luck protection: the three cards come from different categories while possible, and an
	# upgrade that keeps being skipped by the draw grows more likely each offer.
	var out: Array[String] = []
	var used_cats := {}
	# A ready evolution always takes the first slot (one at a time).
	var evos := ready_evolutions()
	if not evos.is_empty():
		out.append(evos[randi() % evos.size()])
	while out.size() < 3 and not pool.is_empty():
		var cands: Array[String] = []
		for id in pool:
			if not used_cats.has(UPGRADES[id]["cat"]):
				cands.append(id)
		if cands.is_empty():
			cands = pool
		var pick := _weighted_upgrade(cands)
		out.append(pick)
		pool.erase(pick)
		used_cats[UPGRADES[pick]["cat"]] = true
	var hurt: bool = player.hp < player.max_hp
	if hurt and (player.hp * 2 <= player.max_hp or randf() < 0.25 or out.size() < 3):
		if out.size() >= 3:
			out[2] = "repair"
		else:
			out.append("repair")
	for id in eligible:
		offer_misses[id] = 0 if out.has(id) else int(offer_misses.get(id, 0)) + 1
	while out.size() < 3:
		out.append("bonus")
	return out


func _weighted_upgrade(cands: Array[String]) -> String:
	var weights := {}
	for id in cands:
		weights[id] = 1.0 + PITY_STEP * mini(int(offer_misses.get(id, 0)), PITY_MAX)
	return _roll_from(weights)


func choose_upgrade(i: int) -> void:
	if is_guest():
		if coop.guest_picked:
			return
		coop.pick(i)
		var gi := card_info(offer[i])
		fx.text(player.position, gi["name"], gi["color"])
		sfx.play("pickup")
		offer.clear()
		return
	_apply_card(player, offer[i])
	offer.clear()
	coop.local_picked = true
	if coop.peer_picked:
		_finish_upgrade()


func _apply_card(ship: Node2D, id: String) -> void:
	var info := card_info(id)
	if id == "bonus":
		score += 500 * wave
	else:
		ship.add_upgrade(id)
	fx.ring(ship.position, 80, info["color"], 0.4)
	fx.text(ship.position, info["name"], info["color"])
	sfx.play("pickup")


## Host: the guest picked card i of its offer (-1: they left).
func remote_pick(i: int) -> void:
	if coop.peer_picked or state != State.UPGRADE:
		return
	var rp := remote_player()
	if rp and i >= 0 and i < coop.peer_offer.size():
		var me := player
		player = rp
		_apply_card(rp, coop.peer_offer[i])
		player = me
	coop.peer_picked = true
	if coop.local_picked:
		_finish_upgrade()


func _finish_upgrade() -> void:
	state = State.PLAYING
	# Every upgrade also reshapes the arena; the extra pause covers the warn + rise.
	if (wave + 1) % 5 == 0:
		_shift_to_boss_arena(wave + 1)
	else:
		# Don't pick the coming boss's arena now, or the next shift would be skipped.
		var next_boss := (wave / 5 + 1) * 5
		var avoid: String = arena.BOSS_LAYOUTS[boss_type(next_boss)] if next_boss - wave <= 4 else ""
		arena.shift_next(avoid)
		hud.announce(t("arena_shift") % arena.display_name(), Color(1, 0.85, 0.35))
	sfx.play("charge")
	intermission = 2.6


## Evolutions whose requirements are all met and that aren't owned yet.
func ready_evolutions() -> Array[String]:
	var out: Array[String] = []
	for id in UPGRADES:
		var d: Dictionary = UPGRADES[id]
		if d["cat"] != "evo" or player.level(id) > 0:
			continue
		var ok := true
		for r in d["req"]:
			if player.level(r) < int(d["req"][r]):
				ok = false
		if ok:
			out.append(id)
	return out


## "Evolves into X (needs A Lv3 + B)" lines for an upgrade that is part of a recipe.
func evo_hint(id: String) -> String:
	var lines: Array[String] = []
	for ev in UPGRADES:
		var d: Dictionary = UPGRADES[ev]
		if d["cat"] != "evo" or not d["req"].has(id):
			continue
		var parts: Array[String] = []
		for r in d["req"]:
			var need := int(d["req"][r])
			parts.append(t("up_" + r) + ("" if need <= 1 else " " + t("lv_short") % need))
		lines.append(t("evo_hint") % [t("up_" + ev), " + ".join(parts)])
	return "\n".join(lines)


## REACTIVE ARMOR: the barrier bursts when it breaks.
func reactive_blast(p: Vector2) -> void:
	var dmg: float = 6.0 * player.damage_mult()
	fx.ring(p, REACTIVE_RADIUS * 1.2, CAT_COLORS["evo"], 0.45)
	fx.burst(p, CAT_COLORS["evo"], 30, 420, 3.5, 0.45)
	sfx.play("shock")
	arena.damage_blocks_in(p, REACTIVE_RADIUS, dmg)
	for e in enemies:
		if not e.dead and e.position.distance_to(p) < REACTIVE_RADIUS + e.radius:
			var n: Vector2 = (e.position - p).normalized()
			e.knock += n * 360.0 * minf(e.knock_scale, 1.0)
			damage_enemy(e, dmg, Vector2.ZERO, true)
	for b in bullets:
		if not b.from_player and not b.dead and b.position.distance_to(p) < REACTIVE_RADIUS + 70.0:
			b.dead = true


## MAGSTORM: every pickup collected releases a pulse.
func storm_pulse(p: Vector2) -> void:
	var dmg: float = 4.0 * player.damage_mult()
	fx.ring(p, STORM_RADIUS * 1.15, CAT_COLORS["evo"], 0.4)
	sfx.play("shock")
	arena.damage_blocks_in(p, STORM_RADIUS, dmg)
	for e in enemies:
		if not e.dead and e.position.distance_to(p) < STORM_RADIUS + e.radius:
			damage_enemy(e, dmg, Vector2.ZERO, true)
	for b in bullets:
		if not b.from_player and not b.dead and b.position.distance_to(p) < STORM_RADIUS:
			b.dead = true


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
	if d["cat"] == "evo":
		lvl = t("lv_evo")
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
	_save_setting("ui", "lang", lang)


## Mutes every sound through the master bus.
func _query_fullscreen() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("!!(document.fullscreenElement || document.webkitFullscreenElement)", true))
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


## Runs inside a click / key / tap handler, so the browser accepts the request.
func toggle_fullscreen() -> void:
	sfx.play("card")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(function () {
			var d = document, e = d.documentElement;
			if (d.fullscreenElement || d.webkitFullscreenElement) {
				(d.exitFullscreen || d.webkitExitFullscreen).call(d);
				return;
			}
			var req = e.requestFullscreen || e.webkitRequestFullscreen;
			if (!req) return;
			var p = req.call(e, {navigationUI: 'hide'});
			if (p && p.then) p.then(function () {
				if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(function () {});
			}).catch(function () {});
		})()""", true)
		fs_on = not fs_on
		fs_poll = 0.6
		return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	fs_on = not full


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, muted)
	if not muted:
		sfx.play("pickup")
	_save_setting("audio", "muted", muted)


func _save_setting(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var default_lang := "zh" if OS.get_locale_language() == "zh" else "en"
	if cfg.load(SETTINGS_PATH) == OK:
		lang = String(cfg.get_value("ui", "lang", default_lang))
		muted = bool(cfg.get_value("audio", "muted", false))
		touch_mode_setting = String(cfg.get_value("input", "touch_mode", "hybrid"))
		shake_setting = String(cfg.get_value("video", "shake", "full"))
		if not SHAKE_LEVELS.has(shake_setting):
			shake_setting = "full"
		AudioServer.set_bus_mute(0, muted)
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
	b.owner_ship = player
	b.pierce = player.level("pierce")
	b.bounce = player.level("bounce")
	b.homing = player.level("homing") > 0
	b.split = player.level("split") > 0
	# Point-blank: bullets appear at the muzzle, so enemies pressed against the ship would be
	# skipped. Check the stretch from the ship's centre to the muzzle once at spawn time.
	var from: Vector2 = player.position
	var near: Array = []
	for e in enemies:
		if not e.dead and e.position.distance_to(from) < e.radius + r + from.distance_to(p):
			near.append(e)
	near.sort_custom(func(a, c): return a.position.distance_squared_to(from) < c.position.distance_squared_to(from))
	for e in near:
		if b.dead:
			break
		var cp := Geometry2D.get_closest_point_to_segment(e.position, from, p)
		if cp.distance_to(e.position) < e.radius + r:
			_player_bullet_hits(b, cp)


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
		var oi := _obstacle_at(p, b.radius)
		if oi >= 0:
			var ob: Vector3 = obstacles[oi]
			if b.from_player and b.bounce > 0:
				_bounce_off(b, Vector2(ob.x, ob.y), ob.z + b.radius)
			else:
				b.dead = true
				fx.burst(p, b.color, 5, 160, 2.5, 0.25)
			# Crystals crack under any fire, including enemy bullets.
			arena.damage_block(oi, b.damage if b.from_player else 1.0)
			continue
		if b.from_player:
			var me := player
			if b.owner_ship != null and is_instance_valid(b.owner_ship):
				player = b.owner_ship
			_player_bullet_hits(b, p)
			player = me
		elif state == State.PLAYING:
			for s in hurtable_players():
				var rr2: float = s.radius * 0.7 + b.radius
				if p.distance_squared_to(s.position) < rr2 * rr2:
					if s.hurt(1):
						b.dead = true
						break


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
	# Snake and hydra bodies are armoured: they stop (or deflect) shots.
	for e in enemies:
		if e.dead or e.segs.is_empty():
			continue
		for s in e.segs:
			var sr: float = e.seg_r + b.radius
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
	var wall_hit := ray_hit
	for e in enemies:
		if e.dead or e.segs.is_empty():
			continue
		for s in e.segs:
			var tt := _ray_circle(o, d, s, e.seg_r)
			if tt >= 0.0 and tt < length:
				length = tt
				wall_hit = -1
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
	arena.damage_block(wall_hit, dmg)


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
	ray_hit = -1
	if d.x > 0.0001:
		best_t = minf(best_t, (ARENA.end.x - o.x) / d.x)
	elif d.x < -0.0001:
		best_t = minf(best_t, (ARENA.position.x - o.x) / d.x)
	if d.y > 0.0001:
		best_t = minf(best_t, (ARENA.end.y - o.y) / d.y)
	elif d.y < -0.0001:
		best_t = minf(best_t, (ARENA.position.y - o.y) / d.y)
	for i in obstacles.size():
		var ob: Vector3 = obstacles[i]
		var tt := _ray_circle(o, d, Vector2(ob.x, ob.y), ob.z)
		if tt > 0.0 and tt < best_t:
			best_t = tt
			ray_hit = i
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
	if e.is_boss and e.invulnerable():
		if not quiet:
			fx.burst(e.position - dir * e.radius, Color(1, 1, 1), 2, 120, 2.0, 0.15)
		return
	e.flash = 0.08
	if e.stunned():
		dmg *= EnemyScript.STUN_DAMAGE_MULT
	if e.shield_blocks(dir):
		e.shield -= dmg
		e.knock += dir * 30.0
		fx.burst(e.position - dir * e.radius, e.elite_color(), 3, 160, 2.0, 0.2)
		if e.shield <= 0:
			fx.ring(e.position, e.radius * 3, e.elite_color(), 0.35)
			sfx.play("shield")
		elif not quiet:
			sfx.play("hit")
		return
	e.hp = e.boss_clamp(e.hp - dmg) if e.is_boss else e.hp - dmg
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
		"mine":
			explode(e.position, EnemyScript.MINE_BLAST, 3.0, true)
	for s in e.segs:
		fx.burst(s, e.color, 8, 220, 3.0, 0.5)
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


## A boss crossed a phase threshold: clear the air, shove the player back, announce it.
func boss_phase_change(e: Node2D) -> void:
	for b in bullets:
		if not b.from_player and not b.dead:
			b.dead = true
			fx.burst(b.position, b.color, 3, 90, 2.0, 0.25)
	for s in hurtable_players():
		var away: Vector2 = s.position - e.position
		if away.length() < 260.0:
			var n := away.normalized() if away.length() > 1.0 else Vector2.RIGHT
			s.vel = n * 700.0
			s.position = resolve_static(s.position + n * (260.0 - away.length()) * 0.5, s.radius)
	fx.ring(e.position, 300, Color(1, 1, 1), 0.6)
	fx.burst(e.position, e.color, 50, 480, 5.0, 0.9)
	add_shake(16)
	sfx.play("explode_big")
	hud.announce(t("boss_phase") % e.boss_phase, e.color.lightened(0.3))


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
	arena.damage_blocks_in(p, r, enemy_dmg)
	for e in enemies:
		if e.dead:
			continue
		var d: Vector2 = e.position - p
		if d.length() < r + e.radius:
			damage_enemy(e, enemy_dmg, d.normalized(), true)
	if hurt_player and state == State.PLAYING:
		for s in hurtable_players():
			if s.position.distance_to(p) < r + s.radius * 0.5:
				s.hurt(1)


## SHOCKWAVE upgrade: fires when a dash ends.
func shockwave(p: Vector2, lvl: int) -> void:
	var r := 110.0 + 35.0 * (lvl - 1)
	var dmg: float = (3.0 + 2.0 * (lvl - 1)) * player.damage_mult()
	fx.ring(p, r * 1.15, Color(0.4, 0.95, 1), 0.35)
	fx.burst(p, Color(0.4, 0.95, 1), 20, 360, 3.0, 0.35)
	sfx.play("shock")
	add_shake(6)
	arena.damage_blocks_in(p, r, dmg)
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
	hazards.append({"p": p, "life": INFERNO_LIFE if player.level("inferno") > 0 else 1.4, "tick": 0.0})


func _update_hazards(delta: float) -> void:
	if hazards.is_empty():
		return
	var inferno: bool = player.level("inferno") > 0
	var dmg: float = (2.0 if inferno else 1.0) * player.damage_mult()
	for h in hazards:
		h["life"] -= delta
		h["tick"] -= delta
		if inferno:
			var hp0: Vector2 = h["p"]
			for e in enemies:
				if not e.dead and not e.is_boss and hp0.distance_to(e.position) < 22.0 + e.radius:
					e.slow_t = 0.3
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
	var me := player
	for pk in pickups:
		if pk.dead:
			continue
		player = nearest_player(pk.position)  # the closest ship pulls and collects it
		var reach: float = player.pickup_range()
		pk.step(delta)
		var d: float = pk.position.distance_to(player.position)
		if d < reach:
			pk.position = pk.position.move_toward(player.position, delta * maxf(520.0 - d * 2.5, 260.0))
		if d < player.radius + 16:
			pk.dead = true
			if player.level("storm") > 0:
				storm_pulse(player.position)
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
	player = me


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


## Index of the obstacle a point overlaps, or -1.
func _obstacle_at(p: Vector2, r: float) -> int:
	for i in obstacles.size():
		var o: Vector3 = obstacles[i]
		var rr: float = o.z + r * 0.5
		if p.distance_squared_to(Vector2(o.x, o.y)) < rr * rr:
			return i
	return -1


func add_shake(amount: float) -> void:
	var k: float = SHAKE_SCALE.get(shake_setting, 1.0) * (SHAKE_TOUCH if touch and touch.active else 1.0)
	shake = minf(maxf(shake, amount * k), 26.0)


func cycle_shake() -> void:
	shake_setting = SHAKE_LEVELS[(SHAKE_LEVELS.find(shake_setting) + 1) % SHAKE_LEVELS.size()]
	_save_setting("video", "shake", shake_setting)
	sfx.play("card")
	shake = 0.0
	add_shake(10)  # a sample of the new strength


func load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) == OK:
		for c in bests:
			bests[c] = int(cfg.get_value("best", c, 0))
	elif FileAccess.file_exists(SAVE_PATH):
		# Scores from before the split were all keyboard-and-mouse (or near enough).
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			bests["kbm"] = int(f.get_line())
			save_best()


func save_best() -> void:
	var cfg := ConfigFile.new()
	for c in bests:
		cfg.set_value("best", c, int(bests[c]))
	cfg.save(BEST_PATH)


# ---------------------------------------------------------------- arena drawing

func _draw() -> void:
	draw_rect(Rect2(-2000, -1500, WORLD.x + 4000, WORLD.y + 3000), Color(0.02, 0.02, 0.05))
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
	# Pillars, crystals and mechanisms are drawn by arena.gd.
