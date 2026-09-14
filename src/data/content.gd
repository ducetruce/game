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
const QUESTS_PATH := "res://data/quests.json"
const MAP_PATH_FORMAT := "res://data/maps/%s.json"

var type_chart: TypeChart = null

## Parsed straight from JSON rather than into a class -- it is one small
## nested table (rules + flavor lines per temperament) with no behaviour of
## its own, so a dedicated class would just be a pass-through.
var temperaments: Dictionary = {}

## Every quest, in the order the data declares them. Each quest's own `steps`
## are ordered too, and that order is the whole meaning of them: "further on"
## is defined by position, so nothing may read a step list as an unordered
## set. See docs/DESIGN.md § 34.
var quests: Array = []

## How many quests must be finished before the Elder's Gauntlet can be
## challenged, and what to show the player when no quest is telling them what
## to do.
var gauntlet_requirement := 0
var default_objective := ""

## False if anything failed to parse. Callers that can degrade gracefully
## should check it; everything else can rely on the pushed errors.
var loaded := false

var _moves := {}
var _species := {}
var _species_order := PackedStringArray()
var _items := {}
var _map_names := {}


func _ready() -> void:
	reload()


func reload() -> void:
	loaded = false
	type_chart = null
	temperaments.clear()
	quests.clear()
	_moves.clear()
	_species.clear()
	_species_order = PackedStringArray()
	_items.clear()
	_map_names.clear()

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

	var quest_doc := _read_json(QUESTS_PATH)
	if not (quest_doc.get("quests", null) is Array):
		push_error("%s: missing 'quests' array." % QUESTS_PATH)
		return
	gauntlet_requirement = int(quest_doc.get("gauntlet_requirement", 0))
	default_objective = str(quest_doc.get("default_objective", ""))
	for entry in quest_doc["quests"]:
		if not (entry is Dictionary) or not entry.has("id"):
			push_error("%s: every quest needs an 'id'." % QUESTS_PATH)
			return
		if not (entry.get("steps", null) is Array) or (entry["steps"] as Array).is_empty():
			push_error("%s: quest '%s' needs a non-empty 'steps' array."
				% [QUESTS_PATH, entry["id"]])
			return
		quests.append(entry)

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


## A map's own display_name, read straight from its JSON and remembered.
##
## Maps are scenes, and the two places that want this -- the title screen's
## save summary and the quest log -- both want it without one loaded. Loading
## a map to read a string would be a great deal of machinery for a label, and
## two copies of the same file-reading was how it started.
func map_name(map_id: String) -> String:
	if map_id.is_empty():
		return "Somewhere"
	if _map_names.has(map_id):
		return _map_names[map_id]

	var name := map_id
	var path := MAP_PATH_FORMAT % map_id
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			name = str((parsed as Dictionary).get("display_name", map_id))
	_map_names[map_id] = name
	return name


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
