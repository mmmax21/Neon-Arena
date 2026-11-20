extends Node
## Boss entrance countdown and the three newer bosses: each one's attacks fire, phases advance,
## it dies cleanly; the hydra's body blocks shots; the comet stuns on pillars.

var main: Node2D
var fails := 0
const DT := 1.0 / 60.0


func ok(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1


func clear_field() -> void:
	for e in main.enemies + main.new_enemies:
		e.dead = true
	for b in main.bullets + main.new_bullets:
		b.dead = true
	main.spawn_markers.clear()
	main.spawn_queue.clear()
	main._sweep()
	main._sweep()
	main.boss = null


func tank_player() -> void:
	main.player.max_hp = 9999
	main.player.hp = 9999


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.start_game()
	tank_player()

	# --- entrance countdown
	main.boss_order.assign(["boss3", "boss4", "boss5", "boss", "boss2"])
	main.wave = 4
	main.intermission = 0.01
	var t := 0.0
	var spawned_at := -1.0
	var saw_count := 0
	var prev_digit := 0
	while t < 6.0:
		main.update_game(DT)
		t += DT
		if main.boss_intro_t > 0 and main.boss_intro_t <= 3.0:
			var d := ceili(main.boss_intro_t)
			if d != prev_digit:
				saw_count += 1
				prev_digit = d
		if main.boss != null and spawned_at < 0:
			spawned_at = t
	ok(main.wave == 5, "wave 5 began")
	ok(saw_count == 3, "countdown shows 3, 2, 1 (%d digits)" % saw_count)
	ok(absf(spawned_at - main.BOSS_INTRO) < 0.1, "boss lands after the countdown (%.2f s)" % spawned_at)
	ok(main.boss != null and main.boss.type == "boss3", "wave 5 boss follows the run's order")
	ok(main.boss != null and main.boss.position.distance_to(main.player.position) >= 149.0, "landing never on top of the player")
	ok(main.spawn_queue.size() > 0 or main.field_count() > 0, "escorts still queued / arriving after the boss")

	# --- each boss in its arena (hp lost against a strafing circle is printed as a rough
	# difficulty signal; only the total is checked, since single runs vary)
	var total_hurt := 0.0
	for kind in ["boss3", "boss4", "boss5", "boss", "boss2"]:
		clear_field()
		main.arena.set_layout(main.arena.BOSS_LAYOUTS[kind], true)
		main.intermission = 9999.0
		main.wave = 15
		tank_player()
		var C: Vector2 = main.arena.CENTER
		main.player.position = C + Vector2(0, 200)
		var e = main._spawn_enemy(kind, main.resolve_static(C + Vector2(0, -220), 60))
		main._sweep()
		var phases := {}
		var max_phase := 1
		var max_bullets := 0
		var stuns := 0
		var dashes := 0
		var detonations := 0
		var grids := 0
		var prev_phase := ""
		var prev_strikes := 0
		var hp0: float = main.player.hp
		var orbit := 0.0
		for i in 60 * 45:
			orbit += DT * 0.9
			# A player strafing in a wide circle
			main.player.position = main.resolve_static(C + Vector2.from_angle(orbit) * 300.0, 15)
			main.player.vel = Vector2.from_angle(orbit + PI / 2) * 270.0
			main.update_game(DT)
			if e.dead:
				break
			if i % 360 == 359 and not e.invulnerable():
				main.damage_enemy(e, e.max_hp * 0.2, Vector2.RIGHT, true)
			phases[e.phase] = true
			max_phase = maxi(max_phase, e.boss_phase)
			var nb := 0
			for b in main.bullets:
				if not b.dead and not b.from_player:
					nb += 1
			max_bullets = maxi(max_bullets, nb)
			if e.phase != prev_phase:
				if e.phase == "stun":
					stuns += 1
				if e.phase == "dash":
					dashes += 1
				if e.phase == "grid":
					grids += 1
				prev_phase = e.phase
			if e.strikes.size() < prev_strikes:
				detonations += prev_strikes - e.strikes.size()
			prev_strikes = e.strikes.size()
		var hurt: float = hp0 - main.player.hp
		print(kind, ": phases ", phases.keys(), " max boss phase ", max_phase, " peak bullets ", max_bullets, " player hp lost ", hurt)
		ok(max_phase == 3, kind + " reached phase 3")
		ok(e.dead, kind + " died from damage")
		ok(main.boss == null, kind + " cleared the boss slot on death")
		ok(max_bullets > 5, kind + " fires (%d bullets peak)" % max_bullets)
		total_hurt += hurt
		match kind:
			"boss3":
				ok(dashes >= 3, "comet dashed (%d)" % dashes)
				ok(phases.has("aim") and phases.has("stalk"), "comet aims and stalks")
			"boss4":
				ok(detonations >= 3, "beacon strikes detonated (%d)" % detonations)
				ok(grids >= 1, "beacon fired laser grids (%d)" % grids)
			"boss5":
				ok(phases.has("spit") and phases.has("volley_aim") and phases.has("coil"), "hydra uses spit / broadside / coil")

	ok(total_hurt >= 5, "bosses land hits on a strafing player (%d total)" % total_hurt)

	# --- comet stuns when it dashes into a pillar, and takes double damage
	clear_field()
	main.arena.set_layout("fortress", true)
	var CC: Vector2 = main.arena.CENTER
	var c3 = main._spawn_enemy("boss3", CC + Vector2(-260, 0))
	main._sweep()
	c3.charge_dir = Vector2.RIGHT
	c3.phase = "dash"
	c3.dash_dist = 0.0
	main.player.position = CC + Vector2(0, 300)
	for i in 120:
		c3.update(DT)
		if c3.phase != "dash":
			break
	ok(c3.phase == "stun", "comet dashing into the centre pillar is stunned (%s)" % c3.phase)
	var hpb: float = c3.hp
	main.damage_enemy(c3, 2.0, Vector2.RIGHT, true)
	ok(is_equal_approx(hpb - c3.hp, 4.0), "stunned comet takes double damage (%.1f)" % (hpb - c3.hp))

	# --- hydra body blocks player shots; the head takes them
	clear_field()
	main.arena.set_layout("open", true)
	var h = main._spawn_enemy("boss5", CC + Vector2(-200, 0))
	main._sweep()
	main.player.position = CC + Vector2(400, 0)
	for i in 120:
		h.update(DT)
	var seg: Vector2 = h.segs[8]
	var hp_before: float = h.hp
	var b = main.spawn_bullet(seg + Vector2(0, -80), Vector2(0, 600), true, 5, 5, Color.WHITE)
	main._sweep()
	for i in 30:
		main._update_bullets(DT)
		main._sweep()
	ok(b.dead, "shot into the hydra's body is stopped")
	ok(h.hp == hp_before, "hydra body takes no damage (%.1f -> %.1f)" % [hp_before, h.hp])
	main.damage_enemy(h, 5.0, Vector2.RIGHT, true)
	ok(h.hp < hp_before, "hydra head takes damage")

	print("FAILS: ", fails)
	get_tree().quit()
