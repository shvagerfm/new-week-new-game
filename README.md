# New Week, New Game

One small Godot game every week, playable on phones and in the browser.

Every push to `main` exports all games to the web and publishes them on GitHub Pages, with an index page that lists them newest first.

## Layout

```
template/        starter Godot 4.7 project (portrait, touch, web + Android presets)
games/           one folder per week, e.g. games/2026-w46-tap-tap-boom
tools/new-game.sh    copies the template into a new week's folder
tools/build-web.sh   exports every game to site/ (used by CI, works locally too)
.github/workflows/pages.yml   builds and deploys to GitHub Pages
```

## Start this week's game

```bash
tools/new-game.sh tap-tap-boom          # -> games/<this ISO week>-tap-tap-boom
```

Then in Godot 4.7, use **Import** and pick `games/<folder>/project.godot`. Commit and push to `main` when you want it online.

On Windows, run the script from Git Bash.

## What the template sets up

- **Portrait, any screen.** 720×1280 base resolution with `canvas_items` stretch and `expand` aspect, so it fills phones, tablets and desktop browsers. Lay things out from `get_viewport_rect()` or with Control anchors, not fixed pixel positions.
- **Touch first.** Handle `InputEventScreenTouch` / `InputEventScreenDrag`. Mouse clicks are turned into touches (`emulate_touch_from_mouse`), so the same code works on desktop.
- **Compatibility renderer**, which is what the web and older phones need.
- **Web export without threads**, so it runs on GitHub Pages and itch.io with no special server headers.
- **Android preset** (arm64, immersive). Exporting needs the Android SDK and a keystore set up in the Godot editor. iOS needs a Mac with Xcode, so it's left out for now.

## Assets

- Art: SpriteCook (Claude can generate sprites, tilesets and animations and drop them into the game folder).
- Sound effects: [jsfxr](https://sfxr.me/). Export as WAV into the game's `sfx/` folder.

## Build the site locally

```bash
GODOT=/path/to/godot tools/build-web.sh site
python3 -m http.server -d site 8000
```

Web export templates for your Godot version must be installed (Editor → Manage Export Templates).

## Bumping Godot

Change `GODOT_VERSION` in `.github/workflows/pages.yml` and the `config/features` version in `template/project.godot`.
