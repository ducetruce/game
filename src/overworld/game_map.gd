class_name GameMap
extends Node2D
## One explorable area of the world.
##
## The tile grid is loaded from a JSON file at runtime and painted into the
## TileMapLayer nodes, rather than being baked into this scene. That keeps maps
## as diffable plain text while the art is placeholder -- see docs/DESIGN.md § 7
## for the trade-off and when we switch to editor-painted layers.

## Raised when something in this map wants a line of text shown. The Overworld
## wires this to the dialogue box; the map itself owns no UI.
signal dialogue_requested(pages: PackedStringArray)
signal shop_requested(catalog: PackedStringArray)
## A shrine was used. The overworld opens storage; the map knows nothing of it.
signal storage_requested
## A rest spring was used. The overworld treats this as a save point.
signal checkpoint_reached
## An object handed the player something. The overworld says so after the
## object's own lines.
signal item_received(item_id: String, count: int)
## A tamer wants a fight. The overworld owns battles; the map only places the
## person and says who they are.
signal challenge_requested(tamer_id: String)
## A gauntlet trial-giver wants a fight. Same division: the map only places
## them, the overworld knows what a gauntlet trial actually is.
signal gauntlet_challenge_requested(trial_id: String)
## A quest was finished here, and paid what `reward` says. The overworld says
## so; the map knows nothing about how.
signal quest_completed(quest_id: String, reward: Dictionary)

const TILE_SIZE := 16

## Physics layer bits for spawned props. Solid ones sit on layer 1, which the
## player's body masks; walkable ones sit on layer 3, which only the
## interaction probe masks. That split is the whole mechanism behind an object
## declaring `"solid": false` -- see docs/DESIGN.md § 25.
const LAYER_SOLID_PROP := 1
const LAYER_WALKABLE_PROP := 4
const SIGN_SCENE := preload("res://scenes/overworld/sign_post.tscn")
const SPRING_SCENE := preload("res://scenes/overworld/rest_spring.tscn")
const SHOPKEEPER_SCENE := preload("res://scenes/overworld/shopkeeper.tscn")
const VILLAGER_SCENE := preload("res://scenes/overworld/villager.tscn")
const SHRINE_SCENE := preload("res://scenes/overworld/shrine.tscn")
const TAMER_SCENE := preload("res://scenes/overworld/tamer.tscn")

@export_file("*.json") var map_data_path: String = ""

## Stable identifier saved alongside the player's position. Distinct from the
## node/scene name so a map can be renamed or moved without invalidating
## existing saves.
var id := ""
var display_name := ""
var grid_size := Vector2i.ZERO

## [low, high] coin a resolved encounter here pays, inclusive. Zero means this
## area pays nothing, which is right for somewhere with no encounters at all.
var coin_reward := Vector2i.ZERO

var _player_start := Vector2i.ZERO
var _rows := PackedStringArray()
var _encounters := {}
## Vector2i tile -> {target_map: String, target_tile: Vector2i}. Walking onto
## one of these tiles is what actually leaves the map, checked by the
## overworld the same way it checks encounter terrain.
var _warps := {}
## Tamer id -> the spec that placed them, so the overworld can ask who it is
## about to fight without the map knowing what a battle is.
var _tamers := {}

@onready var _ground: TileMapLayer = $Ground
@onready var _obstacles: TileMapLayer = $Obstacles
@onready var _objects: Node2D = $Objects


func _ready() -> void:
	var data := _read_map_file()
	if data.is_empty():
		return
	id = str(data.get("id", name))
	display_name = str(data.get("display_name", name))
	_player_start = _tile_from(data["player_start"])
	coin_reward = _tile_from(data.get("coin_reward", [0, 0]))
	_encounters = data.get("encounters", {})
	_tamers.clear()
	_paint(data["tiles"])
	_spawn_objects(data.get("objects", []))
	# Some places are themselves the beat: arriving at the mere is the point of
	# going there, and making the player hunt for a sign to be told so would be
	# a worse version of the same moment.
	var arrival_quest := str(data.get("arrival_quest", ""))
	var arrival_step := str(data.get("arrival_step", ""))
	if not arrival_quest.is_empty() and not arrival_step.is_empty():
		Journal.advance(arrival_quest, arrival_step)


## World-space position the player should occupy when entering this map.
func player_spawn_position() -> Vector2:
	return tile_to_world(_player_start)


