extends Node
## Online leaderboard client (server code in server/, Cloudflare Worker + D1).
## Anonymous identity per device, a server token per run, submit at game over, board queries.
## Everything is optional: with no API_URL, or no connection, the game plays as before.

## Set this to the deployed Worker URL, e.g. "https://neon-arena-leaderboard.<you>.workers.dev".
## On the web build "?api=<url>" in the page address overrides it (handy for local testing).
const API_URL := "https://neon-arena-leaderboard.neon-arena-leaderboard.workers.dev"
## TapTap build (export feature "taptap"): its own server address. *.workers.dev is not
## reliably reachable in mainland China, so point this at a domain you own that routes to
## the same Worker (see server/README.md). Empty: fall back to API_URL.
const API_URL_TAPTAP := ""
## Store builds that must not take free text (TapTap): names are generated from these words.
const NAME_ADJ := ["霓虹", "疾风", "闪电", "极光", "星火", "量子", "赤焰", "苍蓝", "幻影", "迅捷",
	"暗影", "银翼", "烈焰", "寒霜", "雷鸣", "流光", "破晓", "深空"]
const NAME_NOUN := ["飞行员", "猎手", "游侠", "机师", "突击手", "先锋", "领航员", "守望者", "游骑兵",
	"彗星", "战机", "信标", "旅人", "哨兵"]
const TIMEOUT := 8.0
const PLAYER_PATH := "user://player.cfg"
const PLATFORMS := ["pc", "phone", "tablet"]
const MODES := ["kbm", "twin", "hybrid", "auto"]
const PERIODS := ["all", "week", "day"]

var main: Node2D
var base_url := ""
var player_id := ""
var secret := ""
var player_name := ""
var notice := ""  # i18n key shown on the leaderboard screen (e.g. a refused name), or ""
var platform := "pc"
var season := 1

# Current run: "" (no leaderboard), starting, ready, offline, submitting, done, flagged, error
var run_state := ""
var run_token := ""
var result := {}  # ranks from the last submit: {all: {rank, score, total, gap}, week: ..., day: ...}
var result_board := ""  # "platform/mode" of that result

# Board view
var board := {}  # last /api/board response
var board_state := ""  # loading, ok, error
var board_req := 0  # ignore stale responses


func _ready() -> void:
	base_url = API_URL_TAPTAP if OS.has_feature("taptap") and API_URL_TAPTAP != "" else API_URL
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('api') || ''", true)
		if q is String and q != "":
			base_url = q
		platform = _detect_platform()
	base_url = base_url.rstrip("/")
	_load_identity()


func enabled() -> bool:
	return base_url != ""


## Phone / tablet / pc from the browser: a coarse pointer means a touch device,
## and its short side decides phone (< 600 CSS px) or tablet. iPads that report a
## desktop user agent still have a coarse pointer.
func _detect_platform() -> String:
	var js := """(function(){
		var coarse = window.matchMedia && matchMedia('(pointer: coarse)').matches;
		var ua = navigator.userAgent || '';
		var mobileUa = /Mobi|Android|iPhone|iPad|iPod/.test(ua);
		if (!coarse && !mobileUa) return 'pc';
		var s = Math.min(screen.width, screen.height);
		return s < 600 ? 'phone' : 'tablet';
	})()"""
	var p = JavaScriptBridge.eval(js, true)
	return p if p is String and PLATFORMS.has(p) else "pc"


func _load_identity() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PLAYER_PATH) == OK:
		player_id = String(cfg.get_value("player", "id", ""))
		secret = String(cfg.get_value("player", "secret", ""))
		player_name = String(cfg.get_value("player", "name", ""))
	if player_id.length() < 16 or secret.length() < 16:
		var c := Crypto.new()
		player_id = c.generate_random_bytes(16).hex_encode()
		secret = c.generate_random_bytes(24).hex_encode()
		_save_identity()
	if not free_text_names() and player_name == "":
		player_name = random_name()
		_save_identity()


## Whether players may type their own name. TapTap's rules require filtering any free text,
## and its in-app browser may not support prompt(), so that build generates names instead.
func free_text_names() -> bool:
	return not OS.has_feature("taptap")


func random_name() -> String:
	return "%s%s%d" % [NAME_ADJ[randi() % NAME_ADJ.size()], NAME_NOUN[randi() % NAME_NOUN.size()], randi_range(10, 99)]


