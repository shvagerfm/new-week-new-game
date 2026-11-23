# Rooftop Dash

A courier runs across the rooftops of a city at night. Running is automatic; one button jumps, and holding it jumps higher. The goal is to get as far as you can.

This week's game is **landscape** (1280×720), unlike the portrait template: a runner needs to see the roofs coming.

## Controls

| Input | Action |
| --- | --- |
| Tap, click, Space, Up, W, Enter | Jump. Hold for a higher, longer jump |
| M, or the speaker in the top-right corner | Sound on/off |
| Esc, P, or the pause button in the top-left corner | Pause |

The game also pauses when the window or tab loses focus.

### On phones

- The game needs landscape. Held upright, it pauses and asks you to turn the phone.
- Every new touch is a jump, even while another thumb is still down, so you can alternate thumbs. A tap shorter than one frame still counts.
- A typical tap (up to about 0.15 s) passes under wires; only a deliberate hold hits them.
- Jumps forgive a little touch lag: 0.10 s of coyote time after leaving a roof, and a press up to 0.15 s before landing still jumps.
- The corner buttons are 88 px (about 48 pt on a phone) and sit 40 px in from the sides, clear of rounded corners and notches.
- On very wide screens the far skyline shows twice, so every other copy hides its moon. After a fall, a tap restarts straight away (taps in the first 0.45 s are ignored so a panicked press doesn't skip the results).

## How a run works

- **Speed** starts at 400 px/s and climbs toward 800 px/s (about 540 px/s at 250 m, 620 at 500 m, 720 at 1000 m). Gaps get wider with it, roofs get shorter, and obstacles show up more often (difficulty is full at 1200 m).
- **Edge landings.** Landing within 40 px of a roof's front edge raises the multiplier (up to ×5) and gives 10 × multiplier points. A normal landing on a new roof resets it. The edge zone of each roof ahead glows gold with small chevrons.
- **Parcels** give 25 × multiplier. Parcels picked up close together play rising notes of a scale. They hang at the top of a full jump over a gap, above antennas, or in rows on roofs.
- **Obstacles**
  - Air conditioner: jump over it or land on top.
  - Antenna (150 px): a well-timed tap clears it, a hold is safer.
  - Skylight (from 150 m): glass in the roof. Running onto it breaks it, so jump over.
  - Wire across a gap: a tap passes under, a held jump hits it.
  - Crumbling roof (cracked, rust-tinted): it gives way a quarter second after you land, so jump off quickly.
- **Puzzle points** (secret tricks, 50 × multiplier each, from 230 m, one every 350 to 600 m)
  - Bat ride: two wide gaps you can just clear, then a third one step wider than any jump, with a bat hovering above its edge. Jump into the bat and the courier grabs it and is carried across.
  - Steam lift (from 450 m): a wall far too tall to jump, with steam rising from a pipe at its foot and laundry hanging before it. Jump into the laundry and the sheet catches the steam like a parachute and lifts you onto the wall.
- **Score** is metres plus bonus points. The best score and the best distance are saved. A flag marks the best distance on the roofs, and a line counts down the last 100 m to it.

## Windows

- Windows are big (64×80 on screen). About half are lit, each showing a room.
- From 60 m, about half the buildings have one scene in a window on the top two floors. The scenes never hurt you; they are there to pull your eye away from the jump:
  - Cat: pushes a pot off the sill as you come near, and the pot falls past the facade.
  - Disco dancer: in shorts, with coloured lights sweeping over the roofs.
  - Granny: opens the curtains, watches through binoculars, then switches on a lamp whose beam follows you.
  - Couple: argue, and a pillow flies out of the window and tumbles towards the screen.
  - Grandpa: lifts dumbbells in front of a flickering TV that lights up the wall.
  - Dog: wakes as you come, barks (WOOF, the glass shakes), then squashes its nose on the glass.

## Screens

- **Title:** the logo, a Play button, your best score and distance, and two lines on how to play. Any tap starts a run. The logo is `sprites/rooftop-dash-logo.png` (800×300 pixel art, 4×4 blocks), drawn at a whole-number scale with nearest filtering. If the file is missing, the title is set in the pixel font.
- **Game Over:** a panel slides in after 0.45 s with the cause, the score, NEW BEST! or your best, then distance, parcels and best combo. A tap anywhere (or Space) runs again, and the Menu button (or Esc) goes back to the title.
- **Mute:** the speaker button in the top-right corner, on every screen.

## Sound

Every sound is synthesized by `sfx/make_sfx.py`, so a recipe change is one script run away.

- **Effects:** jump, landing (louder after a long drop), a quiet footstep each stride, edge chime (pitched up with the multiplier), combo lost, parcel, crumble creak, roof collapse, new best, and a death sound for each cause: a knock for walls and AC units, a clang for antennas, a zap for wires, breaking glass for skylights and a whistle for falls. Grabbing the bat squeaks; grabbing the laundry flaps. The parcel sound is a soft bloop into a bell.
- **Music:** an 8-bar loop at 128 bpm in three stems. The base (bass, kick, pad) plays from the first step. The drums fade in from 6% to 22% of the speed ramp (about 40-150 m), and the lead (arpeggio and a hook) from 30% to 50% (about 210-420 m). The loop also plays up to 12% faster at top speed. On death it slows and fades out.
- **Mute:** the speaker button or M. The setting is saved.
- **Web:** browsers keep audio locked until the first tap, click or key, and that same press starts the run and the music.

## Code

| File | What it does |
| --- | --- |
| `world.gd` | The whole run as data and rules (physics, generation, collisions, score), with no drawing. Tests play it directly |
| `main.gd` | Input, camera, drawing, effects, screens, HUD, saving |
| `sprites/courier.png` | The courier: 9 frames of 64×64 (run 1-6, jump up, fall, landing squash), feet at y = 58 |
| `sprites/rooftop.png` | 4×2 atlas of 64×64 cells: roof left, middle, right, cracked; AC unit, antenna, wire, parcel. The roof surface is at y = 26 |
| `sprites/skyline-*.png` | Far, middle and near parallax layers, wrapping. 1280×720 is drawn 1:1; 640×360 is drawn at 2x |
| `sprites/facade.png` | 4×2 atlas of 64×64 facade cells, one floor each: left end, wall with window, plain wall, right end; row 2 is the crumbling look. The window opening (x 16-47, y 12-51) is see-through |
| `sprites/window-rooms.png` | 32×40 rooms behind the glass: kitchen, bedroom, living room, stairs, dark |
| `sprites/window-scenes.png` | Six window scenes, one per row, six 32×40 frames each: cat and pot, disco dancer, granny with binoculars, couple and pillow, grandpa lifting, dog |
| `sprites/window-props.png` | 16×16 bits the scenes throw out: pot, pillow, feather, disco light, WOOF, glint |
| `art.gd` | Palette for the HUD and effects, plus the old string sprites used by `art/make_icon.py` |
| `sfx.gd` | Sound effect pool |
| `screens.gd` | Title and Game Over screens, drawn over the running city; says which button a tap hit |
| `fonts/Jersey10.ttf` | Pixel font for all text (SIL Open Font License, see `fonts/OFL.txt`) |
| `music.gd` | The music: three stems started together, faded in by speed |
| `sfx/make_sfx.py` | Synthesizes every sound and the music loop (`python3 sfx/make_sfx.py`, needs numpy) |
| `art/make_icon.py` | Draws `icon.png` from the courier sprite (needs Pillow) |
| `art/make_placeholders.py` | Draws placeholder sheets at the final sizes, to paint over. It only writes sheets that are missing unless named |

The gameplay layer (courier, roofs, obstacles, parcels) is drawn at 2x; the skylines fill the screen height (1:1 or 2x). Roofs are built from the left, middle and right tiles (the coping), and the facade cells repeat below them, floor after floor, down to the street. The antenna is stretched to its 200 px height by repeating a stretch of its pole.


The generator only places a gap if a jump from the edge covers it with room to spare: it simulates the jump with the same physics (`World.reach`).

## Tests

```bash
# A bot searches for button presses that survive the first 2500 m of 20 seeds.
# A failure means the generator made an unfair jump.
godot --headless --path . --script tests/bot.gd -- --seeds=20 --meters=2500

# Puzzle points need their trick: with the bat (or the laundry) switched off,
# the bot must get stuck at the first one.
godot --headless --path . --script tests/puzzle_check.gd

# Touch input: a second thumb and a tap shorter than a frame both jump.
godot --headless --path . --script tests/input_check.gd

# Screenshots from the real scene, played by the same bot (needs a display: xvfb-run on a server).
godot --path . --rendering-driver opengl3 --script tests/shots.gd -- --out=/tmp/shots --seed=7 --every=2 --until=40
```