## Full extent of the map in world space. Used to clamp the camera.
func world_bounds() -> Rect2:
	var size := Vector2(grid_size) * TILE_SIZE
	if size.x <= 0.0 or size.y <= 0.0:
		# The map failed to load and already pushed an error. Hand back
		# something non-degenerate so the camera does not also misbehave and
		# bury the real cause.
		size = get_viewport_rect().size
	return Rect2(Vector2.ZERO, size)


## Centre of a tile, which is where anything standing on it is placed.
func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile) * TILE_SIZE + Vector2(TILE_SIZE, TILE_SIZE) * 0.5


## False for solid terrain and for anything off the map. Used to sanity-check
## a saved position before trusting it -- the map may have changed shape since
## the save was written.
func is_walkable(world_position: Vector2) -> bool:
	var symbol := terrain_at(world_position)
	return not symbol.is_empty() and not TileLegend.is_solid(symbol)


# --- loading ---------------------------------------------------------------
# Malformed data fails here, loudly, naming the file and the key. A map that
# half-loads is much harder to diagnose than one that refuses to.

func _read_map_file() -> Dictionary:
	if map_data_path.is_empty():
		push_error("GameMap '%s': map_data_path is not set." % name)
		return {}
	if not FileAccess.file_exists(map_data_path):
		push_error("GameMap '%s': no map file at %s" % [name, map_data_path])
		return {}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(map_data_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s: expected a JSON object at the top level." % map_data_path)
		return {}

	var data: Dictionary = parsed
	for key in ["tiles", "player_start"]:
		if not data.has(key):
			push_error("%s: missing required key '%s'." % [map_data_path, key])
			return {}
	if not (data["tiles"] is Array) or (data["tiles"] as Array).is_empty():
		push_error("%s: 'tiles' must be a non-empty array of row strings." % map_data_path)
		return {}
	return data


func _paint(rows: Array) -> void:
	_ground.clear()
	_obstacles.clear()
	grid_size = Vector2i(0, rows.size())
	_rows = PackedStringArray()

	for y in rows.size():
		var row := str(rows[y])
		_rows.append(row)
		grid_size.x = maxi(grid_size.x, row.length())
		for x in row.length():
			var symbol := row[x]
			var cell := Vector2i(x, y)
			# Solid props still get ground painted underneath, so a tileset
			# with transparent edges never shows the void behind the map.
			_ground.set_cell(cell, TileLegend.SOURCE_ID, TileLegend.ground_for(symbol))
			if TileLegend.is_solid(symbol):
				_obstacles.set_cell(cell, TileLegend.SOURCE_ID, TileLegend.SOLID[symbol])
			elif not TileLegend.GROUND.has(symbol):
				push_warning("%s: unknown tile symbol '%s' at (%d, %d)." % [
					map_data_path, symbol, x, y,
				])


func _spawn_objects(objects: Array) -> void:
	for entry in objects:
		if typeof(entry) != TYPE_DICTIONARY:
			push_warning("%s: skipping non-object entry in 'objects'." % map_data_path)
			continue
		var spec: Dictionary = entry
		var kind := str(spec.get("type", ""))
		match kind:
			"sign":
				_spawn_sign(spec)
			"spring":
				_spawn_spring(spec)
			"shop":
				_spawn_shop(spec)
			"npc":
				_spawn_npc(spec)
			"shrine":
				_spawn_shrine(spec)
			"tamer":
				_spawn_tamer(spec)
			"gauntlet_trial":
				_spawn_gauntlet_trial(spec)
			"warp":
				_register_warp(spec)
			_:
				push_warning("%s: unknown object type '%s'." % [map_data_path, kind])


func _spawn_sign(spec: Dictionary) -> void:
	var post: SignPost = SIGN_SCENE.instantiate()
	post.pages = _to_string_array(spec.get("text", []))
	post.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	post.read_requested.connect(_on_read_requested.bind(spec))
	_apply_solidity(post, spec)
	_objects.add_child(post)


func _spawn_spring(spec: Dictionary) -> void:
	var spring: RestSpring = SPRING_SCENE.instantiate()
	spring.pages = _to_string_array(spec.get("text", []))
	spring.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	spring.used.connect(_on_spring_used)
	_apply_solidity(spring, spec)
	_objects.add_child(spring)


func _on_spring_used(pages: PackedStringArray) -> void:
	dialogue_requested.emit(pages)
	checkpoint_reached.emit()


func _spawn_shop(spec: Dictionary) -> void:
	var keeper: Shopkeeper = SHOPKEEPER_SCENE.instantiate()
	var catalog := PackedStringArray()
	for item_id in spec.get("catalog", []):
		catalog.append(str(item_id))
	keeper.catalog = catalog
	keeper.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	keeper.shop_requested.connect(_on_shop_requested)
	_apply_solidity(keeper, spec)
	_objects.add_child(keeper)


func _on_shop_requested(catalog: PackedStringArray) -> void:
	shop_requested.emit(catalog)


func _spawn_npc(spec: Dictionary) -> void:
	var villager: Villager = VILLAGER_SCENE.instantiate()
	villager.pages = _to_string_array(spec.get("text", []))
	villager.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	if spec.has("tint"):
		villager.tint = _color_from(spec["tint"])
	villager.read_requested.connect(_on_read_requested.bind(spec))
	_apply_solidity(villager, spec)
	_objects.add_child(villager)


func _spawn_shrine(spec: Dictionary) -> void:
	var shrine: Shrine = SHRINE_SCENE.instantiate()
	shrine.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	shrine.storage_requested.connect(_on_storage_requested)
	_apply_solidity(shrine, spec)
	_objects.add_child(shrine)


func _on_storage_requested() -> void:
	storage_requested.emit()


func _register_warp(spec: Dictionary) -> void:
	var tile := _tile_from(spec.get("tile", [0, 0]))
	_warps[tile] = {
		"target_map": str(spec.get("target_map", "")),
		"target_tile": _tile_from(spec.get("target_tile", [0, 0])),
	}


## Solid unless the object says otherwise. A person or a signpost should stop
## you; a plaque set into the floor should not, while still being readable.
func _spawn_tamer(spec: Dictionary) -> void:
	var tamer: Tamer = TAMER_SCENE.instantiate()
	tamer.tamer_id = str(spec.get("id", ""))
	if tamer.tamer_id.is_empty():
		push_error("%s: a tamer needs an 'id'; it is what remembers whether"
			% map_data_path + " they have been beaten.")
	_tamers[tamer.tamer_id] = spec
	tamer.display_name = str(spec.get("name", "A tamer"))
	tamer.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	# The beat is given as tiles and walked in world space. A route of one
	# point (or none) is a tamer who stands where they were put, which is a
	# legitimate way to place one.
	var route := PackedVector2Array()
	for point in spec.get("patrol", []):
		route.append(tile_to_world(_tile_from(point)))
	tamer.route = route
	if spec.has("tint"):
		tamer.tint = _color_from(spec["tint"])
	tamer.challenge_requested.connect(_on_challenge_requested)
	_apply_solidity(tamer, spec)
	_objects.add_child(tamer)


func _on_challenge_requested(tamer_id: String) -> void:
	challenge_requested.emit(tamer_id)


## A gauntlet trial-giver, placed with just an `id` (matched against
## data/gauntlet.json) and a `tile`. Everything else about the trial -- who
## they are, what they fight with, what they say -- lives centrally in
## Content.gauntlet_trials rather than per-map, since a trial belongs to the
## gauntlet and not to any one place; only where its giver stands is the
## map's to say. Reuses the Tamer scene for the visual (a person who can be
## challenged) with its patrol left empty, so an elder stands their ground
## rather than wandering. See docs/DESIGN.md § 39.
func _spawn_gauntlet_trial(spec: Dictionary) -> void:
	var trial: Tamer = TAMER_SCENE.instantiate()
	trial.tamer_id = str(spec.get("id", ""))
	if trial.tamer_id.is_empty():
		push_error("%s: a gauntlet_trial needs an 'id' matching one in"
			% map_data_path + " data/gauntlet.json.")
	trial.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	if spec.has("tint"):
		trial.tint = _color_from(spec["tint"])
	trial.challenge_requested.connect(_on_gauntlet_trial_requested)
	_apply_solidity(trial, spec)
	_objects.add_child(trial)


func _on_gauntlet_trial_requested(trial_id: String) -> void:
	gauntlet_challenge_requested.emit(trial_id)


## Who a tamer on this map is, as the data declared them. Empty for an id this
## map does not have.
func tamer_spec(tamer_id: String) -> Dictionary:
	return _tamers.get(tamer_id, {})


## An [r, g, b] array from map data. White for anything malformed, which is
## the no-tint value, so a typo recolours nothing rather than blacking a
## villager out.
func _color_from(value: Variant) -> Color:
	if not (value is Array) or (value as Array).size() < 3:
		push_warning("%s: tint must be an [r, g, b] array." % map_data_path)
		return Color.WHITE
	var rgb: Array = value
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))


