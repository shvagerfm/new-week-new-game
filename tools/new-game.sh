#!/usr/bin/env bash
# Start this week's game from the template.
#   tools/new-game.sh tap-tap-boom           -> games/2026-w46-tap-tap-boom
#   tools/new-game.sh tap-tap-boom 2026-w47  -> pick the week yourself
set -euo pipefail

slug="${1:-}"
if [[ ! "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "usage: $0 <slug-in-kebab-case> [YYYY-wNN]" >&2
  exit 1
fi
week="${2:-$(date +%G-w%V)}"
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/games/$week-$slug"

if [[ -e "$dest" ]]; then
  echo "$dest already exists" >&2
  exit 1
fi

mkdir -p "$dest"
(cd "$root/template" && tar --exclude=.godot -cf - .) | (cd "$dest" && tar -xf -)

# "tap-tap-boom" -> "Tap Tap Boom", Android id "com.newweeknewgame.taptapboom"
title="$(echo "$slug" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')"
pkg="$(echo "$slug" | tr -d '-')"

sed -i.bak "s/^config\/name=.*/config\/name=\"$title\"/" "$dest/project.godot"
sed -i.bak "s/com\.newweeknewgame\.template/com.newweeknewgame.$pkg/" "$dest/export_presets.cfg"
rm -f "$dest"/*.bak

echo "Created games/$week-$slug (\"$title\")"
echo "Open it in Godot: Import -> $dest/project.godot"
