extends Node
func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.touch.active = true
	main.touch.mode = "auto"
	main.weapon = "pulse"
	main.start_game()
	var layouts := []
	var t := 0.0
	while main.wave < 17 and t < 900.0:
		main.player.invuln = 999.0
		main.player.hp = main.player.max_hp
		if main.state == main.State.UPGRADE:
			main.card_lock = 0
			main.choose_upgrade(0)
		elif main.state == main.State.PLAYING:
			main.update_game(1.0 / 30.0)
		var tag: String = "%d:%s" % [main.wave, main.arena.layout]
		if layouts.is_empty() or layouts[-1] != tag:
			layouts.append(tag)
		t += 1.0 / 30.0
		if t > 200.0 and fmod(t, 100.0) < 1.0 / 30.0:
			var left := []
			for e in main.enemies:
				if not e.dead:
					left.append("%s hp%.0f sh%.0f el:%s ph:%s pos%s" % [e.type, e.hp, e.shield, e.elite, e.phase, str(e.position.round())])
			print("t=", int(t), " queue=", main.spawn_queue.size(), " markers=", main.spawn_markers.size(), " target=", main.touch.target.type if main.touch.target else "none", " left=", left, " pl=", main.player.position.round(), " state=", main.state, " inter=", main.intermission, " clear=", main.clear_timer, " boss_t=", main.boss_shift_t, " new_en=", main.new_enemies.size())
	print("reached wave ", main.wave, " in ", int(t), " s sim; layouts: ", layouts)
	get_tree().quit()