## Solid unless the spec says otherwise -- or, if `blocks_until_met` is set
## alongside a `requires`, solid until that requirement holds. Evaluated once,
## at spawn: nothing on this map re-checks itself while the player stands on
## it, the same as a shop's stock never restocking mid-visit, so becoming
## eligible while already on the map takes leaving and coming back to show.
## See docs/DESIGN.md § 39.
func _apply_solidity(node: CollisionObject2D, spec: Dictionary) -> void:
	var solid := bool(spec.get("solid", true))
	if bool(spec.get("blocks_until_met", false)):
		var wants: Dictionary = spec.get("requires", {})
		# Never allowed to consume here: solidity is decided once at spawn,
		# for every object on the map, well before the player has chosen to
		# interact with any single one of them. A has_item requirement that
		# consumed on this check would spend the player's item just for
		# walking within render distance of a gate.
		solid = not _requirement_met(wants, false)
	node.collision_layer = LAYER_SOLID_PROP if solid else LAYER_WALKABLE_PROP


func _on_read_requested(pages: PackedStringArray, spec: Dictionary = {}) -> void:
	# An object that asks for something it has not been given says so and does
	# not move: the refusal is the reply, so it replaces the lines rather than
	# preceding them.
	var refusal := _unmet_requirement(spec)
	if not refusal.is_empty():
		dialogue_requested.emit(refusal)
		return
	dialogue_requested.emit(_speech_for(spec, pages))
	_give(spec)
	_advance_quest(spec)


