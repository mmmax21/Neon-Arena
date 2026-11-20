extends Node
## Store capture: a scripted run (autopilot) for the TapTap gameplay video and screenshots.
## Run windowed in Movie Maker mode, e.g.
##   godot --path . --resolution 1920x1080 --fixed-fps 60 --write-movie /tmp/store/run.avi tests/store_capture.tscn
## The pilot drives the ship through the co-op remote-input fields (move, aim, fire, dash),
## so the game itself runs unmodified. Screenshots land in /tmp/store/shot_*.png.
## With the user argument `frames` (after `--`) every frame is also written to
## /tmp/store/frames/NNNNN.jpg and each sound effect is logged with its frame number
## (/tmp/store/sfx_log.json, sounds in /tmp/store/sfx/*.wav); tools/store_video.py turns
## that into the MP4. Frames are forced through RenderingServer, so the window can stay
## minimized (Movie Maker records nothing from a hidden window on macOS).

const OUT := "/tmp/store/"
const DT := 1.0 / 60.0

var main: Node2D
var bot_pos := Vector2.ZERO
var dash_seq := 0
var t := 0.0
var seg := "combat"
var seg_t := 0.0
var shots := {}
var aim_target := Vector2.ZERO
var calm := 0  # frames since the boss last flashed from a hit (clean boss screenshots)
var dump_frames := false
var frame_i := 0
var sfx_log: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	# Stay out of the way: frames are forced in _process, so a minimized window still records.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.net.base_url = ""  # no leaderboard traffic from a capture
	dump_frames = OS.get_cmdline_user_args().has("frames")
	if dump_frames:
		DirAccess.make_dir_recursive_absolute(OUT + "frames")
		DirAccess.make_dir_recursive_absolute(OUT + "sfx")
		for n in main.sfx.sounds:
			main.sfx.sounds[n].save_to_wav(OUT + "sfx/%s.wav" % n)
	main.lang = "zh"
	AudioServer.set_bus_mute(0, false)
	main.weapon = "pulse"
	main.start_game()
	main.sfx.record = dump_frames  # after start_game, which resets it
	var p = main.player
	p.remote = true
	p.lv = {"power": 3, "rapid": 3, "multi": 1, "split": 1, "quick": 2, "vital": 2, "shield": 1}
	p.max_hp = 7
	p.hp = 7
	p.shield_up = true
	main.boss_order.assign(["boss", "boss3", "boss4", "boss5", "boss2"])  # wave 10 -> RAZOR COMET
	main.arena.set_layout("cross", true)
	main.wave = 8
	main.score = 48210
	main.kills = 163
	main.waves_since_upgrade = 2
	main.intermission = 0.05
	bot_pos = p.position
	# Action from the first frame: a mixed group already closing in.
	var kinds := ["chaser", "chaser", "shooter", "dodger", "tank", "chaser", "shooter", "splitter", "chaser", "snake"]
	for i in kinds.size():
		var a := TAU * i / kinds.size() + 0.3
		var sp: Vector2 = main.resolve_static(bot_pos + Vector2.from_angle(a) * randf_range(330.0, 520.0), 30)
		main.spawn_enemy_now(kinds[i], sp)


func snap(name: String) -> void:
	if shots.has(name):
		return
	shots[name] = true
	var img := get_viewport().get_texture().get_image()
	if img:  # null when run headless (timeline dry runs)
		img.save_png(OUT + "shot_%s.png" % name)
	print("shot ", name, " at ", snappedf(t, 0.01))


func _process(delta: float) -> void:
	t += delta
	seg_t += delta
	var p = main.player
	if p == null:
		return
	if main.state == main.State.PAUSED:
		main.state = main.State.PLAYING  # the window may open unfocused, which auto-pauses
	if p.hp <= 3:
		p.hp = p.max_hp  # the pilot never dies on camera
	calm = calm + 1 if main.boss != null and main.boss.flash <= 0 else 0
	match seg:
		"combat":
			if main.state == main.State.PLAYING and seg_t > 5.5:
				snap("combat")
			if main.state == main.State.UPGRADE:
				seg = "upgrade"
				seg_t = 0.0
		"upgrade":
			if seg_t > 1.0:
				snap("cards")
			if seg_t > 2.2 and main.state == main.State.UPGRADE:
				main.choose_upgrade(1)
			if main.state == main.State.PLAYING:
				seg = "to_boss"
				seg_t = 0.0
		"to_boss":
			if main.boss_intro_t > 0 and main.boss_intro_t < 1.75:
				snap("countdown")
			if main.boss != null:
				seg = "comet"
				seg_t = 0.0
		"comet":
			var b = main.boss
			if b != null and not b.dead:
				if calm >= 3 and b.phase == "aim" and b.phase_t < 0.45 and seg_t > 3.0:
					snap("comet_aim")
				if calm >= 3 and b.boss_phase >= 2 and not b.trail.is_empty() and b.trail_t > 0:
					snap("comet_trail")
				if seg_t > 24.0 and not b.invulnerable():
					main.damage_enemy(b, 9999.0, Vector2.RIGHT, true)
			elif seg_t > 3.0:
				_next_boss("beacon", "portals", "boss4")
		"beacon":
			var b = main.boss
			if b != null:
				if calm >= 3 and (b.phase == "grid" or (b.phase == "grid_aim" and b.phase_t < 0.3)):
					snap("beacon_grid")
				if calm >= 3 and b.strikes.size() >= 3:
					snap("beacon_strike")
			if seg_t > 10.0:
				_next_boss("hydra", "open", "boss5")
		"hydra":
			var b = main.boss
			if b != null and seg_t > 3.0 and calm >= 3 and (b.phase == "volley_aim" or b.phase == "coil" or b.phase == "spit"):
				snap("hydra")
			if seg_t > 10.0:
				_finish()
	if main.state == main.State.PLAYING:
		_pilot(p, delta)
	# macOS stops drawing a window it considers hidden (covered, other Space, display asleep);
	# force the frame so Movie Maker never records a frozen picture.
	RenderingServer.force_draw(false)
	if dump_frames:
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_jpg(OUT + "frames/%05d.jpg" % frame_i, 0.92)
		for n in main.sfx.events:
			sfx_log.append([frame_i, n])
		main.sfx.events.clear()
		frame_i += 1


