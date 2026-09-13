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

## 15. The party screen, and a recurring bug class worth naming

The first real playtest (§ 13–14 were both verified by proxy before this;
this was the first time a human actually played) found the overworld had
zero visibility into the party outside of battle — no nicknames, HP, levels,
or moves. `PartyMenu` (`M` / `Tab` to open) is a **read-only viewer**, on
purpose: no reordering, no releasing, no forgetting moves. Those all need
their own confirmation flows and a reason to exist first; building them
speculatively now would be guessing at UI nobody has asked for yet.

**The same debounce bug showed up twice in one playtest, in two different
places, and is worth naming as a class rather than two unrelated fixes.**
Closing the signpost's dialogue is itself an "interact" press; with nothing
to distinguish "the press that just closed this" from "a fresh press that
should open something new," standing in the interaction zone made every
subsequent interact — including ones mashed to skip text — immediately
reopen it. Building `PartyMenu` reproduced the identical shape: closing it
via the same `menu` key that opens it, with nothing to suppress the next
press, meant mashing `menu` never actually closed it.

**The rule, now applied in both places and worth keeping in mind for any
future menu:** whenever a menu can be opened and closed by the *same
action*, or opening one action can be triggered by standing somewhere the
closing action of another leaves you, closing it must arm a brief lock
(`Player.lock_interact()`, `Overworld._menu_lock`) before that action is
live again. A single-frame guard is not enough — real button-mashing is
fast enough to land a new press before the very next physics tick; both
locks hold for 0.3s, long enough to swallow mashing, short enough that a
deliberate press right after still works normally. `Overworld._on_ui_closed()`
is the one place every menu's closing already flows through, so both locks
are armed there unconditionally rather than tracked per menu.

---

## 16. World: connected region, implemented

§ 3 committed to one continuous world, scene-per-map, joined by warp nodes at
the edges. This is that seam actually built, plus the second map: a village
north of the Hollow Clearing, reached through a gap carved in its tree
border.

**Warps are data, not nodes.** A map's JSON gains a `warp` object type --
`{"type": "warp", "tile": [x, y], "target_map": "...", "target_tile": [x, y]}`
-- registered by `GameMap` into a plain `Vector2i -> {target_map, target_tile}`
dictionary (`_warps`) rather than spawning a scene node. Every other object
type (`sign`, `spring`, `shop`, and the new `npc`) exists in the world as a
body the player can bump into and read; a warp is not a thing to look at, it
is a location that fires when walked onto, so `GameMap.warp_at(world_position)`
is a lookup alongside `terrain_at()`, sharing the same tile-quantising helper
(`_tile_at`). `Overworld._physics_process` checks it right after updating
`_last_position`, the same place it already checks encounter terrain.

**The map a player is standing on is no longer fixed at scene-tree
authoring time.** `Overworld` used to hold `@onready var _map: GameMap =
$Map`, a direct child instanced once in `overworld.tscn`. That cannot survive
a second map, so `overworld.tscn` now holds an empty `MapContainer` node
instead, and `Overworld._load_map(map_id, target)` frees whatever is
currently loaded, instantiates `res://scenes/overworld/maps/<map_id>.tscn`
under it, reconnects the three signals every map exposes
(`dialogue_requested`, `shop_requested`, `checkpoint_reached` -- Godot
disconnects a freed node's own signals automatically, so there is nothing to
unhook first), and places the player. `target` is deliberately loose --
`null`, a `Vector2i` tile (what a warp gives), or a `Vector2` world position
(what a restored save gives) -- and falls back to the new map's own
`player_spawn_position()` whenever the given target does not land on
walkable ground, exactly as `is_walkable` already guarded a restored save
against a map that changed shape (§ 14). `_ready()` now resolves `map_id`
from the save (or the `hollow_clearing` default) *before* the first
`_load_map` call, rather than validating a save's `map_id` against an
already-fixed single map -- the thing that made a "which map has multiple
maps" restructure necessary in the first place.

**A warp transition reuses the battle transition's shape**, not just its
`_fade_to` helper: set `_busy`, disable input, fade to black, do the actual
work, fade back in, re-enable input -- and like a battle finishing, it calls
`_tracker.start_grace()` (so the very first tile on the new map cannot roll
an encounter before the player has taken a step) and `_autosave()` (so a
crash right after arriving does not roll the player back to the map they
just left). The two warp tiles for the Hollow Clearing <-> village gap are
registered as a pair (`[20, y]` and `[21, y]` on each side) rather than one,
because the gap carved in the tree border is two tiles wide and a player
walking through the untested column would otherwise just stand in the
opening -- caught by extending `tools/validate_data.py` (below), not by
playtesting.

**Two new tile symbols, `H` (wall) and `V` (roof), compose vertically into
one building.** They are two ordinary solid tiles in the tileset -- nothing
enforces the pairing at the data level -- but by convention a `V` row sits
directly above the matching `H` row, so a two-tile-tall facade reads as one
structure despite being two independent grid cells. There is no interior;
these are props, the same as a `T` or `F`, until there is a reason to open a
door. A third symbol, `c` (plaza), is ordinary walkable ground with its own
flagstone art -- it exists because "a village has grass right up to the
building walls" reads wrong, not because it behaves differently from `G`.

**A fourth object type, `npc`, is conversation with no other behaviour.**
`Villager` (`src/overworld/villager.gd`) is `SignPost` in every structural
way that matters -- a `StaticBody2D` in the `interactable` group, placeholder
art drawn in `_draw()`, a `read_requested` signal wired to the same
`dialogue_requested` path -- but is kept as its own scene/script rather than
reusing `SignPost` directly, because a sign reads as a prop and a villager
reads as a person, and that distinction is likely to matter once NPCs need
anything a signpost never will (schedules, quest state, a name in a text
box). The one thing `Villager` has that `SignPost` does not is `tint`, a
`Color` multiplied into its cloak so several villagers on one map do not all
look identical without needing separate sprites yet.