## Hands the player whatever this object `gives`, once. Tied to the quest step
## the object sets, when it sets one: the gift is part of that beat, and a
## beat already reached is not repeated. An object that gives but sets no
## step gives every time it is read, which is what a shelf of something
## would do and is a data-authoring choice rather than a bug.
func _give(spec: Dictionary) -> void:
	var gift: Dictionary = spec.get("gives", {})
	if gift.is_empty():
		return
	var quest_id := str(spec.get("quest", ""))
	var step := str(spec.get("sets_step", ""))
	if not quest_id.is_empty() and not step.is_empty() \
			and Journal.reached(quest_id, step):
		return
	var item_id := str(gift.get("item", ""))
	var count := maxi(1, int(gift.get("count", 1)))
	if Content.get_item(item_id) == null:
		return
	Inventory.add(item_id, count)
	item_received.emit(item_id, count)


## Which lines an object says right now.
##
## An object naming a `quest` may carry alternatives keyed by how far that
## quest has got, as a "quest_text" array of {from, text}; the one that wins is
## the last whose step the player has reached. Resolved here, at the moment of
## reading, rather than when the map spawned: talking to one villager can move
## a quest on, and the villager standing next to them has to have the newer
## thing to say without the map being reloaded first. See docs/DESIGN.md § 34.
func _speech_for(spec: Dictionary, fallback: PackedStringArray) -> PackedStringArray:
	var quest_id := str(spec.get("quest", ""))
	var chosen := fallback
	for entry in spec.get("quest_text", []):
		if not (entry is Dictionary):
			push_warning("%s: 'quest_text' entries must be objects." % map_data_path)
			continue
		var from := str(entry.get("from", ""))
		if from.is_empty() or not Journal.reached(quest_id, from):
			continue
		chosen = _to_string_array(entry.get("text", []))
	return chosen


## Moves a quest on, if this object is a beat in one. Does nothing when the
## player is already past that point, which is what makes walking back and
## re-reading a sign harmless.
func _advance_quest(spec: Dictionary) -> void:
	var quest_id := str(spec.get("quest", ""))
	if quest_id.is_empty():
		return
	var step := str(spec.get("sets_step", ""))
	if not step.is_empty():
		Journal.advance(quest_id, step)
	if bool(spec.get("completes_quest", false)):
		var paid := Journal.complete(quest_id)
		if not paid.is_empty():
			quest_completed.emit(quest_id, paid)


