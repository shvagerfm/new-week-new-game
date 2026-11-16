# Crate Push

Kip, a little cargo robot, restarts an abandoned space station by pushing battery crates onto their chargers. The game has seven zones, and each one adds a mechanic and a tool.

| Zone | New mechanic | New tool |
| --- | --- | --- |
| 1 Warehouse | pushing crates, stars | |
| 2 Cold Storage | ice, one-way arrows | Hint |
| 3 Boiler Room | fire, pressure plates | Pull |
| 4 Security | keys and doors, colored crates | |
| 5 Maintenance Tunnels | crumbling floor, heavy crates | Blast |
| 6 Lab | teleporters | |
| 7 Core | black holes, move limits, clocks | +5 moves |

## Controls

Tap the arrow buttons under the board, or swipe on the board. Hold an arrow (or keep dragging) to keep walking. On a keyboard, use the arrows or WASD. Swipes that start on the bottom controls are ignored, so a press on an arrow never also counts as a swipe. Undo and Restart sit in the top bar, away from the arrows, and Restart asks before it clears the room.

| Key | Action |
| --- | --- |
| Z, U, Backspace | Undo |
| R | Restart (asks first, and can be undone) |
| H | Hint |
| Esc | Back |
| Enter, Space | Default button on a popup |

Tap the CRATE PUSH logo on the main menu seven times to unlock every zone, for testing.

## Tips

A tip card under the room title teaches the game as it goes. Every card shows once, and the save file remembers which ones were seen.

- **First room walkthrough.** Three steps: move Kip, push the crate, charge it. Each step moves on when the player does it, and the board points at Kip, the crate and the charger (and the arrow buttons in the first step).
- **New things.** The first time a room has a new tile, crate or tool (ice, arrows, fire, plates, keys and doors, colored crates, cracked floor, heavy crates, teleporters, black holes, move limits, clocks, and each tool), a card explains it and outlines it on the board or around its button. Undo and Restart get a card in the second room.
- **Stars** are explained on the first win screen.
- A card closes with **Got it** (or Enter), or by itself after 6 moves. **Skip tips** turns all cards off; the **Tips** button in the top-right corner of the main menu turns them back on and shows every card again.

The cards and the rules for when each one shows are in `tutorials.gd`. A new tile type needs a topic there and a line in `topics_for`.

## Stars and tools

- ★★★ means you used the fewest possible moves (the level's `par`) and no tools.
- ★★ means you stayed within par + max(4, par / 3) moves.
- ★ means you solved it.

Each tool can be used a set number of times per attempt: Hint 3, the others 1. Using any tool caps the result at ★★.

- **Hint** solves the level from where you stand and shows the next move.
- **Pull** arms the grabber, so the next step away from a crate drags it along.
- **Blast** arms a charge. Swipe toward an inner wall to remove it. Outer walls can't be blasted.
- **+5 moves** only works in rooms with a move limit.

## Levels

Each zone is a folder in `levels/`, played in name order. The folder holds a `zone.cfg` (name, color, story, and the tool it unlocks) and one `.txt` map per level, also played in name order. To add a level, drop a new file in.

```
; Switch
; tip A crate on the plate puts out every fire.
; par 5
#########
#@ $ _  #
####~####
#   $   #
#   .   #
#########
```

The first comment line is the title. `; tip` is shown above the board for the first few moves, `; limit N` sets a move limit, and `; par N` is the fewest moves (the checker writes this one).

| Char | Meaning |
| --- | --- |
| `#` | wall |
| space | floor |
| `@` / `+` | Kip / Kip on a charger |
| `$` / `*` | crate / crate on a charger |
| `.` | charger (takes any crate) |
| `a` `b` `c` | colored crates |
| `A` `B` `C` | colored chargers (only take a crate of the same color) |
| `&` | heavy crate: doesn't slide on ice, crashes through cracked floor |
| `=` | ice: Kip and crates slide until they hit something or reach plain floor |
| `>` `<` `^` `v` | one-way arrow: can only be entered in that direction |
| `~` | fire: blocks Kip, burns crates |
| `O` | black hole: swallows crates and Kip |
| `_` | pressure plate: fire and black holes switch off while every plate has a crate on it |
| `%` | cracked floor: becomes a hole once it's left empty. A crate pushed into the hole fills it |
| `k` / `D` | key / door. Each key opens one door. Crates can't open doors |
| `1`–`9` | teleporter pads, in pairs with the same digit |
| `t` | clock: +5 moves in a room with a move limit |

## Tools for level makers

```bash
# Check that every level can be solved, and print the fewest moves
godot --headless --path games/2026-w46-crate-push --script tests/check_levels.gd
# ...and store each result as "; par N" (used for stars)
godot --headless --path games/2026-w46-crate-push --script tests/check_levels.gd -- --write-par
# Only some levels
godot --headless --path games/2026-w46-crate-push --script tests/check_levels.gd -- --only=cold-storage

# Generate random room ideas with given features and print the most interesting ones
godot --headless --path games/2026-w46-crate-push --script tests/generate.gd -- --features=ice,arrows --crates=2
```

The checker, the hint and the game all use the same rules in `rules.gd`, so they always agree.

## Art

- `art/source/sheet-1..4` hold the board and HUD sprites (128 px tiles). `sprites.gd` maps names to tiles.
- `art/source/ui/crate-push-ui-assets.png` holds the menu art: logo, buttons, level tiles, stars, panel frame and zone icons. Some pieces cross the 256 px grid, so `ui_art.gd` and `ui/atlas.json` store the measured bounds of each piece. Buttons and the panel frame are stretched as 9-slice boxes.
- The mockups in `art/source/ui/` are reference only and are not used in the game.
