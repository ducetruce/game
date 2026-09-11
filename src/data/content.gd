extends Node
## Content database. Parses data/*.json once at startup and hands out typed
## objects.
##
## Registered as the `Content` autoload. Deliberately has no class_name: an
## autoload and a global class cannot share a name in Godot.

const TYPE_CHART_PATH := "res://data/type_chart.json"
const MOVES_PATH := "res://data/moves.json"
const CREATURES_PATH := "res://data/creatures.json"

var type_chart: TypeChart = null

## False if anything failed to parse. Callers that can degrade gracefully
## should check it; everything else can rely on the pushed errors.
var loaded := false

var _moves := {}
var _species := {}
var _species_order := PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	loaded = false
	type_chart = null
	_moves.clear()
	_species.clear()
	_species_order = PackedStringArray()

	var chart_doc := _read_json(TYPE_CHART_PATH)
	if chart_doc.is_empty():
		return
	type_chart = TypeChart.from_dict(chart_doc, TYPE_CHART_PATH)
	if type_chart == null:
		return

	var moves_doc := _read_json(MOVES_PATH)
	if not (moves_doc.get("moves", null) is Array):
		push_error("%s: missing 'moves' array." % MOVES_PATH)
		return
	for entry in moves_doc["moves"]:
		var move := MoveData.from_dict(entry, MOVES_PATH)
		if move == null:
			return
		if _moves.has(move.id):
			push_error("%s: duplicate move id '%s'." % [MOVES_PATH, move.id])
			return
		_moves[move.id] = move

	var creatures_doc := _read_json(CREATURES_PATH)
	if not (creatures_doc.get("creatures", null) is Array):
		push_error("%s: missing 'creatures' array." % CREATURES_PATH)
		return
	for entry in creatures_doc["creatures"]:
		var species := SpeciesData.from_dict(entry, CREATURES_PATH)
		if species == null:
			return
		if _species.has(species.id):
			push_error("%s: duplicate creature id '%s'." % [CREATURES_PATH, species.id])
			return
		_species[species.id] = species
		_species_order.append(species.id)

	loaded = _cross_check()


## Catches the failures that only show up between files: a learnset pointing at
## a move that was renamed, a creature typed with something not in the chart.
## Cheap to run at startup and far easier to read than the same problem
## surfacing as a null mid-battle.
func _cross_check() -> bool:
	var ok := true
	for species_id in _species:
		var species: SpeciesData = _species[species_id]
		for type_id in species.types:
			if not type_chart.has_type(type_id):
				push_error("%s: '%s' has unknown type '%s'." % [
					CREATURES_PATH, species_id, type_id,
				])
				ok = false
		for entry in species.learnset:
			if not _moves.has(entry["move"]):
				push_error("%s: '%s' learns unknown move '%s' at level %d." % [
					CREATURES_PATH, species_id, entry["move"], entry["level"],
				])
				ok = false
	for move_id in _moves:
		var move: MoveData = _moves[move_id]
		if move.type != TypeChart.NO_TYPE and not type_chart.has_type(move.type):
			push_error("%s: '%s' has unknown type '%s'." % [MOVES_PATH, move_id, move.type])
			ok = false
	return ok


func get_move(move_id: String) -> MoveData:
	if not _moves.has(move_id):
		push_error("No move with id '%s'." % move_id)
		return null
	return _moves[move_id]


func get_species(species_id: String) -> SpeciesData:
	if not _species.has(species_id):
		push_error("No creature with id '%s'." % species_id)
		return null
	return _species[species_id]


func has_species(species_id: String) -> bool:
	return _species.has(species_id)


## Ids in the order they appear in the data file, so listings are stable.
func species_ids() -> PackedStringArray:
	return _species_order.duplicate()


func move_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for move_id in _moves:
		ids.append(move_id)
	return ids


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Content: no such file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s: expected a JSON object at the top level." % path)
		return {}
	return parsed
