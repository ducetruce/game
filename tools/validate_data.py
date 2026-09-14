#!/usr/bin/env python3
"""Validate the JSON content in data/ against the rules in docs/DESIGN.md.

Godot fails loudly on malformed content at load, but only for the file it
happens to touch, and only once the game is running. This checks everything up
front and cross-references it, so a typo in a learnset is caught before it
turns into an empty move slot mid-battle.

    python3 tools/validate_data.py

Exits non-zero on any error. Warnings do not fail the run.
"""

from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
SRC = os.path.join(ROOT, "src")

MAX_LEVEL = 50
STATS = ("hp", "attack", "defense", "spirit", "resolve", "speed")
CATEGORIES = ("physical", "spirit", "status")
TEMPERAMENTS = ("skittish", "proud", "feral")
EFFECT_KINDS = ("stat_stage", "heal")

# Mirrors src/overworld/tile_legend.gd. Duplicated on purpose: the point of
# this check is to catch the two drifting apart.
WALKABLE_TILES = set("GgPpbcr")
SOLID_TILES = set("WRTFHV")
OBJECT_TYPES = ("sign", "spring", "shop", "npc", "shrine", "warp")

# Mirrors ItemData.EFFECT_KINDS, which is what BattleState._do_item can
# actually apply. Duplicated on purpose, same as the tile legend: the point is
# to catch the two drifting apart.
ITEM_EFFECT_KINDS = ("restrain_hit", "heal", "revive", "restore_uses")
TEMPERAMENT_NAMES = ("skittish", "proud", "feral")
# Mirrors the flavor_state values BattleState._tick_reactive_resonance /
# _tick_feral_resonance actually look up -- a state missing here fails
# silently in-game (no flavor line), so it is checked explicitly rather
# than just requiring the "flavor" dict to be non-empty.
REQUIRED_FLAVOR_STATES = {
    "skittish": ("gain", "reset", "stalled"),
    "proud": ("gain", "penalty_still", "penalty_disrespect", "stalled"),
    "feral": ("gain", "healed", "stalled"),
}

errors: list[str] = []
warnings: list[str] = []


def err(where: str, msg: str) -> None:
    errors.append("%s: %s" % (where, msg))


def warn(where: str, msg: str) -> None:
    warnings.append("%s: %s" % (where, msg))


def check_items(types_unused=None) -> dict:
    doc = load("items.json")
    if doc is None:
        return {}
    entries = require(doc, "items", list, "items.json")
    if entries is None:
        return {}

    by_id = {}
    for i, item in enumerate(entries):
        where = "items.json[%d]" % i
        if not isinstance(item, dict):
            err(where, "entry must be an object")
            continue
        item_id = item.get("id")
        if not item_id:
            err(where, "missing 'id'")
            continue
        where = "items.json '%s'" % item_id
        if item_id in by_id:
            err(where, "duplicate item id")
        by_id[item_id] = item

        for key in ("name", "price", "effect"):
            if key not in item:
                err(where, "missing required key '%s'" % key)
        price = item.get("price")
        if not isinstance(price, int) or price <= 0:
            err(where, "price must be a positive integer, got %r" % price)

        effect = item.get("effect")
        if not isinstance(effect, dict):
            err(where, "'effect' must be an object")
        elif effect.get("kind") not in ITEM_EFFECT_KINDS:
            err(where, "effect kind '%s' is not one of %s"
                % (effect.get("kind"), ", ".join(ITEM_EFFECT_KINDS)))
        elif effect["kind"] == "restrain_hit":
            ratio = effect.get("cap_ratio")
            if not isinstance(ratio, (int, float)) or not (0.0 < ratio <= 1.0):
                err(where, "cap_ratio must be a number in (0, 1], got %r" % ratio)
            if not item.get("usable_in_battle"):
                warn(where, "restrain_hit only means anything in a battle, but"
                     " this item is not usable_in_battle")
        elif effect["kind"] in ("heal", "revive"):
            pct = effect.get("percent")
            if not isinstance(pct, int) or not (1 <= pct <= 100):
                err(where, "%s 'percent' must be an integer 1-100, got %r"
                    % (effect["kind"], pct))
            # A revive has nothing to do mid-fight: a fainted creature is not
            # the active one, and reviving to dodge a loss is exactly what the
            # defeat penalty exists to charge for. See DESIGN.md section 23.
            if effect["kind"] == "revive" and item.get("usable_in_battle"):
                err(where, "a revive must not be usable_in_battle")
        elif effect["kind"] == "restore_uses":
            uses = effect.get("uses")
            if not isinstance(uses, int) or uses <= 0:
                err(where, "restore_uses 'uses' must be a positive integer,"
                    " got %r" % uses)
    return by_id


