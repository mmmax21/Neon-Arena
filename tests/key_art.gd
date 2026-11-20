extends Node
## Store key art: stages the game's own ships, bosses and bullet patterns in one composed scene
## and renders it at any size by stitching window-sized tiles (the scene is frozen, so tiles
## line up exactly). Title and glow are added afterwards by tools/store_art.py. Usage:
##   godot --path . tests/key_art.tscn -- <variant> <width> <height> <out.png>
## variant: wide (16:9), square (1:1), tall (2:3), icon

var main: Node2D
var view_w := 1320.0  # world units across the output; set by _stage with the camera centre


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var variant: String = args[0] if args.size() > 0 else "wide"
	var out_size := Vector2i(int(args[1]) if args.size() > 1 else 3840, int(args[2]) if args.size() > 2 else 2160)
	var out: String = args[3] if args.size() > 3 else "/tmp/keyart/raw_%s.png" % variant
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)  # frames are forced below
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED  # 1 px = 1 unit at zoom 1
	get_viewport().msaa_2d = Viewport.MSAA_4X
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.net.base_url = ""
	main.lang = "en"
	main.start_game()
	main.set_process(false)
	main.hud.visible = false
	main.touch.visible = false
	main.arena.set_layout("open", true)
	var C: Vector2 = main.arena.CENTER
	_stage(variant, C)
	for i in 6:
		main.fx.update(1.0 / 60.0)
		await get_tree().process_frame
	var cam: Camera2D = main.camera
	cam.offset = Vector2.ZERO
	var centre := cam.position
	RenderingServer.force_draw(false)
	var tile: Vector2i = get_viewport().get_texture().get_image().get_size()
	var s := out_size.x / view_w  # output pixels per world unit
	var top_left := centre - Vector2(out_size) / s / 2.0
	var cols := ceili(float(out_size.x) / tile.x)
	var rows := ceili(float(out_size.y) / tile.y)
	cam.zoom = Vector2(s, s)
	var tiles: Array = []
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	for j in rows:
		for i in cols:
			cam.position = top_left + Vector2((i + 0.5) * tile.x, (j + 0.5) * tile.y) / s
			cam.force_update_scroll()
			RenderingServer.force_draw(false)  # also draws while the window is hidden
			RenderingServer.force_draw(false)
			var path := out.get_basename() + "_tile_%d_%d.png" % [i, j]
			get_viewport().get_texture().get_image().save_png(path)
			tiles.append([i * tile.x, j * tile.y, path])
	# tools/store_art.py stitches the tiles and crops to the output size.
	var f := FileAccess.open(out.get_basename() + "_tiles.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"size": [out_size.x, out_size.y], "tiles": tiles}))
	f.close()
	print("saved tiles for ", out, " ", out_size, " ", cols, "x", rows, " of ", tile)
	get_tree().quit()


func _stage(variant: String, C: Vector2) -> void:
	var cam: Camera2D = main.camera
	var p = main.player
	var ship := C + Vector2(-300, 120)
	var warden_at := C + Vector2(250, -30)
	match variant:
		"square":
			ship = C + Vector2(-190, 200)
			warden_at = C + Vector2(150, -60)
		"tall":
			ship = C + Vector2(-40, 250)
			warden_at = C + Vector2(40, -60)
		"icon":
			ship = C
			warden_at = C + Vector2(400, -400)
	# Player: dashing in from the lower left, ghost trail behind, a stream of shots ahead.
	p.position = ship
	var to_w := (warden_at - ship).normalized()
	p.aim = to_w
	p.queue_redraw()
	if variant == "icon":
		# Close-up: the ship firing, a few enemy shots in the lower corner for contrast.
		for i in range(1, 3):
			main.spawn_bullet(ship + to_w * (24.0 + i * 15.0), to_w * 600.0, true, 1, 4, Color(0.5, 1, 1))
		for off in [Vector2(16, 36), Vector2(30, 31), Vector2(41, 21)]:
			main.spawn_bullet(ship + off, Vector2.LEFT * 200.0, false, 1, 4, Color(1, 0.4, 0.75))
		main.fx.rings.clear()
		cam.position = ship + Vector2(4, 2)
		view_w = 100.0
		return
	for i in range(1, 7):
		main.fx.ghost(ship - to_w.rotated(0.5) * i * 26.0, p.ship_color(), p.radius)
	for i in range(1, 11):
		var bp := ship + to_w * (34.0 + i * 38.0) + to_w.orthogonal() * sin(i * 1.7) * 8.0
		if bp.distance_to(warden_at) > 70.0:
			main.spawn_bullet(bp, to_w * 600.0, true, 1, 5, Color(0.5, 1, 1))
	# CORE WARDEN with its satellites and a double bullet ring.
	var w = main._spawn_enemy("boss", warden_at)
	w.boss_phase = 2
	w.spin = 0.6
	w.facing = (ship - warden_at).angle()
	w.queue_redraw()
	var ring_n := 22
	for k in 2:
		var rr := 125.0 + k * 75.0
		for i in ring_n:
			var a := TAU * i / ring_n + k * 0.14
			main.spawn_bullet(warden_at + Vector2.from_angle(a) * rr, Vector2.from_angle(a) * 210.0, false, 1, 8, Color(1, 0.4, 0.75))
	# NEON HYDRA winding along the bottom right.
	var h = main._spawn_enemy("boss5", C)
	var head := C + Vector2(330, 240)
	if variant == "tall":
		head = C + Vector2(170, 360)
	if variant == "square":
		head = C + Vector2(300, 300)
	if variant == "tall":
		head = C + Vector2(170, 360)
	h.position = head
	h.facing = PI * 1.12
	h.boss_phase = 2
	h.segs.clear()
	for i in h.HYDRA_SEGS:
		var s := head + Vector2(i * 30.0 + 30.0, sin(i * 0.55) * 46.0).rotated(0.15)
		h.segs.append(s)
	h.queue_redraw()
	# RAZOR COMET lining up a dash at the ship (wide / square only).
	if variant != "tall":
		var c_at := C + Vector2(-560, -230) if variant == "wide" else C + Vector2(-350, -170)
		var c = main._spawn_enemy("boss3", c_at)
		c.phase = "aim"
		c.phase_t = 0.2
		c.charge_dir = (ship + Vector2(60, -40) - c_at).normalized()
		c.facing = c.charge_dir.angle()
		c.beam_len = c_at.distance_to(ship) + 140.0
		c.boss_phase = 2
		c.queue_redraw()
	# Small fry closing in.
	var fry := [["chaser", Vector2(-80, -170)], ["chaser", Vector2(40, 260)], ["shooter", Vector2(-470, 260)],
		["dodger", Vector2(520, -230)], ["chaser", Vector2(-20, 330)], ["shooter", Vector2(560, 60)]]
	for f in fry:
		var e = main._spawn_enemy(f[0], C + f[1])
		e.facing = (ship - e.position).angle()
		e.queue_redraw()
	# Hits and sparks for energy (after dropping the engine's spawn rings).
	main.fx.rings.clear()
	main.fx.burst(warden_at + Vector2(-60, 30), Color(1, 0.5, 0.8), 30, 260, 3.5, 0.6)
	main.fx.burst(C + Vector2(-90, -160), Color(1, 0.4, 0.45), 24, 220, 3.0, 0.5)
	main.fx.ring(ship, 70, Color(0.4, 0.95, 1), 0.4)
	match variant:
		"wide":
			cam.position = C + Vector2(-10, -60)
			view_w = 1320.0
		"square":
			cam.position = C + Vector2(-20, -10)
			view_w = 900.0
		"tall":
			cam.position = C + Vector2(20, 0)
			view_w = 560.0
