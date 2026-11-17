extends Control
## Touch controls. Left half: floating move stick. Weapons auto-aim and auto-fire; in hybrid
## mode dragging on the right half takes over aim (twin-stick) until 1 s after release.
## Bottom-right: dash button and target lock. Taps outside play act as clicks (on release).
## Turns on at the first touch (or on phones/tablets from the start); real mouse movement
## switches back to desktop controls.

const Icons := preload("res://scripts/icons.gd")

const MODES := ["auto", "hybrid", "twin"]
const STICK_R := 78.0
const DEAD := 0.15
const DRAG_START := 14.0
const MANUAL_HOLD := 1.0
const DASH_BTN := Vector2(1150, 588)
const DASH_R := 60.0
const LOCK_BTN := Vector2(1022, 646)
const LOCK_R := 34.0
const PAUSE_RECT := Rect2(1198, 88, 38, 38)
const MOVE_HINT := Vector2(170, 570)
const TAP_TIME := 0.45
const TAP_SLOP := 36.0
const RETARGET := 0.15
## Auto-fire range per weapon (pulse bullets fly ~1090 px, scatter ~290 px).
const RANGE := {"pulse": 760.0, "scatter": 340.0, "laser": 1000.0}
const SHOT_SPEED := {"pulse": 780.0, "scatter": 690.0, "laser": 0.0}
## Lower = picked sooner at equal distance.
const PRIORITY := {"sentry": 0.6, "shooter": 0.75, "layer": 0.85, "chaser": 0.9, "dodger": 1.0,
	"splitter": 1.0, "mini": 1.0, "snake": 1.0, "tank": 1.15, "boss": 1.3, "boss2": 1.3, "mine": 1.8}

var main: Node2D
var active := false
var mode := "hybrid"
var t := 0.0
var last_touch := -10.0

var move_id := -1
var move_base := Vector2.ZERO
var move_pos := Vector2.ZERO
var aim_id := -1
var aim_base := Vector2.ZERO
var aim_pos := Vector2.ZERO
var aim_dragged := false
var manual_t := 0.0
var manual_dir := Vector2.ZERO
var button_ids := {}  # touch index -> "dash" / "lock" / "pause" / "mute"
var taps := {}  # touch index -> {start, pos, t} for taps outside play
var dash_buf := 0.0  # a dash press stays queued briefly so taps during cooldown still count
var dash_flash := 0.0

var target: Node2D = null
var line_anchor: Node2D = null  # laser: enemy whose line hits the most enemies
var locked := false
var retarget_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	active = OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile")


func cycle_mode() -> void:
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	main.sfx.play("card")
	main._save_setting("input", "touch_mode", mode)


func set_mode(m: String) -> void:
	if MODES.has(m):
		mode = m


func reset() -> void:
	move_id = -1
	aim_id = -1
	aim_dragged = false
	manual_t = 0.0
	button_ids.clear()
	dash_buf = 0.0
	target = null
	line_anchor = null
	locked = false