def check_temperaments(creatures: dict) -> dict:
    doc = load("temperaments.json")
    if doc is None:
        return {}
    threshold = doc.get("capture_threshold")
    if not isinstance(threshold, int) or not (1 <= threshold <= 1000):
        err("temperaments.json", "capture_threshold must be a positive integer, got %r" % threshold)
    stall = doc.get("stall_flee_turns")
    if not isinstance(stall, int) or stall <= 0:
        err("temperaments.json", "stall_flee_turns must be a positive integer, got %r" % stall)

    rules = require(doc, "temperaments", dict, "temperaments.json")
    if rules is None:
        return {}
    for name in TEMPERAMENT_NAMES:
        if name not in rules:
            err("temperaments.json", "missing rules for temperament '%s'" % name)
            continue
        where = "temperaments.json '%s'" % name
        entry = rules[name]
        flavor = entry.get("flavor", {})
        if not isinstance(flavor, dict) or not flavor:
            err(where, "missing 'flavor' lines")
        else:
            for state in REQUIRED_FLAVOR_STATES.get(name, ()):
                lines = flavor.get(state)
                if not isinstance(lines, list) or not lines:
                    err(where, "flavor state '%s' is required and must be a non-empty list" % state)
    for name in rules:
        if name not in TEMPERAMENT_NAMES:
            warn("temperaments.json", "'%s' is not a known temperament" % name)

    for species_id, species in creatures.items():
        t = species.get("temperament")
        if t and t not in rules:
            err("creatures.json '%s'" % species_id,
                "temperament '%s' has no rules in temperaments.json" % t)
    return rules


def load(name: str):
    path = os.path.join(DATA, name)
    if not os.path.exists(path):
        err(name, "file is missing")
        return None
    try:
        with open(path) as fh:
            return json.load(fh)
    except json.JSONDecodeError as exc:
        err(name, "invalid JSON: %s" % exc)
        return None


def require(doc: dict, key: str, want_type, where: str):
    if key not in doc:
        err(where, "missing required key '%s'" % key)
        return None
    if not isinstance(doc[key], want_type):
        err(where, "'%s' must be %s, got %s" % (key, want_type.__name__, type(doc[key]).__name__))
        return None
    return doc[key]


# --- type chart ------------------------------------------------------------

def check_type_chart(doc) -> list[str]:
    """Returns the list of valid type names, for the other checks to use."""
    if doc is None:
        return []
    ring = require(doc, "ring", list, "type_chart.json")
    mult = require(doc, "multipliers", dict, "type_chart.json")
    if ring is None or mult is None:
        return []

    types = [str(t) for t in ring]
    if len(set(types)) != len(types):
        err("type_chart.json", "'ring' contains duplicates")

    for atk, row in mult.items():
        if atk not in types:
            err("type_chart.json", "unknown attacking type '%s'" % atk)
            continue
        for dfn, value in row.items():
            if dfn not in types:
                err("type_chart.json", "%s -> unknown defending type '%s'" % (atk, dfn))
            elif value not in (0.5, 2.0):
                err("type_chart.json", "%s -> %s is %s; only 2.0 and 0.5 may be "
                    "listed (1.0 is implied by omission, and there are no "
                    "immunities)" % (atk, dfn, value))

    # The design guarantees every type has exactly two strengths and two
    # weaknesses. If that stops holding, some type has quietly become dominant.
    for t in types:
        strong = [d for d, v in mult.get(t, {}).items() if v == 2.0]
        weak = [a for a in types if mult.get(a, {}).get(t) == 2.0]
        if len(strong) != 2:
            err("type_chart.json", "%s is x2 against %d types, expected 2 (%s)"
                % (t, len(strong), ", ".join(strong) or "none"))
        if len(weak) != 2:
            err("type_chart.json", "%s is weak to %d types, expected 2 (%s)"
                % (t, len(weak), ", ".join(weak) or "none"))

    # x2 one way must mean x0.5 the other, or matchups stop being readable.
    for atk in types:
        for dfn, value in mult.get(atk, {}).items():
            if dfn not in types:
                continue
            back = mult.get(dfn, {}).get(atk)
            want = 0.5 if value == 2.0 else 2.0
            if back != want:
                err("type_chart.json", "%s is x%s against %s, so %s should be "
                    "x%s against %s, but it is x%s"
                    % (atk, value, dfn, dfn, want, atk, back))

    return types


# --- moves -----------------------------------------------------------------

