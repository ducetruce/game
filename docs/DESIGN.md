# Hollowmere — Design Decisions

Decisions recorded here are the expensive-to-change ones. Each entry says what
we chose, why, and what it would cost to reverse. Anything not listed here is
still open.

Status: locked 2026-09-11, at project start.

---

## 1. Capture: Attunement

**Decision.** Capture is earned through battle turns, deterministically. There
is no capture item and no dice roll.

Every wild creature carries a hidden **Resonance** meter (0–100) and a
**Temperament**. The Temperament is a rule set describing what raises and
lowers Resonance. At 100, the creature joins the party. Each turn the creature
emits a line of flavour text telegraphing its state, so a player reads the
Temperament from the fight rather than from a wiki.

A universal non-damaging action, **Still**, is available every turn alongside
the normal move list. It is the primary Attunement verb, and it is deliberately
useless in some matchups.

**Temperaments at launch** (three; the set is data, and grows):

| Temperament | Resonance rises | Resonance falls |
|---|---|---|
| **Skittish** | You take no aggressive action (`Still`) | Any damage you deal — resets to 0 |
| **Proud** | You land a hit with **no** type advantage, while above 50% HP | `Still` (reads as weakness); exploiting a type weakness (reads as disrespect) |
| **Feral** | Its HP is low | Its HP is restored |

Each wild encounter also runs a **flee timer**. Attunement has a fail state:
push the wrong verb long enough and the creature leaves.

**Why.** It moves the interesting decision inside the turn loop instead of
outside it. Determinism kills save-scumming and makes capture a skill to learn
rather than a slot machine. It reuses the battle system rather than adding an
item economy. And it fits the tone — the fantasy is understanding a creature,
not subduing it.

**Reversal cost.** Low-to-moderate. Resonance is one integer on the battle
state and one rules table in `data/`. Adding, removing or retuning a
Temperament is a data edit. Replacing Attunement wholesale would mean
rewriting the wild-encounter turn loop but nothing below it.

---

## 2. Types: seven, sparse

**Decision.** Seven types. Multipliers are only ×2, ×1 and ×0.5 — **no
immunities**. Creatures are single-type at launch, but `types` is stored as an
array from day one, so dual-typing is later a data change and a damage-calc
tweak, not a schema migration.

The chart lives in `data/type_chart.json`, not in code.

**The types.** Bloom, Stone, Gale, Mire, Cinder, Wane, Beast.

- **Bloom** — growth, root, leaf
- **Stone** — mineral, weight, permanence
- **Gale** — wind, height, open air
- **Mire** — swamp, silt, standing water
- **Cinder** — flame, ash, heat, light
- **Wane** — entropy, twilight, decline
- **Beast** — flesh, instinct, the living animal

**Structure.** The seven sit on a ring:

```
Bloom → Stone → Gale → Mire → Cinder → Wane → Beast → (back to Bloom)
```

Each type deals ×2 to **the next type on the ring and the type three steps
ahead**. Whatever a type is ×2 against deals ×0.5 back to it. That is the whole
rule — 14 cells at ×2, 14 at ×0.5, 21 neutral. Every type has exactly two
strengths and exactly two weaknesses, so nothing is structurally dominant.

Full matrix, **row = attacker, column = defender**:

|  ATK ↓ / DEF → | Bloom | Stone | Gale | Mire | Cinder | Wane | Beast |
|---|---|---|---|---|---|---|---|
| **Bloom**  |  1  |  2  |  1  |  2  | ½   |  1  | ½   |
| **Stone**  | ½   |  1  |  2  |  1  |  2  | ½   |  1  |
| **Gale**   |  1  | ½   |  1  |  2  |  1  |  2  | ½   |
| **Mire**   | ½   |  1  | ½   |  1  |  2  |  1  |  2  |
| **Cinder** |  2  | ½   |  1  | ½   |  1  |  2  |  1  |
| **Wane**   |  1  |  2  | ½   |  1  | ½   |  1  |  2  |
| **Beast**  |  2  |  1  |  2  | ½   |  1  | ½   |  1  |

Every pairing has a reading: roots crack stone and drink the swamp; stone is
unmoved by wind and smothers flame; wind dries the mire and disperses the
fading; the mire douses fire and bogs down the beast; fire burns growth and
drives back twilight; entropy claims the living and wears down stone; the
beast tramples growth and takes the flier.

**Why seven.** Eighteen types is 324 cells and only works with a thousand
creatures to fill it. Seven is 49 cells, 28 of them non-neutral — small enough
to hold in your head, large enough that team composition is a real decision.
Adding an eighth type later costs 15 new cells, not 37.

**Reversal cost.** Adding a type: cheap, hand-tune 15 cells. Removing one:
cheap. Going to a Pokémon-scale matrix with immunities: moderate — the damage
formula would need an immunity branch and every creature would need retyping.

---

## 3. World: one connected region

**Decision.** A single continuous region. Internally it is authored
**scene-per-map**: each map is its own `.tscn`, joined to its neighbours by
named **warp nodes** at the edges. There is no world-map menu and no level
select.

