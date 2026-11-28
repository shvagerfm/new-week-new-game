extends AdProvider
## A stand-in rewarded ad for development and for builds with no SDK yet.
## Shows a full-screen "Test ad" with a countdown; after it the player can close
## it and gets the reward. "Skip" closes early with no reward, to test that path.
## fill_rate < 1 makes some loads fail, to test the "ad not available" path.

var duration := 3.0
var fill_rate := 1.0
var _loaded := false
var _layer: CanvasLayer
var _earned := false


func provider_name() -> String:
	return "mock"


func initialize(config: Dictionary) -> void:
	duration = config.get("mock_duration", duration)
	fill_rate = config.get("mock_fill_rate", fill_rate)
	process_mode = Node.PROCESS_MODE_ALWAYS


func load_rewarded() -> void:
	_loaded = false
	await get_tree().create_timer(0.3, true, false, true).timeout
	if randf() <= fill_rate:
		_loaded = true
		rewarded_loaded.emit()
	else:
		rewarded_load_failed.emit("no fill (mock)")


func is_rewarded_loaded() -> bool:
	return _loaded


func show_rewarded() -> void:
	if not _loaded:
		rewarded_show_failed.emit("not loaded")
		return
	_loaded = false
	_earned = false
	_build_overlay()
	rewarded_opened.emit()


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.add_child(box)
	var title := Label.new()
	title.text = "TEST AD\n(rewarded)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	box.add_child(title)
	var count := Label.new()
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 40)
	box.add_child(count)
	var close := Button.new()
	close.text = "Close ✓"
	close.disabled = true
	close.custom_minimum_size = Vector2(320, 96)
	close.add_theme_font_size_override("font_size", 36)
	box.add_child(close)
	var skip := Button.new()
	skip.text = "Skip (no reward)"
	skip.custom_minimum_size = Vector2(320, 72)
	skip.add_theme_font_size_override("font_size", 28)
	box.add_child(skip)
	close.pressed.connect(_finish)
	skip.pressed.connect(_finish)
	var left := duration
	while left > 0.0 and is_instance_valid(_layer):
		count.text = "%d" % ceili(left)
		await get_tree().create_timer(0.1, true, false, true).timeout
		left -= 0.1
	if not is_instance_valid(_layer):
		return
	count.text = "Reward earned"
	_earned = true
	rewarded_earned.emit()
	close.disabled = false


func _finish() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	rewarded_closed.emit()