def check_moves(doc, types: list[str]) -> dict:
    if doc is None:
        return {}
    entries = require(doc, "moves", list, "moves.json")
    if entries is None:
        return {}

    by_id = {}
    for i, move in enumerate(entries):
        where = "moves.json[%d]" % i
        if not isinstance(move, dict):
            err(where, "entry must be an object")
            continue
        move_id = move.get("id")
        if not move_id:
            err(where, "missing 'id'")
            continue
        where = "moves.json '%s'" % move_id
        if move_id in by_id:
            err(where, "duplicate move id")
        by_id[move_id] = move

        for key in ("name", "type", "category", "power", "accuracy", "uses"):
            if key not in move:
                err(where, "missing required key '%s'" % key)

        category = move.get("category")
        if category not in CATEGORIES:
            err(where, "category '%s' is not one of %s" % (category, ", ".join(CATEGORIES)))

        move_type = move.get("type")
        if move_type != "none" and move_type not in types:
            err(where, "unknown type '%s'" % move_type)
        if move_type == "none" and category != "status":
            err(where, "only status moves may have type 'none'; this one is %s" % category)

        power = move.get("power", 0)
        if category == "status":
            if power != 0:
                err(where, "status moves must have power 0, got %s" % power)
            if "effect" not in move:
                warn(where, "status move has no 'effect'; it will do nothing")
        elif not isinstance(power, int) or power <= 0:
            err(where, "damaging moves need a positive integer power, got %r" % power)

        accuracy = move.get("accuracy")
        if not isinstance(accuracy, int) or not (1 <= accuracy <= 100):
            err(where, "accuracy must be an integer 1-100, got %r" % accuracy)

        uses = move.get("uses")
        if not isinstance(uses, int) or uses <= 0:
            err(where, "uses must be a positive integer, got %r" % uses)

        effect = move.get("effect")
        if effect is not None:
            if not isinstance(effect, dict):
                err(where, "'effect' must be an object")
            elif effect.get("kind") not in EFFECT_KINDS:
                err(where, "effect kind '%s' is not one of %s"
                    % (effect.get("kind"), ", ".join(EFFECT_KINDS)))
            elif effect["kind"] == "stat_stage":
                if effect.get("stat") not in STATS:
                    err(where, "effect stat '%s' is not a real stat" % effect.get("stat"))
                if not isinstance(effect.get("stages"), int) or effect.get("stages") == 0:
                    err(where, "effect 'stages' must be a non-zero integer")
            elif effect["kind"] == "heal":
                pct = effect.get("percent")
                if not isinstance(pct, int) or not (1 <= pct <= 100):
                    err(where, "heal 'percent' must be an integer 1-100, got %r" % pct)

    return by_id


# --- creatures -------------------------------------------------------------

def check_creatures(doc, types: list[str], moves: dict) -> dict:
    if doc is None:
        return {}
    entries = require(doc, "creatures", list, "creatures.json")
    if entries is None:
        return {}

    by_id = {}
    for i, species in enumerate(entries):
        where = "creatures.json[%d]" % i
        if not isinstance(species, dict):
            err(where, "entry must be an object")
            continue
        species_id = species.get("id")
        if not species_id:
            err(where, "missing 'id'")
            continue
        where = "creatures.json '%s'" % species_id
        if species_id in by_id:
            err(where, "duplicate species id")
        by_id[species_id] = species

        if not species.get("name"):
            err(where, "missing 'name'")

        species_types = species.get("types")
        if not isinstance(species_types, list) or not species_types:
            err(where, "'types' must be a non-empty array")
        else:
            if len(species_types) > 2:
                err(where, "a creature may have at most 2 types, got %d" % len(species_types))
            if len(set(species_types)) != len(species_types):
                err(where, "'types' contains the same type twice")
            for t in species_types:
                if t not in types:
                    err(where, "unknown type '%s'" % t)

        temperament = species.get("temperament")
        if temperament not in TEMPERAMENTS:
            err(where, "temperament '%s' is not one of %s"
                % (temperament, ", ".join(TEMPERAMENTS)))

        rate = species.get("attunement_rate", 1.0)
        if not isinstance(rate, (int, float)) or not (0.1 <= rate <= 3.0):
            err(where, "attunement_rate must be a number 0.1-3.0, got %r" % rate)

        base = species.get("base_stats")
        if not isinstance(base, dict):
            err(where, "'base_stats' must be an object")
        else:
            for stat in STATS:
                if stat not in base:
                    err(where, "base_stats is missing '%s'" % stat)
                elif not isinstance(base[stat], int) or not (1 <= base[stat] <= 200):
                    err(where, "base_stats.%s must be an integer 1-200, got %r"
                        % (stat, base[stat]))
            for stat in base:
                if stat not in STATS:
                    err(where, "base_stats has unknown stat '%s'" % stat)

        learnset = species.get("learnset")
        if not isinstance(learnset, list) or not learnset:
            err(where, "'learnset' must be a non-empty array")
            continue

        seen_moves = set()
        last_level = 0
        starts_at_one = False
        for entry in learnset:
            if not isinstance(entry, dict):
                err(where, "learnset entries must be objects")
                continue
            level = entry.get("level")
            move_id = entry.get("move")
            if not isinstance(level, int) or not (1 <= level <= MAX_LEVEL):
                err(where, "learnset level must be an integer 1-%d, got %r" % (MAX_LEVEL, level))
            else:
                if level == 1:
                    starts_at_one = True
                if level < last_level:
                    warn(where, "learnset is not sorted by level (%s at %d follows %d)"
                         % (move_id, level, last_level))
                last_level = max(last_level, level)
            if move_id not in moves:
                err(where, "learnset references unknown move '%s'" % move_id)
            elif move_id in seen_moves:
                err(where, "learns '%s' more than once" % move_id)
            else:
                seen_moves.add(move_id)

        if not starts_at_one:
            err(where, "has no level-1 move, so it would enter battle with an empty move list")

    return by_id


