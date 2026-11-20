extends Node2D
## Arena layouts and their mechanisms: crystal blocks, laser fences, conveyors, portals.
## Owns the pillars; main.gd collides against main.obstacles, rebuilt here from solid elements.
## Layouts swap after every upgrade pick: old pillars fade, new ones warn, then rise.

const WARN_TIME := 1.2
const FADE_TIME := 0.6
const RISE_TIME := 0.25
const BELT_SPEED := 150.0
const FENCE_PERIOD := 6.0
const FENCE_WARN := 0.6
const PORTAL_R := 30.0
const BLOCK_HP := 8.0
const LAYOUTS := ["classic", "cross", "ring", "fortress", "portals", "open"]
## Rotation pool: the six hand-made layouts plus two generated ones per cycle.
const POOL := ["classic", "cross", "ring", "fortress", "portals", "open", "gen", "gen"]
## Openness class of each layout; the next layout prefers a different class than the current
## one so tight and open spaces alternate (Totten, "arrivals"). Generated layouts are measured.
const LAYOUT_CLASS := {"open": "open", "classic": "mid", "portals": "mid", "fortress": "mid",
	"ring": "tight", "cross": "tight"}
## Boss waves always play on the layout built for that boss.
## RAZOR COMET slams into the fortress pillars; STORM BEACON's grids leave the portals as
## escape hatches; NEON HYDRA needs the open field to wind through.
const BOSS_LAYOUTS := {"boss": "open", "boss2": "classic", "boss3": "fortress", "boss4": "portals",
	"boss5": "open"}
# Generator constraints (player radius 15, dash ~140 px, run ~290 px/s)
const GEN_PASSAGE := 60.0      # narrowest gap between separate obstacles / walls
const GEN_COVER_REACH := 480.0 # every spot within one dash + ~1 s run of a pillar (1.4× arena)
const GEN_CENTER_CLEAR := 90.0
const GEN_TRIES := 160
## Arena is 1.4× the original single-screen field (see main.ARENA); the camera follows.
const SCALE := 1.4
const CENTER := Vector2(884, 492)
const PILLAR_COL := Color(0.6, 0.45, 1.0)
const BLOCK_COL := Color(0.55, 0.9, 1.0)
const FENCE_COL := Color(1, 0.3, 0.5)
const BELT_COL := Color(1, 0.65, 0.25)
const PORTAL_COLS := [Color(0.4, 0.8, 1), Color(1, 0.5, 0.9)]

var main: Node2D
var layout := "classic"
var elements: Array = []  # {kind, p, r, state: warn/solid/fade, t, rise, hp, max_hp, flash}
var refs: Array = []  # main.obstacles index -> element
var fences: Array = []  # {a, b, group}
var belts: Array = []  # {rect, dir}
var portals: Array = []  # two Vector2
var mech_delay := 0.0  # mechanisms switch on once the new layout has risen
var mech_t := 0.0
var fence_tick := 0.0
var portal_cd := {}  # instance id -> seconds until it can teleport again
var bag: Array = []
var gen_data := {}      # data of the current / pending generated layout
var gen_pending := {}   # generated but not yet used (rejected by the contrast rule)
var gen_count := 0
var gen_rng := RandomNumberGenerator.new()
var t := 0.0


## Hand-made layouts are authored on the original 1280×720 frame; _m() maps an anchor onto
## the enlarged arena. Cluster offsets stay unscaled so touching walls stay closed.
func _m(x: float, y: float) -> Vector2:
	return main.ARENA.position + (Vector2(x, y) - Vector2(30, 30)) * SCALE


func _mp(x: float, y: float, r: float) -> Vector3:
	var p := _m(x, y)
	return Vector3(p.x, p.y, r)


