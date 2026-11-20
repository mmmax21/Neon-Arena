extends Control
## Screen-space HUD, title / select / upgrade / pause / game-over overlays and the crosshair.

const Icons := preload("res://scripts/icons.gd")

# Mirrors main.gd State enum.
enum { TITLE, PLAYING, PAUSED, GAMEOVER, SELECT, UPGRADE, BOARD, LOBBY }

const CARD_W := 290.0
const CARD_H := 330.0
const CARD_GAP := 36.0
const ICON := 30.0
const ICON_GAP := 5.0
const ICONS_PER_ROW := 6
const HUD_X := 44.0
const LANG_BUTTONS := {"en": Rect2(986, 44, 96, 34), "zh": Rect2(1090, 44, 96, 34)}
## Mute toggle, same spot on every screen (top-right corner).
const MUTE_RECT := Rect2(1198, 42, 38, 38)

var main: Node2D
var announce_text := ""
var announce_color := Color.WHITE
var announce_t := 0.0
var announce_font: Font = null  # the font of the language it was written in
var t := 0.0
var tooltip := {}  # {pos, title, body, color} set while drawing the HUD


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func announce(s: String, c: Color) -> void:
	announce_text = s
	announce_color = c
	announce_t = 2.0
	announce_font = main.ui_font()


func _process(delta: float) -> void:
	t += delta
	if main and main.state != PAUSED:
		announce_t = maxf(0.0, announce_t - delta)


func _font() -> Font:
	return main.ui_font()


func _text(s: String, pos: Vector2, fs: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, font: Font = null) -> void:
	if font == null:
		font = _font()
	draw_string(font, pos + Vector2(2, 2), s, align, w, fs, Color(0, 0, 0, c.a * 0.6))
	draw_string(font, pos, s, align, w, fs, c)


func _center(s: String, y: float, fs: int, c: Color) -> void:
	_text(s, Vector2(0, y), fs, c, HORIZONTAL_ALIGNMENT_CENTER, size.x)


# ---------------------------------------------------------------- cards

