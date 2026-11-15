# Crate Push

Push every crate onto a ring. Swipe (or keep dragging to keep walking), or use the arrow keys / WASD.

| Key | Action |
| --- | --- |
| Arrows, WASD | Move |
| Z, U, Backspace | Undo |
| R | Restart (can be undone) |
| Enter, Space | Next level after solving |
| PageUp/PageDown, `[` `]` | Previous / next unlocked level |

Progress (unlocked level and current level) is saved in `user://progress.cfg`.

## Adding a level

Drop a `.txt` file into `levels/`. Files are played in name order, so `13-my-level.txt` comes after `12-storage-room.txt`.

```
; My level
#######
#@ $ .#
#######
```

| Char | Meaning |
| --- | --- |
| `#` | wall |
| space, `-`, `_` | floor |
| `@` | player |
| `+` | player on a ring |
| `$` | crate |
| `.` | ring (goal) |
| `*` | crate on a ring |

- The first `;` line above a map is its title. Other `;` lines are comments.
- One file can hold several maps separated by blank lines.
- A map needs exactly one player, at least one ring, and a crate for every ring. Broken maps are skipped with a warning.
- Floor is found by flood fill from the player, so the outside of the walls stays empty.
