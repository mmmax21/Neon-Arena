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
const CENTER := Vector2(640, 360)
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
var t := 0.0


func _layout_data(id: String) -> Dictionary:
	var d := {"pillars": [], "blocks": [], "fences": [], "belts": [], "portals": []}
	match id:
		"classic":
			d["pillars"] = [Vector3(300, 210, 42), Vector3(980, 210, 42), Vector3(300, 510, 42),
				Vector3(980, 510, 42), Vector3(640, 140, 28), Vector3(640, 580, 28)]
		"cross":
			# Four L-shaped clusters leave cross-shaped corridors; crystals dot the corridors.
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var c := CENTER + Vector2(sx * 330, sy * 190)
					d["pillars"].append(Vector3(c.x, c.y, 40))
					d["pillars"].append(Vector3(c.x + sx * 72, c.y, 32))
					d["pillars"].append(Vector3(c.x, c.y + sy * 66, 32))
			for p in [Vector2(640, 250), Vector2(640, 470), Vector2(500, 360), Vector2(780, 360),
					Vector2(640, 145), Vector2(640, 575), Vector2(230, 360), Vector2(1050, 360)]:
				d["blocks"].append(Vector3(p.x, p.y, 22))
		"ring":
			var ring: Array = []
			for i in 8:
				var p := CENTER + Vector2.from_angle(TAU * i / 8 + PI / 8) * 230
				ring.append(Vector3(p.x, p.y, 24))
			d["pillars"].append_array(ring)
			for p in [Vector2(170, 130), Vector2(1110, 130), Vector2(170, 590), Vector2(1110, 590)]:
				d["pillars"].append(Vector3(p.x, p.y, 34))
			for i in 8:
				var a: Vector3 = ring[i]
				var b: Vector3 = ring[(i + 1) % 8]
				var pa := Vector2(a.x, a.y)
				var pb := Vector2(b.x, b.y)
				var dir := (pb - pa).normalized()
				d["fences"].append({"a": pa + dir * a.z, "b": pb - dir * b.z, "group": i % 2})
		"fortress":
			d["pillars"] = [Vector3(640, 360, 56), Vector3(250, 360, 34), Vector3(1030, 360, 34)]
			d["belts"] = [{"rect": Rect2(30, 140, 1220, 90), "dir": Vector2.RIGHT},
				{"rect": Rect2(30, 490, 1220, 90), "dir": Vector2.LEFT}]
		"portals":
			d["pillars"] = [Vector3(460, 220, 38), Vector3(820, 220, 38), Vector3(460, 500, 38), Vector3(820, 500, 38)]
			d["blocks"] = [Vector3(640, 220, 22), Vector3(640, 500, 22)]
			d["portals"] = [Vector2(150, 360), Vector2(1130, 360)]
		"open":
			d["pillars"] = [Vector3(220, 170, 18), Vector3(1060, 170, 18), Vector3(220, 550, 18), Vector3(1060, 550, 18)]
	return d


func reset() -> void:
	bag.clear()
	set_layout("classic", true)


## Next layout from a shuffled bag, never repeating the current one.
func shift_next() -> String:
	if bag.is_empty():
		bag = LAYOUTS.duplicate()
		bag.shuffle()
	var next: String = bag.pop_back()
	if next == layout:
		if bag.is_empty():
			bag = LAYOUTS.duplicate()
			bag.shuffle()
			bag.erase(layout)
		next = bag.pop_back()
	set_layout(next)
	return next


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
	var pl = main.player
	for f in fences:
		if fence_state(f["group"]) != "on":
			continue
		if not pl.dead:
			var cp := Geometry2D.get_closest_point_to_segment(pl.position, f["a"], f["b"])
			if cp.distance_to(pl.position) < 6.0 + pl.radius * 0.6:
				pl.hurt(1)
		if tick:
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
	for b in belts:
		var r: Rect2 = b["rect"]
		var dir: Vector2 = b["dir"]
		var a := 1.0 if live else 0.35 + 0.25 * sin(t * 12.0)
		draw_rect(r, Color(BELT_COL, 0.06 * a))
		draw_line(r.position, Vector2(r.end.x, r.position.y), Color(BELT_COL, 0.35 * a), 2.0)
		draw_line(Vector2(r.position.x, r.end.y), r.end, Color(BELT_COL, 0.35 * a), 2.0)
		var spacing := 60.0
		var off := fmod(t * BELT_SPEED, spacing) if live else 0.0
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
				draw_line(f["a"], f["b"], Color(FENCE_COL, 0.12), 1.0, true)
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