func _finish() -> void:
	if dump_frames:
		var f := FileAccess.open(OUT + "sfx_log.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"fps": 60, "frames": frame_i, "events": sfx_log}))
		f.close()
	get_tree().quit()


func _next_boss(next_seg: String, layout: String, kind: String) -> void:
	for e in main.enemies + main.new_enemies:
		e.dead = true
	for b in main.bullets + main.new_bullets:
		b.dead = true
	main.spawn_queue.clear()
	main.spawn_markers.clear()
	main.boss = null
	main.intermission = 9999.0
	main.arena.set_layout(layout, true)
	var C: Vector2 = main.arena.CENTER
	bot_pos = C + Vector2(0, 230)
	main.player.position = bot_pos
	main.snap_camera()
	var e = main._spawn_enemy(kind, main.resolve_static(C + Vector2(-80, -150), 60))
	e.boss_phase = 2
	if kind == "boss5":
		e.boss_phase = 3
	main.hud.announce(main.t("boss_" + kind), e.color.lightened(0.2))
	seg = next_seg
	seg_t = 0.0


## A simple pilot: aim at the nearest enemy with lead, keep fighting distance, sidestep incoming
## shots and boss telegraphs, dash through close calls.
func _pilot(p: Node2D, delta: float) -> void:
	var C: Vector2 = main.arena.CENTER
	var target: Node2D = null
	var best := INF
	for e in main.enemies:
		if e.dead or e.type == "mine":
			continue
		var d: float = e.position.distance_to(bot_pos)
		if e.is_boss:
			d *= 0.6
		if d < best:
			best = d
			target = e
	var aim: Vector2 = p.aim
	if target:
		var lead: Vector2 = target.vel * (best / 900.0)
		aim_target = target.position + lead
		aim = (aim_target - bot_pos).normalized()
	var push := Vector2.ZERO
	for e in main.enemies:
		if e.dead:
			continue
		var d: Vector2 = bot_pos - e.position
		var l := maxf(d.length(), 1.0)
		var r: float = (360.0 if e.is_boss else 200.0) + e.radius * 2.0
		if l < r:
			push += d / l * (r - l) / r * 2.2
		for s in e.segs:
			var ds: Vector2 = bot_pos - s
			if ds.length() < 90.0:
				push += ds.normalized() * (1.0 - ds.length() / 90.0) * 1.5
	var danger := false
	for b in main.bullets:
		if b.dead or b.from_player:
			continue
		var rel: Vector2 = bot_pos - b.position
		var l := rel.length()
		if l < 170.0 and b.vel.dot(rel) > 0.0:
			var side: Vector2 = b.vel.orthogonal().normalized()
			push += side * signf(rel.dot(side) + 0.01) * 1.6 * (1.0 - l / 170.0)
			if l < 48.0:
				danger = true
	var boss = main.boss
	if boss != null and not boss.dead:
		for s in boss.strikes:
			var ds: Vector2 = bot_pos - Vector2(s.x, s.y)
			if ds.length() < boss.STRIKE_R + 40.0:
				push += ds.normalized() * 3.0
		for ln in boss.lines:
			var off: float = (bot_pos.x if ln.x == 0 else bot_pos.y) - ln.y
			if absf(off) < 60.0:
				var n := Vector2(signf(off + 0.01), 0) if ln.x == 0 else Vector2(0, signf(off + 0.01))
				push += n * 3.0
		if boss.type == "boss3" and boss.phase == "aim":
			var cd: Vector2 = boss.charge_dir
			var rel: Vector2 = bot_pos - boss.position
			var lat := rel - cd * rel.dot(cd)
			if lat.length() < boss.radius + 70.0 and rel.dot(cd) > 0:
				push += (lat.normalized() if lat.length() > 1.0 else cd.orthogonal()) * 3.0
	# Keep moving: circle the fight, drift back from the walls.
	var tangent := (bot_pos - (target.position if target else C)).orthogonal().normalized()
	push += tangent * 0.55
	push += (C - bot_pos) / 900.0
	var mv := push.normalized() if push.length() > 0.1 else tangent
	if danger and p.dash_cd <= 0 and p.dash_t <= 0:
		dash_seq += 1
	# Integrate the pilot's own position; the remote ship follows it.
	if p.dash_t > 0:
		bot_pos += p.dash_dir * p.DASH_SPEED * delta
	else:
		bot_pos += mv * p.move_speed() * delta
	bot_pos = main.resolve_static(bot_pos, p.radius)
	# Short pauses in fire during the later boss segments leave unflashed frames for stills.
	var firing: bool = target != null and not ((seg == "comet" or seg == "beacon" or seg == "hydra") and fmod(seg_t, 1.2) > 0.85)
	p.net_in = {"mv": mv, "aim": aim, "fire": firing, "dash": dash_seq, "pos": bot_pos}
	main.pointer_override = main.world_to_hud(aim_target) if target else null
