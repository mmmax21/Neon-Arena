extends Node
func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.start_game()
	main.intermission = 9999.0
	main.arena.set_layout("cross", true)
	var e = main._spawn_enemy("chaser", main.arena.CENTER + Vector2(-462, -266) + Vector2(-36, -39))
	main._sweep()
	main.player.position = (main.arena.CENTER + Vector2(462, 266) + Vector2(36, 39))
	main._update_flow()
	print("flow size ", main.flow.size(), " w ", main.flow_w, " h ", main.flow_h, " player cell ", main._flow_cell(main.player.position))
	var nb := 0
	for y in main.flow_h:
		for x in main.flow_w:
			var cc: Vector2 = main._flow_center(x, y)
			for ob in main.obstacles:
				if cc.distance_to(Vector2(ob.x, ob.y)) < ob.z + main.FLOW_CLEAR:
					nb += 1
					break
	print("blocked by test calc: ", nb, " obstacles: ", main.obstacles.size(), " first center ", main._flow_center(0, 0))
	var reached := 0
	for v in main.flow:
		if v >= 0:
			reached += 1
	print("reached cells ", reached)
	for y in main.flow_h:
		var line := ""
		for x in main.flow_w:
			var v: int = main.flow[y * main.flow_w + x]
			line += "#" if v < 0 else str(v % 10)
		print(line)
	var c: Vector2i = main._flow_cell(e.position)
	for y in range(c.y - 2, c.y + 3):
		var row := ""
		for x in range(c.x - 3, c.x + 4):
			if x < 0 or y < 0:
				row += "  ."
			else:
				row += "%4d" % main.flow[y * main.flow_w + x]
		print(row)
	for i in 300:
		main.player.position = (main.arena.CENTER + Vector2(462, 266) + Vector2(36, 39))
		e.update(1.0 / 60.0)
		if i % 30 == 0:
			print(i, " pos ", e.position.round(), " unstick ", snappedf(e.unstick_t, 0.01), " stuck_t ", snappedf(e.stuck_t, 0.01), " fd ", main.flow_dir(e.position), " vel ", e.vel.round())
	get_tree().quit()
