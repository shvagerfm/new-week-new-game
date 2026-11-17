class_name Kip
extends RefCounted
## Kip's hand-drawn animation frames (art/source/kip/kip.tres, a SpriteFrames
## resource with idle, drive, push and look_around). The sheet only faces down,
## so the other directions rotate it. The board picks the frame itself (see
## frame_for) so Kip keeps the hop, lean and shadow drawn in main.gd.

const FRAMES: SpriteFrames = preload("res://art/source/kip/kip.tres")

## Rotation that turns the down-facing sheet toward each direction.
const ANGLE := {
	Vector2i.DOWN: 0.0, Vector2i.LEFT: PI / 2.0, Vector2i.UP: PI, Vector2i.RIGHT: -PI / 2.0,
}

const BLINK_EVERY := 3.6  # seconds between blinks while standing still
const LOOK_AFTER := 4.0   # standing still this long starts a look around ...
const LOOK_EVERY := 8.0   # ... and repeats it this often


static func angle(dir: Vector2i) -> float:
	return ANGLE.get(dir, 0.0)


## A frame of an animation, played at the speed set in kip.tres.
static func frame(anim: StringName, t: float) -> Texture2D:
	var n := FRAMES.get_frame_count(anim)
	var i := int(t * FRAMES.get_animation_speed(anim))
	i = posmod(i, n) if FRAMES.get_animation_loop(anim) else clampi(i, 0, n - 1)
	return FRAMES.get_frame_texture(anim, i)


## What Kip shows standing still for `still` seconds: a slow bob with the
## lens glow pulsing, a blink every few seconds (sometimes a double blink),
## and now and then a look around.
static func idle_frame(still: float) -> Texture2D:
	if still > LOOK_AFTER:
		var lt := fmod(still - LOOK_AFTER, LOOK_EVERY)
		var look_len := FRAMES.get_frame_count(&"look_around") / FRAMES.get_animation_speed(&"look_around")
		if lt < look_len:
			return frame(&"look_around", lt)
	var bt := fmod(still, BLINK_EVERY)
	var cyc := int(still / BLINK_EVERY)
	if still > 1.0:
		var blink := _blink(bt)
		if blink < 0 and cyc % 3 == 2:
			blink = _blink(bt - 0.4)
		if blink >= 0:
			return FRAMES.get_frame_texture(&"idle", blink)
	# idle frames 0-2 are the bob; 3 and 4 have the eye shut, 5 opens it again
	var bob: Array[int] = [0, 1, 2, 1]
	return FRAMES.get_frame_texture(&"idle", bob[int(still * 4.0) % bob.size()])


static func _blink(t: float) -> int:
	if t < 0.0 or t >= 0.3:
		return -1
	return 3 + int(t / 0.1)
