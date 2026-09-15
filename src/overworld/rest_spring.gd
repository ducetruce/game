class_name RestSpring
extends StaticBody2D
## A place to put the party back together. Solid, like the signpost, so
## interacting with it means standing in front of it.

## `spring_id` goes out with the signal so the overworld can record which
## spring was just reached, for fast travel -- see docs/DESIGN.md § 41.
signal used(spring_id: String, pages: PackedStringArray)

const WATER := Color("2e4e6e")
const WATER_HI := Color("44688c")
const STONE := Color("60626a")
const STONE_HI := Color("7e808a")

var pages := PackedStringArray()
var spring_id := ""


func interact(_who: Node) -> void:
	Party.restore_all()
	used.emit(spring_id, pages)


func _draw() -> void:
	draw_rect(Rect2(-9.0, -8.0, 18.0, 9.0), STONE)
	draw_rect(Rect2(-7.0, -7.0, 14.0, 6.0), WATER)
	draw_rect(Rect2(-5.0, -6.0, 6.0, 1.0), WATER_HI)
	for offset in [-9, -5, 0, 5]:
		draw_rect(Rect2(float(offset), -9.0, 4.0, 2.0), STONE_HI)