def reachable_from(rows: list, start_x: int, start_y: int) -> set:
    """Every walkable tile the player can actually get to, four-directionally.

    Props are ignored: they are single tiles and a solid one never seals a
    route the terrain left open.
    """
    if not (0 <= start_y < len(rows) and 0 <= start_x < len(rows[start_y])):
        return set()
    seen = {(start_x, start_y)}
    queue = [(start_x, start_y)]
    while queue:
        x, y = queue.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if (nx, ny) in seen:
                continue
            if not (0 <= ny < len(rows) and 0 <= nx < len(rows[ny])):
                continue
            if rows[ny][nx] not in WALKABLE_TILES:
                continue
            seen.add((nx, ny))
            queue.append((nx, ny))
    return seen


def encounters_declared(doc: dict) -> bool:
    table = doc.get("encounters")
    return isinstance(table, dict) and bool(table)


def check_maps(types: list[str], creatures: dict, items: dict,
               sold: set, encountered: set, quests: dict,
               staged: dict, completers: dict) -> int:
    """Validates every map in data/maps/. Returns how many were checked.

    Fills `sold` with every item id any shop stocks and `encountered` with
    every species id any encounter table names, for check_obtainable, and
    `staged` with {quest id: set of steps} some map can actually move the
    player on to, and `completers` with the map that finishes each quest.
    """
    maps_dir = os.path.join(DATA, "maps")
    if not os.path.isdir(maps_dir):
        return 0

    # Warps name other maps, which may not have been parsed yet if the
    # target sorts later than the source (e.g. hollow_clearing -> village_
    # square). So parsing and cross-map warp validation are separate passes:
    # this dict is filled in the first and read in the second.
    parsed: dict[str, dict] = {}

    checked = 0
    for filename in sorted(os.listdir(maps_dir)):
        if not filename.endswith(".json"):
            continue
        checked += 1
        where = "maps/" + filename
        try:
            with open(os.path.join(maps_dir, filename)) as fh:
                doc = json.load(fh)
        except json.JSONDecodeError as exc:
            err(where, "invalid JSON: %s" % exc)
            continue

        rows = doc.get("tiles")
        if not isinstance(rows, list) or not rows:
            err(where, "'tiles' must be a non-empty array of row strings")
            continue

        map_id = str(doc.get("id") or filename[: -len(".json")])
        parsed[map_id] = {"where": where, "doc": doc, "rows": rows}

        width = len(rows[0])
        known = WALKABLE_TILES | SOLID_TILES
        seen = set()
        for y, row in enumerate(rows):
            if len(row) != width:
                err(where, "row %d is %d wide, expected %d" % (y, len(row), width))
            for x, symbol in enumerate(row):
                seen.add(symbol)
                if symbol not in known:
                    err(where, "unknown tile symbol '%s' at (%d, %d)" % (symbol, x, y))

        def walkable_at(tile, label):
            if (not isinstance(tile, list) or len(tile) < 2
                    or not all(isinstance(v, int) for v in tile[:2])):
                err(where, "%s must be an [x, y] pair of integers" % label)
                return
            x, y = tile[0], tile[1]
            if not (0 <= y < len(rows) and 0 <= x < len(rows[y])):
                err(where, "%s at (%d, %d) is outside the map" % (label, x, y))
                return
            if rows[y][x] not in WALKABLE_TILES:
                err(where, "%s at (%d, %d) sits on solid tile '%s'"
                    % (label, x, y, rows[y][x]))

        walkable_at(doc.get("player_start"), "player_start")

        arrival_quest = doc.get("arrival_quest")
        arrival_step = doc.get("arrival_step")
        if (arrival_quest is None) != (arrival_step is None):
            err(where, "arrival_quest and arrival_step go together; only one"
                " of them is set")
        elif arrival_quest is not None:
            if arrival_quest not in quests:
                err(where, "arrival_quest '%s' is not a quest in quests.json"
                    % arrival_quest)
            elif arrival_step not in quests[arrival_quest]:
                err(where, "arrival_step '%s' is not a step of quest '%s'"
                    % (arrival_step, arrival_quest))
            else:
                staged.setdefault(arrival_quest, set()).add(arrival_step)

        # Coin bracket. Absent means "this area pays nothing", which is right
        # for somewhere with no encounters, so only a malformed one is an error.
        bracket = doc.get("coin_reward")
        if bracket is not None:
            if (not isinstance(bracket, list) or len(bracket) != 2
                    or not all(isinstance(v, int) for v in bracket)):
                err(where, "coin_reward must be [low, high] integers, got %r" % (bracket,))
            elif not (0 <= bracket[0] <= bracket[1]):
                err(where, "coin_reward %r must satisfy 0 <= low <= high" % (bracket,))
        elif encounters_declared(doc):
            warn(where, "has encounters but no coin_reward, so its battles pay nothing")

        for i, spec in enumerate(doc.get("objects", [])):
            label = "objects[%d]" % i
            if not isinstance(spec, dict):
                err(where, "%s must be an object" % label)
                continue
            if spec.get("type") not in OBJECT_TYPES:
                err(where, "%s has unknown type '%s'" % (label, spec.get("type")))
            obj_type = spec.get("type")
            # A warp fires just by the player standing on its tile (unlike
            # every other object type, which spawns a solid body there), so
            # its tile must be walkable ground or the warp can never fire.
            walkable_at(spec.get("tile"), label + ".tile")
            if obj_type == "shop":
                catalog = spec.get("catalog")
                if not isinstance(catalog, list) or not catalog:
                    err(where, "%s needs a non-empty 'catalog'" % label)
                else:
                    for item_id in catalog:
                        sold.add(item_id)
                        if item_id not in items:
                            err(where, "%s catalog names unknown item '%s'" % (label, item_id))
            quest_id = spec.get("quest")
            quest_steps = quests.get(quest_id, []) if quest_id else []
            needs_quest = any(key in spec for key in
                              ("quest_text", "sets_step", "completes_quest"))
            if needs_quest and not quest_id:
                err(where, "%s uses quest keys but names no 'quest'" % label)
            elif quest_id is not None and quest_id not in quests:
                err(where, "%s names unknown quest '%s'" % (label, quest_id))

            for j, variant in enumerate(spec.get("quest_text", [])):
                variant_label = "%s.quest_text[%d]" % (label, j)
                if not isinstance(variant, dict):
                    err(where, "%s must be an object" % variant_label)
                    continue
                if variant.get("from") not in quest_steps:
                    err(where, "%s 'from' is '%s', which is not a step of quest"
                        " '%s'" % (variant_label, variant.get("from"), quest_id))
                lines = variant.get("text")
                if not isinstance(lines, list) or not lines:
                    err(where, "%s needs a non-empty 'text'" % variant_label)

            sets_step = spec.get("sets_step")
            if sets_step is not None:
                if sets_step not in quest_steps:
                    err(where, "%s sets_step '%s' is not a step of quest '%s'"
                        % (label, sets_step, quest_id))
                else:
                    staged.setdefault(quest_id, set()).add(sets_step)

            if spec.get("completes_quest"):
                if quest_id in quests:
                    if quest_id in completers:
                        warn(where, "%s also completes quest '%s', which"
                             " %s already does" % (label, quest_id,
                                                   completers[quest_id]))
                    completers.setdefault(quest_id, where)

            wants = spec.get("requires")
            if wants is not None:
                if not isinstance(wants, dict):
                    err(where, "%s 'requires' must be an object" % label)
                else:
                    kind = wants.get("kind")
                    if kind == "has_item":
                        if wants.get("item") not in items:
                            err(where, "%s requires unknown item '%s'"
                                % (label, wants.get("item")))
                    elif kind == "defeated":
                        if wants.get("species") not in creatures:
                            err(where, "%s requires defeating unknown species"
                                " '%s'" % (label, wants.get("species")))
                    else:
                        err(where, "%s requirement kind '%s' is not one of"
                            " has_item, defeated" % (label, kind))
                    if not wants.get("text"):
                        err(where, "%s 'requires' needs a 'text' to say what is"
                            " missing; without it the object refuses silently"
                            % label)

            solid = spec.get("solid")
            if solid is not None and not isinstance(solid, bool):
                err(where, "%s 'solid' must be true or false, got %r" % (label, solid))
            if obj_type == "warp" and solid is not None:
                warn(where, "%s sets 'solid', which a warp has no body to apply it to"
                     % label)

            if obj_type == "npc":
                tint = spec.get("tint")
                if tint is not None and (
                    not isinstance(tint, list) or len(tint) != 3
                    or not all(isinstance(v, (int, float)) for v in tint)
                ):
                    err(where, "%s tint must be a [r, g, b] array of numbers" % label)
            elif obj_type == "warp":
                if not spec.get("target_map"):
                    err(where, "%s needs a 'target_map'" % label)
                if (not isinstance(spec.get("target_tile"), list)
                        or len(spec.get("target_tile", [])) < 2):
                    err(where, "%s target_tile must be an [x, y] pair" % label)

        encounters = doc.get("encounters", {})
        if not isinstance(encounters, dict):
            err(where, "'encounters' must be an object keyed by tile symbol")
            encounters = {}
        for symbol, config in encounters.items():
            label = "encounters['%s']" % symbol
            if symbol not in WALKABLE_TILES:
                err(where, "%s is keyed on '%s', which is not walkable terrain"
                    % (label, symbol))
            elif symbol not in seen:
                warn(where, "%s has a table but no '%s' tile appears on the map"
                     % (label, symbol))
            chance = config.get("chance", 0)
            if not isinstance(chance, (int, float)) or not (0.0 < chance <= 1.0):
                err(where, "%s chance must be a number in (0, 1], got %r" % (label, chance))
            table = config.get("table")
            if not isinstance(table, list) or not table:
                err(where, "%s needs a non-empty 'table'" % label)
                continue
            for j, entry in enumerate(table):
                row_label = "%s.table[%d]" % (label, j)
                if not isinstance(entry, dict):
                    err(where, "%s must be an object" % row_label)
                    continue
                encountered.add(entry.get("species"))
                if entry.get("species") not in creatures:
                    err(where, "%s names unknown species '%s'"
                        % (row_label, entry.get("species")))
                weight = entry.get("weight")
                if not isinstance(weight, int) or weight <= 0:
                    err(where, "%s weight must be a positive integer, got %r"
                        % (row_label, weight))
                levels = entry.get("levels")
                if (not isinstance(levels, list) or len(levels) != 2
                        or not all(isinstance(v, int) for v in levels)):
                    err(where, "%s levels must be [low, high] integers" % row_label)
                elif not (1 <= levels[0] <= levels[1] <= MAX_LEVEL):
                    err(where, "%s levels %r must satisfy 1 <= low <= high <= %d"
                        % (row_label, levels, MAX_LEVEL))

        # Encounter terrain you cannot walk to is an area with nothing in it.
        # Cheap to get wrong when a map is authored as text, and invisible
        # until someone walks the whole shore looking for a fight.
        start = doc.get("player_start")
        if encounters and isinstance(start, list) and len(start) >= 2:
            reached = reachable_from(rows, start[0], start[1])
            for symbol in encounters:
                if symbol in seen and not any(
                        rows[y][x] == symbol for x, y in reached):
                    err(where, "encounters['%s'] is on tiles the player cannot"
                        " reach from player_start" % symbol)

        # A map whose walkable tiles are all encounter terrain has nowhere safe
        # to stand, which is almost always a mistake rather than a design.
        walkable_seen = seen & WALKABLE_TILES
        if walkable_seen and walkable_seen <= set(encounters.keys()):
            warn(where, "every walkable tile on this map triggers encounters")

    # Second pass: warps name another map by id and a tile within it. Both
    # can only be checked now that every map file has been parsed.
    for map_id, info in parsed.items():
        where = info["where"]
        for i, spec in enumerate(info["doc"].get("objects", [])):
            if not isinstance(spec, dict) or spec.get("type") != "warp":
                continue
            label = "objects[%d]" % i
            target_id = spec.get("target_map")
            if not target_id:
                continue  # already reported above
            target = parsed.get(str(target_id))
            if target is None:
                err(where, "%s target_map '%s' does not exist" % (label, target_id))
                continue
            tile = spec.get("target_tile")
            if not isinstance(tile, list) or len(tile) < 2:
                continue  # already reported above
            x, y = tile[0], tile[1]
            target_rows = target["rows"]
            if not (isinstance(x, int) and isinstance(y, int)
                    and 0 <= y < len(target_rows) and 0 <= x < len(target_rows[y])):
                err(where, "%s target_tile (%r, %r) is outside map '%s'"
                    % (label, x, y, target_id))
            elif target_rows[y][x] not in WALKABLE_TILES:
                err(where, "%s target_tile (%d, %d) sits on solid tile '%s' in map '%s'"
                    % (label, x, y, target_rows[y][x], target_id))

    return checked


