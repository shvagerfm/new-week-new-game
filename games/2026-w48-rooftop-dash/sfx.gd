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
	"zap": preload("res://sfx/zap.wav"),
	"clang": preload("res://sfx/clang.wav"),
	"collapse": preload("res://sfx/collapse.wav"),
	"step": preload("res://sfx/step.wav"),
	"glass": preload("res://sfx/glass.wav"),
	"squeak": preload("res://sfx/squeak.wav"),
	"cloth": preload("res://sfx/cloth.wav"),
	"fall": preload("res://sfx/fall.wav"),
	"best": preload("res://sfx/best.wav"),
	"click": preload("res://sfx/click.wav"),
	# Window scenes
	"meow": preload("res://sfx/meow.wav"),
	"pot": preload("res://sfx/pot.wav"),
	"disco": preload("res://sfx/disco.wav"),
	"granny": preload("res://sfx/granny.wav"),
	"pillow": preload("res://sfx/pillow.wav"),
	"grunt": preload("res://sfx/grunt.wav"),
	"woof": preload("res://sfx/woof.wav"),
	"eek": preload("res://sfx/eek.wav"),
	"curtain": preload("res://sfx/curtain.wav"),
}
const VOICES := 10

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