**`tools/validate_data.py` now validates warps across map files, not just
within one.** Every other object type is checked against data that lives in
the same file (a shop's catalog against `items.json`, a tile position against
that map's own grid); a warp's `target_map` and `target_tile` name a
*different* file, one that may not have been parsed yet if it sorts later
alphabetically than the map naming it (`hollow_clearing.json` is checked
before `village_square.json` exists to check against). `check_maps` is now
two passes: the first parses every map file and validates everything
self-contained, keeping each parsed document around; the second walks every
warp and checks its `target_map` exists and its `target_tile` lands on
walkable ground in *that* map's grid, only possible once every file has been
read.

**Verification, and the bug only walking found.** The first check moved the
player onto each warp tile by assigning `global_position`, and it passed
both ways. Then the same trip was driven with actual held key input --
walking the path north from the real spawn point and back -- and the return
leg landed the player 7.4px off the tile the warp named, permanently, every
time.

The cause: `_load_map` freed the outgoing map with `queue_free()`, which
does not take effect until the end of the frame. So when the player was
placed on the incoming map, the *outgoing* map's collision was still live in
the physics space at the same world coordinates, and `move_and_slide()`
depenetrated them out of it. Arriving back in the Hollow Clearing at tile
`(20, 1)` put the player inside the village's solid tree border, which
occupies those exact coordinates on the map being torn down. The northbound
leg looked fine only by luck: the Hollow Clearing happens to have walkable
path at the village's arrival coordinates, so there was nothing to push
against. The fix is one line -- `_map_container.remove_child(_map)` before
the `queue_free()`, so the old collision leaves the physics space
immediately and deletion stays deferred and safe.

**Worth generalising: a teleport is not a walk.** Assigning
`global_position` skips everything the physics body does on arrival, which
is exactly where this bug lived. This is the same lesson as the black-screen
incident and the interact-mash bug (§ 15) in a third costume -- verifying
the mechanism rather than the experience keeps producing checks that pass
over real defects. Warp travel is now checked by holding a movement key and
letting the player's own controller do the walking, over two full round
trips, asserting the exact landing tile each way and that map instances do
not accumulate in the container.

Cross-map save/restore is checked the same way, against real save files: a
save naming the village boots into the village at the saved position, and a
save naming a map that no longer exists falls back to the Hollow Clearing
with an error rather than a black screen. A position saved on top of a prop
(the well) restores and is then nudged clear by physics, which is the right
outcome -- `is_walkable()` reads the tile grid, not spawned bodies, and does
not need to.

The village map itself was screenshotted through a real `Camera2D` under
Xvfb + llvmpipe: grass border, both building facades, the flagstone plaza,
the three villagers, and the well all render as designed.

---

## 17. The title screen, and what "new game" has to undo

The game booted straight into the overworld and silently resumed whatever
save it found. That made starting over a matter of deleting
`user://savegame.json` by hand, which is not something a player should ever
be asked to do -- and it also meant the fresh-start experience could not be
tested without leaving the game.

`scenes/ui/title_screen.tscn` is now the project's main scene, and the
overworld is entered from it with `change_scene_to_file`. The shell is
deliberately three lines long: **Continue** (offered only when a save
actually exists), **New Game**, **Quit**.

**A new game has to undo more than the save file.** `SaveGame.erase()`
deletes the file, but `Party` and `Inventory` are autoloads -- they outlive
the scene change into the overworld, and they seed their defaults in
`_ready()`, which runs once per process and never again. So a New Game
started *after playing* would have kept the previous run's creatures and
coin while claiming to be new: the file would be gone, the state would not.
Both now expose `reset_for_new_game()`, which the title screen calls
alongside the erase. Their `_ready()` calls the same function rather than
duplicating the starting loadout, so "what a new game starts with" has one
definition, and running `overworld.tscn` directly from the editor still
lands in a playable game.

**Confirmation, but only when there is something to lose.** Choosing New
Game with a save present asks first, and the cursor starts on *Keep my
game* -- the answer that changes nothing. A destructive action should never
be one keypress away from someone mashing through a menu, which is the same
concern as the interact/menu debounce locks in § 15, arrived at from the
other direction. With no save present there is nothing to destroy and the
prompt is skipped entirely.

**One bug worth recording, because it generalises to any menu that changes
scenes.** The first version marked the input handled *after* acting on it,
the way every other menu in the project does. On the option that enters the
overworld that pushed an error every time: `change_scene_to_file` takes this
node out of the tree, so by the time the handler got to
`get_viewport().set_input_as_handled()` the viewport was null. The fix is to
decide whether the event belongs to this screen, consume it, and only then
act -- `_handles()` then `_act_on()`. Any menu whose actions can tear down
its own scene needs that ordering.

**Deliberately not built yet.** There is no quit-to-title from inside the
overworld (that belongs to a pause menu, which still does not exist), and
Continue does not describe the save it would resume -- no map name, party, or
playtime. Showing that needs `SaveGame` to be able to read a save *without*
applying it, which is a real API addition and not worth making until there
is more than one slot to tell apart.

---

## 18. The pause menu

`X` / `Esc` in the overworld opens **Resume / Party / Save / Quit to Title**.
That completes the shell the title screen (§ 17) started: there is now a way
out of a run that is not closing the window, and a manual save that does not
depend on walking to a spring.

**Save reports the truth.** `SaveGame.save()` returned `void`, so a manual
save had no way to know whether it worked and would have claimed success
even when the file could not be opened. It now returns a bool, the Overworld
passes that back with `report_saved()`, and the menu says "Saved." or "Could
not save." Autosaves still ignore the result -- there is nobody to tell.

**Quit to Title saves on the way out**, matching what closing the window
already did. Leaving through a menu should not be the one exit that costs
progress, and there is no prompt to go with it because there is nothing to
warn about.

**The party screen nests, which needed the Overworld to hold the seam.**
Opening the party screen from the pause menu and closing it returns to the
pause menu, not to the world. The pause menu hides itself *without* emitting
`closed` when it hands over, because `closed` is what gives input back to the
player -- emitting it would drop control into the world for the frame between
the two menus. The Overworld tracks `_party_from_pause` and routes the party
screen's close either back to the pause menu or to the usual
`_on_ui_closed()`. If the party screen refuses to open, the pause menu is put
back rather than leaving the player with no menu and no input, which is the
one failure here that would be a genuine soft-lock.

`M` / `Tab` still opens the party screen directly, since it was already built
and the shortcut is worth keeping.

**No new debounce machinery was needed**, which is the useful part. The
pause menu opens and closes on the same `cancel` action -- exactly the shape
that bit twice in § 15 -- but `Overworld._on_ui_closed()` already arms
`_menu_lock` for every menu that closes, and gating the pause key on that
same lock was the whole fix. Verified by mashing `X` twelve times in a frame
and confirming it settles closed.

---

## 19. The economy loop

Coin existed, a shop existed, and there was no way to earn a single piece:
the player got one starting purse and that was the whole economy (§ 13 left
this open deliberately). Aldenmere (§ 16) had the matching problem from the
other side -- a village with nothing to do in it.

> **Superseded in part by § 20.** The `4 + 3 × level` formula below lasted
> one playtest and is gone: coin is now a bracket declared by the area and
> rolled uniformly, independent of the creature. Everything else here — that
> encounters pay at all, and that taming pays the same as killing — stands.

**Encounters pay, and taming pays the same as killing.** `coin_award()` was
`4 + 3 × the foe's level`, granted on `WON` and on `ATTUNED` alike. Paying
only for knockouts is the traditional choice and it was rejected here: the
entire design points at Attunement, and an economy that quietly made taming
the poorer option would be arguing with the rest of the game. It is also the
wrong tone for a world whose own signposts say *they do not hunt you, they
are only curious*.

Unlike `experience_award()`, coin deliberately ignores the species' base
stats and scales on level alone. Experience already carries "that one was
worth more"; coin is read against a price tag, and a number the player can
predict is worth more than a number that is precisely fair. The clearing's
levels 3-7 pay 13-25 a fight against 16-20 coin items -- roughly an item per
win, which is generous, and is two constants to turn once there is
playtesting to turn them by.

**A second effect kind, and Aldenmere's reason to exist.** Items now support
`heal` alongside `restrain_hit`, mirroring the `percent`-of-max-HP shape
moves already used rather than inventing a flat-amount variant. The village
sells the **Knitbone Salve** (50%, 16 coin) and the clearing does not, so the
walk north buys something the walk east cannot. Rest springs are still free
and still the only full-party heal; the salve is what you carry *into* a
fight, which is where the gap actually was.

Healing applies to whoever is out, not a creature of the player's choosing --
picking a target needs a selection step the battle UI does not have.

**Items no longer charge for doing nothing.** `_do_item` consumed the item
first and worked out whether it applied second, so a Draught used while
already Restrained was spent to print "You are already holding back." Adding
a heal would have made that much worse, since being at full HP is a state
players walk into constantly. Applicability is now decided before the charge
is spent, via `_item_refusal()`. The *turn* is still used up: that is the
price of choosing wrongly, and unwinding it would mean reaching into the turn
machine for a case the player can simply avoid.

**The purse is visible outside a shop.** A shop counter was the only place
coin was ever displayed, which was tolerable when the number never changed
and absurd once battles move it. The pause menu (§ 18) shows it.

---

## 20. The standing questions, answered

All twelve open questions were decided in one pass. They are recorded here
before most of them are built, because several constrain each other: a
revive only became acceptable once losing started costing something, and
per-area coin only makes sense once coin stopped scaling off the creature.
Where an answer needed a number that was not given, the number chosen is
called out as mine rather than smuggled in as if it were decided.

**Coin belongs to the area, not the creature.** § 19's `4 + 3 x level` is
withdrawn. Each map declares a bracket in its own JSON and every resolved
encounter there pays a uniform roll inside it, so what an hour in a place is
worth is a property of the place. This also means the number stops leaking
information about the creature you just met -- a heavy payout no longer
quietly tells you it was a rare one. Still paid on a knockout and an
attunement alike (§ 19). *Mine:* the Hollow Clearing pays 10-18, against
16-20 coin items.

**Losing costs 5-10% of the purse**, rolled per loss, and nothing else --
creatures are still restored and the player is still put back on the path.
Money is the right thing to lose because it is the only resource the player
is accumulating; taking creatures or progress would punish the part of the
game we want people doing. A player with nothing loses nothing, which is
correct: the floor should not be a wall.

**The item catalog grows**, revives included. The objection to a revive was
that it softened the only consequence of losing; losing now has a
consequence a revive cannot undo, so the objection is spent.

**Critical hits exist.** *Mine:* an uncommon roll at a modest multiplier
rather than a rare roll at a big one, because the design leans on readable
combat and a 2x spike makes a fight unplannable. The interaction that
matters is with the Tempering Draught: a crit must respect the restrain cap,
or the one item whose entire job is preventing an accidental kill would have
a hole in it exactly when it matters most.

**Battles with no moves left resolve by Struggle**, adopted from Pokémon: a
typeless attack that cannot miss and hurts the user too. It is the rule that
makes "both sides out of moves" terminate without a draw state, and the
recoil is what stops it being a free infinite move.

**Attunement stays wild-only.** Nobody else owns creatures yet; when tamers
exist, taking one out from under its owner is a different mechanic with
different consent, not a reuse of this one.

**Experience curve, and moves learned by level.** Both confirm what is
already built (§ 10) -- recorded so they stop reading as undecided.

**Level-up asks which move to forget.** Today a full move list announces the
new move and skips it, which silently costs the player the thing they just
earned.

**Storage exists, on the Pokémon model:** party of six, everything else into
boxes, accessible somewhere fixed rather than anywhere.

**Save slots: one slot, plus a peek.** *Mine, asked for.* Slots exist to let
one person keep parallel playthroughs, and nothing in the game yet gives a
reason to branch; the cost is a slot-select step on both saving and loading
plus per-slot files. What is worth taking now is the other half -- a
`SaveGame` read that does not apply, so Continue can say which map and what
party it would resume. That is the part with a use today, and it is also the
API multiple slots would need first, so nothing is wasted if slots arrive
later.

**Interactable solidity is per-interactable**, declared by the object rather
than assumed by the type, defaulting to solid. A ground item or a floor
plaque should be walkable and still probeable; a person should not be.

---

## 21. Critical hits and Struggle

Two of § 20's answers, built together because both live in the turn loop.

**Crits are 1.5x at a 1-in-16 roll**, and they are rolled by the caller, not
inside `Damage.compute()` -- the same split `variance` already used, so a
preview or a test can ask for either outcome deliberately instead of hoping
for one. The multiplier is applied *before* the floor rather than to the
floored result, which is the less lossy order and means a crit can land one
point above `floor(normal x 1.5)`.

**A crit cannot punch through the Tempering Draught.** The restrain cap is
applied in `_do_move` after `Damage.compute` returns, so it clamps a crit
exactly as it clamps anything else. This is the interaction worth stating
outright: the Draught's entire job is preventing an accidental kill, and a
hole in it on the single biggest roll -- the one most likely to kill the
creature you were three turns into reading -- would make it untrustworthy
precisely when it matters. Verified by swinging an over-levelled attacker at
a level 5 wild creature 400 times: every hit landed, none exceeded the cap,
and it never died.

**Struggle is code, not content.** Nothing learns, teaches or sells it, no
learnset may name it, and `MoveData.from_dict()` quite rightly refuses a
damaging move with no type -- which is exactly what Struggle has to be, so it
can neither take STAB nor be resisted. Putting it in `moves.json` would have
meant an exemption there *and* in the validator for one reserved id, so it is
built by `MoveData.struggle()` instead.

It surfaces in two places and needed no UI work for either. `move_options()`
returns Struggle as an ordinary single row when nothing has uses left, so the
battle menu never learns it exists; and the foe AI reaches for it instead of
the `Still` it used to fall back on, which was the actual stalemate -- two
creatures with nothing left standing at each other forever.

**The recoil is a quarter of the user's own max HP, not of the damage
dealt.** Struggle exists to end a fight nobody can win, and a cost measured
against the target's remaining health would shrink exactly when the fight
most needs ending. Against your own maximum it caps the stalemate at four
turns; in practice a stripped-bare pair resolves in three.

**A note on the test that nearly lied.** The first version of the crit-cap
check picked `moves[0]` to swing with. At level 40 that creature's four-move
list has dropped its attack for later-learned utility, so `moves[0]` was
`Howl` -- a buff. The test measured zero damage 300 times and passed. It now
picks the first *damaging* move and asserts the hits actually land before
asserting they are capped. A test that can pass while doing nothing is worse
than no test, because it reports safety it never checked.

---

## 22. Choosing what to forget

A creature that levelled into a fifth move used to be told "could learn X,
but has no room" and the move was gone. That silently costs the player the
thing they just earned, which is the one outcome nobody wants.

**The rule stays in `BattleState`, the asking stays in the battle screen.**
`_learn_new_moves` now parks the move on `pending_learns` instead of dropping
it, and `resolve_pending_learn(forget_index)` performs the swap or the
decline and returns the lines to show. The state machine never blocks on a
player, which is what keeps `scenes/debug/battle_sim.tscn` able to run four
hundred battles with no UI in sight -- the simulator simply never drains the
queue.

**It is offered before the outcome screen**, not after, so a move earned by
the winning blow still gets asked about rather than vanishing with the
battle. `_after_messages()` is the seam: it already ran between every burst
of log lines and whatever came next.

**Two steps, not one, and the second reason is the load-bearing one.** The
prompt asks "make room for it?" and only then lists the four moves. Partly
because five rows do not fit the 46px menu panel -- the first build cut the
last row clean off, and it was the row the cursor defaulted to, so nothing
appeared selected at all. But mostly because a one-step list puts the cursor
on a real move, and this prompt appears in the middle of a run of messages
the player is mashing Z through. That is § 15's hazard again, and the answer
is the same shape as the title screen's: make the mashed outcome the
harmless one. The question defaults to *Keep the four I have*.

**Backing out is an answer, not an escape.** `X` on the list goes back to the
question; `X` on the question declines. Neither drops to the action menu,
which would strand an unanswered prompt in a battle that may already be
over.

Declining is currently permanent -- there is no relearning later. That is
listed below rather than solved here.

---

## 23. The bag, and why the revive is not a battle item

§ 20 said the catalog grows and unblocked the revive. Building it turned up a
hole underneath: **every item in the game was unreachable outside a fight**.
There was no bag. That was survivable while both items were battle items, and
it is not survivable for a revive, because a fainted creature is never the
active one -- there was nowhere for the effect to point.

**The revive is deliberately `usable_in_battle: false`,** and the validator
now rejects one that is not. I had written in § 20 that losing having a cost
spent the objection to revives; working it through, that was too quick. A
revive used mid-fight does not soften the defeat penalty, it *prevents the
defeat*, so the 5-10% is never charged at all. Out of battle it is what it
should be: a convenience that saves a walk back to a spring, bought with coin
the player earned, after the loss has already been paid for.

**So the bag exists**, opened from the pause menu: pick an item, then pick who
it goes on. It offers only what can do something out here -- a Tempering
Draught is real and owned and simply not listed, because its effect is a
statement about an ongoing battle. The party list is shown whole with
inapplicable rows greyed rather than filtered out, since a list that changes
shape depending on the item is harder to read than one that is always the
same list.

**Refusals come before the charge is spent**, the same rule as § 19's: using
a revive on someone standing, or a salve on someone fainted or unhurt, says
so and costs nothing. That rule has now been worth applying three times, and
is the sort of thing worth doing by default rather than per item.

**The pause menu grew a row and needed a taller panel** -- five entries in a
box sized for four, which is the second time in two sections that a menu
outgrew its panel. Worth checking the geometry whenever a row is added; the
symptom is invisible in code and obvious in a screenshot.

---

## 24. Storage, and the shrine that holds it

§ 20 said storage exists on the Pokemon model. It is reached at a **standing
stone in Aldenmere** and nowhere else -- not the pause menu.

**Somewhere, not anywhere.** Having to walk back is the whole point: it makes
the six you are carrying a commitment rather than a loadout re-picked before
every fight, and it gives the village a second reason to exist beyond the
salve stall (§ 19). It also makes a full party a real decision out in the
field rather than a menu away from being undone.

**A flat list, not numbered boxes.** Boxes are Pokemon's answer to a thousand
species and a 1996 memory budget. The function they serve -- somewhere to put
what the party cannot hold -- is a list, and the shrine's window scrolls
rather than paging by hand. Partitioning can be added later without changing
what is stored or how it is saved.

**The one rule worth enforcing is that you cannot leave with nothing.**
Depositing your last creature is refused; everything else is allowed,
including walking out with a party that is entirely fainted, which the
overworld already handles by refusing to start an encounter. Rules that guard
against states the game already handles are just places for the two to
disagree later.

**Storage fixed a creature being destroyed.** Attuning with a full party used
to say "there is no room to carry it yet, and it slips away regardless" --
the player did everything right and lost the creature. It now goes to the
shrine. That was listed as an open question and is answered by the feature
that made it answerable.

**The save gained a `storage` block with no version bump**, per § 5's rule:
an added field with a safe default does not need one. A save written before
the shrine existed simply has no block, which reads as empty storage, which
is exactly right.

**Two things bit, both familiar.** The enum quirk from § 21 returned in a new
costume: an enum named `Side` in the storage menu collided with
`BattleState.Side`, and GDScript then refused to assign the script's own enum
to a variable annotated with it. Renamed to `Pane` and left inferred. And the
refusal messages all rendered in the success colour, because one `_notice`
string carried both -- a footer that looks like confirmation whatever it says
is worse than no footer.

---

## 25. Solidity per object, and reading a save without opening it

The last two of § 20's answers, unrelated to each other except in size.

**Solidity is declared, not assumed.** An object spec may carry
`"solid": false`; everything defaults to solid. The mechanism is two physics
layers rather than a flag anyone checks at runtime: solid props sit on layer
1, which the player's *body* masks, and walkable ones sit on layer 3, which
only the *interaction probe* masks. So a walkable prop is still found by a
probe that reaches for it and simply is not there as far as movement is
concerned -- no branch, no special case in the controller.

Aldenmere's plaza gained a floor plaque to exercise it, since a capability
with nothing using it is a capability nobody will notice has broken.

**`SaveGame.peek()` reads a save without applying it**, and the title
screen's Continue now says which place, which lead creature and how many are
carried. Deliberately a separate function from `load_and_apply()`: describing
a save and entering it are different acts, and a screen that is only
*offering* a choice must not have already made it. The map's readable name
comes from reading that map's JSON directly -- loading a whole map scene to
pull one string out would be a great deal of machinery for a label.

This is also the API multiple save slots would need first (§ 20), so the half
that has a use today is built and the half that does not is still deferred.

**Two tests in this section were written wrong first, the same way.** The
solidity check asserted the probe's mask against a number typed into the
test rather than read from the player scene -- it would have passed with the
scene misconfigured. And the walk-over check gave the player 45 loop
iterations to cross four tiles, which in headless mode is nothing like 45
frames of walking: the player moved one tile, and "did not get past the
plaque" looked exactly like "was blocked by the plaque". With 400 iterations
the player walks 67px clean over the plaque and is stopped after 3px by a
villager. Both failures are the § 21 lesson in a new costume: a test that
cannot fail proves nothing, and headless iteration count is not time.

---

## 26. The Hollowmere, and a second coin bracket

The world is three areas now, which is the shape § 3 planned from the start:
a wooded hollow, a village, and the water the game is named after. The mere
lies **north of Aldenmere**, so the village keeps its role as the safe middle
of the map -- encounters on either side of it, none in it.

**It exists to give the economy something to compare against.** § 19's coin
brackets are a property of the area, and with one encounter area there was
only one bracket, so the idea was untestable by construction. The mere pays
**18-30** against the clearing's **10-18**, on creatures four to seven levels
higher. Whether that gradient is right is exactly the sort of thing that
needs playing rather than reasoning, and now it can be.

**A new terrain, `r` reeds**, rather than reusing bracken. A second area that
looks like the first is a worse test of anything, and encounter terrain has
to be readable at a glance without a legend (§ 6's argument for bracken being
darker and busier than grass). The reeds are bluer and taller, with standing
water showing between the stems.

**Cairnling was unobtainable.** It is one of seven creatures and appeared in
no encounter table anywhere -- not a design decision, just a gap nobody had
looked for. The mere's rocky shore is now where it lives.

**The validator gained a reachability check**, which is the durable part of
this section. Encounter terrain the player cannot walk to is an area with
nothing in it, and authoring maps as text makes that easy to get wrong and
invisible until somebody walks the whole shore looking for a fight. It flood-
fills the walkable tiles from `player_start` and fails if a declared
encounter symbol has no reachable tile. Confirmed by walling the mere's path
off and watching it fail -- a check nobody has seen fail is a check nobody
knows works.

---

## 27. Two bugs a playtest found, and what they were hiding

**Walking north bounced the player straight back.** The clearing's north warp
lands you on Aldenmere's tile `(20, 21)` -- which is Aldenmere's *own* warp
back to the clearing. The first frame of movement after arriving fired it,
which fired the other one, forever. The village was unreachable in practice,
and so was everything past it.

The fix is general rather than a map edit: `Overworld` remembers the tile a
warp put the player on and ignores warps there until they step off it. A
two-way doorway *wants* both sides' tiles in the same place, so this will
keep happening every time a map is linked, and pushing the arrival tile one
square inward each time is a rule nobody will remember.

**The round-trip test missed it because it let go of the key.** It walked
north, and the moment the map id changed it released the movement key,
waited, then deliberately pressed the other direction. A player holds the key
down. That single frame of continued input is the entire bug, and the test
stepped around it precisely. The route is now walked end to end -- clearing,
village, mere, and back -- with the key held the whole way and an assertion
that each map is still the current one several hundred frames after arrival.

**A second-order lesson: the tests were polluting each other.** Warp arrival
autosaves, so a run that reached the village left a save behind, and the next
run booted into the village instead of the clearing. The first trace of the
fix looked like a fresh bug until that was spotted. Every run now clears the
save first.

**Losing gave everything back.** `Party.restore_all()` on defeat handed back
full health *and* refilled every move, so the only cost was the 5-10% coin --
invisible unless you were watching the purse. § 20 chose that penalty on the
understanding that creatures being restored was a mercy; in play it read as
nothing having happened at all.

Creatures now stay down. The walk back is still safe by construction: an
encounter cannot start while the whole party is fainted, so a wiped player
can always reach a spring, and springs are free. Losing therefore costs coin,
the walk, and the time to patch everyone up -- none of which is a wall.

**That change needed an item nobody could buy.** The Waking Root was added in
§ 23, priced, and then sold in no shop anywhere -- the same gap cairnling had
in § 26, found the same way, by asking what actually reaches the player.
Aldenmere's stall sells it now. Worth a standing habit: anything added to
`data/` wants a matching answer to "and how does a player get it?"

---

## 28. A debug menu, and the debounce bug caught building it

Every bug found in this project has been found by playing, and playing to the
part worth testing meant walking three maps and grinding a party up first.
`F1` now opens a developer menu: jump to any map, patch the party up, force
an encounter, grant coin, items, a Lv12 creature, or three levels, over a
readout of what the overworld currently believes -- map, tile, terrain under
foot, encounter chance, the area's coin bracket, purse, party HP.

**Gated on `OS.is_debug_build()`, in two places.** The node frees itself at
`_ready` outside a debug build, and the `F1` check is gated too. Absent from
a release export rather than hidden behind an undocumented key, because an
undocumented key is one somebody finds.

**Building it reproduced § 15's debounce bug for the third time.** Closing
with `F1` emits `closed`, which hands input back in the same physics frame
the press is still "just pressed" in, so the overworld reopened it instantly
-- the menu could not be closed with the key that opened it. The two menu
keys beside it are both gated on `_menu_lock`; the new one was not, because
the rule lives in a doc rather than in the code. Worth noting that this is
now the failure mode of *writing the rule down*: § 15 predicted precisely
this and it still happened.

**Commands that take input over themselves need `dismiss()`, not close.**
Jumping maps and forcing an encounter both hide the menu without emitting
`closed`, because `closed` would hand input to the player for the frame
before the command takes it. The forced encounter hands input back explicitly
first -- `_begin_encounter` bails early when the party is empty or wiped, and
without that the player would be left frozen with the menu already gone.

**Three test-harness lessons, all the same shape as the § 25/§ 27 ones.**
Synthetic taps sent in one frame arrive in one input flush, so the first
press after opening a menu lands before it starts listening -- counted
keypresses silently drifted the cursor one row, and the test then exercised
the wrong command while looking like it exercised the right one. It now
*seeks* the cursor by command id and asserts where it actually landed. And
the menu outgrew its panel again (nine rows in a box for eight, the third
time), which no assertion caught and a screenshot showed immediately.

---

## 29. Turning the recurring bugs into machinery

Three classes of defect have now appeared three or more times each, and every
time the fix was the same: write the rule down in this document and remember
it next time. Four menus have shipped with their last row clipped off the
bottom of their panel. Two pieces of content have shipped complete, correct,
and impossible to obtain -- the Cairnling had stats, a learnset and a
temperament but appeared in no encounter table; the Waking Root had a price
and an effect but was stocked by no shop. And more than one test has passed
while stepping around the exact frame the bug lived on.

A rule in a document is a rule somebody has to remember. These are now three
checks that run without being remembered.

**`UiFit`, an autoload (`src/core/ui_fit.gd`).** Every twentieth frame it
walks the active scene, finds every visible non-scrolling `RichTextLabel`,
and compares `get_content_height()` to the box's own height. Anything showing
less than it holds is a warning naming the node path and the shortfall. It
needs no cooperation from the menus, which is the point: the failure was
never in the code a menu author reads. It is gated on `OS.is_debug_build()`
and does nothing in a release export.

It found the party screen's footer clipped by 2px within seconds of existing,
and then -- through the soak below -- the battle's own action menu, which had
been clipping its fifth row since the day the Run option was added. That is
the most-used menu in the game. Nobody had noticed.

The battle menu's fix is not just a bigger box. Its list is five rows for
actions, up to six for a full party, and as many as the item catalog ever
grows to, so any fixed box is a box that breaks on the next piece of content.
The arena moved up, the bottom panel grew from 54px to 72px, and every menu
now renders through `_set_menu`, which shows a window of five rows following
the cursor and marks the rows it is hiding -- the same treatment the storage
screen already gave its stored list (§ 24).

**Obtainability, in `tools/validate_data.py`.** Every species must appear in
some map's encounter table or in the starting party; every item must be
stocked by some shop or granted at the start. Neither of the two escapes was
a schema error -- every field was correct -- so nothing short of this would
have caught them.

The starting party and the free Draught live in GDScript, not JSON, so the
validator reads them out of `reset_for_new_game()` in `src/data/party.gd` and
`src/data/inventory.gd` by regex rather than restating them and letting the
copy rot. If that scrape ever stops matching, it reports every species and
item as unobtainable: wrong, but loud, which is the failure mode worth
having.

**A soak (`src/debug/soak.gd`, run by `tools/soak.sh`).** It plays the game
with real held key presses for as long as you ask, and asserts almost nothing
about what happens -- only that the player never loses control of the game for
longer than any screen could justify, that no engine error is printed, and
that every map gets visited. A soak that demands specific outcomes from random
input is a soak that gets loosened until it passes.

Three things about it were wrong on the first attempt, and all three are the
same mistake this document keeps recording -- a test that looks like it
exercises the game and does not:

- It counted its own loop iterations as frames. A `-s` script's `_process`
  runs as fast as the machine can loop, so "3000 frames" bought about four
  seconds of walking. It now ticks on `Engine.get_physics_frames()`, which is
  what the game itself runs on, and fast-forwards by raising the tick rate
  and time scale together -- four times the steps per second, each still a
  normal 1/60s step as far as every piece of game code is concerned.
- Its bursts were up to 40 frames, or about four tiles. A random walk in
  four-tile steps never leaves the corner it starts in: it walked 5000px
  without once reaching the bracken and reported a clean run for a game it
  had never seen fight.
- It reported only on the way out of its own loop. Random input found "quit
  to title", the title screen's Quit ended the process, and the run died
  without a word -- which looks exactly like a run that passed. Reporting now
  happens in `_finalize()`, on every exit path, and a run that ends early
  fails.

It nudges: after 45 frames with no player control it starts tapping cancel
and confirm itself, mostly confirm, because two screens that each back out
into the other would oscillate forever on a strict alternation and the
battle's Fight/move pair is exactly that shape. Without the nudge two thirds
of a run was spent sitting in a menu waiting for X to come up in the shuffle,
which bought no coverage and forced the lockout budget to be so slack that a
real lockout fitted comfortably inside it.

It also travels on purpose every 1500 frames, through the same debug command
the F1 menu uses, because random walking found a warp about as often as it
found anything else -- three seeds in a row never left the first map. It goes
somewhere it has not been yet where it can: picking uniformly at random made
"every map was visited" a coin flip rather than an assertion. The map list is
read off `scenes/overworld/maps/` rather than named in the script, so a map
added later is soaked without anyone remembering to add it, and a run too
short to have had a trip due for every map says so instead of either failing
for being short or quietly claiming a coverage it never attempted.

F1 is in the key mix, so the debug menu gets scanned like everything else.
That is how the tenth command got caught clipping off the bottom of a panel
already nearly the height of the screen -- the fifth instance of the box
problem and the first one found before it shipped. The panel could not get
taller, so the list got wider: two labels side by side rather than one, since
the placeholder font is not monospaced and a column built out of space
padding is a ragged column.


---

## 30. A reason to go, and a road to go on

Two things were missing between Aldenmere and the Hollowmere: a reason to
walk north, and something to walk through. Both were asked about and both
were answered the same way -- a story reason to reach the mere, and a route
between the two rather than a step from level 5 to level 14.

**The Fen Road** sits between them: 41x28, levels 6-10, and a coin bracket of
14-22 between the clearing's 10-18 and the mere's 18-30. The road itself goes
the long way -- south gate, west along the old drainage cut, north past the
sluice, then east and north to the shore -- and the whole middle of the fen
is one wide bracken field. Cutting straight from gate to gate is four tiles
shorter and nine tiles of bracken. That is the choice the area exists to
offer, and it is a choice rather than a wall: the road is slow and safe, the
fen is quick and expensive, and a player who wants levels knows where to get
them. There is a spring at the sluice, one step off the bracken, so grinding
the fen does not mean walking back to Aldenmere between fights.

Aldenmere now has two exits instead of one, and the mere is two warps further
out than it was.

**The story is one ordered position, not a bag of flags.** `Journal` (an
autoload, backed by `data/story.json`) holds an index into a list of stages.
Every question the game asks of the story is "has the player got at least
this far" -- which line an NPC says, what the pause menu shows as the current
objective -- and a position answers all of them without anyone reasoning about
which combinations of flags are possible. It also cannot be driven into a
state the writing does not cover, which a bag of booleans can and eventually
does.

Moving backwards is not possible: `advance_to` on an earlier stage is ignored
rather than treated as an error, because walking back into a map and
re-reading a sign is a normal thing to do and must not undo progress. Saves
record the stage by *id*, not by index, so inserting a stage in the middle
does not silently move every existing save to the wrong place in the story.

The six stages run: out of the clearing, into Aldenmere and the low well,
north up the fen road, past the warden at the sluice, onto the shore, and
then the marker at the mouth of the cut -- where the mere is not draining,
and is not rising either, and is turning slowly around something that is not
there.

**Dialogue varies by stage, and resolves when read rather than when spawned.**
An object in a map file may carry a `stage_text` array of `{from, text}`; the
entry that wins is the last one whose stage the player has reached, falling
back to the plain `text`. It is resolved in `GameMap._speech_for` at the
moment of reading, not when the map loaded its objects -- talking to one
villager can move the story on, and the villager standing next to them has to
have the newer thing to say without the map being reloaded first.

An object may also carry `sets_stage`, and a map `arrival_stage`. The latter
exists because some places *are* the beat: arriving at the mere is the point
of going there, and making the player hunt for a sign to be told so would be
a worse version of the same moment.

**The validator checks the story the same way it checks everything else.**
Every `from`, `sets_stage` and `arrival_stage` must name a real stage, and --
the check worth having -- every stage past the first must be reachable: if no
object's `sets_stage` and no map's `arrival_stage` names it, the story stops
at the stage before it and every line written for the rest is unreachable.
That is § 29's unobtainable-content bug one level up, and it would have been
just as invisible.


---

## 31. Two more items, and the gap one of them fills

§ 20 settled that the item catalog should grow. It grows by two, and one of
them exists because of a mechanic that had no answer outside a rest spring.

**The Ninebark Tonic** (30 coin, usable in a fight) is a new effect kind,
`restore_uses`: it puts five uses back into every move a creature knows, each
capped at its own maximum. Move uses were the one resource with exactly one
source of resupply -- a spring -- which was fine when a spring was four tiles
away and stopped being fine the moment the Fen Road made the trip north a
long one. Running dry mid-crossing meant Struggle (§ 21) or walking all the
way back, and neither is a decision, just a tax.

It refuses before it charges, like everything else here: a creature with
nothing spent is told so and keeps the tonic. In the bag it is deliberately
allowed on a fainted creature -- topping its moves up before reviving it is
exactly what you would want to do, and refusing would only mean using the two
in a particular order for no reason.

**The Heartwood Root** (90 coin, out of battle only) is a Waking Root that
brings one back whole rather than halfway, at more than twice the price. It
is the same effect kind, so it needed no code at all -- which is the point of
having effect kinds in data.

The road now has a pedlar by the sluice spring, since a long crossing with
nowhere to restock is a crossing you make carrying everything, and Aldenmere's
stall carries the Heartwood Root.

Two boxes had to grow to fit them, both found by `UiFit` rather than by
looking: the bag's description line clipped on the Heartwood Root's longer
description, and the bag's item list was a fixed six rows in a game whose
item catalog was just declared to be growing. The list now windows like the
battle menu and the storage screen (§ 29). That is three screens with the
same treatment, which is a sign it belongs in one place -- worth doing when
there is a fourth.


---

## 32. Three creatures, and the first dual types

The roster was one creature per type, seven single-typed, and the two new
areas were drawing on the same seven the clearing does. Three more, and all
three dual-typed, which the data model has always allowed and nothing had
used:

- **Rushwither** (bloom/wane, skittish) grows back along the fen road's dead
  channel and leans away from you at exactly the speed you approach.
- **Reedwitch** (mire/gale, feral) stands in the mere's reed beds at the
  height of the reeds and moves when they move.
- **Drownbell** (mire/wane, proud) hangs a hand's width under the surface and
  does not rise. The rarest thing at the mere, and the one that reads as
  having been there before whatever the story is about.

Dual typing means a creature can be x4 weak or x0.25 resistant, which is a
sharper edge than the chart's flat two-strengths-two-weaknesses shape (§ 5)
produces on its own. That is the point of using it sparingly: the seven
single-typed creatures remain the readable baseline, and a dual type is a
thing worth noticing rather than the norm. Base stat totals stay in the
established 320-336 band, so what differs is shape and matchup, not power.

The placeholder generator draws a dual-typed creature in its first type's
colours and grew three new silhouettes, so they do not all fall back to the
hound shape.

`UiFit` caught one more thing on the way: the codex's roster line was one row
of every creature in the game, and the tenth wrapped it onto a second row the
box had no height for. Growing the box would only have moved the problem to
the eleventh, so the line now shows a window of seven around the selection
with markers for the rest -- the fourth screen to get that treatment.

While checking them on a battle screen: every fight in the game opened with
"comes out of the bracken", including the ones on the mere's reed beds, which
have no bracken anywhere on them. The terrain symbol already reaches the
battle; it now carries its name with it (`TileLegend.terrain_name`), with a
fallback that is true of any ground, since a forced encounter can start on a
path.


---

## 33. Walking the route, and what it said about the fen road

Every area's level band was chosen by reasoning, and the open questions have
said since § 20 that the numbers want a session of play to judge. Reasoning
cannot tell you whether a party that leaves the clearing the moment it can
win there arrives at the mere able to survive it. Nothing in the game tells
you either: a player finds out by walking there and losing.

`tools/curve.sh` walks the route -- the starting party, each area's own
encounter table in map order, one creature tamed per area, a spring between
fights -- and reports how many fights each area takes before it is crossable
and what level the party leaves at. Two things about it were wrong first, and
both of them made the game look like something it is not:

**A win streak is not readiness.** The first version advanced the party once
it had won eight fights in a row from full health. A party can do that long
before it can *cross* anything, and the fen road is a crossing: it left the
clearing at level 6, left the road at 6.3, and arrived at the mere four
levels under its band -- at which point the tool reported the mere as a wall.
It was measuring its own exit criterion. An area is now crossable when the
party can sustain four fights on one rest, which is the thing the road
actually asks.

**One fight from full health is not the question either.** Winning every
fight from a spring says the matchups are survivable one at a time. The
number a player feels is how far they get before going down, so that is what
is reported: walk in rested, keep fighting, count.

What it found: the fen road was the hardest area in the game, harder than the
mere. The curve went up and then down. The road's table averaged level 8
against a party arriving at 6, while the mere's averaged 10.5 against a party
that had already ground the road to 8 and had more creatures. The road's
band is now weighted to its low end -- 5-10 rather than 6-10, averaging 7.2 --
which makes the first stretch of the crossing a step rather than a spike.
After it: 8 fights to cross the clearing, 24 to cross the road, 16 to cross
the mere, leaving at levels 6.0, 7.3 and 7.8. The road is still the biggest
grind in the game, which is right for the longest area, and it is no longer
the sharpest wall.

One incidental finding, which is about the rules rather than the tool: a
policy that switches out a creature below a third of its health does
*worse* than one that never switches at all -- 2.4 fights a rest against 4.3
on the road. A switch costs the turn and whatever comes in eats a free hit,
so switching as a rescue loses more than it saves. Switching is for a matchup
you can see coming, not for one you are already losing. That is a defensible
rule and it is left alone, but it means the battle menu's Party option is
narrower than it looks, and anything that later makes switching cheaper
should be weighed against it.


---

## Open questions

Everything below is downstream of § 20 -- numbers to feel rather than
decisions to make, plus what has not been reached yet.

- The crit rate and multiplier (1-in-16, 1.5x), the Struggle recoil fraction
  (a quarter of max HP), and the two coin brackets -- the clearing's 10-18
  and the mere's 18-30, and whether the gradient between them is right. All
  picked by reasoning and all now built (§ 19, § 21); all single constants,
  and all want a session of actual play to judge.
- Relearning a move that was declined at level-up (§ 22). Declining is
  permanent today, and there is no tutor to undo it.
- Which items the catalog grows by beyond the Waking Root (§ 23). Held items
  in particular imply an equip step that does not exist.
- Whether the bag should be reachable from the battle's Item menu too, sharing
  one list rather than two rules about what is usable where.
- Multiple save slots, deferred in § 20 rather than rejected. The reading
  half of the API now exists (§ 25).
- Whether storage should ever be partitioned into boxes, which only matters
  once anyone fills 60 slots (§ 24).
- Tamer battles, which Attunement is now explicitly not part of.
