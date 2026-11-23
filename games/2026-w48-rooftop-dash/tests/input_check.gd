extends SceneTree
## Checks the touch fixes in World.step: a second thumb pressing while the
## first is still down jumps, and so does a tap that starts and ends between
## two ticks.
##   godot --headless --path . --script tests/input_check.gd


func _initialize() -> void:
	var fails := 0
	# Second thumb: the button stays held, a new press arrives on tick 2.
	var w := World.new(7)
	w.start()
	w.step(true)          # first thumb jumps
	for i in 40:
		w.step(true)      # ...and stays down until the landing
	while not w.grounded and w.alive:
		w.step(true)
	var jumped := false
	for e in w.step(true, true):
		jumped = jumped or e.type == "jump"
	if not jumped:
		print("FAIL: a second thumb's press didn't jump")
		fails += 1
	# A tap between ticks: never seen as held, only as tapped.
	w = World.new(7)
	w.start()
	w.step(false)
	jumped = false
	for e in w.step(false, true):
		jumped = jumped or e.type == "jump"
	if not jumped:
		print("FAIL: a tap shorter than a tick didn't jump")
		fails += 1
	print("input checks: %d failed" % fails)
	quit(1 if fails > 0 else 0)
