#!/usr/bin/env bash
# Run this project as a game.
# Override the engine path with: GODOT=/path/to/godot ./play.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		echo "$GODOT"; return
	fi
	local candidates=(
		"$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
		"/Applications/Godot.app/Contents/MacOS/Godot"
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot"
		"$(command -v godot4 2>/dev/null || true)"
		"$(command -v godot 2>/dev/null || true)"
	)
	for c in "${candidates[@]}"; do
		[[ -n "$c" && -x "$c" ]] && { echo "$c"; return; }
	done
}

GODOT_BIN="$(find_godot)"
if [[ -z "$GODOT_BIN" ]]; then
	echo "Godot not found. Set GODOT=/path/to/godot and retry." >&2
	exit 1
fi

exec "$GODOT_BIN" --path "$DIR" --fullscreen
