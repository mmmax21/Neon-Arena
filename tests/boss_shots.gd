extends Node
## Screenshots of the boss countdown and each new boss mid-fight (run windowed, not headless).

var main: Node2D


func snap(name: String) -> void:
	main.hud.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/bs_%s.png" % name)


func run(n: int) -> void:
	for i in n:
		main.update_game(1.0 / 60.0)
		main.fx.update(1.0 / 60.0)
		await get_tree().process_frame


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.lang = args[0] if args.size() > 0 else "zh"
	main.set_process(false)
	main.state = main.State.TITLE
	await snap("title_" + main.lang)
	main.start_game()
	main.player.invuln = 9999.0
	main.player.max_hp = 999
	main.player.hp = 999
	main.boss_order.assign(["boss3", "boss4", "boss5", "boss", "boss2"])
	main.wave = 4
	main.intermission = 0.01
	await run(10)
	await snap("intro_warning")
	await run(40)
	await snap("intro_3")
	await run(110)
	await snap("intro_1")
	await run(70)
	await snap("arrive")
	for kind in ["boss3", "boss4", "boss5"]:
		for e in main.enemies + main.new_enemies:
			e.dead = true
		main._sweep()
		main._sweep()
		main.spawn_queue.clear()
		main.intermission = 9999.0
		main.arena.set_layout(main.arena.BOSS_LAYOUTS[kind], true)
		var C: Vector2 = main.arena.CENTER
		main.player.position = C + Vector2(0, 180)
		var e = main._spawn_enemy(kind, C + Vector2(-60, -180))
		main._sweep()
		var shots := 0
		for i in 60 * 30:
			main.player.invuln = 9999.0
			main.update_game(1.0 / 60.0)
			main.fx.update(1.0 / 60.0)
			if i % 2 == 0:
				await get_tree().process_frame
			var want := ""
			match kind:
				"boss3":
					want = "aim" if shots == 0 else "dash"
				"boss4":
					want = "strike" if shots == 0 else "grid_aim"
				"boss5":
					want = "hunt" if shots == 0 else "volley_aim"
			var hit: bool = (want == "strike" and e.strikes.size() >= 3) or (want != "strike" and e.phase == want and (want != "hunt" or i > 200))
			if hit and (want != "aim" or e.phase_t < 0.4):
				await snap("%s_%d" % [kind, shots])
				shots += 1
				if shots == 1 and kind != "boss5":
					e.boss_phase = 2
				if shots >= 2:
					break
	get_tree().quit()