## What this object says instead, when it wants something the player has not
## got. Empty when there is nothing to want or the want is met.
##
## Two kinds, because they are the two shapes of every quest errand: bring me
## a thing, and deal with a thing. Both are checked *before* the object moves
## the quest on, and `has_item` consumes only once it is going to.
func _unmet_requirement(spec: Dictionary) -> PackedStringArray:
	var wants: Dictionary = spec.get("requires", {})
	if wants.is_empty():
		return PackedStringArray()
	# Only asked for while the object still has something to do. Walking back
	# past a door you have already opened should not be asked to open it
	# again. "Something to do" is completing the quest if this object does
	# that, else reaching its step -- keyed to the step alone, the cradle that
	# both marks a step early and finishes the quest later was skipping its
	# gate on the return trip, and the weight it asked for was never taken.
	var quest_id := str(spec.get("quest", ""))
	var step := str(spec.get("sets_step", ""))
	if not quest_id.is_empty():
		if bool(spec.get("completes_quest", false)):
			if Journal.is_complete(quest_id):
				return PackedStringArray()
		elif not step.is_empty() and Journal.reached(quest_id, step):
			return PackedStringArray()

	if _requirement_met(wants, true):
		return PackedStringArray()
	return _to_string_array(wants.get("text", ["Not yet."]))


## The boolean core of a `requires` block, shared by the refusal message above
## and the solidity gate in _apply_solidity. `allow_consume` is false from the
## solidity path -- decided for every object at spawn, before the player has
## chosen to interact with any of them -- and true from an actual interaction,
## which is the only place a has_item requirement may spend what it asked for.
func _requirement_met(wants: Dictionary, allow_consume: bool) -> bool:
	var kind := str(wants.get("kind", ""))
	match kind:
		"has_item":
			var item_id := str(wants.get("item", ""))
			var count := maxi(1, int(wants.get("count", 1)))
			var met := Inventory.count(item_id) >= count
			if met and allow_consume and bool(wants.get("consume", false)):
				for _i in count:
					Inventory.consume(item_id)
			return met
		"defeated":
			return Journal.defeats_of(str(wants.get("species", ""))) >= maxi(1, int(wants.get("count", 1)))
		"gauntlet_unlocked":
			return Journal.gauntlet_unlocked()
		_:
			push_warning("%s: unknown requirement kind '%s'." % [map_data_path, kind])
			return true


# --- encounters ------------------------------------------------------------

## Which tile a world position falls on. Public because the overworld needs to
## tell "still standing where the warp put me" from "stepped off it".
func tile_at(world_position: Vector2) -> Vector2i:
	return Vector2i(
		int(floorf(world_position.x / float(TILE_SIZE))),
		int(floorf(world_position.y / float(TILE_SIZE))))


## Tile symbol under a world position, or "" if it is off the map.
func terrain_at(world_position: Vector2) -> String:
	var tile := tile_at(world_position)
	if tile.y < 0 or tile.y >= _rows.size():
		return ""
	var row := _rows[tile.y]
	if tile.x < 0 or tile.x >= row.length():
		return ""
	return row[tile.x]


## {target_map, target_tile} if a warp sits under this world position, or {}
## if there is none.
func warp_at(world_position: Vector2) -> Dictionary:
	return _warps.get(tile_at(world_position), {})


## Tile symbols this map can produce encounters on, in declaration order.
func encounter_symbols() -> PackedStringArray:
	var symbols := PackedStringArray()
	for symbol in _encounters:
		symbols.append(str(symbol))
	return symbols


## Per-check probability for this terrain. Zero means no encounters here.
func encounter_chance(symbol: String) -> float:
	if symbol.is_empty() or not _encounters.has(symbol):
		return 0.0
	return float(_encounters[symbol].get("chance", 0.0))


## Picks a creature from this terrain's weighted table. Returns null if the
## terrain has no table, or if it names a species that does not exist.
func roll_encounter(symbol: String, rng: RandomNumberGenerator) -> Creature:
	if not _encounters.has(symbol):
		return null
	var table: Array = _encounters[symbol].get("table", [])
	var total := 0
	for entry in table:
		total += maxi(0, int(entry.get("weight", 0)))
	if total <= 0:
		return null

	var pick := rng.randi_range(1, total)
	for entry in table:
		pick -= maxi(0, int(entry.get("weight", 0)))
		if pick > 0:
			continue
		var species_id := str(entry.get("species", ""))
		if not Content.has_species(species_id):
			push_error("%s: encounter table names unknown species '%s'." % [
				map_data_path, species_id,
			])
			return null
		var levels: Array = entry.get("levels", [1, 1])
		var low := int(levels[0]) if levels.size() > 0 else 1
		var high := int(levels[1]) if levels.size() > 1 else low
		return Creature.create(species_id, rng.randi_range(mini(low, high), maxi(low, high)))
	return null


func _tile_from(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	push_warning("%s: expected a [x, y] tile pair, got %s." % [map_data_path, value])
	return Vector2i.ZERO


func _to_string_array(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for line in value:
			out.append(str(line))
	elif value is String:
		out.append(value)
	return out