# --- obtainability ---------------------------------------------------------
#
# Twice now a piece of content has existed, validated cleanly, and been
# impossible to get hold of: the Cairnling had stats and a learnset but
# appeared in no encounter table, and the Waking Root had a price and an
# effect but was stocked by no shop. Neither is a schema error -- every field
# was correct -- so nothing caught them until somebody went looking for the
# thing and could not find it.
#
# The two ways in are a map's data (encounter tables, shop catalogs) and the
# new-game seed, which lives in GDScript rather than JSON. Rather than restate
# the seed here and let the copy rot, these read it out of the source. If the
# seeding moves somewhere else the scrape returns nothing and the check
# reports every species and item as unobtainable, which is wrong but loud --
# the failure mode worth having.

SEED_PARTY_FILE = os.path.join(SRC, "data", "party.gd")
SEED_ITEM_FILE = os.path.join(SRC, "data", "inventory.gd")


def _seed_function_body(path: str) -> str:
    """The body of reset_for_new_game() in a GDScript file, or ''."""
    try:
        with open(path) as fh:
            text = fh.read()
    except OSError:
        return ""
    match = re.search(r"^func reset_for_new_game\(.*?$", text, re.M)
    if match is None:
        return ""
    lines = text[match.end():].splitlines()
    body = []
    for line in lines:
        # The body ends at the first line that starts a new top-level
        # declaration -- anything unindented and not blank.
        if line.strip() and not line.startswith(("\t", " ")):
            break
        body.append(line)
    return "\n".join(body)


