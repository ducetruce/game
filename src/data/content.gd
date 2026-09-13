extends Node
## Content database. Parses data/*.json once at startup and hands out typed
## objects.
##
## Registered as the `Content` autoload. Deliberately has no class_name: an
## autoload and a global class cannot share a name in Godot.

const TYPE_CHART_PATH := "res://data/type_chart.json"
const MOVES_PATH := "res://data/moves.json"
const CREATURES_PATH := "res://data/creatures.json"
const ITEMS_PATH := "res://data/items.json"
const TEMPERAMENTS_PATH := "res://data/temperaments.json"
const STORY_PATH := "res://data/story.json"

var type_chart: TypeChart = null

## Parsed straight from JSON rather than into a class -- it is one small
## nested table (rules + flavor lines per temperament) with no behaviour of
## its own, so a dedicated class would just be a pass-through.
var temperaments: Dictionary = {}

## The story's stages in order, as {id, objective} dictionaries. Order is the
## whole meaning of this list: "further on" is defined by position in it, so
## nothing may read it as an unordered set. See docs/DESIGN.md § 30.
var story_stages: Array = []

## False if anything failed to parse. Callers that can degrade gracefully
## should check it; everything else can rely on the pushed errors.
var loaded := false

var _moves := {}
var _species := {}
var _species_order := PackedStringArray()
var _items := {}


func _ready() -> void:
	reload()


func reload() -> void:
	loaded = false
	type_chart = null
	temperaments.clear()
	story_stages.clear()
	_moves.clear()
	_species.clear()
	_species_order = PackedStringArray()
	_items.clear()

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

	var items_doc := _read_json(ITEMS_PATH)
	if not (items_doc.get("items", null) is Array):
		push_error("%s: missing 'items' array." % ITEMS_PATH)
		return
	for entry in items_doc["items"]:
		var item := ItemData.from_dict(entry, ITEMS_PATH)
		if item == null:
			return
		if _items.has(item.id):
			push_error("%s: duplicate item id '%s'." % [ITEMS_PATH, item.id])
			return
		_items[item.id] = item

	var temperament_doc := _read_json(TEMPERAMENTS_PATH)
	if not (temperament_doc.get("temperaments", null) is Dictionary):
		push_error("%s: missing 'temperaments' object." % TEMPERAMENTS_PATH)
		return
	temperaments = temperament_doc

	var story_doc := _read_json(STORY_PATH)
	if not (story_doc.get("stages", null) is Array):
		push_error("%s: missing 'stages' array." % STORY_PATH)
		return
	for entry in story_doc["stages"]:
		if not (entry is Dictionary) or not entry.has("id"):
			push_error("%s: every stage needs an 'id'." % STORY_PATH)
			return
		story_stages.append(entry)

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
	var rules: Dictionary = temperaments.get("temperaments", {})
	for species_id in _species:
		var species: SpeciesData = _species[species_id]
		if not rules.has(species.temperament):
			push_error("%s: '%s' has temperament '%s', which is not in %s." % [
				CREATURES_PATH, species_id, species.temperament, TEMPERAMENTS_PATH,
			])
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


func get_item(item_id: String) -> ItemData:
	if not _items.has(item_id):
		push_error("No item with id '%s'." % item_id)
		return null
	return _items[item_id]


func has_item(item_id: String) -> bool:
	return _items.has(item_id)


func item_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item_id in _items:
		ids.append(item_id)
	return ids


## Rules dictionary for one temperament from data/temperaments.json, or an
## empty dictionary if it is unknown.
func temperament_rules(temperament: String) -> Dictionary:
	return temperaments.get("temperaments", {}).get(temperament, {})


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
