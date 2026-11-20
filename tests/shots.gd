extends Node

var main: Node2D
var tag := ""


func snap(name: String) -> void:
	if main.state == main.State.PAUSED and not name.begins_with("pause"):
		main.state = main.State.PLAYING
	main.hud.queue_redraw()
	main.touch.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/s_%s_%s.png" % [tag, name])


func run(n: int) -> void:
	for i in n:
		if main.state == main.State.PAUSED:
			main.state = main.State.PLAYING
		main.update_game(1.0 / 60.0)
		await get_tree().process_frame


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	tag = args[0] if args.size() > 0 else "pc"
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.lang = "zh"
	main.touch.active = tag == "phone"
	main.set_process(false)
	await get_tree().process_frame
	main.state = main.State.TITLE
	await snap("title")
	main.start_game()
	main.intermission = 9999.0
	main.player.invuln = 9999.0
	main.player.lv = {"power": 2, "rapid": 1, "vital": 2, "shield": 1, "quick": 3, "shock": 1}
	main.player.max_hp = 8
	main.score = 123450
	main.wave = 7
	await run(5)
	await snap("hud")
	if tag == "phone":
		main.state = main.State.PAUSED
		await snap("pause")
		get_tree().quit()
		return
	main.state = main.State.PAUSED
	await snap("pause")
	main.state = main.State.PLAYING
	for id in ["fortress", "ring", "portals"]:
		main.arena.set_layout(id)
		main.hud.announce(main.t("arena_shift") % main.arena.display_name(), Color(1, 0.85, 0.35))
		await run(30)
		await snap("preview_" + id)
	for i in 4:
		main.arena.gen_pending = {}
		main.arena._use("gen")
		main.arena.set_layout("gen", true)
		await run(2)
		await snap("gen%d" % i)
	get_tree().quit()