Saves store `map_id` plus position, which works for any topology.

**Why.** An exploration-led game wants the world to read as a place. Hub-and-
spoke reads as a menu. Scene-per-map is the structure we would use for
hub-and-spoke anyway, so choosing "connected" costs nothing and keeps the other
option live.

**First pass.** One area, growing to three: a village, a route out of it, and a
wooded hollow.

**Reversal cost.** Near zero. Switching to hub-and-spoke means changing which
warps exist, not how maps load.

---

## 4. Data format: JSON

**Decision.** All game content — creatures, moves, type chart, encounter
tables — is JSON in `data/`, parsed into typed GDScript objects at load.
Not Godot `.tres` Resources.

**Why.** `.tres` buys inspector editing and engine-side type checking, but it
is verbose, merge-hostile in git, and its references break when a class is
renamed. Plain-text editability is the stated reason this project is in Godot
at all, so JSON is the consistent choice.

**Accepted trade-off.** No inspector editing of content, and no load-time type
safety from the engine. Mitigated by parsing into typed GDScript classes with
explicit validation, so a malformed data file fails loudly at load with the
offending file and key named, rather than producing a null deep in a battle.

**Reversal cost.** Moderate but mechanical — content would need converting, but
only the loader layer touches the format.

---

## 5. Save format: versioned JSON

**Decision.** Saves are JSON in `user://`, with a top-level `save_version`
integer and a migration function that upgrades older saves forward on load.

**Why.** Debuggable and hand-editable during development, which matters far
more right now than save size or tamper resistance. This is single-player;
there is nothing to cheat against.

**Rule.** `save_version` increments whenever a field is removed or its meaning
changes. Adding an optional field with a sane default does not need a bump.
Every bump gets a migration step, and the migration chain is never broken —
old saves must keep loading.

**Reversal cost.** Low, and the version field exists precisely so this stays
low.

---

## 6. Art pipeline

**Decision.** **16×16 tiles.** Base render resolution 320×180 (20 tiles wide),
integer-scaled to the window. Texture filtering is nearest-neighbour
project-wide. Character and creature sprites are authored at the same pixel
density as the environment — a flat-looking creature against a densely
textured world is the specific failure to avoid.

**Placeholders.** Gameplay is never blocked on art. Everything visible early is
shapes and colour drawn in code or from a generated placeholder atlas.

**On third-party tilesets.** Buying a licensed tileset as placeholder or final
environment art is reasonable and keeps the world dense from the start.
Two constraints:

1. **Verify the grid before committing.** If a pack ships at 32×32 rather than
   16×16, that is a project-settings change — cheap now, painful after maps
   exist. Either match the pack's tile size or don't use it.
2. **Creatures stay original regardless.** Licensed environment art does not
   extend to creature designs, and creature art is the thing that has to be
   ours.

**Reversal cost.** Tile size is the expensive one — it is baked into every map,
collision shape and sprite. Everything else about art is swappable.

---

## 7. Movement: fully free

**Decision.** Free 8-directional analogue movement over a collision grid. The
player is never snapped to tiles and can stand at any sub-pixel position.
Diagonals are normalised, so moving diagonally is not faster than moving
straight.

**The problem this creates.** Grid-locked movement answers "which tile is the
player facing" for free — you are always on a tile, facing an axis. Free
movement does not, so three systems need explicit answers:

1. **Facing** is tracked as a discrete four-way value updated from *input*, not
   from position. On an exact diagonal the horizontal axis wins; the rule is
   arbitrary but it has to be deterministic or facing flickers as you walk.
2. **Interaction targeting** uses a 12×12 probe box parented to the player and
   offset in the facing direction, rather than a tile lookup. Anything solid
   and in the `interactable` group that overlaps the probe can be acted on.
   Interactables are solid, so bumping into one leaves you facing it.
3. **Encounter triggers** cannot count steps. When encounters land, they
   accumulate *distance travelled* inside an encounter zone and roll against a
   threshold. This is arguably better than step-counting: it makes running
   through tall grass genuinely riskier per second than creeping.

**Pixel snapping.** `snap_2d_transforms_to_pixel` and
`snap_2d_vertices_to_pixel` are both on. Without them, fractional positions
round inconsistently between frames and the entire scene shimmers while
walking. The cost is that motion is very slightly steppy at low speeds, which
is inherent to pixel art and not worth fighting.

**Accepted cost.** Tile-aligned puzzle mechanics — pushable blocks, ice
sliding, pressure plates — get awkward, because "the block is on tile X" stops
being naturally true. If we want those later they need their own snap-on-
release logic rather than coming free from the movement system.

**Reversal cost.** Low. The controller is one script; facing, the probe, and
the encounter accumulator are the only things that assume free movement.

---

## 8. Map authoring: text now, editor later

