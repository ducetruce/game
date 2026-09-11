class_name Shopkeeper
extends StaticBody2D
## A person to buy things from. Solid, like the signpost and the spring, so
## interacting with it means standing in front of it.
##
## Placeholder art is drawn in code, matching the other overworld props.

signal shop_requested(catalog: PackedStringArray)

const CLOAK := Color("4a5a4a")
const CLOAK_HI := Color("647c64")
const SKIN := Color("c6a07e")
const PACK := Color("6e543a")

## Item ids this shopkeeper sells, set by GameMap from the map's JSON.
var catalog := PackedStringArray()


func interact(_who: Node) -> void:
	shop_requested.emit(catalog)


func _draw() -> void:
	draw_rect(Rect2(-3.0, -14.0, 6.0, 3.0), SKIN)
	draw_rect(Rect2(-5.0, -11.0, 10.0, 9.0), CLOAK)
	draw_rect(Rect2(-5.0, -11.0, 10.0, 2.0), CLOAK_HI)
	draw_rect(Rect2(3.0, -8.0, 4.0, 5.0), PACK)