def seed_species() -> set:
    body = _seed_function_body(SEED_PARTY_FILE)
    return set(re.findall(r'Creature\.create\(\s*"([^"]+)"', body))


def seed_items() -> set:
    body = _seed_function_body(SEED_ITEM_FILE)
    return set(re.findall(r'\badd\(\s*"([^"]+)"', body))


def check_quests() -> dict:
    """Returns {quest_id: [step ids in order]} for the map checks to use."""
    doc = load("quests.json")
    if doc is None:
        return {}
    entries = require(doc, "quests", list, "quests.json")
    if entries is None:
        return {}

    requirement = doc.get("gauntlet_requirement")
    if not isinstance(requirement, int) or requirement <= 0:
        err("quests.json", "gauntlet_requirement must be a positive integer,"
            " got %r" % requirement)
    elif requirement > len(entries):
        # Not an error while the game is being built out -- the whole point of
        # the number is that quests are still being written toward it -- but
        # worth saying out loud, because until it is met the endgame cannot be
        # reached at all.
        warn("quests.json", "gauntlet_requirement is %d but only %d quest(s)"
             " exist, so the gauntlet cannot yet be unlocked"
             % (requirement, len(entries)))
    if not doc.get("default_objective"):
        err("quests.json", "needs a 'default_objective' to show when no quest"
            " is telling the player what to do")

    quests: dict = {}
    areas: dict = {}
    for i, quest in enumerate(entries):
        where = "quests.json[%d]" % i
        if not isinstance(quest, dict):
            err(where, "entry must be an object")
            continue
        quest_id = quest.get("id")
        if not quest_id or not isinstance(quest_id, str):
            err(where, "missing 'id'")
            continue
        where = "quests.json '%s'" % quest_id
        if quest_id in quests:
            err(where, "duplicate quest id")

        for key in ("name", "area", "summary"):
            if not quest.get(key):
                err(where, "missing '%s'" % key)
        # One quest per area is the shape the endgame counts in: ten quests in
        # ten areas. Two quests in one area and one area with none would still
        # total ten and would not be that.
        area = quest.get("area")
        if area:
            if area in areas:
                err(where, "area '%s' already has the quest '%s'; the gauntlet"
                    " counts quests in distinct areas" % (area, areas[area]))
            areas[area] = quest_id

        steps = quest.get("steps")
        if not isinstance(steps, list) or not steps:
            err(where, "needs a non-empty 'steps' array")
            quests[quest_id] = []
            continue

        ids: list[str] = []
        for j, step in enumerate(steps):
            step_where = "%s step[%d]" % (where, j)
            if not isinstance(step, dict):
                err(step_where, "must be an object")
                continue
            step_id = step.get("id")
            if not step_id or not isinstance(step_id, str):
                err(step_where, "missing 'id'")
                continue
            if step_id in ids:
                err(step_where, "duplicate step id '%s'" % step_id)
            ids.append(step_id)
            if not step.get("objective"):
                err("%s step '%s'" % (where, step_id),
                    "needs a non-empty 'objective'; it is what the pause menu"
                    " shows while the player is on this step")
        quests[quest_id] = ids

        reward = quest.get("reward", {})
        if not isinstance(reward, dict):
            err(where, "'reward' must be an object")
        else:
            coin = reward.get("coin", 0)
            if not isinstance(coin, int) or coin < 0:
                err(where, "reward coin must be a non-negative integer, got %r" % coin)
    return quests


