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
STATS = ("hp", "attack", "defense", "spirit", "speed")
CATEGORIES = ("physical", "spirit", "status")
TEMPERAMENTS = ("skittish", "proud", "feral")
EFFECT_KINDS = ("stat_stage", "heal")

errors: list[str] = []
warnings: list[str] = []


def err(where: str, msg: str) -> None:
    errors.append("%s: %s" % (where, msg))


def warn(where: str, msg: str) -> None:
    warnings.append("%s: %s" % (where, msg))


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


def main() -> int:
    types = check_type_chart(load("type_chart.json"))
    moves = check_moves(load("moves.json"), types)
    creatures = check_creatures(load("creatures.json"), types, moves)

    # Content coverage: not wrong, but worth knowing about.
    for t in types:
        if not any(t in c.get("types", []) for c in creatures.values()):
            warn("creatures.json", "no creature has type '%s'" % t)
        if not any(m.get("type") == t for m in moves.values()):
            warn("moves.json", "no move has type '%s'" % t)

    for line in warnings:
        print("warning  %s" % line)
    for line in errors:
        print("ERROR    %s" % line)

    print("\n%d types, %d moves, %d creatures -- %d error(s), %d warning(s)"
          % (len(types), len(moves), len(creatures), len(errors), len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
