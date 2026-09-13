#!/usr/bin/env bash
# Play the game at random for a while and fail if anything breaks.
#
#   tools/soak.sh [--frames=N] [--seed=N]
#
# Wraps src/debug/soak.gd, which drives real key presses through the overworld
# and watches for the player losing control. This script adds the half the
# script cannot check from inside: engine-level errors. A pushed error or a
# script error does not stop a -s run or change its exit code, so a soak that
# printed a stack trace on every frame would otherwise "pass".
#
# Set GODOT to point at a different binary.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/tmp/godot_bin/Godot_v4.3-stable_linux.x86_64}"

if [ ! -x "$GODOT" ]; then
	echo "soak.sh: no Godot binary at $GODOT (set GODOT=/path/to/godot)" >&2
	exit 2
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

"$GODOT" --headless --path "$ROOT" -s res://src/debug/soak.gd ++ "$@" 2>&1 | tee "$log"

status=0

if ! grep -q "^soak: result pass" "$log"; then
	echo "soak.sh: the play-through reported a failure (or did not finish)" >&2
	status=1
fi

# UiFit warnings are included deliberately: a clipped panel is a real defect
# and has shipped four times. Godot's own "Attempt to disconnect" style
# warnings would be here too, which is the point -- none should be firing.
if grep -qE "SCRIPT ERROR|USER ERROR|USER SCRIPT ERROR|^ERROR:|WARNING: UiFit" "$log"; then
	echo "soak.sh: the engine reported errors or UI clipping during the run:" >&2
	grep -nE "SCRIPT ERROR|USER ERROR|USER SCRIPT ERROR|^ERROR:|WARNING: UiFit" "$log" >&2
	status=1
fi

exit $status