func _layout_data(id: String) -> Dictionary:
	var d := {"pillars": [], "blocks": [], "fences": [], "belts": [], "portals": []}
	var ar: Rect2 = main.ARENA
	match id:
		"gen":
			return gen_data
		"classic":
			d["pillars"] = [_mp(300, 210, 46), _mp(980, 210, 46), _mp(300, 510, 46),
				_mp(980, 510, 46), _mp(640, 140, 30), _mp(640, 580, 30),
				_mp(470, 360, 26), _mp(810, 360, 26)]
		"cross":
			# Four L-shaped clusters leave cross-shaped corridors; crystals dot the corridors.
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var c := CENTER + Vector2(sx * 330, sy * 190) * SCALE
					d["pillars"].append(Vector3(c.x, c.y, 40))
					d["pillars"].append(Vector3(c.x + sx * 72, c.y, 32))
					d["pillars"].append(Vector3(c.x, c.y + sy * 66, 32))
					d["pillars"].append(Vector3(c.x + sx * 136, c.y, 32))  # longer arm along x only:
					# a y extension would leave a slit by the wall too narrow for tanks
			for p in [Vector2(640, 250), Vector2(640, 470), Vector2(500, 360), Vector2(780, 360),
					Vector2(640, 145), Vector2(640, 575), Vector2(230, 360), Vector2(1050, 360)]:
				var q := _m(p.x, p.y)
				d["blocks"].append(Vector3(q.x, q.y, 22))
		"ring":
			var ring: Array = []
			for i in 8:
				var p := CENTER + Vector2.from_angle(TAU * i / 8 + PI / 8) * 300
				ring.append(Vector3(p.x, p.y, 28))
			d["pillars"].append_array(ring)
			for p in [Vector2(170, 130), Vector2(1110, 130), Vector2(170, 590), Vector2(1110, 590)]:
				d["pillars"].append(_mp(p.x, p.y, 38))
			for i in 8:
				var a: Vector3 = ring[i]
				var b: Vector3 = ring[(i + 1) % 8]
				var pa := Vector2(a.x, a.y)
				var pb := Vector2(b.x, b.y)
				var dir := (pb - pa).normalized()
				d["fences"].append({"a": pa + dir * a.z, "b": pb - dir * b.z, "group": i % 2})
		"fortress":
			d["pillars"] = [Vector3(CENTER.x, CENTER.y, 60), _mp(250, 360, 36), _mp(1030, 360, 36),
				_mp(445, 360, 26), _mp(835, 360, 26)]
			d["belts"] = [{"rect": Rect2(ar.position.x, _m(0, 140).y, ar.size.x, 100), "dir": Vector2.RIGHT},
				{"rect": Rect2(ar.position.x, _m(0, 580).y - 100, ar.size.x, 100), "dir": Vector2.LEFT}]
		"portals":
			d["pillars"] = [_mp(460, 220, 40), _mp(820, 220, 40), _mp(460, 500, 40), _mp(820, 500, 40)]
			d["blocks"] = [_mp(640, 220, 22), _mp(640, 500, 22), _mp(640, 120, 22), _mp(640, 600, 22)]
			d["portals"] = [_m(150, 360), _m(1130, 360)]
		"open":
			d["pillars"] = [_mp(220, 170, 20), _mp(1060, 170, 20), _mp(220, 550, 20), _mp(1060, 550, 20)]
	return d


func reset() -> void:
	bag.clear()
	set_layout("classic", true)


## Next layout from a shuffled bag: never the current one, and preferably of a different
## openness class (tight <-> open), so each arrival contrasts with the space before it.
func shift_next(avoid := "") -> String:
	var cur_class := layout_class(layout)
	for attempt in 2:
		if bag.is_empty():
			bag = POOL.duplicate()
			bag.shuffle()
		var pick := -1
		for i in range(bag.size() - 1, -1, -1):
			var id: String = bag[i]
			if (id == layout and id != "gen") or id == avoid:
				continue
			if _candidate_class(id) != cur_class:
				pick = i
				break
		if pick == -1 and attempt == 0:
			bag.clear()  # nothing contrasting left in this cycle: start a fresh one
			continue
		if pick == -1:
			for i in range(bag.size() - 1, -1, -1):
				if bag[i] != layout and bag[i] != avoid:
					pick = i
					break
		if pick != -1:
			var next: String = bag[pick]
			bag.remove_at(pick)
			_use(next)
			return next
	_use("classic")
	return "classic"


