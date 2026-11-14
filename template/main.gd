extends Node2D
## Starter game: tap the dot before the timer runs out.
## Replace this with the week's game. It shows the patterns worth keeping:
## touch input (mouse clicks become touches too), a layout that adapts to any
## screen via get_viewport_rect(), and a simple title -> play -> game over loop.

const ROUND_TIME := 20.0
const TARGET_RADIUS := 70.0

var score := 0
var best := 0
var time_left := 0.0
var playing := false
var target := Vector2.ZERO

@onready var score_label: Label = $HUD/Score
@onready var hint_label: Label = $HUD/Hint


func _ready() -> void:
	get_viewport().size_changed.connect(_move_target)
	_show_hint("Tap to start")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_on_tap(event.position)


func _process(delta: float) -> void:
	if not playing:
		return
	time_left -= delta
	if time_left <= 0.0:
		_game_over()
	score_label.text = "%d   ·   %ds" % [score, ceili(maxf(time_left, 0.0))]
	queue_redraw()


func _draw() -> void:
	if playing:
		draw_circle(target, TARGET_RADIUS, Color("ffb347"))
		draw_circle(target, TARGET_RADIUS * 0.4, Color("171a29"))


func _on_tap(pos: Vector2) -> void:
	if not playing:
		_start()
	elif pos.distance_to(target) <= TARGET_RADIUS * 1.2:
		score += 1
		_move_target()


func _start() -> void:
	score = 0
	time_left = ROUND_TIME
	playing = true
	hint_label.hide()
	_move_target()


func _game_over() -> void:
	playing = false
	best = maxi(best, score)
	queue_redraw()
	_show_hint("Score %d\nBest %d\n\nTap to play again" % [score, best])


func _move_target() -> void:
	var area := get_viewport_rect().grow(-TARGET_RADIUS * 1.5)
	area.position.y += 120.0  # keep clear of the score label
	area.size.y -= 120.0
	target = area.position + Vector2(randf() * area.size.x, randf() * area.size.y)
	queue_redraw()


func _show_hint(text: String) -> void:
	hint_label.text = text
	hint_label.show()
