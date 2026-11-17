class_name Sfx
extends Node
## Plays the short sound effects in sfx/. Sounds are made by sfx/make_sfx.py.
## A small pool of players lets sounds overlap (a step and a chime, say).

const SOUNDS := {
	"step": preload("res://sfx/step.wav"),
	"push": preload("res://sfx/push.wav"),
	"bump": preload("res://sfx/bump.wav"),
	"charge": preload("res://sfx/charge.wav"),
	"win": preload("res://sfx/win.wav"),
	"fail": preload("res://sfx/fail.wav"),
	"undo": preload("res://sfx/undo.wav"),
	"click": preload("res://sfx/click.wav"),
	"teleport": preload("res://sfx/teleport.wav"),
	"pickup": preload("res://sfx/pickup.wav"),
	"door": preload("res://sfx/door.wav"),
	"crumble": preload("res://sfx/crumble.wav"),
	"tool": preload("res://sfx/tool.wav"),
	"finale": preload("res://sfx/finale.wav"),
}
const VOICES := 8
## Seconds before the same sound can play again (holding an arrow into a wall).
const COOLDOWN := {"bump": 0.3}

var muted := false
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}  # sound -> ticks msec when it last played


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## pitch_jitter varies the pitch a little, so repeated steps don't drone.
func play(sound: String, pitch_jitter := 0.0, volume_db := 0.0, pitch := 1.0) -> void:
	if muted or not SOUNDS.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - _last.get(sound, -100000) < COOLDOWN.get(sound, 0.0) * 1000.0:
		return
	_last[sound] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = SOUNDS[sound]
	p.pitch_scale = pitch + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db
	p.play()
