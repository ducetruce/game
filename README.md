# Hollowmere

A standalone top-down 2D monster-taming RPG built in **Godot 4.x** with GDScript.
Original world, original creatures, original code.

Tonally inspired by atmospheric pixel-art creature RPGs — feel and mood only.
No third-party assets, code, or creature designs.

## Running it

1. Install [Godot 4.3 or newer](https://godotengine.org/download) (standard build, not .NET).
2. Open Godot, choose **Import**, and select the `project.godot` file in this folder.
3. Press **F5** (or the ▶ play button, top right).

## Project layout

| Path              | Contents |
|-------------------|----------|
| `scenes/`         | `.tscn` scene files, grouped by area of the game |
| `src/`            | GDScript, mirroring the `scenes/` grouping |
| `data/`           | Game content as JSON — creatures, moves, type chart |
| `assets/`         | Sprites, tilesets, audio, fonts |
| `docs/DESIGN.md`  | Locked design decisions and the reasoning behind them |

## Conventions

- **Tile size is 16×16.** Base render resolution is 320×180 (20 tiles wide),
  integer-scaling to 1280×720 / 1920×1080 without shimmer.
- **Texture filtering is nearest-neighbour**, set project-wide.
- **Content lives in `data/*.json`**, not in code, so it can be edited and
  diffed as plain text.
- Scripts live in `src/` mirroring their scene's folder, rather than beside
  the `.tscn`, so scripts are greppable in one tree.

## Art status

Everything visible right now is a placeholder drawn in code. See
`docs/DESIGN.md` § Art pipeline for the tile-size contract any purchased or
commissioned art has to meet.

## Build order

1. ✅ Project setup — scaffolding, folder structure, git
2. ⬜ Overworld movement & map
3. ⬜ Creature data model
4. ⬜ Turn-based battle system
5. ⬜ Attunement (capture) mechanic
6. ⬜ Save/load
