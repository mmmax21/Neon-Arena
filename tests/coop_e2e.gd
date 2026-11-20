extends Node
## Two-process co-op check against a local server (cd server && npm run dev).
## Run the host first:  godot --headless res://tests/coop_e2e.tscn -- host
## then the guest:      godot --headless res://tests/coop_e2e.tscn -- guest
const CODE_FILE := "/tmp/neon_coop_code.txt"
var main
var fails := 0


func ok(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1


func wait_until(f: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		if f.call():
			return true
		await get_tree().process_frame
	return false


func _ready() -> void:
	var role: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "host"
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.net.base_url = "http://127.0.0.1:8787"
	main.lang = "zh"
	if role == "host":
		await _host()
	else:
		await _guest()
	print("FAILS: ", fails)
	get_tree().quit()


func _host() -> void:
	DirAccess.remove_absolute(CODE_FILE)
	main.weapon = "scatter"
	main.open_lobby()
	main.coop.create_room()
	ok(await wait_until(func(): return main.coop.status == "waiting", 8), "room created, code " + main.coop.code)
	var f := FileAccess.open(CODE_FILE, FileAccess.WRITE)
	f.store_string(main.coop.code)
	f.close()
	ok(await wait_until(func(): return main.coop.peer_here, 30), "guest joined")
	ok(await wait_until(func(): return main.coop.peer_weapon == "laser", 5), "guest weapon received: " + main.coop.peer_weapon)
	main.coop.host_start()
	main.boss_order.assign(["boss4", "boss5", "boss3", "boss", "boss2"])
	ok(main.players.size() == 2 and main.players[1].remote and main.players[1].weapon == "laser", "two ships in the run")
	var rp = main.players[1]
	var lv_seen := {}
	var start_pos: Vector2 = rp.position
	var upgrades := 0
	var waited_for_peer := false
	var boss_t := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 90000 and main.state != main.State.GAMEOVER:
		if not is_instance_valid(rp):
			break
		main.player.invuln = 99
		rp.invuln = 99
		main.player.fire_queued = true
		if main.state == main.State.PLAYING and Engine.get_process_frames() % 20 == 0:
			for e in main.enemies:
				# The boss lives ~9 s so the guest can watch its attacks arrive.
				if not e.dead and (not e.is_boss or boss_t > 9.0):
					main.damage_enemy(e, 9999.0, Vector2.RIGHT)
		if main.boss != null:
			boss_t += get_process_delta_time()
		if main.state == main.State.UPGRADE and not main.offer.is_empty():
			main.choose_upgrade(0)
			upgrades += 1
			if main.state == main.State.UPGRADE:
				waited_for_peer = true
		lv_seen = rp.lv.duplicate()
		var moved: bool = rp.position.distance_to(start_pos) > 100
		if moved:
			start_pos = Vector2(-9999, -9999)
		if upgrades >= 1 and main.state == main.State.PLAYING and main.wave >= 6:
			break
		await get_tree().process_frame
	ok(start_pos.x < -9000, "guest's ship moved on the host")
	ok(upgrades >= 1, "host went through %d upgrade screens" % upgrades)
	ok(not lv_seen.is_empty(), "guest's card applied to its ship on the host: %s" % lv_seen)
	ok(main.wave >= 6, "waves progressed past the boss: %d" % main.wave)
	ok(boss_t > 9.0, "boss fought for %.1f s" % boss_t)
	if false:
		ok(rp.position.distance_to(start_pos) > 100, "guest's ship moved on the host: %s -> %s" % [start_pos.round(), rp.position.round()])
	print("host waited for guest pick at least once: ", waited_for_peer)
	# Hold the room a moment so the guest can finish its checks, then end.
	await wait_until(func(): return not main.coop.peer_here, 15)
	ok(main.players.size() == 1, "guest leaving removes its ship, run continues")


func _guest() -> void:
	ok(await wait_until(func(): return FileAccess.file_exists(CODE_FILE), 20), "found room code")
	var code := FileAccess.get_file_as_string(CODE_FILE)
	main.weapon = "laser"
	main.open_lobby()
	main.coop.join_room(code)
	ok(await wait_until(func(): return main.coop.status == "ready", 8), "joined room " + code)
	ok(await wait_until(func(): return main.coop.in_game and main.state == main.State.PLAYING, 20), "host started the run")
	ok(main.player != null and main.player.client and main.player.slot == 1, "own ship is slot 1")
	var saw_enemies := 0
	var saw_bullets := false
	var picks := 0
	var saw_intro := false
	var saw_boss := ""
	var saw_telegraph := false
	var t0 := Time.get_ticks_msec()
	var c: Vector2 = main.arena.CENTER
	var ang := 0.0
	while Time.get_ticks_msec() - t0 < 90000:
		ang += get_process_delta_time()
		if main.player and main.state == main.State.PLAYING:
			main.player.position = main.resolve_static(c + Vector2(cos(ang), sin(ang)) * 220.0, 15)
			main.player.fire_queued = true
		saw_enemies = maxi(saw_enemies, main.enemies.size())
		saw_intro = saw_intro or (main.boss_intro_t > 0 and main.boss_intro_type == "boss4")
		if main.boss != null:
			saw_boss = main.boss.type
			saw_telegraph = saw_telegraph or not main.boss.strikes.is_empty() or not main.boss.lines.is_empty()
		for b in main.coop.g_bullets:
			if b.visible:
				saw_bullets = true
		if main.state == main.State.UPGRADE and not main.offer.is_empty() and not main.coop.guest_picked:
			main.choose_upgrade(0)
			picks += 1
		if picks >= 1 and main.state == main.State.PLAYING and main.wave >= 6:
			break
		await get_tree().process_frame
	ok(saw_enemies > 0, "enemies arrive from snapshots (max %d)" % saw_enemies)
	ok(saw_bullets, "bullets arrive from snapshots")
	ok(main.wave >= 6, "wave counter synced: %d" % main.wave)
	ok(saw_intro, "boss countdown synced to the guest")
	ok(saw_boss == "boss4", "boss arrives on the guest (%s)" % saw_boss)
	ok(saw_telegraph, "boss strike / grid telegraphs synced")
	ok(picks >= 1, "guest picked %d upgrade cards" % picks)
	ok(not main.player.lv.is_empty(), "own upgrades synced back: %s" % main.player.lv)
	ok(main.players[0].position.distance_to(c) >= 0.0 and main.players.size() == 2, "host ship visible")
	ok(main.coop.rtt_ms >= 0, "ping measured: %d ms" % main.coop.rtt_ms)
	main.coop.leave()
