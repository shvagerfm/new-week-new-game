extends AdProvider
## Template for a real ad SDK. Copy to e.g. admob_provider.gd, replace every TODO
## with the plugin's API, and return it from Ads._make_provider().
##
## Most Godot ad plugins expose an Engine singleton on Android/iOS
## (Engine.get_singleton("...")) and report results through signals or callbacks.
## On the web, SDKs such as Poki or CrazyGames are JavaScript; call them through
## JavaScriptBridge and turn their promises/callbacks into the signals below.

var _sdk = null
var _loaded := false


func provider_name() -> String:
	return "TODO sdk name"


func initialize(config: Dictionary) -> void:
	# TODO: _sdk = Engine.get_singleton("SdkName") if Engine.has_singleton("SdkName") else null
	# TODO: connect the SDK's callbacks to the handlers below
	# TODO: _sdk.initialize(config.app_id, config.test_mode)
	pass


func load_rewarded() -> void:
	_loaded = false
	# TODO: _sdk.load_rewarded(config.rewarded_unit_id)


func is_rewarded_loaded() -> bool:
	return _loaded


func show_rewarded() -> void:
	if not _loaded:
		rewarded_show_failed.emit("not loaded")
		return
	_loaded = false
	# TODO: _sdk.show_rewarded()


# --- SDK callbacks -> contract signals
func _on_sdk_loaded() -> void:
	_loaded = true
	rewarded_loaded.emit()


func _on_sdk_load_failed(error) -> void:
	rewarded_load_failed.emit(str(error))


func _on_sdk_opened() -> void:
	rewarded_opened.emit()


func _on_sdk_user_earned_reward(_type = null, _amount = null) -> void:
	rewarded_earned.emit()


func _on_sdk_closed() -> void:
	rewarded_closed.emit()


func _on_sdk_show_failed(error) -> void:
	rewarded_show_failed.emit(str(error))
