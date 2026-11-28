class_name Rotor
extends RefCounted
## Turns a level's rotation program into an angular speed (degrees per second).
## Positive = clockwise on screen.
##   const   {"s": 90}                         steady
##   flip    {"s": 120, "every": 2.0}          reverses every few seconds, with a short ease
##   pulse   {"s": 100, "amp": 0.8, "period": 3}  speed swings around s; amp > 1 rocks back and forth
##   random  {"min": 60, "max": 220, "rev": 0.4, "t0": 1, "t1": 2.4}
##           every t0..t1 seconds picks a new speed in min..max and reverses with chance rev

const EASE := 6.0  # how fast the speed catches up with its target, per second

var prog: Dictionary
var speed := 0.0
var t := 0.0
var _target := 0.0
var _next := 0.0
var _dir := 1.0
var _rng := RandomNumberGenerator.new()


func _init(p: Dictionary, seed_value := -1) -> void:
	prog = p
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	match prog.get("m", "const"):
		"const", "flip", "pulse":
			speed = prog.s
			_target = prog.s
			_next = prog.get("every", 0.0)
		"random":
			_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_target = _rng.randf_range(prog.min, prog.max) * _dir
			speed = _target
			_next = _rng.randf_range(prog.t0, prog.t1)


func step(delta: float) -> float:
	t += delta
	match prog.get("m", "const"):
		"const":
			speed = prog.s
		"flip":
			if t >= _next:
				_target = -_target
				_next += prog.every
			speed = lerpf(speed, _target, 1.0 - exp(-EASE * 2.0 * delta))
		"pulse":
			speed = prog.s * (1.0 + prog.amp * sin(TAU * t / prog.period))
			if prog.amp >= 1.0:
				speed = prog.s * prog.amp * sin(TAU * t / prog.period) + prog.s * 0.25
		"random":
			if t >= _next:
				if _rng.randf() < prog.rev:
					_dir = -_dir
				_target = _rng.randf_range(prog.min, prog.max) * _dir
				_next = t + _rng.randf_range(prog.t0, prog.t1)
			speed = lerpf(speed, _target, 1.0 - exp(-EASE * delta))
	return speed


## An exact copy, for looking ahead (the aim booster and the test bot).
func clone() -> Rotor:
	var r := Rotor.new(prog, 0)
	r.speed = speed
	r.t = t
	r._target = _target
	r._next = _next
	r._dir = _dir
	r._rng.state = _rng.state
	return r
