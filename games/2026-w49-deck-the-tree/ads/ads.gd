extends Node
## Autoload "Ads": the only place the game asks for ads.
##
##   if await Ads.show_rewarded("continue"):
##       # give the reward
##
## show_rewarded() pauses the game and mutes sound while the ad is up, waits for
## it to close and returns true only if the reward was earned. If no ad is ready
## it returns false at once (the UI should check is_rewarded_ready() first and
## grey the button out). It reloads the next ad after every show.
##
## Placements are just names for analytics and per-placement rules:
##   continue        keep playing after a miss
##   booster_<kind>  get one booster when you have none
##   double_reward   double the level reward

signal availability_changed(ready: bool)
## For analytics: placement, event ("request", "shown", "rewarded", "skipped", "failed").
signal ad_event(placement: String, event: String)

const CONFIG := {
	# Which adapter to use. "mock" until an SDK is chosen. See _make_provider().
	"provider": "mock",
	"test_mode": true,
	"app_id_android": "",
	"rewarded_unit_android": "",
	"app_id_ios": "",
	"rewarded_unit_ios": "",
	"mock_duration": 3.0,
	"mock_fill_rate": 1.0,
	# Seconds before another rewarded ad can be shown (0 = no limit).
	"cooldown": 0.0,
	"retry_load_after": 8.0,
}

var provider: AdProvider
var showing := false
var _last_shown := -1e9
var _earned := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	provider = _make_provider(CONFIG.provider)
	add_child(provider)
	provider.rewarded_loaded.connect(func(): availability_changed.emit(true))
	provider.rewarded_load_failed.connect(_on_load_failed)
	provider.rewarded_earned.connect(func(): _earned = true)
	provider.initialize(CONFIG)
	provider.load_rewarded()


func _make_provider(name: String) -> AdProvider:
	match name:
		# "admob": return preload("res://ads/admob_provider.gd").new()
		_:
			return preload("res://ads/mock_ad_provider.gd").new()


func is_rewarded_ready() -> bool:
	if showing or provider == null:
		return false
	if CONFIG.cooldown > 0.0 and _now() - _last_shown < CONFIG.cooldown:
		return false
	return provider.is_rewarded_loaded()


## Shows a rewarded ad. Returns true if the player earned the reward.
func show_rewarded(placement: String) -> bool:
	ad_event.emit(placement, "request")
	if not is_rewarded_ready():
		ad_event.emit(placement, "failed")
		return false
	showing = true
	_earned = false
	availability_changed.emit(false)
	var was_paused := get_tree().paused
	get_tree().paused = true
	var bus := AudioServer.get_bus_index("Master")
	var was_muted := AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, true)
	var result := [false]  # [done]
	var on_done := func(): result[0] = true
	provider.rewarded_closed.connect(on_done, CONNECT_ONE_SHOT)
	var on_fail := func(_e): result[0] = true
	provider.rewarded_show_failed.connect(on_fail, CONNECT_ONE_SHOT)
	provider.show_rewarded()
	ad_event.emit(placement, "shown")
	while not result[0]:
		await get_tree().process_frame
	if provider.rewarded_closed.is_connected(on_done):
		provider.rewarded_closed.disconnect(on_done)
	if provider.rewarded_show_failed.is_connected(on_fail):
		provider.rewarded_show_failed.disconnect(on_fail)
	# Some SDKs report the reward a moment after closing.
	await get_tree().create_timer(0.1, true, false, true).timeout
	AudioServer.set_bus_mute(bus, was_muted)
	get_tree().paused = was_paused
	showing = false
	_last_shown = _now()
	ad_event.emit(placement, "rewarded" if _earned else "skipped")
	provider.load_rewarded()
	return _earned


func _on_load_failed(_error: String) -> void:
	availability_changed.emit(false)
	await get_tree().create_timer(CONFIG.retry_load_after, true, false, true).timeout
	if not provider.is_rewarded_loaded():
		provider.load_rewarded()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
