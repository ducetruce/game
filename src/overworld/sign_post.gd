class_name SignPost
extends StaticBody2D
## A readable sign. Solid, so the player bumps into it and ends up facing it.
##
## Placeholder art is drawn in code -- there is no sign sprite yet, and adding
## one just to delete it later is not worth the import.

signal read_requested(pages: PackedStringArray)

const POST := Color("4a3a2c")
const BOARD := Color("6e543a")
const BOARD_HI := Color("8a6c4c")
const TEXT_MARK := Color("352a1e")

## Set by GameMap from the map's JSON. One page per dialogue box.
var pages := PackedStringArray()


## Called by Player through the interaction probe.
func interact(_who: Node) -> void:
	read_requested.emit(pages)


func _draw() -> void:
	# Origin sits at the base of the post, matching how the player's feet are
	# its origin, so both sort against the ground the same way.
	draw_rect(Rect2(-2.0, -11.0, 4.0, 11.0), POST)
	draw_rect(Rect2(-8.0, -20.0, 16.0, 10.0), BOARD)
	draw_rect(Rect2(-8.0, -20.0, 16.0, 2.0), BOARD_HI)
	for i in 3:
		draw_rect(Rect2(-5.0, -17.0 + i * 2.0, 10.0 - i * 2.0, 1.0), TEXT_MARK)
