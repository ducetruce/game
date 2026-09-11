class_name MoveData
extends RefCounted
## One move definition, loaded from data/moves.json.

const CATEGORY_PHYSICAL := "physical"
const CATEGORY_SPIRIT := "spirit"
const CATEGORY_STATUS := "status"

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


func is_damaging() -> bool:
	return category != CATEGORY_STATUS


## Which of the attacker's stats this move hits with, and which of the
## defender's stats resists it. Spirit is both the offensive and the defensive
## stat for non-physical moves -- see docs/DESIGN.md § 9.
func attack_stat() -> String:
	return "attack" if category == CATEGORY_PHYSICAL else "spirit"


func defense_stat() -> String:
	return "defense" if category == CATEGORY_PHYSICAL else "spirit"
