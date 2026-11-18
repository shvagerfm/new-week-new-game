# Crate Push: itch.io page

Copy these fields into the itch.io project page when the game goes up. The icon files are in `art/icon/`: use `icon-1024.png` as the cover source (itch.io wants 630×500, so crop or pad it on the navy background).

## Title

Crate Push

## Short description (tagline, under 140 characters)

Help a little cargo robot bring a dark space station back to life, one battery crate at a time.

## Classification

- Kind of project: HTML (playable in the browser). Add Android as a platform only once the APK is uploaded and tested on a phone: itch.io may unlist pages with platforms that don't really run.
- Genre: Puzzle
- Tags: sokoban, robots, sci-fi, space, cute, casual, relaxing, logic, 2d, singleplayer. Leave out tags the classification already covers: the genre (puzzle), inputs and "Mobile friendly" (mobile, touch) and "Made with" (godot).
- Made with: Godot
- Viewport: 405 × 720 (portrait), with "Mobile friendly" and "Fullscreen button" turned on
- Inputs: touchscreen, keyboard, mouse
- Languages: English
- AI disclosure: **Yes**, the project contains generative AI output. Tick **Graphics** (all the art was made with AI image generation). Sounds are synthesized in code and the levels were designed and checked with our own solver, so they are not generative AI.

## Screenshots

`screenshots/` holds the images for the page, in upload order: 720 × 1280 PNGs and two GIFs of a whole room being solved (`play-ice.gif`, `play-teleport.gif`). Upload both GIFs first, then the PNGs. To make them again after the art changes:

```bash
xvfb-run -a godot --path games/2026-w46-crate-push --rendering-driver opengl3 --resolution 720x1280 --script tests/store_shots.gd -- --out=/tmp/shots
```

The script writes the PNGs and a folder of frames per GIF; turn frames into a GIF with ffmpeg (`-framerate 14`, scaled to 360 px wide).

## Before publishing

- Upload the cover, the screenshots and the web build, and set every field above, while the page is still a Draft. A page goes to the top of "Most recent" only once, the first time it's made public.
- Tick the AI disclosure on the edit page.

## Description

The station has been dark for years. Kip, a small cargo robot, wakes up in the warehouse with one job: put the battery crates back on their chargers.

Crate Push is a crate-pushing puzzle game with 60 hand-picked rooms across 7 zones. Every zone brings something new to think about:

- **Warehouse.** Learn to push crates, and mind the corners: a crate in a corner is stuck for good.
- **Cold Storage.** Ice floors that slide you to the wall, and one-way conveyor arrows.
- **Boiler Room.** Fire that burns crates, and pressure plates that shut the burners off.
- **Security.** Keys, locked doors and color-coded charging bays.
- **Maintenance Tunnels.** Rotten floor that gives way, and heavy crates that crash straight through it.
- **Lab.** Teleporter pads that send Kip and crates to their twins.
- **Core.** Black holes, move limits and spare batteries.

Stuck? Kip picks up tools along the way: a scanner that shows a good next move, a grabber that drags a crate behind you, a mining charge that removes one wall, and spare batteries for rooms with a move limit. Solve a room in the fewest moves without tools to earn three stars.

Power up the core at the end to see the whole station light up.

**Features**

- 60 rooms, each one checked by a solver so it can always be finished
- Unlimited undo, and restart at any time
- Short tip cards that teach each new tile the first time you see it
- Plays with swipes, on-screen arrows, or the keyboard (arrows or WASD)
- Progress, stars and settings are saved in the browser

**Controls**

| Action | Touch | Keyboard |
| --- | --- | --- |
| Move | swipe on the board, or tap the arrows | arrows or WASD |
| Undo | Undo button | Z, U or Backspace |
| Restart | Restart button | R |
| Hint | Hint button | H |
| Sound on/off | speaker on the main menu | M |

**About the art**

The art (Kip, the station tiles and the menus) was made with AI image generation, then cleaned up and cut into sprites for the game. The sounds are made in code, and every room was designed and checked with our own solver.

Made in a week with Godot, for the New Week, New Game series.