func card_rects(n: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var total := n * CARD_W + (n - 1) * CARD_GAP
	var x0 := (size.x - total) / 2.0
	var y := size.y * 0.5 - CARD_H / 2.0 + 40.0
	for i in n:
		out.append(Rect2(x0 + i * (CARD_W + CARD_GAP), y, CARD_W, CARD_H))
	return out


func card_at(pos: Vector2) -> int:
	if main == null:
		return -1
	var cards: Array = main.current_cards()
	var rects := card_rects(cards.size())
	for i in rects.size():
		if rects[i].has_point(pos):
			return i
	return -1


func mute_at(pos: Vector2) -> bool:
	return mute_rect().has_point(pos)


func _draw_mute_button() -> void:
	var r := mute_rect()
	var hot := r.has_point(main.pointer_pos())
	var col := Color(1, 0.45, 0.5) if main.muted else Color(0.4, 0.95, 1)
	draw_rect(r, Color(0.03, 0.04, 0.09, 0.85))
	draw_rect(r, Color(col, 0.18 if hot else 0.08))
	draw_rect(r, Color(col, 0.9 if hot else 0.5), false, 2.0)
	Icons.draw(self, "sound_off" if main.muted else "sound_on", r.get_center(), 12.0, col)
	if hot:
		var label: String = main.t("mute_on") if main.muted else main.t("mute_off")
		if _touch():
			label = label.replace("  (M)", "").replace("（M）", "")
		var w := _font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20
		var box := Rect2(r.end.x - w, r.end.y + 6, w, 26)
		draw_rect(box, Color(0.02, 0.03, 0.07, 0.95))
		draw_rect(box, Color(col, 0.8), false, 1.5)
		_text(label, box.position + Vector2(0, 18), 14, Color(col, 0.95), HORIZONTAL_ALIGNMENT_CENTER, w)


## The whole screen in frame coordinates (the HUD covers only the 1280×720 play frame).
func full_rect() -> Rect2:
	return Rect2(-position, get_viewport_rect().size)


func mute_rect() -> Rect2:
	if main.side_hud():
		return Rect2(main.W + main.side_margin() - 50, 42, 38, 38)
	return MUTE_RECT


func _touch() -> bool:
	return main.touch != null and main.touch.active


## Name of the score category whose best is shown (keyboard, twin-stick, hybrid or auto).
func _cat_name() -> String:
	return main.t("mode_" + main.score_cat())


## Touch control-mode button (title and pause screens, touch mode only).
func ctrl_rect() -> Rect2:
	if main.state == TITLE:
		return Rect2(986, 88, 200, 34)
	if main.state == PAUSED:
		return Rect2(size.x / 2 - 130, size.y * 0.45 + 70, 260, 42)
	return Rect2()


func ctrl_at(pos: Vector2) -> bool:
	var r := ctrl_rect()
	return r.size.x > 0 and r.has_point(pos)


func _draw_ctrl_button() -> void:
	var r := ctrl_rect()
	if r.size.x <= 0:
		return
	var col := Color(1, 0.85, 0.35)
	var hot := r.has_point(main.pointer_pos())
	draw_rect(r, Color(0.03, 0.04, 0.09, 0.9))
	draw_rect(r, Color(col, 0.2 if hot else 0.08))
	draw_rect(r, Color(col, 0.9 if hot else 0.6), false, 2.0)
	var label: String = main.t("ctrl_mode") % main.t("mode_" + main.touch.mode)
	_text(label, r.position + Vector2(0, r.size.y / 2 + 6), 17, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## Screen-shake setting button (title and pause screens).
func shake_rect() -> Rect2:
	if main.state == TITLE:
		return Rect2(986, 132, 200, 30)
	if main.state == PAUSED:
		return Rect2(size.x / 2 - 110, size.y * 0.45 + (190 if _touch() else 108), 220, 34)
	return Rect2()


func shake_at(pos: Vector2) -> bool:
	var r := shake_rect()
	return r.size.x > 0 and r.has_point(pos)


func _draw_shake_button() -> void:
	var r := shake_rect()
	if r.size.x > 0:
		_button(r, main.t("shake_btn") % main.t("shake_" + main.shake_setting), false, Color(0.8, 0.85, 1), 14)


func lang_at(pos: Vector2) -> String:
	for l in LANG_BUTTONS:
		if LANG_BUTTONS[l].has_point(pos):
			return l
	return ""


func _draw_cards(title: String, subtitle: String) -> void:
	var cards: Array = main.current_cards()
	_center(title, size.y * 0.5 - CARD_H / 2.0 - 34, 44, Color(0.4, 0.95, 1))
	_center(subtitle, size.y * 0.5 - CARD_H / 2.0 + 2, 18, Color(1, 1, 1, 0.7))
	var rects := card_rects(cards.size())
	var hover := card_at(main.pointer_pos())
	var locked: bool = main.card_lock > 0
	for i in cards.size():
		var c: Dictionary = cards[i]
		var col: Color = c["color"]
		var r := rects[i]
		var hot := i == hover and not locked
		if hot:
			r = r.grow(6)
		draw_rect(r, Color(0.03, 0.04, 0.09, 0.95))
		draw_rect(r, Color(col, 0.10 if not hot else 0.18))
		draw_rect(r, Color(col, 0.9 if hot else 0.55), false, 3.0 if hot else 2.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), col)
		_text(c["tag"], r.position + Vector2(0, 36), 15, Color(col, 0.85), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var ic := r.position + Vector2(r.size.x / 2, 82)
		draw_circle(ic, 31, Color(col, 0.10))
		draw_arc(ic, 31, 0, TAU, 40, Color(col, 0.5), 2.0, true)
		Icons.draw(self, c["icon"], ic, 20.0, col)
		_text(c["name"], r.position + Vector2(0, 150), 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var ly := r.position.y + 190
		for line in String(c["desc"]).split("\n"):
			_text(line, Vector2(r.position.x, ly), 18, Color(0.85, 0.9, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			ly += 25
		if c["level"] != "":
			_text(c["level"], Vector2(r.position.x, r.end.y - 46), 16, Color(col, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if not _touch():
			_text("[%d]" % (i + 1), Vector2(r.position.x, r.end.y - 16), 16, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# ---------------------------------------------------------------- icons

## Framed icon. Hovering it queues a tooltip at tip_pos.
func _icon_box(id: String, r: Rect2, col: Color, badge: String, tip_title: String, tip_body: String, tip_pos: Vector2) -> void:
	draw_rect(r, Color(0.03, 0.04, 0.09, 0.85))
	draw_rect(r, Color(col, 0.12))
	draw_rect(r, Color(col, 0.75), false, 1.5)
	Icons.draw(self, id, r.get_center(), r.size.x * 0.32, col)
	if badge != "":
		var bp := r.end - Vector2(11, 1)
		draw_rect(Rect2(bp - Vector2(1, 11), Vector2(12, 12)), Color(0, 0, 0, 0.75))
		_text(badge, bp + Vector2(0, -1), 11, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeDB.fallback_font)
	if r.has_point(main.pointer_pos()):
		draw_rect(r.grow(2), Color(col, 0.9), false, 1.5)
		tooltip = {"pos": tip_pos, "title": tip_title, "body": tip_body, "color": col}


func _draw_tooltip() -> void:
	if tooltip.is_empty():
		return
	var lines := String(tooltip["body"]).split("\n")
	var w := 230.0
	var h := 34.0 + lines.size() * 20.0
	var p: Vector2 = tooltip["pos"]
	var col: Color = tooltip["color"]
	var r := Rect2(p, Vector2(w, h))
	draw_rect(r, Color(0.02, 0.03, 0.07, 0.95))
	draw_rect(r, Color(col, 0.8), false, 1.5)
	_text(tooltip["title"], p + Vector2(10, 24), 16, col)
	var y := p.y + 46
	for l in lines:
		_text(l, Vector2(p.x + 10, y), 14, Color(0.85, 0.9, 1, 0.9))
		y += 20


## Weapon + upgrade icons in a wrapped row; returns the y below the last row.
func _draw_build(x0: float, y0: float, per_row: int, centered := false) -> float:
	var pl = main.player
	var items: Array = main.owned_upgrades()
	var n := items.size() + 1
	var cols := mini(n, per_row)
	var x_start := x0
	if centered:
		x_start = (size.x - (cols * (ICON + ICON_GAP) - ICON_GAP)) / 2.0
	var wi: Dictionary = main.weapon_info(pl.weapon)
	var bottom := y0 + ceili(float(n) / per_row) * (ICON + ICON_GAP)
	for i in n:
		var r := Rect2(x_start + (i % per_row) * (ICON + ICON_GAP), y0 + (i / per_row) * (ICON + ICON_GAP), ICON, ICON)
		# Tooltips sit beside (HUD) or below (results) the whole grid so they never cover icons.
		var tip := Vector2(r.position.x - 40, bottom + 6) if centered else Vector2(x0 + per_row * (ICON + ICON_GAP) + 6, r.position.y)
		if i == 0:
			_icon_box(pl.weapon, r, wi["color"], "", wi["name"], wi["desc"], tip)
		else:
			var id: String = items[i - 1][0]
			var lvl: int = items[i - 1][1]
			var d: Dictionary = main.UPGRADES[id]
			var col: Color = main.CAT_COLORS[d["cat"]]
			var badge := "" if int(d["max"]) == 1 else str(lvl)
			var title: String = main.t("up_" + id) + ("" if badge == "" else "  %d/%d" % [lvl, int(d["max"])])
			var desc: String = main.t("cat_" + d["cat"]) + " · " + main.t("up_" + id + "_d")
			var hint: String = main.evo_hint(id)
			if hint != "":
				desc += "\n" + hint
			_icon_box(id, r, col, badge, title, desc, tip)
	return bottom


# ---------------------------------------------------------------- off-screen indicators

## Arrows on the screen edge for enemies and spawn warnings outside the view, so the larger,
## scrolling arena keeps the "nothing hits you unannounced" promise of the single screen.
func _draw_offscreen() -> void:
	if main.player == null or main.state == GAMEOVER:
		return
	var view: Rect2 = main.view_rect()
	var frame := full_rect().grow(-18)
	var centre := frame.get_center()
	var items: Array = []
	for e in main.enemies:
		if not e.dead and e.type != "mine" and not view.grow(-4).has_point(e.position):
			items.append([e.position, e.color, e.is_boss, 1.0])
	for m in main.spawn_markers:
		if not view.has_point(m["p"]):
			items.append([m["p"], Color(1, 0.35, 0.4), String(m["type"]).begins_with("boss"), 0.5 + 0.5 * sin(t * 14.0)])
	for it in items:
		var hp: Vector2 = main.world_to_hud(it[0])
		var d: Vector2 = hp - centre
		if d.length() < 1.0:
			continue
		# Intersect the ray centre -> target with the frame.
		var sx: float = (frame.size.x / 2.0) / absf(d.x) if absf(d.x) > 0.001 else INF
		var sy: float = (frame.size.y / 2.0) / absf(d.y) if absf(d.y) > 0.001 else INF
		var edge: Vector2 = centre + d * minf(sx, sy)
		var dir := d.normalized()
		var dist: float = (it[0] as Vector2).distance_to(main.player.position)
		var size_k := clampf(1.4 - dist / 1400.0, 0.6, 1.2) * (1.6 if it[2] else 1.0)
		var a := 10.0 * size_k
		var tip := edge
		var pts := PackedVector2Array([tip, tip - dir * a * 1.6 + dir.orthogonal() * a,
			tip - dir * a * 1.6 - dir.orthogonal() * a])
		var col: Color = it[1]
		draw_colored_polygon(pts, Color(col, 0.75 * float(it[3])))


# ---------------------------------------------------------------- screens

func _draw() -> void:
	if main == null:
		return
	tooltip = {}
	if main.state == TITLE:
		_draw_title()
	elif main.state == BOARD:
		draw_rect(full_rect(), Color(0, 0, 0.02, 0.82))
		_draw_board()
	elif main.state == LOBBY:
		draw_rect(full_rect(), Color(0, 0, 0.02, 0.82))
		_draw_lobby()
	elif main.state == SELECT:
		draw_rect(full_rect(), Color(0, 0, 0.02, 0.7))
		_draw_cards(main.t("choose_weapon"), main.t("choose_weapon_sub_t" if _touch() else "choose_weapon_sub"))
	else:
		_draw_offscreen()
		_draw_game_hud()
		if main.state == UPGRADE:
			tooltip = {}
			draw_rect(full_rect(), Color(0, 0, 0.02, 0.65))
			if main.offer.is_empty():
				# Co-op: our card is in, the teammate is still choosing (or the offer is on its way).
				_center(main.t("wave_cleared") % main.wave, size.y * 0.42, 44, Color(0.4, 0.95, 1))
				_center(main.t("coop_wait_pick"), size.y * 0.42 + 46, 22, Color(1, 1, 1, 0.75))
			else:
				_draw_cards(main.t("wave_cleared") % main.wave, main.t("choose_upgrade_sub_t" if _touch() else "choose_upgrade_sub"))
		elif main.state == PAUSED:
			draw_rect(full_rect(), Color(0, 0, 0, 0.55))
			_center(main.t("paused"), size.y * 0.45, 56, Color(0.4, 0.95, 1))
			if _touch():
				_center(main.t("resume_t"), size.y * 0.45 + 50, 20, Color(1, 1, 1, 0.8))
				_draw_ctrl_button()
				_center(main.t("mode_" + main.touch.mode + "_d"), size.y * 0.45 + 140, 16, Color(1, 1, 1, 0.55))
				_center(main.t("icon_hint_t"), size.y * 0.45 + 166, 15, Color(1, 1, 1, 0.4))
			else:
				_center(main.t("resume"), size.y * 0.45 + 50, 20, Color(1, 1, 1, 0.8))
				_center(main.t("lang_hint"), size.y * 0.45 + 84, 16, Color(1, 1, 1, 0.5))
			_draw_shake_button()
		elif main.state == GAMEOVER:
			tooltip = {}
			_draw_gameover()
	_draw_mute_button()
	_draw_tooltip()
	_draw_crosshair()


func _draw_title() -> void:
	draw_rect(full_rect(), Color(0, 0, 0.02, 0.6))
	var glow := 0.75 + 0.25 * sin(t * 3.0)
	_text("NEON ARENA", Vector2(0, size.y * 0.32), 88, Color(0.35, 0.95, 1, glow), HORIZONTAL_ALIGNMENT_CENTER, size.x, ThemeDB.fallback_font)
	_center(main.t("title_sub"), size.y * 0.32 + 44, 22, Color(1, 0.4, 0.7, 0.9))
	var y := size.y * 0.52
	var lines := ["ctl_move", "ctl_aim", "ctl_dash", "ctl_pause", "", "ctl_build"]
	if _touch():
		lines = ["ctl_t_move", "mode_" + main.touch.mode + "_d", "ctl_t_dash", "ctl_t_pause", "", "ctl_build"]
	for k in lines:
		if k != "":
			_center(main.t(k), y, 20, Color(0.85, 0.9, 1, 0.85))
		y += 30
	if int(t * 2) % 2 == 0:
		_center(main.t("tap_start" if _touch() else "click_start"), size.y * 0.84, 32, Color(1, 0.9, 0.35))
	if main.best > 0:
		_center(main.t("best_title") % [_cat_name(), main.best], size.y * 0.92, 20, Color(1, 1, 1, 0.6))
	# Language toggle; each label is drawn in its own script's font.
	var m: Vector2 = main.pointer_pos()
	for l in LANG_BUTTONS:
		var r: Rect2 = LANG_BUTTONS[l]
		var on: bool = main.lang == l
		var col := Color(0.4, 0.95, 1) if on else Color(1, 1, 1, 0.55)
		draw_rect(r, Color(col, 0.18 if on else 0.05))
		draw_rect(r, Color(col, 0.9 if on or r.has_point(m) else 0.4), false, 2.0)
		var label := "English" if l == "en" else "中文"
		var f: Font = ThemeDB.fallback_font if l == "en" else main.FONT_ZH
		_text(label, r.position + Vector2(0, 24), 17, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, f)
	if _touch():
		_draw_ctrl_button()
	else:
		_text(main.t("lang_hint"), Vector2(786, 100), 13, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, 400)
	_draw_board_button()
	_draw_shake_button()
	_text("v" + main.VERSION, Vector2(size.x - 244, size.y - 44), 14, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, 200, ThemeDB.fallback_font)


func _draw_teammate() -> void:
	if main.players.size() < 2 or main.player == null:
		return
	for p in main.players:
		if p == main.player or not is_instance_valid(p):
			continue
		var col: Color = p.ship_color()
		var label: String = main.t("coop_mate") + ("  " + main.t("coop_mate_down") if p.dead else "")
		_text(label, Vector2(HUD_X, size.y - 34), 15, Color(col, 0.85))
		for i in p.max_hp:
			var r := Rect2(HUD_X + 70 + i * 16, size.y - 46, 12, 10)
			draw_rect(r, Color(0, 0, 0, 0.5))
			if i < p.hp and not p.dead:
				draw_rect(r, Color(col, 0.85))
	if main.player.dead:
		_center(main.t("coop_you_down"), size.y * 0.3, 22, Color(1, 0.5, 0.6))


func _draw_game_hud() -> void:
	_draw_teammate()
	var pl = main.player
	var side: bool = main.side_hud()
	var m: float = main.side_margin()
	var lx := -m + 12.0 if side else HUD_X
	if pl:
		# HP pips (in the left margin on phones: four per row)
		_text(main.t("hp"), Vector2(lx, 64), 16, Color(1, 1, 1, 0.7))
		var hp_rows := ceili(pl.max_hp / 4.0) if side else 1
		for i in pl.max_hp:
			var r := Rect2(lx + (i % 4) * 24, 74 + (i / 4) * 22, 18, 16) if side else Rect2(92 + i * 24, 50, 18, 16)
			draw_rect(r, Color(0, 0, 0, 0.5))
			if i < pl.hp:
				var c := Color(1, 0.3, 0.4) if pl.hp <= 2 and int(t * 6) % 2 == 0 else Color(0.35, 1, 0.55)
				draw_rect(r.grow(-2), c)
			draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
		# Dash bar
		var k: float = 1.0 - pl.dash_cd / pl.dash_cd_max
		var dash_col := Color(0.3, 0.9, 1) if k >= 1.0 else Color(0.3, 0.6, 0.8)
		var build_y := 102.0
		if side:
			var dy := 74.0 + hp_rows * 22.0 + 14.0
			_text(main.t("dash"), Vector2(lx, dy), 13, Color(1, 1, 1, 0.6))
			var bw := m - 24.0
			draw_rect(Rect2(lx, dy + 6, bw, 8), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(lx, dy + 6, bw * k, 8), dash_col)
			build_y = dy + 26.0
		else:
			_text(main.t("dash"), Vector2(HUD_X, 90), 13, Color(1, 1, 1, 0.6))
			draw_rect(Rect2(92, 80, 120, 8), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(92, 80, 120 * k, 8), dash_col)
		# Build: weapon + upgrades as icons
		var per_row := maxi(1, int((m - 16.0) / (ICON + ICON_GAP))) if side else ICONS_PER_ROW
		var info_y := _draw_build(lx, build_y, per_row) + 16
		if pl.rapid > 0:
			_text(main.t("overdrive_t") % pl.rapid, Vector2(lx, info_y), 15, Color(1, 0.9, 0.3))
			info_y += 22
		if pl.level("shield") > 0 and not pl.shield_up:
			_text(main.t("barrier_t") % ceili(pl.shield_cd), Vector2(lx, info_y), 14, Color(0.6, 0.95, 1, 0.8))
	_center(main.t("wave") % main.wave, 66, 26, Color(0.4, 0.95, 1, 0.9))
	_draw_upgrade_meter(Vector2(size.x / 2, 86))
	_center(main.t("arena_label") % main.arena.display_name(), 112, 13, Color(1, 0.85, 0.35, 0.55))
	# While a new layout rises, a one-line hint explains its mechanism.
	if not main.arena.mechanisms_on() and main.wave > 0:
		var h: String = main.arena.hint()
		if h != "":
			_center(h, size.y * 0.3 + 46, 18, Color(1, 0.85, 0.35, 0.8 + 0.2 * sin(t * 8.0)))
	# Score column: top-right of the arena, or the right margin (under mute / pause) on phones
	var rx: float = main.W + m - 312.0 if side else size.x - 394.0
	var ry := 168.0 if side else 66.0
	_text("%d" % main.score, Vector2(rx, ry), 30 if not side else 26, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, 300, ThemeDB.fallback_font)
	_text(main.t("best_hud") % [_cat_name(), maxi(main.best, main.score)], Vector2(rx, ry + 24), 15 if not side else 13, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	if main.combo >= 2:
		var ck: float = clampf(main.combo_timer / 2.5, 0, 1)
		_text(main.t("combo") % main.combo, Vector2(rx, ry + 52), 20 if not side else 17, Color(1, 0.5, 0.8, 0.4 + ck * 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	# Boss bar
	var b = main.boss
	if b and is_instance_valid(b) and not b.dead:
		var w := 520.0
		var x := (size.x - w) / 2
		var y := size.y - 60
		_center(main.t("boss_" + b.type), y - 8, 16, b.color.lightened(0.2))
		draw_rect(Rect2(x, y, w, 12), Color(0, 0, 0, 0.6))
		var bar_col: Color = Color(1, 1, 1) if b.invulnerable() else b.color
		draw_rect(Rect2(x, y, w * maxf(b.hp, 0.0) / b.max_hp, 12), bar_col)
		draw_rect(Rect2(x, y, w, 12), Color(1, 1, 1, 0.4), false, 1.0)
		for f in b.BOSS_PHASE_AT:
			draw_line(Vector2(x + w * f, y - 3), Vector2(x + w * f, y + 15), Color(1, 1, 1, 0.8), 2.0)
	# Announcement
	if announce_t > 0 and (main.state == PLAYING or main.state == PAUSED):
		var a := clampf(announce_t, 0, 1)
		var scale_in := 1.0 + maxf(0.0, announce_t - 1.7) * 1.5
		_text(announce_text, Vector2(0, size.y * 0.3), int(48 * scale_in), Color(announce_color, a), HORIZONTAL_ALIGNMENT_CENTER, size.x, announce_font)


## "UPGRADE ◆◆◇": waves cleared toward the next upgrade card.
func _draw_upgrade_meter(c: Vector2) -> void:
	var total: int = main.UPGRADE_EVERY
	var filled: int = main.waves_since_upgrade
	var label: String = main.t("upgrade_meter")
	var font := _font()
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var pip_w := 16.0
	var full_w := lw + 8 + total * pip_w
	var x := c.x - full_w / 2
	_text(label, Vector2(x, c.y + 5), 13, Color(1, 1, 1, 0.55))
	x += lw + 8 + pip_w / 2
	for i in total:
		var p := Vector2(x + i * pip_w, c.y)
		var pts := PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)])
		if i < filled:
			draw_colored_polygon(pts, Color(1, 0.85, 0.35, 0.95))
		else:
			pts.append(pts[0])
			draw_polyline(pts, Color(1, 0.85, 0.35, 0.5), 1.5, true)


func _draw_gameover() -> void:
	var a := clampf(main.gameover_timer * 1.5, 0, 1)
	draw_rect(full_rect(), Color(0.05, 0, 0.02, 0.6 * a))
	_center(main.t("game_over"), size.y * 0.34, 72, Color(1, 0.3, 0.45, a))
	_center(main.t("score") % main.score, size.y * 0.34 + 60, 30, Color(1, 1, 1, a))
	var new_best: bool = main.score >= main.best and main.score > 0
	_center(main.t("new_best") % _cat_name() if new_best else main.t("best_over") % [_cat_name(), main.best], size.y * 0.34 + 96, 20,
		Color(1, 0.9, 0.3, a) if new_best else Color(1, 1, 1, 0.6 * a))
	_center(main.t("stats") % [main.wave, main.kills, int(main.time_alive)], size.y * 0.34 + 130, 18, Color(0.8, 0.9, 1, 0.8 * a))
	if main.player and a >= 1.0:
		_draw_build(0, size.y * 0.34 + 150, 16, true)
	var online := _online_result()
	if online != "":
		_center(online, size.y * 0.69, 18, Color(0.45, 0.95, 1, 0.9 * a))
	if main.coop.active():
		_center(main.t("coop_no_board"), size.y * 0.69, 18, Color(0.45, 0.95, 1, 0.9 * a))
		if main.gameover_timer > 0.8 and int(t * 2) % 2 == 0:
			_center(main.t("coop_back_lobby"), size.y * 0.76, 24, Color(1, 0.9, 0.35))
		return
	if main.gameover_timer > 0.8 and int(t * 2) % 2 == 0:
		_center(main.t("retry_t" if _touch() else "retry"), size.y * 0.76, 24, Color(1, 0.9, 0.35))
	if main.gameover_timer > 0.8:
		_draw_board_button()


func _draw_crosshair() -> void:
	if _touch():
		return
	var m: Vector2 = main.pointer_pos()
	var c := Color(1, 0.95, 0.5, 0.95)
	draw_arc(m, 10, 0, TAU, 24, c, 2.0, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(m + d * 5, m + d * 15, c, 2.0)
	draw_circle(m, 1.5, c)


# ---------------------------------------------------------------- leaderboard

## "Leaderboard" button on the title and game-over screens (hidden until a server is set).
func board_button_rect() -> Rect2:
	if not main.net.enabled():
		return Rect2()
	if main.state == TITLE:
		return Rect2(44, size.y - 84, 200, 44)
	if main.state == GAMEOVER and main.gameover_timer > 0.8:
		return Rect2(size.x / 2 - 120, size.y * 0.83, 240, 44)
	return Rect2()


func board_button_at(pos: Vector2) -> bool:
	var r := board_button_rect()
	return r.size.x > 0 and r.has_point(pos)


func _draw_board_button() -> void:
	var r := board_button_rect()
	if r.size.x > 0:
		_button(r, main.t("lb_button"), false, Color(0.45, 0.95, 1), 18)
	var cr := coop_button_rect()
	if cr.size.x > 0:
		_button(cr, main.t("coop_button"), false, Color(1, 0.45, 0.85), 18)


# ---------------------------------------------------------------- co-op lobby

func coop_button_rect() -> Rect2:
	if not main.net.enabled() or main.state != TITLE:
		return Rect2()
	return Rect2(256, size.y - 84, 200, 44)


func coop_button_at(pos: Vector2) -> bool:
	var r := coop_button_rect()
	return r.size.x > 0 and r.has_point(pos)


func lobby_buttons() -> Array:
	var c = main.coop
	var out: Array = []
	var cx := size.x / 2
	var by := size.y * 0.74
	var w := 130.0
	var x0 := cx - (3 * w + 20) / 2
	for i in main.WEAPON_ORDER.size():
		out.append({"kind": "weapon", "value": main.WEAPON_ORDER[i], "rect": Rect2(x0 + i * (w + 10), size.y * 0.56, w, 40)})
	if c.role == "":
		out.append({"kind": "create", "rect": Rect2(cx - 230, by, 220, 48)})
		out.append({"kind": "join", "rect": Rect2(cx + 10, by, 220, 48)})
	else:
		if c.role == "host":
			out.append({"kind": "start", "rect": Rect2(cx - 230, by, 220, 48), "on": c.peer_here})
		out.append({"kind": "leave", "rect": Rect2(cx + 10 if c.role == "host" else cx - 110, by, 220, 48)})
	out.append({"kind": "back", "rect": Rect2(size.x - 110 - 160, size.y - 70, 160, 40)})
	return out


func _draw_lobby() -> void:
	var c = main.coop
	_center(main.t("coop_title"), 90, 36, Color(1, 0.45, 0.85))
	_center(main.t("coop_sub"), 124, 17, Color(1, 1, 1, 0.6))
	var y := size.y * 0.30
	if c.code != "":
		_center(main.t("coop_room"), y, 18, Color(1, 1, 1, 0.65))
		_text(c.code, Vector2(0, y + 62), 64, Color(1, 0.9, 0.35), HORIZONTAL_ALIGNMENT_CENTER, size.x, ThemeDB.fallback_font)
	var st: String = c.status
	var line := ""
	if st.begins_with("err_"):
		line = main.t("coop_" + st)
	elif st == "creating" or st == "connecting":
		line = main.t("coop_connecting")
	elif c.role == "host":
		line = main.t("coop_ready_host") if c.peer_here else main.t("coop_waiting")
	elif c.role == "guest" and st == "ready":
		line = main.t("coop_ready_guest")
		if c.rtt_ms >= 0:
			line += "   " + main.t("coop_ping") % c.rtt_ms
	elif c.role == "":
		line = main.t("coop_intro")
	var col := Color(1, 0.45, 0.4) if st.begins_with("err_") else Color(0.45, 0.95, 1)
	_center(line, y + 100, 20, col)
	_center(main.t("coop_weapon"), size.y * 0.56 - 12, 16, Color(1, 1, 1, 0.6))
	for b in lobby_buttons():
		var r: Rect2 = b["rect"]
		match b["kind"]:
			"weapon":
				var wi: Dictionary = main.weapon_info(b["value"])
				_button(r, wi["name"], main.weapon == b["value"], wi["color"], 16)
			"create":
				_button(r, main.t("coop_create"), false, Color(1, 0.45, 0.85), 18)
			"join":
				_button(r, main.t("coop_join"), false, Color(0.45, 0.95, 1), 18)
			"start":
				_button(r, main.t("coop_start"), b.get("on", true), Color(0.5, 1, 0.6) if b.get("on", true) else Color(1, 1, 1, 0.35), 18)
			"leave":
				_button(r, main.t("coop_leave"), false, Color(1, 0.6, 0.4), 18)
			"back":
				_button(r, main.t("lb_back"), false, Color(1, 1, 1, 0.8), 16)


func _button(r: Rect2, label: String, on: bool, col: Color, fs := 16) -> void:
	var hot := r.has_point(main.pointer_pos())
	draw_rect(r, Color(0.03, 0.04, 0.09, 0.9))
	draw_rect(r, Color(col, 0.25 if on else (0.14 if hot else 0.05)))
	draw_rect(r, Color(col, 0.95 if on or hot else 0.45), false, 2.0)
	_text(label, r.position + Vector2(0, r.size.y / 2 + fs * 0.36), fs, col if on or hot else Color(col, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _tab_row(out: Array, kind: String, values: Array, y: float, w: float, h: float) -> void:
	var gap := 10.0
	var total := values.size() * w + (values.size() - 1) * gap
	var x := (size.x - total) / 2
	for v in values:
		out.append({"kind": kind, "value": v, "rect": Rect2(x, y, w, h)})
		x += w + gap


## Every clickable element of the leaderboard screen; drawing and clicks both use this.
func board_buttons() -> Array:
	var out: Array = []
	_tab_row(out, "platform", main.net.PLATFORMS, 96, 140, 38)
	_tab_row(out, "mode", main.net.MODES, 144, 140, 32)
	_tab_row(out, "period", main.net.PERIODS, 186, 120, 30)
	out.append({"kind": "rename", "value": "", "rect": Rect2(110, size.y - 70, 320, 40)})
	out.append({"kind": "back", "value": "", "rect": Rect2(size.x - 110 - 160, size.y - 70, 160, 40)})
	return out


func _draw_board() -> void:
	var net = main.net
	_center(main.t("lb_title") % net.season, 64, 32, Color(0.45, 0.95, 1))
	for b in board_buttons():
		var r: Rect2 = b["rect"]
		match b["kind"]:
			"platform":
				_button(r, main.t("plat_" + b["value"]), main.board_platform == b["value"], Color(1, 0.85, 0.35), 18)
			"mode":
				_button(r, main.t("mode_" + b["value"]), main.board_mode == b["value"], Color(0.45, 0.95, 1), 15)
			"period":
				_button(r, main.t("per_" + b["value"]), main.board_period == b["value"], Color(1, 0.5, 0.8), 14)
			"rename":
				_button(r, main.t("lb_rename") % net.display_name(), false, Color(0.8, 0.85, 1), 15)
			"back":
				_button(r, main.t("lb_back"), false, Color(1, 1, 1), 16)
	var top := 236.0
	var row_h := 33.0
	var data: Dictionary = net.board
	var entries: Array = data.get("entries", [])
	if entries.is_empty():
		var msg := ""
		match net.board_state:
			"loading":
				msg = main.t("lb_loading")
			"error":
				msg = main.t("lb_offline")
			"ok":
				msg = main.t("lb_empty")
		_center(msg, top + 150, 20, Color(1, 1, 1, 0.6))
	else:
		for i in entries.size():
			var e: Dictionary = entries[i]
			var col_i := i / 10
			var x := 110.0 + col_i * 540.0
			var y := top + (i % 10) * row_h
			var w := 520.0
			var me: bool = e.get("me", false)
			var rank := int(e["rank"])
			if me:
				draw_rect(Rect2(x - 8, y, w + 16, row_h - 3), Color(0.45, 0.95, 1, 0.16))
			elif i % 2 == 0:
				draw_rect(Rect2(x - 8, y, w + 16, row_h - 3), Color(1, 1, 1, 0.03))
			var rc := Color(1, 0.85, 0.35) if rank == 1 else (Color(0.85, 0.9, 1) if rank <= 3 else Color(1, 1, 1, 0.6))
			_text("#%d" % rank, Vector2(x, y + 22), 16, rc, HORIZONTAL_ALIGNMENT_LEFT, -1, ThemeDB.fallback_font)
			Icons.draw(self, String(e.get("weapon", "pulse")), Vector2(x + 70, y + 15), 8.0, main.WEAPONS.get(String(e.get("weapon", "pulse")), {"color": Color.WHITE})["color"])
			_text(String(e["name"]), Vector2(x + 88, y + 22), 16, Color(0.45, 0.95, 1) if me else Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT, 230)
			_text(main.t("lb_wave") % int(e.get("wave", 0)), Vector2(x + 320, y + 22), 13, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT, 80)
			_text("%d" % int(e["score"]), Vector2(x + 400, y + 22), 17, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, 120, ThemeDB.fallback_font)
	# My standing on this board
	if net.board_state == "ok" or not data.is_empty():
		var me = data.get("me")
		var line: String = main.t("lb_me_none")
		if me is Dictionary:
			line = main.t("lb_me") % [int(me["rank"]), int(me["score"]), int(me["total"])]
			if int(me.get("gap", 0)) > 0:
				line += "    " + main.t("rank_gap") % int(me["gap"])
		_center(line, top + 10 * row_h + 26, 17, Color(0.45, 0.95, 1, 0.9))
	_text(main.t("lb_platform_you") % main.t("plat_" + net.platform), Vector2(0, size.y - 44), 13, Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_CENTER, size.x)


## One line for the game-over screen about the online result of this run.
func _online_result() -> String:
	var net = main.net
	var board_name: String = main.t("plat_" + net.platform) + " · " + main.t("mode_" + main.run_cat)
	match net.run_state:
		"submitting", "starting", "ready":
			return main.t("rank_sending")
		"offline", "error":
			return main.t("rank_offline")
		"flagged":
			return main.t("rank_flagged")
		"done":
			var wk = net.result.get("week")
			var al = net.result.get("all")
			if wk is Dictionary and al is Dictionary:
				var s: String = main.t("rank_line") % [board_name, int(wk["rank"]), int(al["rank"]), int(al["total"])]
				if int(al.get("gap", 0)) > 0:
					s += "    " + main.t("rank_gap") % int(al["gap"])
				return s
	return ""
