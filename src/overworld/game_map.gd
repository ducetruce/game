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

const TILE_SIZE := 16
const SIGN_SCENE := preload("res://scenes/overworld/sign_post.tscn")
const SPRING_SCENE := preload("res://scenes/overworld/rest_spring.tscn")

@export_file("*.json") var map_data_path: String = ""

var display_name := ""
var grid_size := Vector2i.ZERO

var _player_start := Vector2i.ZERO
var _rows := PackedStringArray()
var _encounters := {}

@onready var _ground: TileMapLayer = $Ground
@onready var _obstacles: TileMapLayer = $Obstacles
@onready var _objects: Node2D = $Objects


func _ready() -> void:
	var data := _read_map_file()
	if data.is_empty():
		return
	display_name = str(data.get("display_name", name))
	_player_start = _tile_from(data["player_start"])
	_encounters = data.get("encounters", {})
	_paint(data["tiles"])
	_spawn_objects(data.get("objects", []))


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
			_:
				push_warning("%s: unknown object type '%s'." % [map_data_path, kind])


func _spawn_sign(spec: Dictionary) -> void:
	var post: SignPost = SIGN_SCENE.instantiate()
	post.pages = _to_string_array(spec.get("text", []))
	post.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	post.read_requested.connect(_on_read_requested)
	_objects.add_child(post)


func _spawn_spring(spec: Dictionary) -> void:
	var spring: RestSpring = SPRING_SCENE.instantiate()
	spring.pages = _to_string_array(spec.get("text", []))
	spring.position = tile_to_world(_tile_from(spec.get("tile", [0, 0])))
	spring.used.connect(_on_read_requested)
	_objects.add_child(spring)


func _on_read_requested(pages: PackedStringArray) -> void:
	dialogue_requested.emit(pages)


# --- encounters ------------------------------------------------------------

## Tile symbol under a world position, or "" if it is off the map.
func terrain_at(world_position: Vector2) -> String:
	var tile := Vector2i(
		int(floorf(world_position.x / float(TILE_SIZE))),
		int(floorf(world_position.y / float(TILE_SIZE))))
	if tile.y < 0 or tile.y >= _rows.size():
		return ""
	var row := _rows[tile.y]
	if tile.x < 0 or tile.x >= row.length():
		return ""
	return row[tile.x]


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
