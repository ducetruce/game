class_name SpeciesData
extends RefCounted
## One creature species, loaded from data/creatures.json.
##
## Holds base stats, not actual stats. Actual stats are derived per level by
## compute_stat, so a species entry never has to change when levelling is
## retuned.

const MAX_LEVEL := 50

## Physical moves use attack vs defense; spirit moves use spirit vs resolve.
## Keeping offence and defence separate on both sides is what lets a creature be
## a spirit attacker with a glass jaw, or a wall that cannot hit back.
## See docs/DESIGN.md § 9.
const STATS := ["hp", "attack", "defense", "spirit", "resolve", "speed"]

## Linear growth from level 1 to MAX_LEVEL. The flat terms keep level 1 from
## being degenerate; the scales set how much of a stat is earned by levelling
## rather than granted by the species.
const HP_SCALE := 2.0
const HP_FLAT := 10
const STAT_SCALE := 1.5
const STAT_FLAT := 5

var id := ""
var display_name := ""
var types := PackedStringArray()
var temperament := "feral"
var attunement_rate := 1.0
var base_stats := {}
var learnset: Array[Dictionary] = []
var description := ""


static func from_dict(data: Dictionary, source: String) -> SpeciesData:
	var species_id := str(data.get("id", ""))
	if species_id.is_empty():
		push_error("%s: a creature is missing its 'id'." % source)
		return null

	for key in ["name", "types", "temperament", "base_stats", "learnset"]:
		if not data.has(key):
			push_error("%s: creature '%s' is missing '%s'." % [source, species_id, key])
			return null

	var species := SpeciesData.new()
	species.id = species_id
	species.display_name = str(data["name"])
	species.temperament = str(data["temperament"])
	species.attunement_rate = float(data.get("attunement_rate", 1.0))
	species.description = str(data.get("description", ""))

	for entry in data["types"]:
		species.types.append(str(entry))
	if species.types.is_empty():
		push_error("%s: creature '%s' has no types." % [source, species_id])
		return null

	for stat in STATS:
		if not data["base_stats"].has(stat):
			push_error("%s: creature '%s' has no base '%s'." % [source, species_id, stat])
			return null
		species.base_stats[stat] = int(data["base_stats"][stat])

	for entry in data["learnset"]:
		if not (entry is Dictionary) or not entry.has("level") or not entry.has("move"):
			push_error("%s: creature '%s' has a malformed learnset entry." % [source, species_id])
			return null
		species.learnset.append({
			"level": int(entry["level"]),
			"move": str(entry["move"]),
		})

	return species


## Actual value of one stat at a given level.
static func compute_stat(stat_name: String, base: int, level: int) -> int:
	var effective := clampi(level, 1, MAX_LEVEL)
	var growth := float(base) * float(effective) / float(MAX_LEVEL)
	if stat_name == "hp":
		return int(floorf(growth * HP_SCALE)) + effective + HP_FLAT
	return int(floorf(growth * STAT_SCALE)) + STAT_FLAT


func stat_at(stat_name: String, level: int) -> int:
	return compute_stat(stat_name, int(base_stats.get(stat_name, 0)), level)


## Every move this species knows by a given level, oldest first.
func moves_known_at(level: int) -> PackedStringArray:
	var known := PackedStringArray()
	for entry in learnset:
		if int(entry["level"]) <= level and not known.has(str(entry["move"])):
			known.append(str(entry["move"]))
	return known


## Moves learned exactly on this level, for the "learned a new move" prompt.
func moves_learned_at(level: int) -> PackedStringArray:
	var learned := PackedStringArray()
	for entry in learnset:
		if int(entry["level"]) == level:
			learned.append(str(entry["move"]))
	return learned