func _save_identity() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "id", player_id)
	cfg.set_value("player", "secret", secret)
	cfg.set_value("player", "name", player_name)
	cfg.save(PLAYER_PATH)


func display_name() -> String:
	return player_name if player_name != "" else "Pilot-" + player_id.substr(0, 4)


func _auth() -> Dictionary:
	return {"player_id": player_id, "secret": secret, "name": player_name}


# ---------------------------------------------------------------- runs

func start_run() -> void:
	run_token = ""
	result = {}
	if not enabled():
		run_state = ""
		return
	run_state = "starting"
	_request(HTTPClient.METHOD_POST, "/api/run/start", _auth(), func(code: int, data):
		if code == 200 and data is Dictionary and data.has("token"):
			run_token = data["token"]
			season = int(data.get("season", season))
			if player_name == "" and data.has("name"):
				player_name = data["name"]
				_save_identity()
			if run_state == "starting":
				run_state = "ready"
		elif run_state == "starting":
			run_state = "offline")


## Called at game over with the run summary.
func submit_run(mode: String, score: int, wave: int, kills: int, duration: int, weapon: String) -> void:
	if not enabled():
		return
	if run_token == "":
		# The start request failed (or is still out); this run can't be ranked.
		run_state = "offline"
		return
	var body := _auth()
	body.merge({"token": run_token, "platform": platform, "mode": mode, "score": score, "wave": wave,
		"kills": kills, "duration": duration, "weapon": weapon, "version": main.VERSION})
	run_token = ""
	run_state = "submitting"
	result_board = platform + "/" + mode
	_request(HTTPClient.METHOD_POST, "/api/run/submit", body, func(code: int, data):
		if code == 200 and data is Dictionary:
			if data.get("flagged", false):
				run_state = "flagged"
			else:
				result = data.get("ranks", {})
				run_state = "done"
		else:
			run_state = "error")


# ---------------------------------------------------------------- boards

func fetch_board(p: String, mode: String, period: String) -> void:
	if not enabled():
		board_state = ""
		return
	board_req += 1
	var req := board_req
	if board.get("platform", "") != p or board.get("mode", "") != mode or board.get("period", "") != period:
		board = {}
	board_state = "loading" if board.is_empty() else board_state
	var path := "/api/board?platform=%s&mode=%s&period=%s&limit=20&player_id=%s" % [p, mode, period, player_id]
	_request(HTTPClient.METHOD_GET, path, null, func(code: int, data):
		if req != board_req:
			return
		if code == 200 and data is Dictionary:
			board = data
			season = int(data.get("season", season))
			board_state = "ok"
		else:
			board_state = "error")


func rename(new_name: String, done: Callable) -> void:
	new_name = new_name.strip_edges().left(12)
	if new_name == "":
		return
	var before := player_name
	notice = ""
	player_name = new_name
	_save_identity()
	if not enabled():
		done.call()
		return
	var body := _auth()
	body["name"] = new_name
	_request(HTTPClient.METHOD_POST, "/api/name", body, func(code: int, data):
		if code == 200 and data is Dictionary and data.has("name"):
			player_name = data["name"]
			_save_identity()
		elif code == 400:
			player_name = before  # the server's name filter refused it
			_save_identity()
			notice = "rename_refused"
		done.call())


## A new name: a browser prompt on the web, or a freshly generated one where free text
## isn't allowed. Returns "" when cancelled.
func ask_name() -> String:
	if not free_text_names():
		var n := random_name()
		while n == player_name:
			n = random_name()
		return n
	if not OS.has_feature("web"):
		return ""
	var q: String = main.t("rename_prompt").replace("\\", "\\\\").replace("'", "\\'")
	var cur := display_name().replace("\\", "\\\\").replace("'", "\\'")
	var v = JavaScriptBridge.eval("prompt('%s', '%s') || ''" % [q, cur], true)
	return v if v is String else ""


# ---------------------------------------------------------------- http

func _request(method: int, path: String, body, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(res: int, code: int, _headers, raw: PackedByteArray):
		http.queue_free()
		var data = null
		if res == HTTPRequest.RESULT_SUCCESS:
			data = JSON.parse_string(raw.get_string_from_utf8())
		else:
			code = 0
		done.call(code, data))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		done.call(0, null)