def check_quests_reachable(quests: dict, quest_areas: dict, staged: dict) -> None:
    """Every step and every quest has to be reachable from somewhere.

    The same failure as an unobtainable creature, one level up: a step can be
    written, referenced by an NPC's dialogue, and have nothing anywhere in the
    world that advances the player to it -- at which point that dialogue is
    unreachable and the quest stops at the step before it. A quest with no
    completer never counts toward the gauntlet however many times it is
    finished in spirit.
    """
    for quest_id, steps in quests.items():
        reached = staged.get(quest_id, set())
        for step_id in steps:
            if step_id not in reached:
                err("quests.json '%s'" % quest_id,
                    "nothing advances the player to step '%s' (no object's"
                    " 'sets_step' and no map's 'arrival_step' names it), so the"
                    " quest cannot get past the step before it" % step_id)
        if quest_id not in quest_areas:
            err("quests.json '%s'" % quest_id,
                "no object anywhere sets 'completes_quest' for it, so it can"
                " never be finished and never counts toward the gauntlet")


def check_obtainable(creatures: dict, items: dict, sold: set, encountered: set) -> None:
    starters = seed_species()
    if not starters:
        err("src/data/party.gd", "could not read the starting party out of"
            " reset_for_new_game(); the obtainability check below is"
            " meaningless until this parses again")
    granted = seed_items()
    if not granted:
        err("src/data/inventory.gd", "could not read the starting items out of"
            " reset_for_new_game(); the obtainability check below is"
            " meaningless until this parses again")

    for species_id in starters:
        if species_id not in creatures:
            err("src/data/party.gd", "the starting party contains '%s', which"
                " is not a species in creatures.json" % species_id)
    for item_id in granted:
        if item_id not in items:
            err("src/data/inventory.gd", "a new game grants '%s', which is not"
                " an item in items.json" % item_id)

    for species_id in sorted(creatures):
        if species_id in starters or species_id in encountered:
            continue
        err("creatures.json '%s'" % species_id,
            "appears in no encounter table on any map and is not in the"
            " starting party, so there is no way to obtain it")

    for item_id in sorted(items):
        if item_id in granted or item_id in sold:
            continue
        err("items.json '%s'" % item_id,
            "is stocked by no shop on any map and is not granted at the start,"
            " so there is no way to obtain it")


def main() -> int:
    types = check_type_chart(load("type_chart.json"))
    moves = check_moves(load("moves.json"), types)
    creatures = check_creatures(load("creatures.json"), types, moves)
    items = check_items()
    check_temperaments(creatures)

    # Content coverage: not wrong, but worth knowing about.
    for t in types:
        if not any(t in c.get("types", []) for c in creatures.values()):
            warn("creatures.json", "no creature has type '%s'" % t)
        if not any(m.get("type") == t for m in moves.values()):
            warn("moves.json", "no move has type '%s'" % t)

    quests = check_quests()

    sold: set = set()
    encountered: set = set()
    staged: dict = {}
    completers: dict = {}
    map_count = check_maps(types, creatures, items, sold, encountered,
                           quests, staged, completers)
    check_obtainable(creatures, items, sold, encountered)
    check_quests_reachable(quests, completers, staged)

    for line in warnings:
        print("warning  %s" % line)
    for line in errors:
        print("ERROR    %s" % line)

    print("\n%d types, %d moves, %d creatures, %d item(s), %d map(s), "
          "%d quest(s) -- %d error(s), %d warning(s)"
          % (len(types), len(moves), len(creatures), len(items), map_count,
             len(quests), len(errors), len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