**Decision, and it is temporary.** Maps are JSON in `data/maps/`, holding a
grid of one-character tile symbols plus a player start and an object list.
`GameMap` parses that at runtime and paints it into two `TileMapLayer` nodes —
`Ground` (no collision) and `Obstacles` (carries the tileset's physics layer).
The symbol table lives in `src/overworld/tile_legend.gd`.

**Why not paint in the editor now.** With eight placeholder tiles, a text grid
is faster to edit, reviewable in a diff, and editable without opening Godot.

**Why this does not last.** The stated art direction is dense, layered,
painterly tiles. Authoring that in ASCII would be miserable, and Godot's
TileMapLayer editor with terrain autotiling is the right tool for it. **When
real tilesets land, maps get painted in the editor and this loader is
deleted.** It is scaffolding, not architecture.

**What survives the switch.** Map-as-its-own-scene, the Ground/Obstacles layer
split, the object list, and `player_start`. Only the tile grid moves from JSON
into the scene file.

---

## 9. Stats: six

**Decision.** Six stats: **hp, attack, defense, spirit, resolve, speed**.
Physical moves are attack vs defense; spirit moves are spirit vs resolve;
status moves deal no damage.

**This reverses an earlier decision, and the reason is worth keeping.** The
first cut had five stats, with a single `spirit` doing both the offensive and
the defensive job on the non-physical side — chosen for the same reason the
type chart has seven types rather than eighteen: fewer numbers, each mattering
more.

It was the wrong call. A single Spirit stat is a superstat: the best spirit
attacker is automatically the best spirit wall, so a creature's non-physical
identity collapses into one axis. That *narrows* team-building instead of
widening it, and it hides real weaknesses rather than exposing them.

Splitting it means a creature can now be:

- a spirit attacker with a glass jaw — Moorhound, spirit 34 / resolve 38
- a spirit wall that cannot hit back — Gloamkin, resolve 66 / defense 42
- physically immense and mentally open — Sloughback, defense 60 / resolve 44

Those are distinct, exploitable profiles. Under the five-stat model all three
would have read as "low spirit" and played the same way.

**Cost.** One more number per species, and one more row in every stat display.
Base totals moved from ~275 to ~320-330 to absorb the sixth stat; the spread
between creatures stayed tight (320-328) so nothing is strictly better than
anything else.

**Note.** There is no Normal-equivalent type, so there are no typeless damaging
moves. Status moves may use `"type": "none"`; damaging moves may not, and the
validator enforces it.

---

## 10. Levelling and damage

**Levels 1–50, per-level stat curves.** Linear growth from base stats:

```
hp    = floor(base * level / 50 * 2.0) + level + 10
other = floor(base * level / 50 * 1.5) + 5
```

The flat terms stop level 1 from being degenerate; the scales decide how much
of a stat is earned by levelling rather than granted by the species. No IVs, no
EVs, no per-species growth rates — all three can be added later without
invalidating anything already stored, because a creature persists its
experience total, not its stats.

**Experience.** One curve for every species: `(level - 1)³` cumulative, so
level 50 is 117,649. Per-species rates can come later behind the same API.

**Damage.**

```
ratio  = (A / D) ^ 0.75
base   = ((2 * level / 5 + 2) * power * ratio) / 50 + 2
damage = max(1, floor(base * type_multiplier * stab * variance))
```

STAB is ×1.5. Variance is ×0.85–1.00.

**The exponent is load-bearing.** With a raw `A / D` ratio, the hardest hitter
in the roster one-shot the frailest: a ×2 type match and STAB multiply on top
of an already lopsided stat ratio. Raising the ratio to the power 0.75 dampens
it — doubling your attack against a given defence multiplies damage by 1.68
rather than 2 — which removes every one-shot in the roster at every level
without moving the medians at all. Stat advantages still matter; they just stop
compounding into a single decisive number.

One-shots are not merely unfun here, they are a design failure: a Feral
creature is only attunable at low HP, so a creature that dies in one hit can
never be captured.

**Tuning target, and why it matters here specifically.** Measured across all
78 same-type matchups in the roster at the level cap: neutral hits KO in a
median 4.8 turns, super effective in 2.5, resisted in 9.8, with no one-shot at
any level. That is slower than the genre norm on purpose: **Attunement needs
the fight to last**. Reading a creature's Temperament and acting on it takes
several turns, and a two-turn battle would make the entire capture mechanic
unreachable. The damage divisor is the single knob that controls this.

**On variance.** Attunement is deterministic by design, and damage variance is
the one place randomness remains. It is small, and it is kept because a fully
deterministic battle is solvable rather than played. It does mean a Proud
capture (which requires acting while above half HP) can be disrupted by an
unlucky roll — that is tension, not unfairness, but it is worth watching in
play.

---

## Open questions

- Party size, and whether creatures are stored or all carried.
- Whether critical hits exist at all, given how much the design leans on
  readable, near-deterministic combat.
- Whether Attunement is available against tamer-owned creatures, or wild only.
- Levelling: experience curve, or milestone-based growth.
- Whether moves are learned by level, by taught item, or by Temperament.
- Whether interactables should be solid by default, or whether some
  (ground items, plaques) should be walkable and probed anyway.
