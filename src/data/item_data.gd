class_name ItemData
extends RefCounted
## One item definition, loaded from data/items.json.

const EFFECT_RESTRAIN_HIT := "restrain_hit"

var id := ""
var display_name := ""
var description := ""
var price := 0
var usable_in_battle := false
var effect := {}


static func from_dict(data: Dictionary, source: String) -> ItemData:
	var item_id := str(data.get("id", ""))
	if item_id.is_empty():
		push_error("%s: an item is missing its 'id'." % source)
		return null
	for key in ["name", "price", "effect"]:
		if not data.has(key):
			push_error("%s: item '%s' is missing '%s'." % [source, item_id, key])
			return null

	var item := ItemData.new()
	item.id = item_id
	item.display_name = str(data["name"])
	item.description = str(data.get("description", ""))
	item.price = int(data["price"])
	item.usable_in_battle = bool(data.get("usable_in_battle", false))
	item.effect = data["effect"]

	if not (item.effect is Dictionary) or str(item.effect.get("kind", "")) != EFFECT_RESTRAIN_HIT:
		push_error("%s: item '%s' has an unrecognised effect." % [source, item_id])
		return null

	return item
