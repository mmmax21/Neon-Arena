extends Node
func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.start_game()
	main.intermission = 9999.0
	main.arena.set_layout("cross", true)
	var fails := 0
	var C: Vector2 = main.arena.CENTER
	var spots := []
	for sg in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		# Inside the pocket of each L-shaped cluster
		spots.append(C + sg * Vector2(330, 190) * main.arena.SCALE + sg * Vector2(36, 39))
	for spot in spots:
		for kind in ["chaser", "tank", "splitter"]:
			for e in main.enemies:
				e.dead = true
			main._sweep()
			main._sweep()
			var e = main._spawn_enemy(kind, spot)
			main._sweep()
			var target: Vector2 = C * 2.0 - spot
			var reached := false
			for i in 2700:  # tanks walk 62 px/s; the detour in the 1.4x arena is long
				main.player.position = target
				main.player.invuln = 99
				if i % 24 == 0:
					main._update_flow()
				e.update(1.0 / 60.0)
				if e.position.distance_to(target) < 120:
					reached = true
					break
			print(("PASS  " if reached else "FAIL  "), kind, " from ", spot, " reached the player: ", reached, " end ", e.position.round())
			if not reached:
				fails += 1
	print("FAILS: ", fails)
	get_tree().quit()
