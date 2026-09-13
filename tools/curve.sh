#!/usr/bin/env bash
# Walk the intended route and report whether the level curve holds.
#
#   tools/curve.sh [--seed=N]
#
# Wraps src/debug/curve.gd. Fails the run if an area is never cleared or a
# battle never terminates, and prints the per-area numbers either way -- the
# numbers are the point, not the pass.
#
# Set GODOT to point at a different binary.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/tmp/godot_bin/Godot_v4.3-stable_linux.x86_64}"

if [ ! -x "$GODOT" ]; then
	echo "curve.sh: no Godot binary at $GODOT (set GODOT=/path/to/godot)" >&2
	exit 2
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$GODOT" --headless --path "$ROOT" -s res://src/debug/curve.gd ++ "$@" 2>&1 | tee "$log"

if ! grep -q "^curve: result pass" "$log"; then
	echo "curve.sh: the route does not hold" >&2
	exit 1
fi
