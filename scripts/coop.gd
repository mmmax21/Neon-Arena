extends Node
## Online co-op for two players through the room relay in server/src/room.js.
##
## The host's game is authoritative: it simulates everything, including the guest's ship,
## and sends a snapshot SNAP_HZ times a second. The guest moves its own ship locally (so
## steering feels instant), sends input + position INPUT_HZ times a second, and draws the
## rest of the world from snapshots. Effects and sounds the host makes are logged and
## replayed on the guest.
##
## Frames are base64(var_to_bytes(Dictionary)); bytes_to_var never decodes objects, so a
## peer can't inject code. Text frames keep the relay simple.

const SNAP_HZ := 15.0
const INPUT_HZ := 20.0
const ARENA_EVERY := 2.0
const ENEMY_FIELDS := ["type", "position", "facing", "t", "hp", "max_hp", "flash", "elite",
	"phase", "phase_t", "spin", "shield", "shield_max", "fuse", "beam_dir", "beam_len", "beams",
	"beam_lens", "beam_dirs", "segs", "boss_phase", "transition_t", "radius", "color", "is_boss",
	"display_name", "charge_dir", "vel", "trail", "trail_t", "strikes", "lines"]
const PLAYER_FIELDS := ["hp", "max_hp", "dead", "dash_t", "dash_cd", "dash_cd_max", "invuln",
	"shield_up", "weapon", "lv", "rapid", "aim"]
const LOCAL_ONLY := ["aim", "dash_t", "dash_cd"]

var main: Node2D
var ws: WebSocketPeer = null
var role := ""        # "", "host", "guest"
var code := ""
var slot := -1
var status := ""      # "", creating, connecting, waiting, ready, or an error key (err_*)
var peer_here := false
var peer_weapon := "pulse"
var in_game := false
var rtt_ms := -1      # guest: round trip measured with ping frames
var _ping_t := 0.0
var _snap_t := 0.0
var _in_t := 0.0
var _arena_t := 0.0
var _arena_sig := ""
var _was_open := false
# Upgrades (host)
var peer_offer: Array[String] = []
var peer_picked := true
var local_picked := false
# Guest world
var g_enemies := {}   # host instance id -> enemy node
var g_pickups := {}   # host instance id -> pickup node
var g_bullets: Array = []
var guest_picked := false
var last_snap_ms := 0


func active() -> bool:
	return role != ""


func is_host() -> bool:
	return role == "host" and in_game


func is_guest() -> bool:
	return role == "guest" and in_game


func _ws_url() -> String:
	var b: String = main.net.base_url
	return b.replace("https://", "wss://").replace("http://", "ws://") + "/api/room/%s/ws" % code


# ---------------------------------------------------------------- lobby

func create_room() -> void:
	if not main.net.enabled():
		status = "err_offline"
		return
	leave()
	status = "creating"
	main.net._request(HTTPClient.METHOD_POST, "/api/room", {}, func(c: int, data):
		if status != "creating":
			return
		if c == 200 and data is Dictionary and data.has("code"):
			code = String(data["code"])
			role = "host"
			_connect()
		else:
			status = "err_rate" if c == 429 else "err_offline")


func join_room(c: String) -> void:
	c = c.strip_edges().to_upper()
	if not main.net.enabled():
		status = "err_offline"
		return
	if c.length() < 4:
		status = "err_code"
		return
	leave()
	code = c
	role = "guest"
	_connect()


func _connect() -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	status = "connecting"
	_was_open = false
	if ws.connect_to_url(_ws_url()) != OK:
		status = "err_offline"
		ws = null


func leave() -> void:
	if ws:
		ws.close(1000, "bye")
	ws = null
	role = ""
	code = ""
	slot = -1
	peer_here = false
	in_game = false
	rtt_ms = -1
	status = ""
	_clear_guest_world()


func send_weapon() -> void:
	if role == "guest":
		_send({"t": "wpn", "w": main.weapon})


