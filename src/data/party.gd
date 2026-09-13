extends Node
## The player's creatures, persisting across battles and scene changes.
##
## Registered as the `Party` autoload, so it deliberately has no class_name.
## Battles receive these Creature objects by reference, which is why damage
## taken and experience gained survive the battle ending.

const MAX_SIZE := 6

var members: Array[Creature] = []


func _ready() -> void:
	if members.is_empty():
		reset_for_new_game()


## The party a brand new game starts with. Called by the title screen's New
## Game, and at startup so that running the overworld scene directly from the
## editor still has something playable in it. There is no starter choice yet;
## when there is, it replaces the body of this and nothing else.
##
## This clears rather than appends: Party is an autoload, so it outlives the
## scene change into the overworld, and a New Game started after playing would
## otherwise keep the previous run's creatures.
func reset_for_new_game() -> void:
	members.clear()
	add(Creature.create("thistlecalf", 5))
	add(Creature.create("emberwick", 5))


func add(creature: Creature) -> bool:
	if creature == null or members.size() >= MAX_SIZE:
		return false
	members.append(creature)
	return true


func size() -> int:
	return members.size()


func has_any() -> bool:
	return not members.is_empty()


func all_fainted() -> bool:
	for creature in members:
		if not creature.is_fainted():
			return false
	return true


func restore_all() -> void:
	for creature in members:
		creature.restore()


func to_dict() -> Dictionary:
	var rows := []
	for creature in members:
		rows.append(creature.to_dict())
	return {"members": rows}


func from_dict(data: Dictionary) -> void:
	members.clear()
	for row in data.get("members", []):
		if row is Dictionary:
			add(Creature.from_dict(row))