## Switches straight to a given layout (boss arenas). Returns false if already there.
func shift_to(id: String) -> bool:
	if id == layout:
		return false
	bag.erase(id)
	_use(id)
	return true


func _use(id: String) -> void:
	if id == "gen":
		gen_data = gen_pending if not gen_pending.is_empty() else generate()
		gen_pending = {}
		gen_count += 1
	set_layout(id)


func layout_class(id: String) -> String:
	if id == "gen":
		return String(gen_data.get("class", "mid"))
	return LAYOUT_CLASS.get(id, "mid")


func _candidate_class(id: String) -> String:
	if id == "gen":
		if gen_pending.is_empty():
			gen_pending = generate()
		return String(gen_pending["class"])
	return LAYOUT_CLASS.get(id, "mid")


## Name shown to the player ("MUTATION #3" for generated layouts).
func display_name() -> String:
	if layout == "gen":
		return main.t("arena_gen") % gen_count
	return main.t("arena_" + layout)


## One-line hint about this layout's mechanism, shown while it rises.
func hint() -> String:
	if layout == "gen":
		var parts: Array[String] = []
		if not gen_data.get("fences", []).is_empty():
			parts.append(main.t("hint_fence"))
		if not gen_data.get("belts", []).is_empty():
			parts.append(main.t("hint_belt"))
		if not gen_data.get("portals", []).is_empty():
			parts.append(main.t("hint_portal"))
		if not gen_data.get("blocks", []).is_empty():
			parts.append(main.t("hint_crystal"))
		return "  ·  ".join(parts)
	var key := "hint_" + layout
	return main.t(key) if main.I18n.TEXT.has(key) else ""


func set_layout(id: String, instant := false) -> void:
	layout = id
	var d := _layout_data(id)
	if instant:
		elements.clear()
	else:
		for e in elements:
			if e["state"] != "fade":
				e["state"] = "fade"
				e["t"] = FADE_TIME
	for v in d["pillars"]:
		elements.append(_element("pillar", v, instant))
	for v in d["blocks"]:
		elements.append(_element("block", v, instant))
	fences = d["fences"]
	belts = d["belts"]
	portals = d["portals"]
	mech_t = 0.0
	fence_tick = 0.0
	portal_cd.clear()
	mech_delay = 0.0 if instant else WARN_TIME + RISE_TIME
	rebuild()
	queue_redraw()


func _element(kind: String, v: Vector3, instant: bool) -> Dictionary:
	return {"kind": kind, "p": Vector2(v.x, v.y), "r": v.z, "state": "solid" if instant else "warn",
		"t": 0.0 if instant else WARN_TIME, "rise": 0.0, "hp": BLOCK_HP, "max_hp": BLOCK_HP, "flash": 0.0}


## Copies solid elements into main.obstacles (x, y, radius); refs maps indices back.
func rebuild() -> void:
	main.obstacles.clear()
	refs.clear()
	for e in elements:
		if e["state"] == "solid" or e["state"] == "fade":
			main.obstacles.append(Vector3(e["p"].x, e["p"].y, e["r"]))
			refs.append(e)


func update(delta: float) -> void:
	t += delta
	var changed := false
	for e in elements:
		e["flash"] = maxf(0.0, e["flash"] - delta)
		e["rise"] = maxf(0.0, e["rise"] - delta)
		match e["state"]:
			"warn":
				e["t"] -= delta
				if e["t"] <= 0:
					e["state"] = "solid"
					e["rise"] = RISE_TIME
					changed = true
					main.fx.ring(e["p"], e["r"] * 1.8, BLOCK_COL if e["kind"] == "block" else PILLAR_COL, 0.3)
			"fade":
				e["t"] -= delta
				if e["t"] <= 0:
					e["state"] = "gone"
					changed = true
	if changed:
		elements = elements.filter(func(e): return e["state"] != "gone")
		rebuild()
		for pk in main.pickups:
			pk.position = main.resolve_static(pk.position, 14)
	for k in portal_cd.keys():
		portal_cd[k] -= delta
		if portal_cd[k] <= 0:
			portal_cd.erase(k)
	if mech_delay > 0:
		mech_delay -= delta
	else:
		mech_t += delta
		_update_belts(delta)
		_update_fences(delta)
		_update_portals()
	queue_redraw()


