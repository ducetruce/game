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
## is standing right now; Party and Inventory serialise themselves. Returns
## false if the file could not be written -- autosaves ignore that, but a
## manual save has to be able to say so rather than claim success.
func save(map_id: String, position: Vector2) -> bool:
	var data := {
		"save_version": CURRENT_VERSION,
		"party": Party.to_dict(),
		"storage": Storage.to_dict(),
		"journal": Journal.to_dict(),
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
		return false
	file.store_string(JSON.stringify(data, "\t"))
	has_save = true
	return true


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
	# Optional: saves written before the shrine existed have no storage block,
	# and an absent one correctly reads as empty. No version bump needed for
	# an added field with a safe default -- see section 5.
	Storage.from_dict(_dict_field(data, "storage"))
	# A save written before the story existed has no journal, and from_dict
	# reads that as the beginning -- which is where such a save should be.
	Journal.from_dict(_dict_field(data, "journal"))
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


## Reads the save without applying any of it, for the title screen to describe
## what Continue would resume. Deliberately separate from load_and_apply():
## describing a save and entering it are different acts, and a screen that is
## only offering a choice must not have already made it.
##
## Returns {} if there is nothing readable. Otherwise {map_name, party_size,
## lead_name, lead_level} -- enough for one line, no more.
func peek() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var data := _migrate(parsed as Dictionary)
	if data.is_empty():
		return {}

	var members: Array = _dict_field(data, "party").get("members", [])
	var summary := {
		"map_name": _map_name(str(_dict_field(data, "world").get("map_id", ""))),
		"party_size": members.size(),
		"lead_name": "",
		"lead_level": 0,
	}
	if not members.is_empty() and members[0] is Dictionary:
		var lead := Creature.from_dict(members[0])
		if lead != null:
			summary["lead_name"] = lead.display_name()
			summary["lead_level"] = lead.level
	return summary


func _map_name(map_id: String) -> String:
	return Content.map_name(map_id)


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
