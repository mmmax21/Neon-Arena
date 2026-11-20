extends Node

var main: Node2D
var fails := 0


func ok(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var ar = main.arena
	# hand-made layout classes as measured by the generator's metric
	for id in ar.LAYOUTS:
		print("measured class ", id, ": ", ar._measure_class(ar._layout_data(id)), "  (table: ", ar.LAYOUT_CLASS[id], ")")
	main.start_game()
	main.intermission = 9999.0
	# --- boss arenas
	main.wave = 4
	main.waves_since_upgrade = 0
	ar.set_layout("cross", true)
	main._on_wave_clear()
	ok(main.boss_shift_t > 0, "clearing wave 4 schedules the boss arena")
	for i in 60:
		main._update_waves(1.0 / 60.0)
	ok(ar.layout == ar.BOSS_LAYOUTS[main.boss_type(5)], "wave 5 boss %s gets its arena (%s)" % [main.boss_type(5), ar.layout])
	ok(main.hud.announce_text.contains(ar.display_name()), "boss arena announced: " + main.hud.announce_text)
	main.intermission = 0.0
	main.wave = 9
	ar.set_layout("ring" if ar.BOSS_LAYOUTS[main.boss_type(10)] != "ring" else "cross", true)
	main.offer = ["bonus", "bonus", "bonus"] as Array[String]
	main.state = main.State.UPGRADE
	main.choose_upgrade(0)
	ok(ar.layout == ar.BOSS_LAYOUTS[main.boss_type(10)], "upgrade before wave 10 -> %s arena (%s)" % [main.boss_type(10), ar.layout])
	main.wave = 6
	ar.set_layout("open", true)
	main.offer = ["bonus", "bonus", "bonus"] as Array[String]
	main.state = main.State.UPGRADE
	main.choose_upgrade(0)
	ok(ar.layout != "open", "normal upgrade shifts to a new layout (%s)" % ar.layout)
	main.wave = 14
	main.waves_since_upgrade = 1
	ar.set_layout("ring", true)
	main.intermission = 0
	main._on_wave_clear()
	for i in 60:
		main._update_waves(1.0 / 60.0)
	ok(ar.layout == ar.BOSS_LAYOUTS[main.boss_type(15)], "wave 15 boss %s -> its arena (%s)" % [main.boss_type(15), ar.layout])
	# --- boss order: each run shuffles all five; no back-to-back repeat across cycles
	var order: Array = []
	for w in range(5, 55, 5):
		order.append(main.boss_type(w))
	print("boss order: ", order)
	var first5 := order.slice(0, 5)
	first5.sort()
	ok(first5 == ["boss", "boss2", "boss3", "boss4", "boss5"], "first cycle meets all five bosses")
	var rep := false
	for i in order.size() - 1:
		rep = rep or order[i] == order[i + 1]
	ok(not rep, "no boss twice in a row")
	# --- contrast rule
	ar.bag.clear()
	ar.set_layout("classic", true)
	var same := 0
	var repeats := 0
	var gens := 0
	var seq: Array = []
	var prev_class: String = ar.layout_class(ar.layout)
	var prev: String = ar.layout
	for i in 120:
		var nx: String = ar.shift_next()
		var c: String = ar.layout_class(nx)
		if c == prev_class:
			same += 1
		if nx == prev and nx != "gen":
			repeats += 1
		if nx == "gen":
			gens += 1
		if i < 16:
			seq.append(nx + "/" + c)
		prev_class = c
		prev = nx
	print("sequence: ", seq)
	ok(repeats == 0, "never the same hand-made layout twice in a row")
	ok(same <= 12, "same-class transitions rare (%d / 120)" % same)
	ok(gens >= 20, "generated layouts appear (%d / 120)" % gens)
	# --- generator
	var t0 := Time.get_ticks_msec()
	var classes := {}
	var fallback := 0
	var feats := {"fences": 0, "belts": 0, "portals": 0, "blocks": 0}
	var worst_reach := 0.0
	for i in 300:
		var d: Dictionary = ar.generate()
		classes[d["class"]] = int(classes.get(d["class"], 0)) + 1
		if d["pillars"] == ar._layout_data("classic")["pillars"]:
			fallback += 1
		for k in feats:
			if not d[k].is_empty():
				feats[k] += 1
		if not ar._gen_valid(d) and d["pillars"] != ar._layout_data("classic")["pillars"]:
			ok(false, "generated layout failed its own check")
	var ms := Time.get_ticks_msec() - t0
	print("classes: ", classes, " features: ", feats, " fallbacks: ", fallback, " avg ms: ", ms / 300.0)
	ok(fallback <= 15, "generator rarely falls back (%d / 300)" % fallback)
	ok(ms / 300.0 < 60.0, "generation is quick (%.1f ms each)" % (ms / 300.0))
	ok(classes.size() >= 2, "generated layouts vary in openness")
	# spot-check constraints on 50 layouts
	var bad := 0
	for i in 50:
		var d: Dictionary = ar.generate()
		var solids: Array = d["pillars"] + d["blocks"]
		for a in solids:
			if Vector2(a.x, a.y).distance_to(ar.CENTER) < ar.GEN_CENTER_CLEAR + a.z - 0.01:
				bad += 1
			for b in solids:
				if a == b:
					continue
				var gap: float = Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.z - b.z
				if gap > 4.0 and gap < ar.GEN_PASSAGE - 0.01:
					bad += 1
	ok(bad == 0, "no narrow gaps or blocked centre in 50 samples")
	# names / hints
	ar.gen_pending = {}
	ar._use("gen")
	ok(ar.display_name().contains("#"), "generated layout name: " + ar.display_name())
	print("gen hint: '", ar.hint(), "'")
	ar.set_layout("fortress")
	ok(ar.hint() != "" and not ar.mechanisms_on(), "fortress hint while rising: " + ar.hint())
	# --- shake
	main.touch.active = false
	main.shake_setting = "full"
	main.shake = 0.0
	main.add_shake(20)
	ok(is_equal_approx(main.shake, 20.0), "full shake = 20")
	main.shake_setting = "low"
	main.shake = 0.0
	main.add_shake(20)
	ok(is_equal_approx(main.shake, 7.0), "low shake = 35%%: %.1f" % main.shake)
	main.shake_setting = "off"
	main.shake = 0.0
	main.add_shake(20)
	ok(main.shake == 0.0, "shake off")
	main.shake_setting = "full"
	main.touch.active = true
	main.shake = 0.0
	main.add_shake(20)
	ok(is_equal_approx(main.shake, 12.0), "touch shake = 60%%: %.1f" % main.shake)
	main.touch.active = false
	main.shake = 22.0
	var tt := 0.0
	while main.shake > 0.5 and tt < 3:
		main.shake *= exp(-main.SHAKE_DECAY * 0.016)
		tt += 0.016
	ok(tt > 0.4 and tt < 0.8, "big shake fades in %.2f s" % tt)
	main.state = main.State.PAUSED
	var r: Rect2 = main.hud.shake_rect()
	main.press_at(r.get_center())
	ok(main.shake_setting == "low", "pause-screen button cycles shake (%s)" % main.shake_setting)
	main.shake_setting = "full"
	main._save_setting("video", "shake", "full")
	print("FAILS: ", fails)
	get_tree().quit()