func is_portrait() -> bool:
	var s := DisplayServer.window_get_size()
	return active and s.y > s.x


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		last_touch = t
		if not active:
			active = true
			reset()
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		last_touch = t
		_drag(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif active and event is InputEventMouseMotion and t - last_touch > 1.0 and event.relative.length() > 3.0:
		# A real mouse is being used: back to desktop controls.
		active = false
		reset()


func _press(id: int, p: Vector2) -> void:
	if main.state != main.State.PLAYING or is_portrait():
		taps[id] = {"start": p, "pos": p, "t": t}
		return
	if main.hud.mute_at(p):
		button_ids[id] = "mute"
		main.set_muted(not main.muted)
	elif PAUSE_RECT.grow(8).has_point(p):
		button_ids[id] = "pause"
		main.state = main.State.PAUSED
		main.sfx.play("card")
	elif p.distance_to(DASH_BTN) < DASH_R + 16:
		button_ids[id] = "dash"
		dash_buf = 0.2
		dash_flash = 0.15
	elif mode != "twin" and p.distance_to(LOCK_BTN) < LOCK_R + 12:
		button_ids[id] = "lock"
		_toggle_lock()
	elif p.x < main.W / 2:
		if move_id == -1:
			move_id = id
			move_base = p
			move_pos = p
	elif mode != "auto" and aim_id == -1:
		aim_id = id
		aim_base = p
		aim_pos = p
		aim_dragged = false


func _drag(id: int, p: Vector2) -> void:
	if taps.has(id):
		taps[id]["pos"] = p
	if id == move_id:
		move_pos = p
		var d := move_pos - move_base
		if d.length() > STICK_R:
			move_base = move_pos - d.normalized() * STICK_R  # the stick follows the thumb
	elif id == aim_id:
		aim_pos = p
		var d := aim_pos - aim_base
		if d.length() > DRAG_START:
			aim_dragged = true
			manual_dir = d.normalized()
		if d.length() > STICK_R:
			aim_base = aim_pos - d.normalized() * STICK_R


func _release(id: int, p: Vector2) -> void:
	button_ids.erase(id)
	if id == move_id:
		move_id = -1
	if id == aim_id:
		aim_id = -1
		if aim_dragged:
			manual_t = MANUAL_HOLD
		aim_dragged = false
	if taps.has(id):
		var tap: Dictionary = taps[id]
		taps.erase(id)
		# Short, still taps act as clicks; long presses only show tooltips.
		if t - tap["t"] < TAP_TIME and p.distance_to(tap["start"]) < TAP_SLOP and not is_portrait():
			main.press_at(p)


## Where the HUD should treat the "mouse" as being (hover highlights and tooltips).
func hover_pos() -> Vector2:
	if main.state != main.State.PLAYING:
		for id in taps:
			return taps[id]["pos"]
	return Vector2(-10000, -10000)


func move_vector() -> Vector2:
	if move_id == -1:
		return Vector2.ZERO
	var v := (move_pos - move_base) / STICK_R
	var l := v.length()
	if l < DEAD:
		return Vector2.ZERO
	return v / l * clampf((l - DEAD) / (1.0 - DEAD), 0.0, 1.0)


# ---------------------------------------------------------------- aiming

## Sets the player's aim for this frame; returns true if it should fire.
func steer(pl: Node2D, delta: float) -> bool:
	manual_t = maxf(0.0, manual_t - delta)
	if aim_id != -1 and aim_dragged:
		pl.aim = manual_dir
		return true
	if mode == "twin" or manual_t > 0:
		return false
	retarget_t -= delta
	if not _alive(target):
		target = null
		locked = false
	if retarget_t <= 0:
		retarget_t = RETARGET
		_pick_target(pl)
	if target == null:
		var mv := move_vector()
		if mv.length() > 0.3:
			pl.aim = pl.aim.slerp(mv.normalized(), clampf(delta * 10.0, 0, 1)).normalized()
		return false
	var want := _aim_point(pl) - pl.position
	if want.length() < 1.0:
		return false
	want = want.normalized()
	pl.aim = pl.aim.slerp(want, clampf(delta * 28.0, 0, 1)).normalized()
	var d := pl.position.distance_to(target.position)
	return pl.aim.dot(want) > 0.96 and d < RANGE[pl.weapon] + target.radius and _clear(pl.position, target)


func _alive(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead


func _clear(from: Vector2, e: Node2D) -> bool:
	var d := e.position - from
	var l := d.length()
	if l < 1.0:
		return true
	return main.cast_ray(from, d / l, l) >= l - e.radius - 2.0


func _score(pl: Node2D, e: Node2D) -> float:
	var d := pl.position.distance_to(e.position)
	var w: float = PRIORITY.get(e.type, 1.0)
	if not _clear(pl.position, e):
		w *= 3.0
	if d > RANGE[pl.weapon]:
		w *= 2.0
	return d * w


func _pick_target(pl: Node2D) -> void:
	if not locked:
		var best: Node2D = null
		var best_s := INF
		for e in main.enemies:
			if not _alive(e):
				continue
			var s := _score(pl, e)
			if s < best_s:
				best_s = s
				best = e
		# Stick with the current target unless the new one is clearly better.
		if best != null and (target == null or best == target or best_s < _score(pl, target) * 0.75):
			target = best
	line_anchor = target
	if pl.weapon == "laser" and not locked and target != null:
		line_anchor = _best_laser_line(pl)


## Laser pierces: aim through whichever in-range enemy lines up the most others.
func _best_laser_line(pl: Node2D) -> Node2D:
	var o: Vector2 = pl.position
	var best: Node2D = target
	var best_n := _line_hits(o, target)
	for e in main.enemies:
		if not _alive(e) or e == target or o.distance_to(e.position) > RANGE["laser"]:
			continue
		var n := _line_hits(o, e)
		if n > best_n:
			best_n = n
			best = e
	return best


func _line_hits(o: Vector2, through: Node2D) -> int:
	var d := through.position - o
	if d.length() < 1.0:
		return 0
	d = d.normalized()
	var end: Vector2 = o + d * main.cast_ray(o, d, 1600.0)
	var n := 0
	for e in main.enemies:
		if _alive(e) and Geometry2D.get_closest_point_to_segment(e.position, o, end).distance_to(e.position) < e.radius + 6.0:
			n += 1
	return n


## Aim point with lead for bullet weapons.
func _aim_point(pl: Node2D) -> Vector2:
	var e: Node2D = line_anchor if _alive(line_anchor) else target
	var spd: float = SHOT_SPEED[pl.weapon]
	if spd <= 0.0:
		return e.position
	var lead := pl.position.distance_to(e.position) / spd
	return e.position + e.vel * minf(lead, 0.6)


func _toggle_lock() -> void:
	if locked:
		locked = false
	elif _alive(target):
		locked = true
	main.sfx.play("card")


# ---------------------------------------------------------------- frame + drawing

func _process(delta: float) -> void:
	t += delta
	dash_buf = maxf(0.0, dash_buf - delta)
	dash_flash = maxf(0.0, dash_flash - delta)
	if active and main.state == main.State.PLAYING and is_portrait():
		main.state = main.State.PAUSED
	if main.state != main.State.PLAYING:
		move_id = -1
		aim_id = -1
		aim_dragged = false
		for id in button_ids.keys():
			if button_ids[id] != "pause":
				button_ids.erase(id)
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	if is_portrait():
		_draw_rotate()
		return
	if main.state != main.State.PLAYING or main.player == null:
		return
	var pl = main.player
	var cyan := Color(0.4, 0.95, 1)
	# Target marker
	if _alive(target) and mode != "twin" and manual_t <= 0 and not aim_dragged:
		var c: Vector2 = target.position - main.camera.offset
		var r: float = target.radius + 9.0 + sin(t * 8.0) * 1.5
		var col := Color(1, 0.35, 0.4) if locked else Color(1, 0.95, 0.5, 0.85)
		for k in 4:
			var a := TAU * k / 4 + PI / 4
			var corner := c + Vector2.from_angle(a) * r
			draw_line(corner, corner + Vector2.from_angle(a + PI * 0.75) * 8, col, 2.0)
			draw_line(corner, corner + Vector2.from_angle(a - PI * 0.75) * 8, col, 2.0)
	# Move stick
	if move_id != -1:
		draw_circle(move_base, STICK_R, Color(cyan, 0.06))
		draw_arc(move_base, STICK_R, 0, TAU, 48, Color(cyan, 0.4), 2.0, true)
		var knob := move_base + (move_pos - move_base).limit_length(STICK_R)
		draw_circle(knob, 30, Color(cyan, 0.3))
		draw_arc(knob, 30, 0, TAU, 32, Color(cyan, 0.8), 2.0, true)
	else:
		draw_arc(MOVE_HINT, STICK_R, 0, TAU, 48, Color(cyan, 0.12), 2.0, true)
		draw_circle(MOVE_HINT, 26, Color(cyan, 0.07))
	# Aim stick
	if aim_id != -1:
		var col := Color(1, 0.9, 0.35)
		draw_circle(aim_base, STICK_R, Color(col, 0.05))
		draw_arc(aim_base, STICK_R, 0, TAU, 48, Color(col, 0.35 if aim_dragged else 0.15), 2.0, true)
		var knob := aim_base + (aim_pos - aim_base).limit_length(STICK_R)
		draw_circle(knob, 26, Color(col, 0.25))
		draw_arc(knob, 26, 0, TAU, 32, Color(col, 0.8), 2.0, true)
	# Dash button with cooldown sweep
	var k: float = 1.0 - pl.dash_cd / pl.dash_cd_max
	var ready: bool = k >= 1.0
	var dc := Color(0.35, 0.9, 1) if ready else Color(0.35, 0.6, 0.8)
	draw_circle(DASH_BTN, DASH_R, Color(0.03, 0.04, 0.09, 0.55))
	draw_circle(DASH_BTN, DASH_R, Color(dc, 0.25 if dash_flash > 0 else 0.08))
	draw_arc(DASH_BTN, DASH_R, 0, TAU, 48, Color(dc, 0.3), 2.0, true)
	if not ready:
		draw_arc(DASH_BTN, DASH_R, -PI / 2, -PI / 2 + TAU * k, 48, Color(dc, 0.9), 4.0, true)
	else:
		draw_arc(DASH_BTN, DASH_R, 0, TAU, 48, Color(dc, 0.85), 3.0, true)
	Icons.draw(self, "quick", DASH_BTN, 20.0, Color(dc, 0.95 if ready else 0.5))
	# Lock button
	if mode != "twin":
		var lc := Color(1, 0.35, 0.4) if locked else Color(1, 0.95, 0.5, 0.75 if _alive(target) else 0.3)
		draw_circle(LOCK_BTN, LOCK_R, Color(0.03, 0.04, 0.09, 0.55))
		draw_circle(LOCK_BTN, LOCK_R, Color(lc, 0.2 if locked else 0.06))
		draw_arc(LOCK_BTN, LOCK_R, 0, TAU, 40, Color(lc, 0.8), 2.0, true)
		Icons.draw(self, "crit", LOCK_BTN, 14.0, lc)
	# Pause button
	var pr := PAUSE_RECT
	draw_rect(pr, Color(0.03, 0.04, 0.09, 0.85))
	draw_rect(pr, Color(cyan, 0.5), false, 2.0)
	draw_rect(Rect2(pr.position + Vector2(12, 10), Vector2(5, 18)), Color(cyan, 0.9))
	draw_rect(Rect2(pr.position + Vector2(21, 10), Vector2(5, 18)), Color(cyan, 0.9))


func _draw_rotate() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, 0.96))
	var c := size / 2 + Vector2(0, -40)
	var a := sin(t * 2.0) * 0.5 + 0.5
	var phone := Rect2(-34, -60, 68, 120)
	draw_set_transform(c, lerpf(0.0, -PI / 2, a), Vector2.ONE)
	draw_rect(phone, Color(0.4, 0.95, 1, 0.9), false, 4.0)
	draw_circle(Vector2(0, 46), 5, Color(0.4, 0.95, 1, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var f: Font = main.ui_font()
	draw_string(f, Vector2(0, c.y + 130), main.t("rotate"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 40, Color(0.4, 0.95, 1))
