#!/usr/bin/env bash
# Export every game (and the template) to Web and build the site index.
#   GODOT=/path/to/godot tools/build-web.sh [out-dir]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mkdir -p "${1:-$root/site}" && cd "${1:-$root/site}" && pwd)"
godot="${GODOT:-godot}"

entries=""
build() {
  local dir="$1" name="$2"
  local title week
  week="$(echo "$name" | cut -d- -f1,2)"
  title="$(sed -n 's/^config\/name="\(.*\)"/\1/p' "$dir/project.godot")"
  echo "::group::Export $name"
  mkdir -p "$out/$name"
  # First run imports assets; the second exports.
  "$godot" --headless --path "$dir" --import || true
  "$godot" --headless --path "$dir" --export-release "Web" "$out/$name/index.html"
  echo "::endgroup::"
  if [[ ! -f "$out/$name/index.html" ]]; then
    echo "Export of $name failed" >&2
    exit 1
  fi
  entries+="<li><a href=\"$name/\"><span class=\"week\">$week</span><span class=\"title\">$title</span></a></li>"$'\n'
}

# Newest week first
for dir in $(ls -d "$root"/games/*/ 2>/dev/null | sort -r); do
  [[ -f "$dir/project.godot" ]] && build "${dir%/}" "$(basename "$dir")"
done
build "$root/template" "template"

cat > "$out/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>New Week, New Game</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; font: 16px/1.4 system-ui, sans-serif; background: #171a29; color: #eef; }
  main { max-width: 640px; margin: 0 auto; padding: 32px 16px; }
  h1 { font-size: 28px; margin: 0 0 4px; }
  p { margin: 0 0 24px; color: #aab; }
  ul { list-style: none; padding: 0; margin: 0; display: grid; gap: 12px; }
  a { display: flex; gap: 16px; align-items: baseline; padding: 16px; border-radius: 12px;
      background: #232740; color: inherit; text-decoration: none; }
  a:hover { background: #2d3252; }
  .week { color: #ffb347; font-variant-numeric: tabular-nums; min-width: 6em; }
  .title { font-weight: 600; }
</style>
</head>
<body>
<main>
<h1>New Week, New Game</h1>
<p>One small game every week. Tap one to play; they work on phones too.</p>
<ul>
$entries</ul>
</main>
</body>
</html>
HTML
echo "Site written to $out"
