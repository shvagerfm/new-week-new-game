# Deck the Tree (Прикрась ялинку)

An elf decorates a Christmas tree, tier by tier. Each tier of the tree spins in front of the elf; tap to throw an ornament onto it. Throw every ornament the tier needs without hitting one that is already hanging. When a tier is full it rises onto the tree and the next, smaller tier comes in. Finish every tier and the tree is decorated, star on top.

Portrait (720×1280), touch first. Ukrainian and English.

## Controls

| Input | Action |
| --- | --- |
| Tap anywhere, Space, Up, W | Throw an ornament |
| Booster buttons, 1–5 | Slow, Shield, Aim, Magnet, Fire |
| Pause button, Esc, P | Pause |

The game pauses when the window loses focus.

## Rules

- Hitting a hanging ornament ends the attempt at once. So does landing on an ice plate.
- **Tiers.** Levels 1–3 have one tier; the tree grows to 3 tiers in world 1 and up to 5 by world 5. Upper tiers are smaller and spin faster. The finished tiers show in the corner as the tree grows.
- **Candies** on the rim: hit them all for the second star.
- **Golden stars** on the rim (world 4 on): all of them must be hit before the tier's ornaments run out.
- **Ice plates** (world 3 on): an ornament that lands on one shatters.
- **Sway** (world 4) and **breathing** (world 5): the tier moves left and right, or grows and shrinks.
- **Bosses** (levels 10, 20, 30, 40, 50): the top tier is a golden star with a health bar. At each phase it shakes every ornament off, speeds up and brings new hazards.
- **Stars:** 1 for finishing, 1 for all candies (or none on the level), 1 for a time under par.

## Boosters

Each can be used once per level. You start with one of each; every first clear of a level gives one more (two for a boss). With none left, the button plays a rewarded ad and uses the booster.

| Booster | Effect |
| --- | --- |
| Slow | The tier spins at 40% speed for 5 s |
| Shield | One clash (or ice hit) is forgiven; the ornament comes back |
| Aim | 8 s of a guide line: green when a throw now is safe, red when not |
| Magnet | Takes 3 ornaments off around the landing spot |
| Fire | The next ornament knocks hanging ones aside and melts ice |

## Rewarded ads

All ads go through the `Ads` autoload; a test ad stands in until an SDK is chosen. See [ads/README.md](ads/README.md). Placements: continue after a fail (once per attempt), a booster when you have none, and doubling the level reward.

## Files

| File | What it does |
| --- | --- |
| `main.gd` | Screens and flow: title, level map, HUD, win/fail/pause panels, saving |
| `game.gd` | One level: spin, throws, collisions, boosters, bosses, drawing |
| `levels.gd` | The 50 levels (5 worlds × 10) and how tiers are built from each entry |
| `rotor.gd` | Spin programs: steady, reversing, pulsing, random |
| `tree_art.gd`, `views.gd`, `quiver_view.gd` | The growing tree, the title/win tree, the ornaments-left column |
| `art.gd`, `art/PROMPTS.md` | Optional PNG art and the ChatGPT prompts to make it |
| `ads/` | Rewarded ad wrapper, mock provider, template for a real SDK |
| `sfx/make_sfx.py` | Generates the sound effects (`python3 sfx/make_sfx.py`, needs numpy) |
| `save.gd`, `loc.gd` | Progress file and UA/EN strings |

## Tests

```bash
# A bot plays every level 8 times and reports wins (it only throws when the aim check says it's safe)
godot --headless --path . --script tests/sim.gd -- --tries=8
# Screenshots of the main screens (needs a display; xvfb-run on a server)
xvfb-run godot --path . --rendering-driver opengl3 --script tests/shots.gd -- --out=/tmp/shots
```
