# CLAUDE.md

Orientation for an AI coding agent picking up this repository cold.

## What this is

Hollowmere: a standalone top-down 2D monster-taming RPG, Godot 4.x +
GDScript. Original world, original creatures, original code — no
third-party assets, code, or creature designs. `README.md` is the
player-facing and content-authoring reference (controls, project layout,
every data schema — quests, tamers, maps, the gauntlet). `docs/DESIGN.md`
is the full numbered decision log, currently through § 41.

## Before you change anything

Read, in this order:

1. `README.md` in full — how to run it, project layout, conventions, and
   the schema for every data file you might touch.
2. `docs/DESIGN.md`'s **"Open questions"** section, at the very bottom —
   the current, honest list of what's undecided or unbuilt. Start there
   before assuming something is missing by accident.
3. The most recent few numbered sections of `docs/DESIGN.md` (ending at
   § 41) for what was just built, and why it was built that way.

## Verification workflow (non-negotiable)

This project has no CI. Every change is verified by hand, every time,
before it's considered done — reading the code is not verification.

```
python3 tools/validate_data.py
```

Validates every `data/*.json` file: schema, cross-references, map tile
symbols and walkability, quest-step reachability, obtainability of every
creature and item. Exits non-zero on error.

Then boot every entry-point scene headlessly with the real engine and
check the output for `ERROR` / `SCRIPT ERROR`:

```
GODOT=/path/to/Godot_v4.3-stable_linux.x86_64   # wherever it's installed
"$GODOT" --headless --path . scenes/ui/title_screen.tscn --quit-after 60
"$GODOT" --headless --path . scenes/overworld/overworld.tscn --quit-after 60
"$GODOT" --headless --path . scenes/battle/battle.tscn --quit-after 60
"$GODOT" --headless --path . scenes/debug/codex.tscn --quit-after 60
"$GODOT" --headless --path . scenes/debug/battle_sim.tscn --quit-after 60
# plus every scenes/overworld/maps/*.tscn
```

`tools/soak.sh` drives random real input through the overworld for a
while and fails on lost control or an engine-level error — the half a
`-s` script's own exit code can't see on its own; read its own header
comment for usage.

Never trust GDScript correctness from reading alone. Godot 4 has real,
non-obvious behavior that has broken working-looking code before — e.g.
connecting a signal that emits N arguments to a callable taking fewer
than N *throws at runtime* rather than silently dropping the extras (see
`docs/DESIGN.md` § 41). When behavior is uncertain, write a throwaway
`-s` `SceneTree` probe script, run it against the real binary, and delete
it before committing.

**Autoload singletons (`Content`, `Journal`, `Party`, `Inventory`,
`Storage`, `SaveGame`, `UiFit`) are not resolvable as bare identifiers
from a custom `-s` main-loop script**, unlike from any ordinary scene
script — fetch them with `get_root().get_node("Content")` etc. instead.
A `-s` probe script also needs to live under `res://` (e.g. a
`_`-prefixed file in the repo root) to compile at all with autoloads
resolving as global names elsewhere in the same script.

Before every commit:

- Delete any `_`-prefixed scratch/probe files you created in the repo root.
- Delete the stale local save, so a stray one is never committed and never
  masks a save/load bug:
  `~/.local/share/godot/app_userdata/Hollowmere/savegame.json`
  (path varies by OS — see README.md's "Saving and loading" section).
- Re-run the validator and the scene boots one more time.

## Standing conventions

- **Story and prose ownership.** The user, not the agent, owns every real
  line of in-game text. An agent's job is mechanism plus scaffolding: any
  new text-bearing field gets `[PLACEHOLDER]`-tagged filler, never
  invented narrative. `python3 tools/script.py check` lists every
  placeholder still outstanding.
- **`tools/script.py` is the non-coder writer's interface** into all game
  text — it exports `data/*.json` to `script/*.md` and imports edits back.
  Any new text-bearing field or object type needs export/import support
  added there too (see `OBJECT_LINE_FIELDS` / `OBJECT_PAGE_FIELDS` for the
  pattern single-string vs. multi-page fields follow).
- **Document every non-trivial decision in `docs/DESIGN.md`**, continuing
  its numbered-section pattern (currently through § 41). This file is the
  project's memory across sessions and agents — a change with no entry is
  a change the next agent has no way to know the reasoning behind.
- **Reuse before extending.** This project consistently prefers reusing an
  existing tile symbol, object type, or UI pattern over inventing a new
  one — check for a close-enough existing pattern before adding one. (§ 41's
  fast travel is a recent example: built entirely from three patterns that
  already existed — a scan-at-load registry, a windowed list screen, and
  the existing warp transition.)
- **Never invent settlements, quests, or other structural content
  silently** — flag it to the user first, even when it seems load-bearing
  for something else you were asked to build.

## Current status (as of this commit)

- 3 of the planned 10 quests exist — `the_dry_cut` (Hollow Clearing /
  the mere), `the_weight_of_the_lock` (Sluice Works), and
  `what_denned_in_the_kiln` (Emberwick Row) — gating the Elder's Gauntlet
  endgame, which needs `gauntlet_requirement: 10`. 7 quests remain; see
  `docs/DESIGN.md` § 36 for the proposed list and build order.
- The gauntlet's mechanism itself (3 trials, 2 kinds — tamer and attune)
  is fully built (§ 39) and reachable once enough quests are done.
- Fast travel between rest springs just shipped (§ 41): a "Travel" entry
  in the pause menu, warping instantly and for free to any spring the
  player has ever used.
- Everything marked `[PLACEHOLDER]` in `script/*.md` is placed, gated, and
  reachable in the world already — it is waiting on the user's own words,
  not a decision left for either side to make.
- See `docs/DESIGN.md`'s "Open questions" section for the full, current
  list of what's undecided or unbuilt.
