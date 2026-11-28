# Rewarded ads

The game asks for ads only through the `Ads` autoload (`ads.gd`). The SDK hides behind an `AdProvider` (`ad_provider.gd`), so choosing one later touches only this folder.

```gdscript
if Ads.is_rewarded_ready():          # grey the button out otherwise
    if await Ads.show_rewarded("continue"):
        give_reward()
```

`show_rewarded()` pauses the game, mutes the sound, waits for the ad to close and returns `true` only if the reward was earned. It loads the next ad afterwards and retries failed loads every few seconds.

## Placements in this game

| Placement | Where | Reward |
| --- | --- | --- |
| `continue` | Fail panel, once per attempt | Keep playing: the ornament you hit falls off and the one you threw comes back |
| `booster_<kind>` | Booster button when you have none | One booster, used right away |
| `double_reward` | Win panel | The level's booster reward twice |

## Right now: the mock provider

`mock_ad_provider.gd` shows a full-screen "TEST AD" with a 3 s countdown. "Close" gives the reward, "Skip" gives none. Set `mock_fill_rate` in `Ads.CONFIG` below 1 to test "no ad available".

## Plugging in a real SDK

1. Install the SDK's Godot plugin (Android needs a Gradle build: turn on `gradle_build/use_gradle_build` in the Android export preset).
2. Copy `provider_template.gd` to e.g. `admob_provider.gd` and fill in the TODOs: initialize, load, show, and emit the contract signals from the SDK callbacks.
3. Add it to `Ads._make_provider()` and set `CONFIG.provider`. Put app and ad unit ids in `CONFIG`; keep `test_mode` on until release.
4. Web builds can keep the mock or use a web SDK (Poki, CrazyGames, GameDistribution) through `JavaScriptBridge`; `provider` can be chosen per platform with `OS.has_feature("web")` / `OS.has_feature("android")`.
