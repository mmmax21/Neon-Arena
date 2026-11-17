extends Control
## Screen-space HUD, title / pause / game-over overlays and the crosshair.

# Mirrors main.gd State enum.
enum { TITLE, PLAYING, PAUSED, GAMEOVER }

var main: Node2D
var announce_text := ""
var announce_color := Color.WHITE
var announce_t := 0.0
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func announce(s: String, c: Color) -> void:
	announce_text = s
	announce_color = c
	announce_t = 2.0


func _process(delta: float) -> void:
	t += delta
	if main and main.state != PAUSED:
		announce_t = maxf(0.0, announce_t - delta)


func _text(s: String, pos: Vector2, fs: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(2, 2), s, align, w, fs, Color(0, 0, 0, c.a * 0.6))
	draw_string(font, pos, s, align, w, fs, c)


func _center(s: String, y: float, fs: int, c: Color) -> void:
	_text(s, Vector2(0, y), fs, c, HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _draw() -> void:
	if main == null:
		return
	if main.state == TITLE:
		_draw_title()
	else:
		_draw_game_hud()
		if main.state == PAUSED:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
			_center("PAUSED", size.y * 0.45, 56, Color(0.4, 0.95, 1))
			_center("Press P / Esc or click to resume", size.y * 0.45 + 50, 20, Color(1, 1, 1, 0.8))
		elif main.state == GAMEOVER:
			_draw_gameover()
	_draw_crosshair()


func _draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0.02, 0.6))
	var glow := 0.75 + 0.25 * sin(t * 3.0)
	_center("NEON ARENA", size.y * 0.32, 88, Color(0.35, 0.95, 1, glow))
	_center("top-down arena shooter", size.y * 0.32 + 44, 22, Color(1, 0.4, 0.7, 0.9))
	var lines := [
		"WASD / Arrows  —  move",
		"Mouse  —  aim        Hold Left Click  —  fire",
		"Space / Shift / Right Click  —  dash (brief invincibility)",
		"P / Esc  —  pause",
	]
	var y := size.y * 0.52
	for l in lines:
		_center(l, y, 20, Color(0.85, 0.9, 1, 0.85))
		y += 32
	if int(t * 2) % 2 == 0:
		_center("CLICK TO START", size.y * 0.82, 32, Color(1, 0.9, 0.35))
	if main.best > 0:
		_center("BEST  %d" % main.best, size.y * 0.9, 20, Color(1, 1, 1, 0.6))


func _draw_game_hud() -> void:
	var pl = main.player
	if pl:
		# HP pips
		_text("HP", Vector2(44, 64), 18, Color(1, 1, 1, 0.7))
		for i in pl.max_hp:
			var r := Rect2(78 + i * 24, 50, 18, 16)
			draw_rect(r, Color(0, 0, 0, 0.5))
			if i < pl.hp:
				var c := Color(1, 0.3, 0.4) if pl.hp <= 2 and int(t * 6) % 2 == 0 else Color(0.35, 1, 0.55)
				draw_rect(r.grow(-2), c)
			draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
		# Dash bar
		_text("DASH", Vector2(44, 92), 14, Color(1, 1, 1, 0.6))
		var k: float = 1.0 - pl.dash_cd / pl.dash_cd_max
		draw_rect(Rect2(90, 81, 120, 8), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(90, 81, 120 * k, 8), Color(0.3, 0.9, 1) if k >= 1.0 else Color(0.3, 0.6, 0.8))
		if pl.rapid > 0:
			_text("RAPID FIRE  %.1f" % pl.rapid, Vector2(44, 118), 16, Color(1, 0.9, 0.3))
	_center("WAVE %d" % main.wave, 66, 26, Color(0.4, 0.95, 1, 0.9))
	_text("%d" % main.score, Vector2(size.x - 344, 66), 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	_text("BEST %d" % maxi(main.best, main.score), Vector2(size.x - 344, 90), 15, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	if main.combo >= 2:
		var ck: float = clampf(main.combo_timer / 2.5, 0, 1)
		_text("COMBO x%d" % main.combo, Vector2(size.x - 344, 118), 20, Color(1, 0.5, 0.8, 0.4 + ck * 0.6), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	# Boss bar
	var b = main.boss
	if b and is_instance_valid(b) and not b.dead:
		var w := 520.0
		var x := (size.x - w) / 2
		var y := size.y - 60
		_center("CORE WARDEN", y - 8, 16, Color(1, 0.4, 0.7))
		draw_rect(Rect2(x, y, w, 12), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(x, y, w * b.hp / b.max_hp, 12), Color(1, 0.3, 0.65))
		draw_rect(Rect2(x, y, w, 12), Color(1, 1, 1, 0.4), false, 1.0)
	# Announcement
	if announce_t > 0:
		var a := clampf(announce_t, 0, 1)
		var scale_in := 1.0 + maxf(0.0, announce_t - 1.7) * 1.5
		_center(announce_text, size.y * 0.3, int(48 * scale_in), Color(announce_color, a))


func _draw_gameover() -> void:
	var a := clampf(main.gameover_timer * 1.5, 0, 1)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0, 0.02, 0.6 * a))
	_center("GAME OVER", size.y * 0.36, 72, Color(1, 0.3, 0.45, a))
	_center("SCORE  %d" % main.score, size.y * 0.36 + 60, 30, Color(1, 1, 1, a))
	var new_best: bool = main.score >= main.best and main.score > 0
	_center("NEW BEST!" if new_best else "BEST  %d" % main.best, size.y * 0.36 + 96, 20,
		Color(1, 0.9, 0.3, a) if new_best else Color(1, 1, 1, 0.6 * a))
	_center("Wave %d    Kills %d    Time %ds" % [main.wave, main.kills, int(main.time_alive)], size.y * 0.36 + 130, 18, Color(0.8, 0.9, 1, 0.8 * a))
	if main.gameover_timer > 0.8 and int(t * 2) % 2 == 0:
		_center("CLICK OR PRESS R TO RETRY", size.y * 0.72, 26, Color(1, 0.9, 0.35))


func _draw_crosshair() -> void:
	var m := get_local_mouse_position()
	var c := Color(1, 0.95, 0.5, 0.95)
	draw_arc(m, 10, 0, TAU, 24, c, 2.0, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(m + d * 5, m + d * 15, c, 2.0)
	draw_circle(m, 1.5, c)