func mechanisms_on() -> bool:
	return mech_delay <= 0


# ---------------------------------------------------------------- blocks

## Damages the crystal at obstacle index idx. Returns true if it was a crystal.
func damage_block(idx: int, dmg: float) -> bool:
	if idx < 0 or idx >= refs.size():
		return false
	var e: Dictionary = refs[idx]
	if e["kind"] != "block" or e["state"] != "solid":
		return false
	_hurt_block(e, dmg)
	return true


func damage_blocks_in(p: Vector2, r: float, dmg: float) -> void:
	for e in elements.duplicate():
		if e["kind"] == "block" and e["state"] == "solid" and p.distance_to(e["p"]) < r + e["r"]:
			_hurt_block(e, dmg)


func _hurt_block(e: Dictionary, dmg: float) -> void:
	e["hp"] -= dmg
	e["flash"] = 0.08
	if e["hp"] <= 0:
		e["state"] = "gone"
		elements.erase(e)
		rebuild()
		main.fx.burst(e["p"], BLOCK_COL, 26, 300, 3.5, 0.5)
		main.fx.ring(e["p"], e["r"] * 3, BLOCK_COL, 0.35)
		main.sfx.play("explode")
		main.add_shake(4)
		main.score += 10


# ---------------------------------------------------------------- conveyors

func belt_push(p: Vector2) -> Vector2:
	for b in belts:
		if b["rect"].has_point(p):
			return b["dir"] * BELT_SPEED
	return Vector2.ZERO


func _update_belts(delta: float) -> void:
	if belts.is_empty():
		return
	var pl = main.player
	if not pl.dead:
		pl.position = main.resolve_static(pl.position + belt_push(pl.position) * delta, pl.radius)
	if main.is_guest():
		return  # everything else comes from the host's snapshots
	for e in main.enemies:
		if not e.dead and not e.is_boss:
			e.position = main.resolve_static(e.position + belt_push(e.position) * delta, e.radius)
	for pk in main.pickups:
		pk.position = main.resolve_static(pk.position + belt_push(pk.position) * delta, 14)
	for b in main.bullets:
		if not b.dead:
			b.position += belt_push(b.position) * delta


# ---------------------------------------------------------------- laser fences

## Two groups take turns: warn (flicker) -> on -> off, half a period apart.
func fence_state(group: int) -> String:
	if not mechanisms_on():
		return "off"
	var half := FENCE_PERIOD / 2.0
	var local := fmod(mech_t + (half if group == 1 else 0.0), FENCE_PERIOD)
	if local < FENCE_WARN:
		return "warn"
	if local < half:
		return "on"
	return "off"


func _update_fences(delta: float) -> void:
	if fences.is_empty():
		return
	fence_tick -= delta
	var tick := fence_tick <= 0
	if tick:
		fence_tick = 0.4
	for f in fences:
		if fence_state(f["group"]) != "on":
			continue
		for pl in main.hurtable_players():
			var cp := Geometry2D.get_closest_point_to_segment(pl.position, f["a"], f["b"])
			if cp.distance_to(pl.position) < 6.0 + pl.radius * 0.6:
				pl.hurt(1)
		if tick and not main.is_guest():
			for e in main.enemies:
				if e.dead:
					continue
				var ce := Geometry2D.get_closest_point_to_segment(e.position, f["a"], f["b"])
				if ce.distance_to(e.position) < e.radius + 5.0:
					main.damage_enemy(e, 1.0, Vector2.ZERO, true)


# ---------------------------------------------------------------- portals

