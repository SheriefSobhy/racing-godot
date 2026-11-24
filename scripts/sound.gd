class_name Sound
extends Node
## Engine (two CC0 loops crossfaded, pitch follows speed), nitro, coin,
## crash and near-miss sounds, plus the music. Volumes come from Save.

const DIR := "res://assets/sounds/"

var _eng_low: AudioStreamPlayer
var _eng_high: AudioStreamPlayer
var _music: AudioStreamPlayer
var _one_shots := {}
var _engine_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_eng_low = _player(DIR + "engine_low.wav", "SFX", true)
	_eng_high = _player(DIR + "engine_high.wav", "SFX", true)
	for k in ["coin", "crash", "nitro", "whoosh"]:
		var ext := {"coin": ".wav", "crash": ".ogg", "nitro": ".mp3", "whoosh": ".wav"}[k] as String
		var p := _player(DIR + k + ext, "SFX", false)
		p.max_polyphony = 3
		_one_shots[k] = p
	_music = _player("res://assets/music/pure_raceway.mp3", "Music", true)
	_music.volume_db = -6.0
	_music.play()


func _player(path: String, bus: String, loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var st: AudioStream = load(path)
	if loop:
		if st is AudioStreamWAV:
			var w := st as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif st is AudioStreamMP3:
			(st as AudioStreamMP3).loop = true
	p.stream = st
	p.bus = bus
	add_child(p)
	return p


func play(name: String, pitch := 1.0, db := 0.0) -> void:
	var p: AudioStreamPlayer = _one_shots[name]
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()


## Updates the engine from the car's speed; pass null to silence it.
func engine(car: PlayerCar, paused := false) -> void:
	var on := car != null and not paused
	if on != _engine_on:
		_engine_on = on
		if on:
			_eng_low.play()
			_eng_high.play()
		else:
			_eng_low.stop()
			_eng_high.stop()
	if not on:
		return
	var r := clampf(car.speed / float(car.spec.max_speed), 0.0, 1.35)
	if car.boosting:
		r += 0.08
	# A target "engine note" frequency, matched by both loops (43 Hz and 77 Hz recordings).
	var f := 34.0 + r * 74.0
	_eng_low.pitch_scale = clampf(f / 43.0, 0.5, 3.0)
	_eng_high.pitch_scale = clampf(f / 77.0, 0.4, 2.5)
	var mix := smoothstep(0.25, 0.8, r)
	_eng_low.volume_db = linear_to_db(maxf(0.001, (1.0 - mix) * 0.55 + 0.05))
	_eng_high.volume_db = linear_to_db(maxf(0.001, mix * 0.6 + 0.02))