## Host: both players are in; begin the run.
func host_start() -> void:
	if role != "host" or not peer_here:
		return
	in_game = true
	main.start_game()
	_arena_sig = ""
	_send({"t": "start", "w": main.weapon, "gw": peer_weapon})
	_send_arena()


# ---------------------------------------------------------------- transport

func _send(d: Dictionary, to := -1) -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var frame := Marshalls.raw_to_base64(var_to_bytes(d))
	if to > 0:
		frame = "@%d|%s" % [to, frame]
	ws.send_text(frame)


func _decode(s: String) -> Variant:
	var raw := Marshalls.base64_to_raw(s)
	if raw.is_empty():
		return null
	var v = bytes_to_var(raw)
	return v if v is Dictionary else null


func _process(delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		_was_open = true
		while ws.get_available_packet_count() > 0:
			_on_frame(ws.get_packet().get_string_from_utf8())
			if ws == null:
				return
	elif st == WebSocketPeer.STATE_CLOSED:
		var was_guest_game := is_guest()
		var keep := status
		var was_host_game := is_host()
		ws = null
		if was_host_game:
			# Keep playing alone.
			main.drop_remote()
			role = ""
			in_game = false
			return
		leave()
		status = keep if keep.begins_with("err_") else ("err_lost" if _was_open else "err_offline")
		if was_guest_game:
			main.coop_ended("coop_lost")
		return
	else:
		return
	if role == "host" and in_game:
		_snap_t -= delta
		if _snap_t <= 0:
			_snap_t = 1.0 / SNAP_HZ
			_send(_snapshot())
		_arena_t -= delta
		if _arena_t <= 0 or _arena_signature() != _arena_sig:
			_send_arena()
	elif role == "guest" and in_game:
		_in_t -= delta
		if _in_t <= 0:
			_in_t = 1.0 / INPUT_HZ
			_send_input()
	if role == "guest":
		_ping_t -= delta
		if _ping_t <= 0:
			_ping_t = 2.0
			_send({"t": "ping", "ms": Time.get_ticks_msec()})


func _on_frame(s: String) -> void:
	if s.begins_with("#"):
		_on_system(s)
		return
	if role == "host":
		var bar := s.find("|")
		if bar < 1:
			return
		var from := int(s.left(bar))
		var d = _decode(s.substr(bar + 1))
		if d != null:
			_host_msg(from, d)
	elif role == "guest":
		var d = _decode(s)
		if d != null:
			_guest_msg(d)


func _on_system(s: String) -> void:
	var parts := s.substr(1).split(" ")
	match parts[0]:
		"hello":
			slot = int(parts[1]) if parts.size() > 1 else -1
			status = "waiting" if role == "host" else "ready"
			if role == "guest":
				send_weapon()
		"join":
			peer_here = true
			status = "ready"
			main.sfx.play("pickup")
		"leave":
			peer_here = false
			status = "waiting"
			if in_game:
				main.drop_remote()
		"host_left":
			var was := is_guest()
			leave()
			status = "err_host_left"
			if was:
				main.coop_ended("coop_host_left")
		"full":
			leave()
			status = "err_full"
		"gone":
			leave()
			status = "err_gone"


# ---------------------------------------------------------------- host side

func _host_msg(from: int, d: Dictionary) -> void:
	match String(d.get("t", "")):
		"wpn":
			var w := String(d.get("w", "pulse"))
			if main.WEAPON_ORDER.has(w):
				peer_weapon = w
		"in":
			var rp = main.remote_player()
			if rp == null:
				return
			var mv = d.get("mv", Vector2.ZERO)
			var aim = d.get("aim", Vector2.RIGHT)
			var pos = d.get("pos", rp.position)
			if mv is Vector2 and aim is Vector2 and pos is Vector2:
				rp.net_in["mv"] = mv.limit_length(1.0)
				rp.net_in["aim"] = aim
				rp.net_in["pos"] = pos
				rp.net_in["fire"] = bool(d.get("fire", false))
				rp.net_in["dash"] = int(d.get("dash", 0))
		"pick":
			main.remote_pick(int(d.get("i", -1)))
		"ping":
			_send({"t": "pong", "ms": d.get("ms", 0)}, from)


func send_offer(ids: Array[String]) -> void:
	_send({"t": "offer", "ids": ids})


func _pack_player(p: Node2D) -> Dictionary:
	var d := {"slot": p.slot, "pos": p.position}
	for f in PLAYER_FIELDS:
		d[f] = p.get(f)
	return d


func _snapshot() -> Dictionary:
	var ps: Array = []
	for p in main.players:
		ps.append(_pack_player(p))
	var es: Array = []
	for list in [main.enemies, main.new_enemies]:
		for e in list:
			if e.dead:
				continue
			var row: Array = [e.get_instance_id()]
			for f in ENEMY_FIELDS:
				row.append(e.get(f))
			es.append(row)
	var bf := PackedFloat32Array()
	var bc := PackedInt32Array()  # rgba32 bits
	var bp := PackedByteArray()   # 1 = player bullet
	for list in [main.bullets, main.new_bullets]:
		for b in list:
			if b.dead:
				continue
			bf.append_array([b.position.x, b.position.y, b.vel.x, b.vel.y, b.radius])
			bc.append(b.color.to_rgba32())
			bp.append(1 if b.from_player else 0)
	var ks: Array = []
	for pk in main.pickups:
		if not pk.dead:
			ks.append([pk.get_instance_id(), pk.type, pk.position, pk.life])
	var d := {"t": "s", "st": main.state, "w": main.wave, "sc": main.score, "k": main.kills,
		"ta": main.time_alive, "cb": main.combo, "p": ps, "e": es, "bf": bf, "bc": bc, "bp": bp, "pk": ks,
		"m": main.spawn_markers, "hz": main.hazards, "fx": main.fx.events, "sx": Array(main.sfx.events),
		"cl": main.clear_timer, "im": main.intermission, "picked": [local_picked, peer_picked],
		"bi": [main.boss_intro_t, main.boss_intro_type, main.boss_intro_p]}
	main.fx.events = []
	main.sfx.events.clear()
	return d


func _arena_signature() -> String:
	var a = main.arena
	var n := 0
	var hp := 0.0
	for e in a.elements:
		n += 1
		hp += float(e["hp"]) + (0.0 if e["state"] == "solid" else 100.0)
	return "%s/%d/%d/%d" % [a.layout, n, int(hp), a.gen_count]


func _send_arena() -> void:
	var a = main.arena
	_arena_t = ARENA_EVERY
	_arena_sig = _arena_signature()
	_send({"t": "ar", "lay": a.layout, "el": a.elements, "fe": a.fences, "be": a.belts,
		"po": a.portals, "mt": a.mech_t, "md": a.mech_delay, "gd": a.gen_data, "gc": a.gen_count})


# ---------------------------------------------------------------- guest side

func _send_input() -> void:
	var p = main.player
	if p == null:
		return
	_send({"t": "in", "mv": p.vel / maxf(p.move_speed(), 1.0) if p.dash_t <= 0 else Vector2.ZERO,
		"aim": p.aim, "pos": p.position, "fire": p.want_fire, "dash": p.dash_seq})


func pick(i: int) -> void:
	guest_picked = true
	_send({"t": "pick", "i": i})


func _guest_msg(d: Dictionary) -> void:
	match String(d.get("t", "")):
		"start":
			in_game = true
			guest_picked = false
			main.start_client_game(String(d.get("gw", main.weapon)), String(d.get("w", "pulse")))
		"s":
			if in_game:
				_apply_snapshot(d)
		"ar":
			_apply_arena(d)
		"offer":
			var ids: Array[String] = []
			for x in d.get("ids", []):
				if main.UPGRADES.has(String(x)) or String(x) == "bonus":
					ids.append(String(x))
			guest_picked = false
			main.offer = ids
			main.card_lock = 0.5
			main.state = main.State.UPGRADE
			main.sfx.play("card")
		"pong":
			rtt_ms = Time.get_ticks_msec() - int(d.get("ms", 0))


func _apply_arena(d: Dictionary) -> void:
	var a = main.arena
	if not (d.get("el") is Array):
		return
	a.layout = String(d.get("lay", a.layout))
	a.gen_data = d.get("gd", {}) if d.get("gd") is Dictionary else {}
	a.gen_count = int(d.get("gc", a.gen_count))
	a.elements = d["el"]
	a.fences = d.get("fe", [])
	a.belts = d.get("be", [])
	a.portals = d.get("po", [])
	a.mech_t = float(d.get("mt", 0.0))
	a.mech_delay = float(d.get("md", 0.0))
	a.rebuild()
	a.queue_redraw()


func _apply_snapshot(d: Dictionary) -> void:
	last_snap_ms = Time.get_ticks_msec()
	main.wave = int(d.get("w", 0))
	main.score = int(d.get("sc", 0))
	main.kills = int(d.get("k", 0))
	main.time_alive = float(d.get("ta", 0.0))
	main.combo = int(d.get("cb", 0))
	main.clear_timer = float(d.get("cl", 0.0))
	main.intermission = float(d.get("im", 0.0))
	var bi = d.get("bi")
	if bi is Array and bi.size() == 3 and bi[2] is Vector2:
		var prev: float = main.boss_intro_t
		main.boss_intro_t = float(bi[0])
		main.boss_intro_type = String(bi[1])
		main.boss_intro_p = bi[2]
		# Countdown shakes locally (sounds and rings arrive with the host's effect log).
		for n in [3, 2, 1]:
			if prev > n and main.boss_intro_t <= n:
				main.add_shake(3.0 + (3 - n) * 3.0)
	var st := int(d.get("st", main.state))
	if st == main.State.GAMEOVER and main.state != main.State.GAMEOVER:
		main.state = main.State.GAMEOVER
		main.gameover_timer = 0.0
		main.sfx.play("explode_big")
	elif st == main.State.PLAYING and main.state == main.State.UPGRADE:
		main.state = main.State.PLAYING
		main.offer.clear()
	elif st == main.State.UPGRADE and main.state == main.State.PLAYING:
		main.state = main.State.UPGRADE  # waiting for the offer frame / teammate
	# Players
	for pd in d.get("p", []):
		if not (pd is Dictionary):
			continue
		var p = main.player_by_slot(int(pd.get("slot", -1)))
		if p == null:
			continue
		var was_dead: bool = p.dead
		for f in PLAYER_FIELDS:
			if not pd.has(f) or (p == main.player and LOCAL_ONLY.has(f)):
				continue  # our own aim and dash run locally
			if typeof(pd[f]) != typeof(p.get(f)):
				continue
			if p.get(f) is Dictionary:
				p.set(f, (pd[f] as Dictionary).duplicate())
			else:
				p.set(f, pd[f])
		var pos: Vector2 = pd.get("pos", p.position)
		if p == main.player:
			# Our own ship moves locally; snap only on big corrections (revive, shoves).
			if pos.distance_to(p.position) > 160.0 or (was_dead and not p.dead):
				p.position = pos
		else:
			p.set_meta("tp", pos)
		p.visible = not p.dead
	# Enemies
	var seen := {}
	for row in d.get("e", []):
		if not (row is Array) or row.size() != ENEMY_FIELDS.size() + 1:
			continue
		var id := int(row[0])
		seen[id] = true
		var e = g_enemies.get(id)
		if e == null:
			e = main.EnemyScript.new()
			e.main = main
			e.setup(String(row[1]), main.wave)
			e.position = row[2]
			main.layer_enemies.add_child(e)
			main.enemies.append(e)
			g_enemies[id] = e
		for i in ENEMY_FIELDS.size():
			var f: String = ENEMY_FIELDS[i]
			var v = row[i + 1]
			if f == "position":
				e.set_meta("tp", v)
			elif e.get(f) is Array and v is Array:
				(e.get(f) as Array).assign(v)
			elif typeof(e.get(f)) == typeof(v):
				e.set(f, v)
		e.queue_redraw()
	for id in g_enemies.keys():
		if not seen.has(id):
			var e = g_enemies[id]
			g_enemies.erase(id)
			main.enemies.erase(e)
			if main.boss == e:
				main.boss = null
			e.queue_free()
	main.boss = null
	for e in main.enemies:
		if e.is_boss:
			main.boss = e
	# Bullets: a pool of nodes, moved locally between snapshots.
	var bf: PackedFloat32Array = d.get("bf", PackedFloat32Array())
	var bc: PackedInt32Array = d.get("bc", PackedInt32Array())
	var bp: PackedByteArray = d.get("bp", PackedByteArray())
	var n := mini(bf.size() / 5, mini(bc.size(), bp.size()))
	while g_bullets.size() < n:
		var b = main.BulletScript.new()
		main.layer_bullets.add_child(b)
		g_bullets.append(b)
	for i in g_bullets.size():
		var b = g_bullets[i]
		if i >= n:
			b.visible = false
			continue
		b.visible = true
		b.position = Vector2(bf[i * 5], bf[i * 5 + 1])
		b.vel = Vector2(bf[i * 5 + 2], bf[i * 5 + 3])
		b.radius = bf[i * 5 + 4]
		b.from_player = bp[i] == 1
		b.color = Color.hex(bc[i] & 0xffffffff)
		b.queue_redraw()
	# Pickups
	var pseen := {}
	for k in d.get("pk", []):
		if not (k is Array) or k.size() != 4:
			continue
		var id := int(k[0])
		pseen[id] = true
		var pk = g_pickups.get(id)
		if pk == null:
			pk = main.PickupScript.new()
			pk.type = String(k[1])
			main.layer_pickups.add_child(pk)
			g_pickups[id] = pk
		pk.position = k[2]
		pk.life = float(k[3])
	for id in g_pickups.keys():
		if not pseen.has(id):
			g_pickups[id].queue_free()
			g_pickups.erase(id)
	main.spawn_markers = d.get("m", []) if d.get("m") is Array else []
	main.hazards = d.get("hz", []) if d.get("hz") is Array else []
	var fx_list = d.get("fx", [])
	if fx_list is Array:
		main.fx.replay(fx_list)
	var sx = d.get("sx", [])
	if sx is Array:
		for name in sx:
			main.sfx.play(String(name))


## Guest frame update: smooth snapshot positions, advance bullets and pickups locally.
func guest_step(delta: float) -> void:
	var k := clampf(delta * 14.0, 0.0, 1.0)
	for e in main.enemies:
		if e.has_meta("tp"):
			e.position = e.position.lerp(e.get_meta("tp"), k)
		e.t += delta
		e.queue_redraw()
	for p in main.players:
		if p != main.player and p.has_meta("tp"):
			p.position = p.position.lerp(p.get_meta("tp"), k)
			p.anim += delta
			p.queue_redraw()
	for b in g_bullets:
		if b.visible:
			b.position += b.vel * delta
			b.queue_redraw()
	for pk in g_pickups.values():
		pk.t += delta
		pk.queue_redraw()


func _clear_guest_world() -> void:
	for e in g_enemies.values():
		if is_instance_valid(e):
			e.queue_free()
	g_enemies.clear()
	for pk in g_pickups.values():
		if is_instance_valid(pk):
			pk.queue_free()
	g_pickups.clear()
	for b in g_bullets:
		if is_instance_valid(b):
			b.queue_free()
	g_bullets.clear()
