class_name AdProvider
extends Node
## The contract every ad SDK adapter fulfils. The game never talks to an SDK
## directly: it calls the Ads autoload (ads.gd), which talks to one AdProvider.
##
## To plug in a real SDK (AdMob, AppLovin MAX, Unity Ads, Poki, CrazyGames...):
##   1. Copy provider_template.gd, fill in the TODOs with the SDK plugin's calls.
##   2. Emit the signals below from the SDK's callbacks.
##   3. Pick it in Ads._make_provider().
## See ads/README.md.

## The rewarded ad is loaded and can be shown.
signal rewarded_loaded
signal rewarded_load_failed(error: String)
## The ad is on screen (the game pauses and mutes here).
signal rewarded_opened
## The player watched long enough to earn the reward. May come before or after closed.
signal rewarded_earned
## The ad is gone (watched, skipped or failed). Always comes last.
signal rewarded_closed
signal rewarded_show_failed(error: String)


## Called once at start. config comes from Ads.CONFIG (app ids, ad unit ids, test mode).
func initialize(_config: Dictionary) -> void:
	pass


func load_rewarded() -> void:
	pass


func is_rewarded_loaded() -> bool:
	return false


func show_rewarded() -> void:
	rewarded_show_failed.emit("not implemented")


## Shown in debug overlays and logs.
func provider_name() -> String:
	return "none"
