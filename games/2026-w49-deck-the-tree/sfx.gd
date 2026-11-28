class_name Sfx
extends Node
## Plays the short sound effects in sfx/ (made by sfx/make_sfx.py).

const NAMES := ["throw", "thunk", "clash", "candy", "star", "shatter", "tier", "win", "fail",
	"phase", "click", "booster", "shield", "fire"]
const VOICES := 8

var muted := false
var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		_sounds[n] = load("res://sfx/%s.wav" % n)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch_jitter := 0.05) -> void:
	if muted or not _sounds.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _sounds[sound]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