func _update_portals() -> void:
	if portals.size() < 2:
		return
	var pl = main.player
	if not pl.dead:
		_try_portal(pl, pl.radius, pl.vel)
	if main.is_guest():
		return
	for e in main.enemies:
		if not e.dead and not e.is_boss and e.type != "snake" and e.type != "mine":
			_try_portal(e, e.radius, e.vel)
	for b in main.bullets:
		if not b.dead:
			_try_portal(b, b.radius, b.vel)


func _try_portal(n: Node2D, r: float, v: Vector2) -> void:
	var id := n.get_instance_id()
	if portal_cd.has(id):
		return
	for i in 2:
		if n.position.distance_to(portals[i]) < PORTAL_R + r * 0.3:
			var out: Vector2 = portals[1 - i]
			var dir := v.normalized() if v.length() > 5.0 else (CENTER - out).normalized()
			n.position = main.resolve_static(out + dir * (PORTAL_R + r + 4.0), r)
			portal_cd[id] = 0.6
			main.fx.ring(portals[i], PORTAL_R * 1.6, PORTAL_COLS[i], 0.25)
			main.fx.ring(out, PORTAL_R * 1.6, PORTAL_COLS[1 - i], 0.25)
			if n == main.player:
				main.sfx.play("dash")
			return


func near_portal(p: Vector2, margin: float) -> bool:
	for q in portals:
		if p.distance_to(q) < PORTAL_R + margin:
			return true
	return false


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var live := mechanisms_on()
	# While a new layout rises, its mechanisms play a short preview so players can read them
	# before they switch on: belts scroll, fence groups blink in turn, portals link up.
	var preview := not live
	for b in belts:
		var r: Rect2 = b["rect"]
		var dir: Vector2 = b["dir"]
		var a := 1.0 if live else 0.35 + 0.25 * sin(t * 12.0)
		draw_rect(r, Color(BELT_COL, 0.06 * a))
		draw_line(r.position, Vector2(r.end.x, r.position.y), Color(BELT_COL, 0.35 * a), 2.0)
		draw_line(Vector2(r.position.x, r.end.y), r.end, Color(BELT_COL, 0.35 * a), 2.0)
		var spacing := 60.0
		var off := fmod(t * BELT_SPEED, spacing) if live or preview else 0.0
		var cy := r.get_center().y
		var x := r.position.x - spacing + (off if dir.x > 0 else spacing - off)
		while x < r.end.x + spacing:
			if x > r.position.x + 10 and x < r.end.x - 10:
				var s := dir.x * 12.0
				draw_polyline(PackedVector2Array([Vector2(x - s, cy - 18), Vector2(x + s, cy), Vector2(x - s, cy + 18)]), Color(BELT_COL, 0.28 * a), 3.0, true)
			x += spacing
	for f in fences:
		var st := fence_state(f["group"])
		match st:
			"on":
				draw_line(f["a"], f["b"], Color(FENCE_COL, 0.25), 16.0, true)
				draw_line(f["a"], f["b"], Color(FENCE_COL, 0.9), 6.0, true)
				draw_line(f["a"], f["b"], Color(1, 1, 1, 0.9), 2.0, true)
			"warn":
				var fl := 0.3 + 0.5 * absf(sin(t * 30.0))
				draw_line(f["a"], f["b"], Color(FENCE_COL, fl), 2.0, true)
			_:
				if preview and int(t * 3.0) % 2 == int(f["group"]):
					draw_line(f["a"], f["b"], Color(FENCE_COL, 0.55), 3.0, true)
				else:
					draw_line(f["a"], f["b"], Color(FENCE_COL, 0.12), 1.0, true)
	if preview and portals.size() == 2:
		# Dashed link between the two gates.
		var a0: Vector2 = portals[0]
		var b0: Vector2 = portals[1]
		var n := int(a0.distance_to(b0) / 24.0)
		var phase := fmod(t * 2.0, 1.0)
		for k in n:
			if k % 2 == 0:
				var u0 := (k + phase) / n
				var u1 := minf((k + 1 + phase) / n, 1.0)
				draw_line(a0.lerp(b0, u0), a0.lerp(b0, u1), Color(PORTAL_COLS[0].lerp(PORTAL_COLS[1], u0), 0.35), 2.0, true)
	for i in portals.size():
		var c: Vector2 = portals[i]
		var col: Color = PORTAL_COLS[i]
		var a := 1.0 if live else 0.4
		draw_circle(c, PORTAL_R + 8, Color(col, 0.07 * a))
		draw_circle(c, PORTAL_R, Color(col, 0.12 * a))
		var sp := t * (2.5 if i == 0 else -2.5)
		for k in 3:
			var a0 := sp + TAU * k / 3
			draw_arc(c, PORTAL_R, a0, a0 + 1.4, 12, Color(col, 0.9 * a), 3.0, true)
			draw_arc(c, PORTAL_R * 0.6, -a0 * 1.3, -a0 * 1.3 + 1.2, 10, Color(col, 0.6 * a), 2.0, true)
	for e in elements:
		_draw_element(e)


