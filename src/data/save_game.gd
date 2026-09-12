extends Node
## Where the save file lives, and the version/migration boundary around it.
##
## Registered as the `SaveGame` autoload, so it deliberately has no class_name.
## Saves are versioned JSON in user:// -- see docs/DESIGN.md section 5. This
## does not own Party, Inventory, or world placement; each serialises itself
## and SaveGame just calls into them, so a new field belongs with the system
## that owns it, never bolted on here.

const SAVE_PATH := "user://savegame.json"

## Bump whenever a field is removed or its meaning changes; a bump needs a
## step added to _migrate. Adding an optional field with a safe default does
## not need a bump.
const CURRENT_VERSION := 1

## True if a save file was found at startup. Does not mean it is valid --
## load_and_apply() can still fail on a corrupt or unrecognised file.
var has_save := false


func _ready() -> void:
	has_save = FileAccess.file_exists(SAVE_PATH)


## Writes the whole save file. map_id and position describe where the player
## is standing right now; Party and Inventory serialise themselves.
func save(map_id: String, position: Vector2) -> void:
	var data := {
		"save_version": CURRENT_VERSION,
		"party": Party.to_dict(),
		"inventory": Inventory.to_dict(),
		"world": {
			"map_id": map_id,
			"position": [position.x, position.y],
		},
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame: could not open %s for writing (%s)." % [
			SAVE_PATH, error_string(FileAccess.get_open_error()),
		])
		return
	file.store_string(JSON.stringify(data, "\t"))
	has_save = true


## Loads Party and Inventory in place, and returns the world placement as
## {map_id: String, position: Vector2} -- SaveGame holds no reference to the
## active map or player, so placing them is the overworld's job. Returns {}
## on any failure (missing file, bad JSON, an unrecognised save_version), and
## leaves Party and Inventory untouched so a failed load never half-applies.
func load_and_apply() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		has_save = false
		return {}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("%s: not a valid save file." % SAVE_PATH)
		return {}

	var data := _migrate(parsed as Dictionary)
	if data.is_empty():
		return {}

	Party.from_dict(_dict_field(data, "party"))
	Inventory.from_dict(_dict_field(data, "inventory"))

	var world := _dict_field(data, "world")
	var raw_position: Variant = world.get("position", null)
	var position: Variant = null
	if raw_position is Array and (raw_position as Array).size() >= 2:
		var pair: Array = raw_position
		position = Vector2(float(pair[0]), float(pair[1]))

	return {
		"map_id": str(world.get("map_id", "")),
		"position": position,
	}


## Deletes the save. Nothing currently calls this -- it exists for a future
## "new game" option that should not silently resume an old one.
func erase() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	has_save = false


## Upgrades an older save forward. There is nothing to migrate yet at version
## 1 -- this is scaffolding so the first real bump has an established shape
## to extend rather than inventing one under pressure. Returns {} if the
## version is missing, zero, or newer than this build understands.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version <= 0 or version > CURRENT_VERSION:
		push_error("%s: unrecognised save_version %d." % [SAVE_PATH, version])
		return {}
	# if version < 2:
	#     <transform data in place>
	#     version = 2
	return data


func _dict_field(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key, {})
	return value if value is Dictionary else {}
