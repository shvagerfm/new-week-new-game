class_name Sfx
extends Node
## Plays the short sound effects in sfx/. Sounds are made by sfx/make_sfx.py.
## A small pool of players lets sounds overlap (a jump and a parcel, say).

const SOUNDS := {
	"jump": preload("res://sfx/jump.wav"),
	"land": preload("res://sfx/land.wav"),
	"edge": preload("res://sfx/edge.wav"),
	"combo_lost": preload("res://sfx/combo_lost.wav"),
	"parcel": preload("res://sfx/parcel.wav"),
	"crumble": preload("res://sfx/crumble.wav"),
	"hit": preload("res://sfx/hit.wav"),
	"fall": preload("res://sfx/fall.wav"),
	"best": preload("res://sfx/best.wav"),
	"click": preload("res://sfx/click.wav"),
}
const VOICES := 8

var muted := false
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## pitch_jitter varies the pitch a little, so repeated jumps don't drone.
func play(sound: String, pitch_jitter := 0.0, volume_db := 0.0, pitch := 1.0) -> void:
	if muted or not SOUNDS.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = SOUNDS[sound]
	p.pitch_scale = pitch + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db
	p.play()
