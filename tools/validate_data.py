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
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

MAX_LEVEL = 50
STATS = ("hp", "attack", "defense", "spirit", "resolve", "speed")
CATEGORIES = ("physical", "spirit", "status")
TEMPERAMENTS = ("skittish", "proud", "feral")
EFFECT_KINDS = ("stat_stage", "heal")

# Mirrors src/overworld/tile_legend.gd. Duplicated on purpose: the point of
# this check is to catch the two drifting apart.
WALKABLE_TILES = set("GgPpb")
SOLID_TILES = set("WRTF")
OBJECT_TYPES = ("sign", "spring", "shop")

ITEM_EFFECT_KINDS = ("restrain_hit",)
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


def check_maps(types: list[str], creatures: dict, items: dict) -> int:
    """Validates every map in data/maps/. Returns how many were checked."""
    maps_dir = os.path.join(DATA, "maps")
    if not os.path.isdir(maps_dir):
        return 0

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

        for i, spec in enumerate(doc.get("objects", [])):
            label = "objects[%d]" % i
            if not isinstance(spec, dict):
                err(where, "%s must be an object" % label)
                continue
            if spec.get("type") not in OBJECT_TYPES:
                err(where, "%s has unknown type '%s'" % (label, spec.get("type")))
            walkable_at(spec.get("tile"), label + ".tile")
            if spec.get("type") == "shop":
                catalog = spec.get("catalog")
                if not isinstance(catalog, list) or not catalog:
                    err(where, "%s needs a non-empty 'catalog'" % label)
                else:
                    for item_id in catalog:
                        if item_id not in items:
                            err(where, "%s catalog names unknown item '%s'" % (label, item_id))

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

        # A map whose walkable tiles are all encounter terrain has nowhere safe
        # to stand, which is almost always a mistake rather than a design.
        walkable_seen = seen & WALKABLE_TILES
        if walkable_seen and walkable_seen <= set(encounters.keys()):
            warn(where, "every walkable tile on this map triggers encounters")

    return checked


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

    map_count = check_maps(types, creatures, items)

    for line in warnings:
        print("warning  %s" % line)
    for line in errors:
        print("ERROR    %s" % line)

    print("\n%d types, %d moves, %d creatures, %d item(s), %d map(s) -- %d error(s), %d warning(s)"
          % (len(types), len(moves), len(creatures), len(items), map_count, len(errors), len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
