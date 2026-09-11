class_name TypeChart
extends RefCounted
## The seven-type matchup chart, loaded from data/type_chart.json.
##
## Sparse by design: only x2 and x0.5 pairs are stored, everything else is 1.0,
## and there are no immunities. See docs/DESIGN.md § 2.

## Damaging moves must be typed; only status moves may use this.
const NO_TYPE := "none"

const NEUTRAL := 1.0

var ring := PackedStringArray()

var _multipliers := {}


## Returns null and pushes an error if the document is malformed.
static func from_dict(data: Dictionary, source: String) -> TypeChart:
	if not data.has("ring") or not (data["ring"] is Array):
		push_error("%s: missing or malformed 'ring'." % source)
		return null
	if not data.has("multipliers") or not (data["multipliers"] is Dictionary):
		push_error("%s: missing or malformed 'multipliers'." % source)
		return null

	var chart := TypeChart.new()
	for entry in data["ring"]:
		chart.ring.append(str(entry))

	for attacker in data["multipliers"]:
		var attacker_id := str(attacker)
		if not chart.has_type(attacker_id):
			push_error("%s: '%s' is not in 'ring'." % [source, attacker_id])
			return null
		var row := {}
		for defender in data["multipliers"][attacker]:
			var defender_id := str(defender)
			if not chart.has_type(defender_id):
				push_error("%s: %s lists unknown type '%s'." % [source, attacker_id, defender_id])
				return null
			row[defender_id] = float(data["multipliers"][attacker][defender])
		chart._multipliers[attacker_id] = row

	return chart


func has_type(type_id: String) -> bool:
	return ring.has(type_id)


## Combined multiplier of one attacking type against a defender's type list.
## Multiple defending types multiply together, so a dual-type creature can sit
## at x4 or x0.25 even though no single cell goes past x2.
func multiplier(attack_type: String, defender_types: PackedStringArray) -> float:
	if attack_type == NO_TYPE:
		return NEUTRAL
	var row: Dictionary = _multipliers.get(attack_type, {})
	var total := NEUTRAL
	for defender in defender_types:
		total *= float(row.get(defender, NEUTRAL))
	return total


## Every non-neutral matchup for one attacking type, as { type: multiplier }.
func matchups_for(attack_type: String) -> Dictionary:
	return _multipliers.get(attack_type, {}).duplicate()
