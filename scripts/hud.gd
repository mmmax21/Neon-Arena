extends Control
## Screen-space HUD, title / select / upgrade / pause / game-over overlays and the crosshair.

const Icons := preload("res://scripts/icons.gd")

# Mirrors main.gd State enum.
enum { TITLE, PLAYING, PAUSED, GAMEOVER, SELECT, UPGRADE }

const CARD_W := 290.0
const CARD_H := 330.0
const CARD_GAP := 36.0
const ICON := 30.0
const ICON_GAP := 5.0
const ICONS_PER_ROW := 6
const HUD_X := 44.0
const LANG_BUTTONS := {"en": Rect2(1030, 44, 96, 34), "zh": Rect2(1134, 44, 96, 34)}

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
	var hover := card_at(get_local_mouse_position())
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
	if r.has_point(get_local_mouse_position()):
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
			_icon_box(id, r, col, badge, title, main.t("cat_" + d["cat"]) + " · " + main.t("up_" + id + "_d"), tip)
	return bottom


# ---------------------------------------------------------------- screens

func _draw() -> void:
	if main == null:
		return
	tooltip = {}
	if main.state == TITLE:
		_draw_title()
	elif main.state == SELECT:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0.02, 0.7))
		_draw_cards(main.t("choose_weapon"), main.t("choose_weapon_sub"))
	else:
		_draw_game_hud()
		if main.state == UPGRADE:
			tooltip = {}
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0.02, 0.65))
			_draw_cards(main.t("wave_cleared") % main.wave, main.t("choose_upgrade_sub"))
		elif main.state == PAUSED:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
			_center(main.t("paused"), size.y * 0.45, 56, Color(0.4, 0.95, 1))
			_center(main.t("resume"), size.y * 0.45 + 50, 20, Color(1, 1, 1, 0.8))
			_center(main.t("lang_hint"), size.y * 0.45 + 84, 16, Color(1, 1, 1, 0.5))
		elif main.state == GAMEOVER:
			tooltip = {}
			_draw_gameover()
	_draw_tooltip()
	_draw_crosshair()


func _draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0.02, 0.6))
	var glow := 0.75 + 0.25 * sin(t * 3.0)
	_text("NEON ARENA", Vector2(0, size.y * 0.32), 88, Color(0.35, 0.95, 1, glow), HORIZONTAL_ALIGNMENT_CENTER, size.x, ThemeDB.fallback_font)
	_center(main.t("title_sub"), size.y * 0.32 + 44, 22, Color(1, 0.4, 0.7, 0.9))
	var y := size.y * 0.52
	for k in ["ctl_move", "ctl_aim", "ctl_dash", "ctl_pause", "", "ctl_build"]:
		if k != "":
			_center(main.t(k), y, 20, Color(0.85, 0.9, 1, 0.85))
		y += 30
	if int(t * 2) % 2 == 0:
		_center(main.t("click_start"), size.y * 0.84, 32, Color(1, 0.9, 0.35))
	if main.best > 0:
		_center(main.t("best_title") % main.best, size.y * 0.92, 20, Color(1, 1, 1, 0.6))
	# Language toggle; each label is drawn in its own script's font.
	var m := get_local_mouse_position()
	for l in LANG_BUTTONS:
		var r: Rect2 = LANG_BUTTONS[l]
		var on: bool = main.lang == l
		var col := Color(0.4, 0.95, 1) if on else Color(1, 1, 1, 0.55)
		draw_rect(r, Color(col, 0.18 if on else 0.05))
		draw_rect(r, Color(col, 0.9 if on or r.has_point(m) else 0.4), false, 2.0)
		var label := "English" if l == "en" else "中文"
		var f: Font = ThemeDB.fallback_font if l == "en" else main.FONT_ZH
		_text(label, r.position + Vector2(0, 24), 17, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, f)
	_text(main.t("lang_hint"), Vector2(1030, 100), 13, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 200)
	_text("v" + main.VERSION, Vector2(size.x - 244, size.y - 44), 14, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, 200, ThemeDB.fallback_font)


