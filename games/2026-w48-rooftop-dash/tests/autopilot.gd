extends RefCounted
## Finds button presses that carry a run safely to a distance, by searching
## launch points and hold lengths with the game's own World rules.
## tests/bot.gd uses it to check fairness; tests/shots.gd to play for screenshots.

## Hold lengths it tries, in ticks (0 is a tap). Full hold first.
const HOLDS := [15, 0, 7, 3, 11]
const STEP := 3  # ticks between launch points it tries
var max_tries := 30000

var tried := 0
var best := 0.0
## [tick, hold] per jump, in order; tick counts World steps since start().
var plan: Array = []
var stats := {"ac": 0, "antenna": 0, "skylight": 0, "wire": 0, "crumble": 0}
## Puzzle points met (stats) and solved (rides), by kind.
var rides := {}
var _seen := {}
## Prefer launches this many ticks before the last safe one, like a person
## who doesn't wait for the very edge. 0 jumps as late as possible.
var early := 0


func solve(w: World, goal: float) -> bool:
	plan.clear()
	return _run(w, goal)


## True if the jump button is down on this tick of a planned run.
func held_at(tick: int) -> bool:
	for p in plan:
		if tick >= p[0] and tick <= p[0] + p[1]:
			return true
		if p[0] > tick:
			break
	return false


func _ticks(w: World) -> int:
	return roundi(w.t / World.DT)


func _run(w: World, goal: float) -> bool:
	if w.meters() >= goal:
		return true
	if tried > max_tries:
		return false
	var key := "%d:%d" % [int(w.x / 24.0), int(w.y)]
	if _seen.has(key):
		return false
	_seen[key] = true
	var walker := w.clone()
	var starts: Array = []
	var ticks := 0
	while walker.alive and walker.grounded and ticks < 400:
		if ticks % STEP == 0:
			starts.append(walker.clone())
		walker.step(false)
		ticks += 1
	starts.reverse()
	if early > 0 and starts.size() > early / STEP:
		var skip := starts.slice(0, early / STEP)
		starts = starts.slice(early / STEP) + skip
	for s in starts:
		for h in HOLDS:
			tried += 1
			_tap_tick = -1
			var j := _jump(s.clone(), h)
			if j:
				best = maxf(best, j.meters())
				plan.append([_ticks(s), h])
				var taps := 0
				if _tap_tick >= 0:
					plan.append([_tap_tick, 0])
					taps = 1
				if _run(j, goal):
					_count(w, j)
					return true
				for i in taps + 1:
					plan.pop_back()
	return false


var _tap_tick := -1


## Plays one jump from w; the world where it lands, or null if it dies.
func _jump(w: World, hold: int) -> World:
	for i in 240:
		if w.carry.get("tap", false):
			return _ride(w)
		w.step(i <= hold)
		if not w.alive:
			return null
		if i > 0 and w.grounded:
			return w
	return null


## On a ride that you leave with a tap (the crane): tries letting go on each
## tick in turn, latest first, and keeps the first that lands.
func _ride(w: World) -> World:
	var ticks := 0
	var probe := w.clone()
	while not probe.carry.is_empty() and ticks < 400:
		probe.step(false)
		ticks += 1
	for k in range(ticks - 1, -1, -1):
		var r := w.clone()
		for i in k:
			r.step(false)
		var at := _ticks(r)
		r.step(true, true)
		for i in 240:
			r.step(false)
			if not r.alive:
				break
			if r.grounded:
				_tap_tick = at
				return r
	return null


func _count(from: World, to: World) -> void:
	for o in to.obstacles:
		if o.x1 > from.x and o.x1 <= to.x:
			stats[o.kind] = stats.get(o.kind, 0) + 1
			if o.get("grab", false) and o.used:
				rides[o.kind] = rides.get(o.kind, 0) + 1
	for wr in to.wires:
		if wr.ax > from.x - 20.0 and wr.ax <= to.x:
			stats.wire += 1
	for r in to.roofs:
		if r.crumble and r.x0 > from.x and r.x0 <= to.x:
			stats.crumble += 1
