class_name Music
extends Node
## The music loop, played as three stems that start together and stay in
## step: base (bass, kick, pad), drums, and lead (arpeggio and hook). The
## drums and then the lead fade in as the run speeds up, and the whole loop
## plays a little faster. Made by sfx/make_sfx.py.

const STEMS := [
	preload("res://sfx/music_base.wav"),
	preload("res://sfx/music_drums.wav"),
	preload("res://sfx/music_lead.wav"),
]
## Speed fraction (0 at the start, 1 at top speed) where each stem fades in,
## from a to b. Base is always on.
const FADE_IN := [Vector2(-1, 0), Vector2(0.06, 0.22), Vector2(0.3, 0.5)]
## Top speed plays the loop this much faster (about two semitones higher).
const MAX_TEMPO := 1.12
const SILENT_DB := -60.0

## Overall loudness and speed; main.gd tweens them when a run ends.
var volume_db := -6.0:
	set(v):
		volume_db = v
		_apply()
var pitch_scale := 1.0:
	set(v):
		pitch_scale = v
		for p in _players:
			p.pitch_scale = v

var _players: Array[AudioStreamPlayer] = []
var _gain := [1.0, 0.0, 0.0]   # each stem's fade, 0..1


func _ready() -> void:
	for s: AudioStreamWAV in STEMS:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new()
		p.stream = s
		add_child(p)
		_players.append(p)
	_apply()


## Starts the loop from the top with only the base playing.
func start() -> void:
	volume_db = -6.0
	pitch_scale = 1.0
	set_speed(0.0)
	for p in _players:
		p.stream_paused = false
		p.play()


func stop() -> void:
	for p in _players:
		p.stop()


func is_playing() -> bool:
	return _players[0].playing


func set_paused(paused: bool) -> void:
	for p in _players:
		p.stream_paused = paused


## k is the run's speed fraction: 0 at the start, 1 at top speed.
func set_speed(k: float) -> void:
	for i in _players.size():
		var f: Vector2 = FADE_IN[i]
		_gain[i] = 1.0 if f.x < 0.0 else smoothstep(f.x, f.y, k)
	pitch_scale = lerpf(1.0, MAX_TEMPO, k)
	_apply()


func _apply() -> void:
	for i in _players.size():
		var g: float = _gain[i]
		_players[i].volume_db = volume_db + linear_to_db(g) if g > 0.001 else SILENT_DB