func _draw_element(e: Dictionary) -> void:
	var c: Vector2 = e["p"]
	var r: float = e["r"]
	var block: bool = e["kind"] == "block"
	var col := BLOCK_COL if block else PILLAR_COL
	match e["state"]:
		"warn":
			var pulse := 0.5 + 0.5 * sin(t * 14.0)
			var wc := Color(1, 0.85, 0.35, 0.35 + 0.45 * pulse)
			draw_circle(c, r, Color(1, 0.85, 0.35, 0.06 + 0.06 * pulse))
			for k in 8:
				var a0 := TAU * k / 8 + t
				draw_arc(c, r, a0, a0 + TAU / 16, 6, wc, 2.0, true)
			return
		"fade":
			var k: float = e["t"] / FADE_TIME
			if int(e["t"] * 20) % 2 == 0:
				_draw_solid(c, r * (0.8 + 0.2 * k), col, k * 0.8, block, e)
			return
	var rise_k: float = 1.0 - e["rise"] / RISE_TIME
	_draw_solid(c, r * (0.7 + 0.3 * rise_k), col, 1.0, block, e)


func _draw_solid(c: Vector2, r: float, col: Color, a: float, block: bool, e: Dictionary) -> void:
	if block:
		var hp_k: float = clampf(e["hp"] / e["max_hp"], 0, 1)
		var oc := Color.WHITE if e["flash"] > 0 else col
		var hex := PackedVector2Array()
		for i in 7:
			hex.append(c + Vector2.from_angle(PI / 6 + TAU * i / 6) * r)
		draw_circle(c, r + 6, Color(col, 0.08 * a))
		draw_colored_polygon(hex.slice(0, 6), Color(0.08, 0.14, 0.2, 0.95 * a))
		draw_polyline(hex, Color(oc, 0.95 * a), 2.5, true)
		var inner := PackedVector2Array()
		for i in 7:
			inner.append(c + Vector2.from_angle(PI / 6 + TAU * i / 6) * r * 0.55 * hp_k)
		draw_polyline(inner, Color(col, 0.5 * a), 1.5, true)
		if hp_k < 0.6:
			draw_line(c + Vector2(-r * 0.6, -r * 0.2), c + Vector2(r * 0.1, r * 0.15), Color(oc, 0.7 * a), 1.5)
			draw_line(c + Vector2(r * 0.1, r * 0.15), c + Vector2(r * 0.45, -r * 0.5), Color(oc, 0.7 * a), 1.5)
		return
	draw_circle(c, r + 8, Color(0.5, 0.3, 1.0, 0.08 * a))
	draw_circle(c, r, Color(0.09, 0.08, 0.18, a))
	draw_arc(c, r, 0, TAU, 48, Color(col, 0.9 * a), 3.0, true)
	draw_arc(c, r * 0.6, 0, TAU, 32, Color(col, 0.25 * a), 2.0, true)


# ---------------------------------------------------------------- generator

