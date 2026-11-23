# Rooftop Dash

A courier runs across the rooftops of a city at night. Running is automatic; one button jumps, and holding it jumps higher. The goal is to get as far as you can.

This week's game is **landscape** (1280×720), unlike the portrait template: a runner needs to see the roofs coming.

## Controls

| Input | Action |
| --- | --- |
| Tap, click, Space, Up, W, Enter | Jump. Hold for a higher, longer jump |
| M, or the speaker in the top-right corner | Sound on/off |
| Esc, P, or the pause button in the top-left corner | Pause |

The game also pauses when the window or tab loses focus. After a fall, a tap restarts straight away (taps in the first 0.45 s are ignored so a panicked press doesn't skip the results).

## How a run works

- **Speed** starts at 400 px/s and climbs toward 800 px/s. Gaps get wider with it, roofs get shorter, and obstacles show up more often (difficulty is full at 1200 m).
- **Edge landings.** Landing within 40 px of a roof's front edge raises the multiplier (up to ×5) and gives 10 × multiplier points. A normal landing on a new roof resets it.
- **Parcels** give 25 × multiplier. They hang at the top of a full jump over a gap, above antennas, or in rows on roofs.
- **Obstacles**
  - Air conditioner: jump over it or land on top.
  - Antenna: too tall for a tap, so hold.
  - Wire across a gap: a tap passes under, a held jump hits it.
  - Crumbling roof (reddish brick top): it gives way a quarter second after you land, so jump off quickly.
- **Score** is metres plus bonus points. The best score and the best distance are saved. A flag marks the best distance on the roofs, and a line counts down the last 100 m to it.

## Code

| File | What it does |
| --- | --- |
| `world.gd` | The whole run as data and rules (physics, generation, collisions, score), with no drawing. Tests play it directly |
| `main.gd` | Input, camera, drawing, effects, screens, HUD, saving |
| `art.gd` | Palette and the pixel sprites, written as strings (one character per pixel) |
| `sfx.gd` | Sound effect pool |
| `sfx/make_sfx.py` | Synthesizes every sound and the music loop (`python3 sfx/make_sfx.py`, needs numpy) |
| `art/make_icon.py` | Draws `icon.png` from the courier sprite (needs Pillow) |

The generator only places a gap if a jump from the edge covers it with room to spare: it simulates the jump with the same physics (`World.reach`). The music speeds up with the run (pitch 1.0 to 1.2).

## Tests

```bash
# A bot searches for button presses that survive the first 2500 m of 20 seeds.
# A failure means the generator made an unfair jump.
godot --headless --path . --script tests/bot.gd -- --seeds=20 --meters=2500

# Screenshots from the real scene, played by the same bot (needs a display: xvfb-run on a server).
godot --path . --rendering-driver opengl3 --script tests/shots.gd -- --out=/tmp/shots --seed=7 --every=2 --until=40
```
