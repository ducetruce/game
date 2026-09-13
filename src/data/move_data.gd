class_name MoveData
extends RefCounted
## One move definition, loaded from data/moves.json.

const CATEGORY_PHYSICAL := "physical"
const CATEGORY_SPIRIT := "spirit"
const CATEGORY_STATUS := "status"

const STRUGGLE_ID := "struggle"
const STRUGGLE_POWER := 50
## Struggle's cost to whoever uses it, as a share of their *own* max HP rather
## than of the damage dealt. The move exists to end a fight nobody can win, and
## a cost measured against the target's remaining health would shrink exactly
## when the fight most needs ending. A quarter caps the stalemate at four turns.
const STRUGGLE_RECOIL_RATIO := 0.25

static var _struggle: MoveData = null

var id := ""
var display_name := ""
var type := TypeChart.NO_TYPE
var category := CATEGORY_STATUS
var power := 0
var accuracy := 100
var uses := 1
var effect := {}
var description := ""


static func from_dict(data: Dictionary, source: String) -> MoveData:
	var move_id := str(data.get("id", ""))
	if move_id.is_empty():
		push_error("%s: a move is missing its 'id'." % source)
		return null

	for key in ["name", "type", "category", "power", "accuracy", "uses"]:
		if not data.has(key):
			push_error("%s: move '%s' is missing '%s'." % [source, move_id, key])
			return null

	var move := MoveData.new()
	move.id = move_id
	move.display_name = str(data["name"])
	move.type = str(data["type"])
	move.category = str(data["category"])
	move.power = int(data["power"])
	move.accuracy = int(data["accuracy"])
	move.uses = int(data["uses"])
	move.effect = data.get("effect", {})
	move.description = str(data.get("description", ""))

	if move.category not in [CATEGORY_PHYSICAL, CATEGORY_SPIRIT, CATEGORY_STATUS]:
		push_error("%s: move '%s' has unknown category '%s'." % [source, move_id, move.category])
		return null
	if move.type == TypeChart.NO_TYPE and move.category != CATEGORY_STATUS:
		push_error("%s: move '%s' deals damage, so it needs a real type." % [source, move_id])
		return null

	return move


## What a creature falls back on with nothing left to spend, so that a battle
## in which both sides are out of moves still ends (docs/DESIGN.md § 20).
##
## Built here rather than in data/moves.json because it is not content: nothing
## learns, teaches or sells it, no learnset may name it, and from_dict() quite
## rightly refuses a damaging move with no type -- which is exactly what this
## has to be, so it can neither take STAB nor be resisted. Putting it in data
## would mean an exemption here *and* in the validator, for one reserved id.
static func struggle() -> MoveData:
	if _struggle == null:
		_struggle = MoveData.new()
		_struggle.id = STRUGGLE_ID
		_struggle.display_name = "Struggle"
		_struggle.type = TypeChart.NO_TYPE
		_struggle.category = CATEGORY_PHYSICAL
		_struggle.power = STRUGGLE_POWER
		_struggle.accuracy = 100
		_struggle.uses = 1
		_struggle.description = "What is left when nothing else is. It costs you too."
	return _struggle


func is_damaging() -> bool:
	return category != CATEGORY_STATUS


## Which of the attacker's stats this move hits with, and which of the
## defender's stats resists it.
func attack_stat() -> String:
	return "attack" if category == CATEGORY_PHYSICAL else "spirit"


func defense_stat() -> String:
	return "defense" if category == CATEGORY_PHYSICAL else "resolve"
