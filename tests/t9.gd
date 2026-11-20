extends Node
## Co-op room-code keypad and generated player names (TapTap build).

var main: Node2D
var fails := 0


func ok(c: bool, m: String) -> void:
	print(("PASS  " if c else "FAIL  ") + m)
	if not c:
		fails += 1


func press_kind(kind: String, value := "") -> bool:
	for b in (main.hud.keypad_buttons() if main.entering_code else main.hud.lobby_buttons()):
		if b["kind"] == kind and (value == "" or b.get("value", "") == value):
			main.card_lock = 0.0
			main._lobby_press((b["rect"] as Rect2).get_center())
			return true
	return false


func _ready() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.net.base_url = ""  # offline: join_room reports err_offline instead of connecting
	main.open_lobby()
	ok(press_kind("join"), "lobby has a JOIN button")
	ok(main.entering_code and main.code_entry == "", "JOIN opens the keypad")
	var keys: Array = main.hud.keypad_buttons().filter(func(b): return b["kind"] == "key")
	ok(keys.size() == 31, "31 code keys (%d)" % keys.size())
	var all_inside := true
	for b in main.hud.keypad_buttons():
		all_inside = all_inside and Rect2(0, 0, 1280, 720).encloses(b["rect"])
	ok(all_inside, "keypad fits the 1280x720 frame")
	press_kind("key", "A")
	press_kind("key", "7")
	ok(main.code_entry == "A7", "tapping keys types the code (%s)" % main.code_entry)
	press_kind("del")
	ok(main.code_entry == "A", "DEL removes the last character")
	main._code_key(KEY_I)  # not in the code alphabet
	main._code_key(KEY_B)
	main._code_key(KEY_KP_3)
	ok(main.code_entry == "AB3", "keyboard input, letters outside the alphabet ignored (%s)" % main.code_entry)
	main._code_key(KEY_9)
	ok(not main.entering_code, "fourth character joins automatically")
	ok(main.coop.status == "err_offline" and main.code_entry == "AB39", "join attempted with AB39 (status %s)" % main.coop.status)
	press_kind("join")
	main._code_key(KEY_ESCAPE)
	ok(not main.entering_code and main.state == main.State.LOBBY, "Esc closes the keypad, stays in the lobby")
	press_kind("join")
	press_kind("cancel")
	ok(not main.entering_code, "CANCEL closes the keypad")
	# Generated names (used where free text isn't allowed)
	var seen := {}
	var valid := true
	for i in 200:
		var n: String = main.net.random_name()
		seen[n] = true
		valid = valid and n.length() <= 12 and n.length() >= 5
	ok(valid, "generated names are 5-12 characters")
	ok(seen.size() > 100, "generated names vary (%d unique of 200)" % seen.size())
	ok(main.net.free_text_names(), "editor/web build keeps free-text names")
	var f: Font = ThemeDB.fallback_font
	var w_zh := f.get_string_size("霓虹猎手").x
	ok(f.has_char("霓".unicode_at(0)) or f.fallbacks.has(main.FONT_ZH), "English font falls back to Chinese for names")
	ok(w_zh > 30.0, "Chinese name measures as real glyphs (%.0f px)" % w_zh)
	print("FAILS: ", fails)
	get_tree().quit()
