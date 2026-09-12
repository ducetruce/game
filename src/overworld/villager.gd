class_name Villager
extends StaticBody2D
## A person with something to say. Solid, like every other interactable, so
## talking to one means standing in front of them.
##
## Distinct from Shopkeeper (which opens a buy menu) and SignPost (which reads
## as a prop, not a person) -- this is just conversation. Placeholder art is
## drawn in code; `tint` lets several villagers on one map look different from
## each other without needing separate sprites.

signal read_requested(pages: PackedStringArray)

const CLOAK_BASE := Color("5a4a6a")
const SKIN := Color("c6a07e")
const HAIR := Color("3a2e28")

## Set by GameMap from the map's JSON.
var pages := PackedStringArray()
## Recolours the cloak so villagers on the same map read as different people.
@export var tint := Color.WHITE


func interact(_who: Node) -> void:
	read_requested.emit(pages)


func _draw() -> void:
	var cloak := CLOAK_BASE * tint
	var cloak_hi := cloak.lightened(0.2)
	draw_rect(Rect2(-2.0, -3.0, 4.0, 2.0), Color(0, 0, 0, 0.35))  # ground shadow
	draw_rect(Rect2(-4.0, -13.0, 8.0, 10.0), cloak)
	draw_rect(Rect2(-4.0, -13.0, 8.0, 2.0), cloak_hi)
	draw_rect(Rect2(-3.0, -19.0, 6.0, 6.0), SKIN)
	draw_rect(Rect2(-3.0, -21.0, 6.0, 3.0), HAIR)
