extends Node
## Creatures kept somewhere other than the party.
##
## Registered as the `Storage` autoload, so it deliberately has no class_name.
## Reachable only at the shrine in Aldenmere, never from the pause menu: having
## to walk back somewhere is what makes the six you are carrying a commitment
## rather than a loadout you re-pick every fight. See docs/DESIGN.md § 24.
##
## Flat list rather than numbered boxes. Boxes are Pokemon's answer to a
## thousand creatures and a 1996 memory budget; the function they serve --
## somewhere to put what the party cannot hold -- is this, and partitioning can
## be added later without changing what is stored.

const CAPACITY := 60

var creatures: Array[Creature] = []


func count() -> int:
	return creatures.size()


func has_room() -> bool:
	return creatures.size() < CAPACITY


## False if there is no room, so the caller can say so rather than silently
## dropping a creature.
func deposit(creature: Creature) -> bool:
	if creature == null or not has_room():
		return false
	creatures.append(creature)
	return true


## Removes and returns the creature at `index`, or null if there is none.
func withdraw(index: int) -> Creature:
	if index < 0 or index >= creatures.size():
		return null
	var creature := creatures[index]
	creatures.remove_at(index)
	return creature


## Empty, which is what a new game starts with. Party and Inventory seed
## themselves; there is nothing to seed here.
func reset_for_new_game() -> void:
	creatures.clear()


func to_dict() -> Dictionary:
	var rows := []
	for creature in creatures:
		rows.append(creature.to_dict())
	return {"creatures": rows}


func from_dict(data: Dictionary) -> void:
	creatures.clear()
	for row in data.get("creatures", []):
		if row is Dictionary:
			deposit(Creature.from_dict(row))
