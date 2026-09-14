class_name ItemData
extends RefCounted
## One item definition, loaded from data/items.json.

const EFFECT_RESTRAIN_HIT := "restrain_hit"
const EFFECT_HEAL := "heal"
const EFFECT_REVIVE := "revive"
const EFFECT_RESTORE_USES := "restore_uses"
const EFFECT_KEEPSAKE := "keepsake"

## Every effect kind something knows how to apply -- restrain_hit only in a
## battle, heal and restore_uses in either, revive only outside one, and
## keepsake nowhere at all. An item naming anything else is rejected at load
## rather than failing silently when it is used.
##
## A keepsake does nothing when used because using it is not what it is for:
## it is a thing to be carried to somebody. Modelling those as items rather
## than as a separate inventory means the bag, the shops, the save file and
## the obtainability check all already handle them. See docs/DESIGN.md § 37.
const EFFECT_KINDS := [
	EFFECT_RESTRAIN_HIT, EFFECT_HEAL, EFFECT_REVIVE, EFFECT_RESTORE_USES,
	EFFECT_KEEPSAKE,
]

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

	if not (item.effect is Dictionary) or not EFFECT_KINDS.has(str(item.effect.get("kind", ""))):
		push_error("%s: item '%s' has an unrecognised effect." % [source, item_id])
		return null

	return item
