extends Node
## What the player owns outside of creatures: coin and items.
##
## Registered as the `Inventory` autoload, so it deliberately has no
## class_name. There is currently no way to earn coin -- battles pay out
## creature experience, not currency -- so the player is seeded with a small
## starting purse. See docs/DESIGN.md section 13 for why that gap is left
## open rather than built out now.

const STARTING_COIN := 60

var coin := 0
var _counts := {}


func _ready() -> void:
	if coin <= 0 and _counts.is_empty():
		coin = STARTING_COIN
		# One free Draught so the very first encounter can be attuned without
		# a shop trip first -- the shop is for restocking, not gatekeeping.
		add("tempering_draught")


func count(item_id: String) -> int:
	return int(_counts.get(item_id, 0))


func has(item_id: String) -> bool:
	return count(item_id) > 0


func add(item_id: String, amount: int = 1) -> void:
	_counts[item_id] = count(item_id) + maxi(0, amount)


## Returns false and changes nothing if there isn't at least one.
func consume(item_id: String) -> bool:
	if not has(item_id):
		return false
	_counts[item_id] = count(item_id) - 1
	return true


func can_afford(item_id: String) -> bool:
	var item := Content.get_item(item_id)
	return item != null and coin >= item.price


## Returns false and changes nothing on failure.
func purchase(item_id: String) -> bool:
	if not can_afford(item_id):
		return false
	coin -= Content.get_item(item_id).price
	add(item_id)
	return true


func owned_item_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for item_id in _counts:
		if count(item_id) > 0:
			ids.append(item_id)
	return ids


func to_dict() -> Dictionary:
	return {"coin": coin, "items": _counts.duplicate()}


func from_dict(data: Dictionary) -> void:
	coin = int(data.get("coin", STARTING_COIN))
	_counts.clear()
	var items: Dictionary = data.get("items", {})
	for item_id in items:
		_counts[item_id] = int(items[item_id])