func _draw_game_hud() -> void:
	var pl = main.player
	if pl:
		# HP pips
		_text(main.t("hp"), Vector2(HUD_X, 64), 16, Color(1, 1, 1, 0.7))
		for i in pl.max_hp:
			var r := Rect2(92 + i * 24, 50, 18, 16)
			draw_rect(r, Color(0, 0, 0, 0.5))
			if i < pl.hp:
				var c := Color(1, 0.3, 0.4) if pl.hp <= 2 and int(t * 6) % 2 == 0 else Color(0.35, 1, 0.55)
				draw_rect(r.grow(-2), c)
			draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
		# Dash bar
		_text(main.t("dash"), Vector2(HUD_X, 90), 13, Color(1, 1, 1, 0.6))
		var k: float = 1.0 - pl.dash_cd / pl.dash_cd_max
		draw_rect(Rect2(92, 80, 120, 8), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(92, 80, 120 * k, 8), Color(0.3, 0.9, 1) if k >= 1.0 else Color(0.3, 0.6, 0.8))
		# Build: weapon + upgrades as icons
		var info_y := _draw_build(HUD_X, 102, ICONS_PER_ROW) + 16
		if pl.rapid > 0:
			_text(main.t("overdrive_t") % pl.rapid, Vector2(HUD_X, info_y), 15, Color(1, 0.9, 0.3))
			info_y += 22
		if pl.level("shield") > 0 and not pl.shield_up:
			_text(main.t("barrier_t") % ceili(pl.shield_cd), Vector2(HUD_X, info_y), 14, Color(0.6, 0.95, 1, 0.8))
	_center(main.t("wave") % main.wave, 66, 26, Color(0.4, 0.95, 1, 0.9))
	_draw_upgrade_meter(Vector2(size.x / 2, 86))
	_text("%d" % main.score, Vector2(size.x - 344, 66), 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, 300, ThemeDB.fallback_font)
	_text(main.t("best_hud") % maxi(main.best, main.score), Vector2(size.x - 344, 90), 15, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	if main.combo >= 2:
		var ck: float = clampf(main.combo_timer / 2.5, 0, 1)
		_text(main.t("combo") % main.combo, Vector2(size.x - 344, 118), 20, Color(1, 0.5, 0.8, 0.4 + ck * 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	# Boss bar
	var b = main.boss
	if b and is_instance_valid(b) and not b.dead:
		var w := 520.0
		var x := (size.x - w) / 2
		var y := size.y - 60
		_center(main.t("boss_" + b.type), y - 8, 16, b.color.lightened(0.2))
		draw_rect(Rect2(x, y, w, 12), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(x, y, w * maxf(b.hp, 0.0) / b.max_hp, 12), b.color)
		draw_rect(Rect2(x, y, w, 12), Color(1, 1, 1, 0.4), false, 1.0)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0, 0.02, 0.6 * a))
	_center(main.t("game_over"), size.y * 0.34, 72, Color(1, 0.3, 0.45, a))
	_center(main.t("score") % main.score, size.y * 0.34 + 60, 30, Color(1, 1, 1, a))
	var new_best: bool = main.score >= main.best and main.score > 0
	_center(main.t("new_best") if new_best else main.t("best_over") % main.best, size.y * 0.34 + 96, 20,
		Color(1, 0.9, 0.3, a) if new_best else Color(1, 1, 1, 0.6 * a))
	_center(main.t("stats") % [main.wave, main.kills, int(main.time_alive)], size.y * 0.34 + 130, 18, Color(0.8, 0.9, 1, 0.8 * a))
	if main.player and a >= 1.0:
		_draw_build(0, size.y * 0.34 + 150, 16, true)
	if main.gameover_timer > 0.8 and int(t * 2) % 2 == 0:
		_center(main.t("retry"), size.y * 0.76, 24, Color(1, 0.9, 0.35))


func _draw_crosshair() -> void:
	var m := get_local_mouse_position()
	var c := Color(1, 0.95, 0.5, 0.95)
	draw_arc(m, 10, 0, TAU, 24, c, 2.0, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(m + d * 5, m + d * 15, c, 2.0)
	draw_circle(m, 1.5, c)