## Builds a layout from a small pattern library (pillar, L-wall, crystal row, fence gate,
## conveyor pair, portal pair) mirrored for fairness, then checks it against level-design
## constraints: passages at least GEN_PASSAGE wide, every spot within GEN_COVER_REACH of a
## pillar, the centre clear, and every open spot reachable. Falls back to "classic".
func generate() -> Dictionary:
	gen_rng.randomize()
	for i in GEN_TRIES:
		var d := _gen_candidate()
		if _gen_valid(d):
			d["class"] = _measure_class(d)
			return d
	var fb := _layout_data("classic")
	fb["class"] = "mid"
	return fb


func _gen_candidate() -> Dictionary:
	var d := {"pillars": [], "blocks": [], "fences": [], "belts": [], "portals": []}
	var mirror4 := gen_rng.randf() < 0.6  # else 180° rotational symmetry
	var feature := gen_rng.randi_range(0, 3)  # 0 none, 1 belts, 2 portals, 3 gates
	var ar: Rect2 = main.ARENA
	var lo := ar.position + Vector2(110, 100)
	var hi := CENTER - Vector2(70, 60)  # top-left quadrant; copies fill the rest
	if feature == 1:
		var y := gen_rng.randf_range(140, 200)
		lo.y = y + 96 + 50  # cover goes between the belts, not on them
		hi.y = CENTER.y - 40
		d["belts"] = [{"rect": Rect2(ar.position.x, y, ar.size.x, 96), "dir": Vector2.RIGHT},
			{"rect": Rect2(ar.position.x, CENTER.y * 2.0 - y - 96, ar.size.x, 96), "dir": Vector2.LEFT}]
	elif feature == 2:
		var py := CENTER.y if gen_rng.randf() < 0.6 else gen_rng.randf_range(190, 400)
		var px := gen_rng.randf_range(150, 250)
		d["portals"] = [Vector2(px, py), CENTER * 2.0 - Vector2(px, py)]
	var quad: Array = []  # [kind, Vector3] in the quadrant
	var gates: Array = []
	var n := gen_rng.randi_range(2, 4)
	for k in n:
		var c := Vector2(gen_rng.randf_range(lo.x, hi.x), gen_rng.randf_range(lo.y, hi.y))
		var roll := gen_rng.randf()
		if feature == 3 and k == 0:
			roll = 0.95  # gate theme: one fence gate (mirrored), the rest is cover
		elif roll >= 0.8:
			roll = gen_rng.randf() * 0.8
		if roll < 0.35:
			quad.append(["p", Vector3(c.x, c.y, gen_rng.randf_range(26, 44))])
		elif roll < 0.6:
			var sx := -1.0 if gen_rng.randf() < 0.5 else 1.0
			var sy := -1.0 if gen_rng.randf() < 0.5 else 1.0
			quad.append(["p", Vector3(c.x, c.y, 38)])
			quad.append(["p", Vector3(c.x + sx * 70, c.y, 30)])
			quad.append(["p", Vector3(c.x, c.y + sy * 64, 30)])
		elif roll < 0.8:
			var horiz := gen_rng.randf() < 0.5
			for j in gen_rng.randi_range(2, 3):
				var o := Vector2(j * 46, 0) if horiz else Vector2(0, j * 46)  # touching: one wall
				quad.append(["b", Vector3(c.x + o.x, c.y + o.y, 22)])
		else:
			var gap := gen_rng.randf_range(110, 150)
			var a := Vector3(c.x, c.y, 24)
			var b := Vector3(c.x + gap, c.y, 24) if gen_rng.randf() < 0.5 else Vector3(c.x, c.y + gap, 24)
			quad.append(["p", a])
			quad.append(["p", b])
			gates.append([a, b])
	var copies: Array = [Vector2(1, 1), Vector2(-1, -1)]
	if mirror4:
		copies = [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for ci in copies.size():
		var m: Vector2 = copies[ci]
		for q in quad:
			var v: Vector3 = q[1]
			var w := _mirror(v, m)
			if q[0] == "p":
				d["pillars"].append(w)
			else:
				d["blocks"].append(w)
		for gi in gates.size():
			var ga := _mirror(gates[gi][0], m)
			var gb := _mirror(gates[gi][1], m)
			var pa := Vector2(ga.x, ga.y)
			var pb := Vector2(gb.x, gb.y)
			var dir := (pb - pa).normalized()
			d["fences"].append({"a": pa + dir * ga.z, "b": pb - dir * gb.z, "group": (ci + gi) % 2})
	return d


func _mirror(v: Vector3, m: Vector2) -> Vector3:
	var p := CENTER + (Vector2(v.x, v.y) - CENTER) * m
	return Vector3(p.x, p.y, v.z)


func _gen_valid(d: Dictionary) -> bool:
	var solids: Array = d["pillars"] + d["blocks"]
	if solids.size() < 4 or solids.size() > 26:
		return false
	var arena: Rect2 = main.ARENA
	for v in solids:
		var p := Vector2(v.x, v.y)
		# Room to pass between an obstacle and the wall
		if p.x - v.z - arena.position.x < GEN_PASSAGE or arena.end.x - p.x - v.z < GEN_PASSAGE:
			return false
		if p.y - v.z - arena.position.y < GEN_PASSAGE or arena.end.y - p.y - v.z < GEN_PASSAGE:
			return false
		if p.distance_to(CENTER) < GEN_CENTER_CLEAR + v.z:
			return false
		for b in d["belts"]:
			if (b["rect"] as Rect2).grow(v.z).has_point(p):
				return false
		for q in d["portals"]:
			if p.distance_to(q) < v.z + PORTAL_R + 60:
				return false
	# Separate obstacles either touch (one cluster) or leave a real passage
	for i in solids.size():
		for j in range(i + 1, solids.size()):
			var a: Vector3 = solids[i]
			var b: Vector3 = solids[j]
			var gap := Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)) - a.z - b.z
			if gap > 4.0 and gap < GEN_PASSAGE:
				return false
	# Cover reach and reachability on a 40 px grid
	var step := 40.0
	var free := {}
	for gx in range(int(arena.position.x + 20), int(arena.end.x), int(step)):
		for gy in range(int(arena.position.y + 20), int(arena.end.y), int(step)):
			var p := Vector2(gx, gy)
			var blocked := false
			var nearest := INF
			for v in solids:
				var dd: float = p.distance_to(Vector2(v.x, v.y)) - v.z
				if dd < 15.0:
					blocked = true
				nearest = minf(nearest, dd)
			if blocked:
				continue
			var pillar_near := INF
			for v in d["pillars"]:
				pillar_near = minf(pillar_near, p.distance_to(Vector2(v.x, v.y)) - v.z)
			if pillar_near > GEN_COVER_REACH:
				return false
			free[Vector2i(gx, gy)] = true
	if free.is_empty():
		return false
	var start: Vector2i = free.keys()[0]
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for o in [Vector2i(40, 0), Vector2i(-40, 0), Vector2i(0, 40), Vector2i(0, -40)]:
			var nb: Vector2i = c + o
			if free.has(nb) and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen.size() >= free.size()


## tight / mid / open from the average distance to the nearest obstacle.
func _measure_class(d: Dictionary) -> String:
	var solids: Array = d["pillars"] + d["blocks"]
	var total := 0.0
	var count := 0
	var arena: Rect2 = main.ARENA
	for gx in range(int(arena.position.x + 30), int(arena.end.x), 60):
		for gy in range(int(arena.position.y + 30), int(arena.end.y), 60):
			var p := Vector2(gx, gy)
			var nearest := INF
			for v in solids:
				nearest = minf(nearest, p.distance_to(Vector2(v.x, v.y)) - v.z)
			if nearest > 0:
				total += nearest
				count += 1
	var avg := total / maxf(count, 1)
	# Calibrated on the hand-made layouts (1.4× arena): cross 108, ring 124 | classic 144,
	# fortress 193, portals 199 | open 320.
	if avg < 132.0:
		return "tight"
	if avg > 250.0:
		return "open"
	return "mid"
