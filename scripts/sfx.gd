extends Node
## Procedurally synthesized retro sound effects (no audio files needed).

const RATE := 22050

var sounds := {}
var players: Array[AudioStreamPlayer] = []
var next := 0
var last_played := {}
## Online co-op host: logged sound names, replayed on guests.
var record := false
var events: Array[String] = []


func _ready() -> void:
	sounds["shoot"] = _make(0.07, 1300, 500, "square", 0.1, 0.16)
	sounds["enemy_shoot"] = _make(0.12, 600, 260, "saw", 0.1, 0.16)
	sounds["hit"] = _make(0.05, 300, 150, "square", 0.6, 0.18)
	sounds["explode"] = _make(0.28, 180, 40, "square", 0.85, 0.35)
	sounds["explode_big"] = _make(0.7, 120, 25, "square", 0.9, 0.5)
	sounds["hurt"] = _make(0.25, 420, 90, "saw", 0.4, 0.45)
	sounds["pickup"] = _make(0.18, 600, 1400, "sine", 0.0, 0.4)
	sounds["dash"] = _make(0.14, 200, 900, "sine", 0.5, 0.3)
	sounds["spawn"] = _make(0.2, 900, 1100, "sine", 0.0, 0.12)
	sounds["clear"] = _make(0.45, 500, 1600, "square", 0.0, 0.25)
	sounds["shotgun"] = _make(0.16, 520, 110, "square", 0.75, 0.3)
	sounds["laser"] = _make(0.16, 1900, 320, "saw", 0.15, 0.2)
	sounds["charge"] = _make(0.5, 220, 950, "sine", 0.1, 0.16)
	sounds["beam"] = _make(0.35, 170, 90, "saw", 0.5, 0.3)
	sounds["shield"] = _make(0.3, 1300, 300, "sine", 0.3, 0.35)
	sounds["beep"] = _make(0.09, 1500, 1500, "square", 0.0, 0.14)
	sounds["card"] = _make(0.3, 400, 1300, "square", 0.0, 0.2)
	sounds["shock"] = _make(0.35, 320, 60, "sine", 0.6, 0.4)
	# Boss entrance: alarm, countdown thuds, landing slam
	sounds["siren"] = _make(0.9, 380, 880, "saw", 0.05, 0.2)
	sounds["count"] = _make(0.3, 170, 55, "square", 0.35, 0.5)
	sounds["slam"] = _make(1.0, 95, 20, "square", 0.95, 0.55)
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


func play(name: String) -> void:
	if not sounds.has(name):
		return
	if record and events.size() < 24:
		events.append(name)
	# Throttle very frequent sounds to avoid harsh stacking
	var now := Time.get_ticks_msec()
	var min_gap := 40 if name == "hit" else 25
	if last_played.has(name) and now - int(last_played[name]) < min_gap:
		return
	last_played[name] = now
	var p := players[next]
	next = (next + 1) % players.size()
	p.stream = sounds[name]
	p.pitch_scale = randf_range(0.92, 1.08)
	p.play()


func _make(dur: float, f0: float, f1: float, wave: String, noise: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var held_noise := 0.0
	for i in n:
		var k := float(i) / n
		var f := lerpf(f0, f1, k)
		phase += f / RATE
		var ph := fmod(phase, 1.0)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if ph < 0.5 else -1.0
			"saw":
				s = ph * 2.0 - 1.0
			_:
				s = sin(ph * TAU)
		if i % 2 == 0:
			held_noise = randf() * 2.0 - 1.0
		s = lerpf(s, held_noise, noise)
		var env := minf(1.0, k * 60.0) * pow(1.0 - k, 2.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
