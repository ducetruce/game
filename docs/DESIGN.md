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

**Update, step 5.** "No capture item" held for the core mechanic and still
does — nothing here is decided or gated by an item. Building it surfaced a
real problem (an over-levelled hit can faint a wild creature before Proud or
Feral's conditions are even reachable) that needed a narrow, optional fix: a
purchasable item that prevents a single hit from being lethal, nothing more.
See § 13 for what it does, the design that was tried and rejected first, and
why it does not reopen this decision.

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

**Update, step 6.** Shipped as designed — see § 14 for the exact shape, the
three autosave points that stand in for a save menu that does not exist yet,
and the position/map_id fallback that protects against a save pointing at
ground that no longer exists.

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

## 11. The battle loop

**Decision.** All battle rules live in `BattleState`, which contains no nodes.
The battle scene submits an action and renders the log it gets back.

**Why the split earns its keep.** A turn loop is the one part of this game that
can fail by never finishing, and that failure is invisible in a single
playthrough. Because `BattleState` is headless, `scenes/debug/battle_sim.tscn`
can run hundreds of complete battles and report whether any hit a turn cap.
That check does not exist if the rules are tangled into the scene.

**Turn structure.**

1. The wild creature picks its action.
2. Order: switching and fleeing always go first; otherwise higher effective
   Speed, with a coin flip on an exact tie.
3. Each side acts in turn. **A faint ends the turn immediately** — whoever went
   down does not also get to act.
4. If the player's creature fainted and a reserve is standing, the battle sits
   in `REPLACING` until one is sent out. Backing out of that menu is refused.

**Stat stages** use the standard curve: +1 is ×1.5, −1 is ×0.67, saturating at
±6, cleared whenever a creature switches out. HP is never staged. `Damage`
takes Combatants rather than Creatures specifically so stages cannot be
forgotten — there is no call that quietly skips them.

**The wild creature's AI** takes its single best damaging option 70% of the
time and something random otherwise. A perfectly optimal opponent is both
harder to read and less interesting than one that occasionally does something
else — and Attunement depends on the player being able to read intent.

**Fleeing** scales with the Speed ratio but mostly with the number of attempts,
so a slow party is never permanently trapped by something fast.

### What simulation found

Running 3000 complete battles (parties of three, levels 10–20, both sides
taking their hardest-hitting option every turn):

- **Every battle terminated.** Average 6 turns, median 6, p99 16, longest 24.
- **The flat damage term had to go.** The formula previously added a constant
  +2 to base damage. That is negligible against a level 50 health pool and
  enormous against a level 8 one: it was making the early game — exactly where
  the player is learning to tame things — run three-turn fights, with one-shots
  occurring at level *parity*. Removing it cut near-parity one-shots in the
  5–10 band from 27 to 5 and lengthened early battles from 3.4 to 4.9 turns,
  while leaving level 45–50 untouched. A minimum of 1 damage per hit is kept.

### Known, and deliberately not fixed here

**A sufficiently over-levelled creature still one-shots.** After the fix, the
remaining one-shots come from level advantage rather than stat spreads — rare
at +1 or +2 levels, common at +5 or more. For ordinary combat that is normal
RPG behaviour. For Attunement it is a real problem: **Proud** requires landing
a hit, and **Feral** only attunes at low HP, so a creature that dies to the
first blow cannot be captured at all.

This needs a rule, and the rule belongs with Attunement in § 1 rather than
being improvised into the damage formula now. The obvious shape is that
pulling a punch is a stated intent rather than an accident, but the design is
not settled and inventing it here would couple two systems that should be
decided separately.

**Move exhaustion has no resolution.** If both sides run out of uses on every
move, nothing in the rules ends the battle. Simulation never produced it at
these levels, but the rules permit it. A Struggle-equivalent, or a turn limit
on wild battles, will be needed eventually.

---

## 12. Encounters, and the overworld/battle seam

**Encounters are distance-driven.** Grid movement counts steps; free movement
has no steps to count. `EncounterTracker` accumulates world distance instead
and rolls once every 28 pixels travelled inside an encounter zone.

The consequence is the one worth stating: **risk is per distance, not per
second.** Running through bracken does not dodge encounters, it meets the same
number of them sooner. Creeping is safer per second and identical per tile.
Tuned with the map's 0.12 chance, a check lands about every 14 tiles — roughly
four seconds at a walk, a little over two at a run.

Leaving a zone resets accumulated progress, so clipping the corner of a patch
repeatedly cannot bank a check. After a battle there is a short travel grace,
so walking out of the bracken you just fought in does not immediately drop you
into another fight.

**Encounter tables live in the map file, keyed by tile symbol**, so different
terrain on the same map can hold different creatures without any code change.

**Battles overlay, they do not replace.** The battle scene is instanced onto a
`CanvasLayer` inside the overworld rather than swapped in via
`change_scene_to`. The map stays loaded, the player returns exactly where they
were standing, and nothing has to be saved and restored across the transition.
This is the same seam map-to-map travel will use.

**The party is a singleton passed by reference.** `Party` holds the player's
creatures; battles receive those same `Creature` objects, which is why damage
and experience persist without any copy-back step. It is also already the thing
step 6 will serialise.

**Experience follows risk.** Only creatures that were actually sent out share
the reward, and a creature that fainted does not collect. The award scales with
the defeated creature's level *and* its species' total base stats, so a rare
heavy hitter pays better than a common one at the same level. Measured against
the map's own table, a starting pair at level 5 gains a level every 3 battles,
slowing to every 13 by level 12 — which is the pressure that should push the
player toward somewhere with stronger creatures rather than grinding here.

**Losing** restores the party and returns the player to the map's start. There
is no penalty beyond the walk back. A `spring` object on the map restores the
party on interaction, so winning a fight at low HP is recoverable without
having to lose one deliberately.

**Move learning on level up** announces and skips when a creature already knows
four moves, rather than silently replacing one. Choosing what to forget needs a
prompt that does not exist yet, and guessing on the player's behalf is worse
than waiting.

---

## 13. Attunement, implemented: Resonance, the stall clock, and the Tempering Draught

Section 1 locked the shape of Attunement before any code existed. This is what
building it actually required, including a real design problem simulation
uncovered and the fix that survived a second round of scrutiny.

**Resonance** is a float 0–100 on the wild `Combatant` (not the battle, not the
species — it belongs to this specific encounter and resets to zero if the
creature is met again later). Each temperament reads the fight differently:

- **Skittish** gains Resonance only from `Still`. Any landed, damaging hit
  resets it to zero outright.
- **Proud** gains Resonance from a landed hit that is *not* super effective,
  landed while the creature is still above 50% HP. `Still` reads as weakness
  and costs Resonance. A super-effective hit while healthy reads as disrespect
  and costs more.
- **Feral** is passive: it gains Resonance on any turn its HP is at or below
  30%, regardless of what the player did that turn, and loses a chunk if it
  heals itself back above that line (tracked precisely — a real self-heal
  effect, not just "took less damage than usual" — so a wild creature that
  happens to know Mend can genuinely undo your progress).

A single universal **stall clock** backs all three: any turn Resonance does
not increase adds to a counter; six such turns and the creature breaks off
(`Phase.FOE_FLED`). It resets the instant Resonance rises. This is what turns
"push the wrong verb" from prose into a real fail state, and it is temperament-
agnostic on purpose — one rule, everywhere, rather than three bespoke timers.

Rules and flavour text live in `data/temperaments.json`, not code — the same
choice made for the type chart and it holds for the same reason: the numbers
above are precisely tunable without touching GDScript, and `tools/
validate_data.py` checks every temperament has the exact flavour states the
code actually looks up (a missing state fails loudly at validation time, not
as a silently blank line mid-fight).

### The one-shot problem, and the design that didn't survive contact

Step 4 flagged a blocker: a sufficiently over-levelled hit can faint a wild
creature outright, and both Proud (needs a landed hit) and Feral (needs low,
not zero, HP) become mathematically impossible once that happens. The first
fix proposed was a universal rule — **wild creatures simply cannot be reduced
below 1 HP by the player, ever.** It was rejected in review, correctly: it
quietly removed "fight a wild creature to defeat it" as a playstyle for every
encounter, not just the mismatched ones, which is a far bigger change than the
bug required.

The shape that replaced it, at the user's suggestion: a **purchasable,
consumable item** rather than a rule baked into all combat. This solves the
scope problem (the fix is opt-in, default combat is untouched) but raises a
sharper question — does an item that prevents death also just trivialize the
fight? Simulating the first version of the item (again "cannot go below 1 HP,"
now scoped to only-while-used-this-battle) confirmed exactly that: **Feral
captures hit 100% success with zero attentiveness required**, because the
first hit — however overkill — simultaneously satisfied "low HP" and "cannot
die," leaving nothing left to manage.

**The Tempering Draught, as shipped, caps a single hit's damage at 25% of the
wild creature's max HP — for the rest of that battle. It does not prevent a
death, it prevents a one-hit death.** Simulated head to head:

| Scenario (L50 attacker vs. L10 wild) | Careless (always attacks) | Attentive (holds once fragile) |
|---|---|---|
| With Draught | 0% — still faints it | Skittish 100%, Feral 100%, **Proud 0%** |
| No Draught | 0% (the original blocker) | Same, 0% either way |

Two results matter. **Careless play still fails**, item or not — the Draught
only stops an *instant* end, it does nothing to stop a creature being finished
off over several hits if the player keeps swinging after it's already fragile.
Buying the item does not remove the attention the fight requires. And **a
badly over-levelled Proud creature is never capturable, Draught or not** — it
always breaks off rather than being tamed. That falls out of the same 25% cap:
a capped hit still crosses the "must stay above half HP" line in about two
turns, which is not enough qualifying hits to fill the meter, whatever move is
chosen. This was kept deliberately rather than patched further: overwhelming
force should not be able to buy something whose whole temperament is about
respect. The item buys freedom from *accidents*, never freedom from being
outmatched.

**The 25%-cap / 50%-healthy-line relationship is load-bearing and not
self-enforcing.** Because the cap is exactly half of Proud's healthy threshold,
a capped hit landed while healthy can never itself be lethal — the invariant
that keeps "gained Resonance" and "fainted" from ever being decided by the same
hit under Restrained play. Retuning either constant independently would break
this silently; there is no code assertion for it, only this note and the
simulation that depends on it.

**A genuine race condition surfaced in review and was fixed before shipping,
not after:** a single hit can, on paper, simultaneously be the hit that crosses
the capture threshold *and* the hit that faints the target (resonance already
near 100, no Draught in play, a hot damage roll). The resonance tick runs
before the faint check every turn, so without a guard the faint check would
silently overwrite a just-earned `ATTUNED` with `WON`. The fix makes capture
win that race — a capture is never overwritten by a faint from the same blow —
while a *stall-triggered flee* explicitly cannot fire on a hit that also
fainted the target, so a creature that was actually defeated is never narrated
as having fled and never silently loses its experience payout. Both directions
of this race were reasoned through and fixed; neither showed up in the bulk
simulation, because it requires resonance already near-maximum on the exact
turn a kill lands — worth recording precisely because it is rare enough to
hide.

### The shop

`data/items.json` holds one item today: the Tempering Draught, 20 coin, usable
in battle. A `Shopkeeper` object type (`data/maps/*.json` → `"type": "shop"`,
a `catalog` of item ids) opens a buy menu; `Inventory` (a new autoload,
alongside `Content` and `Party`) tracks coin and owned items.

**There is currently no way to earn coin.** Battles pay creature experience,
not currency. The player is seeded with 60 coin and one free Draught (so the
very first bracken encounter is attunable without a shop trip first — the shop
is for restocking, not gatekeeping), and that is the entire economy for now.
Building out income (a coin reward on defeating a wild creature outright, sold
items, quest rewards) is explicitly future work, not solved here — adding it
later does not touch anything built in this section, since `Inventory` already
owns the coin balance as its own concern.

---

## 14. Save/load, implemented

Section 5 locked the format before any code existed: versioned JSON in
`user://`, hand-editable, with a migration boundary. This is what shipped.

**File:** `user://savegame.json` — one save slot, no multiple files or save
selection. A single Godot project's `user://` resolves to a real,
platform-specific folder named after `config/name` (`Hollowmere`); the file
can be opened in a text editor like any other JSON in this project.

**Shape:**

```json
{
  "save_version": 1,
  "party": { "members": [ /* Creature.to_dict() rows */ ] },
  "inventory": { "coin": 60, "items": { "tempering_draught": 1 } },
  "world": { "map_id": "hollow_clearing", "position": [120.5, 84.0] }
}
```

`Party` and `Inventory` serialise themselves — `SaveGame` calls into them
rather than reaching into their internals, the same separation of concerns
as everywhere else in the data layer. `SaveGame` owns only the file, the
version number, and world placement, since no other system has a natural
claim to "where is the player standing."

**Position is stored exactly, not snapped to a tile** — free movement means
the player's true position is already fractional, and rounding it on save
would be a small, pointless lie. The cost is that a save can point at a
position that is no longer valid if the map changes shape later (a wall gets
added where a save was standing). Rather than trust the save blindly, the
overworld checks `GameMap.is_walkable()` on the stored position before using
it, and falls back to the map's normal spawn point if the check fails, or if
the save names a different map than the one currently loaded (multi-map
loading does not exist yet — `map_id` is recorded now specifically so this
already works once it does, rather than being a field added later).

**No save/load menu exists.** Given no title screen or pause menu exists yet
either, building one just for this would be scope creep on top of scope
creep. Instead, saving is automatic, at three points:

1. **Using a rest spring** — thematically a natural checkpoint, and already
   an existing interaction.
2. **After every battle resolves** — win, loss, capture, or either side
   fleeing. This is where the most state actually changes (HP, experience,
   levels, captured creatures, consumed items), so it is the point most
   worth not losing.
3. **On the window being closed** (`NOTIFICATION_WM_CLOSE_REQUESTED`) — quit
   always saves first.

Loading is equally automatic: if `user://savegame.json` exists when the
overworld starts, it is loaded in place of the seeded starting party.
`Party` and `Inventory` each already seed sensible defaults when empty (the
starting pair of creatures, the starting purse) — a save simply overwrites
that default via the normal `from_dict` path, rather than needing an
explicit "is this a new game" branch.

**Migration.** `_migrate()` exists and is called on every load, but there is
nothing to migrate yet at version 1 — it is scaffolding, not aspiration.
Per the rule in § 5, `save_version` bumps only when a field is removed or
its meaning changes; the first real bump gets one `if version < N:` block
added to this function, and old saves keep loading through it.

**What this does not cover.** There is one save slot, no manual save, and no
way to start a fresh game without deleting the file by hand (`SaveGame.
erase()` exists for this but nothing calls it yet — no menu exists to call
it from). All three are UI gaps, not data-format gaps; the save file itself
does not need to change shape to support any of them later.

---

## Open questions

- Party size beyond the current cap of six, and whether there is storage.
- A prompt for choosing which move to forget at level up.
- Whether losing should cost anything at all.
- What ends a battle in which both sides have exhausted every move.
- Whether critical hits exist at all, given how much the design leans on
  readable, near-deterministic combat.
- Whether Attunement is available against tamer-owned creatures, or wild only.
- How the player earns coin (see § 13) -- the economy is currently one
  starting purse and nothing else.
- Whether the item catalog grows (healing items, held items) or the shop
  stays this narrow.
- Levelling: experience curve, or milestone-based growth.
- Whether moves are learned by level, by taught item, or by Temperament.
- Whether interactables should be solid by default, or whether some
  (ground items, plaques) should be walkable and probed anyway.
- A title screen and pause menu -- there is currently no UI shell at all,
  which is also what stands between the save system and a manual save, a
  "new game" option, or multiple save slots (see § 14).
