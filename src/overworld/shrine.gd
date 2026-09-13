class_name Shrine
extends StaticBody2D
## A standing stone where creatures can be left and collected.
##
## Solid like every other interactable, so using it means standing in front of
## it. Placeholder art drawn in code -- a weathered stone with a carved bowl,
## nothing a real tileset would not replace. See docs/DESIGN.md § 24.

signal storage_requested

const STONE := Color("6a6f7a")
const STONE_HI := Color("858b98")
const STONE_LO := Color("474c56")
const MOSS := Color("54703f")
const BOWL := Color("2b3a46")


func interact(_who: Node) -> void:
	storage_requested.emit()


func _draw() -> void:
	draw_rect(Rect2(-6.0, -3.0, 12.0, 3.0), Color(0, 0, 0, 0.35))  # ground shadow
	# The stone itself: a tapering slab, lit from the left.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-6.0, 0.0), Vector2(-4.0, -20.0),
		Vector2(4.0, -20.0), Vector2(6.0, 0.0),
	]), STONE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-6.0, 0.0), Vector2(-4.0, -20.0), Vector2(-1.0, -20.0), Vector2(-2.0, 0.0),
	]), STONE_HI)
	draw_colored_polygon(PackedVector2Array([
		Vector2(3.0, 0.0), Vector2(2.0, -20.0), Vector2(4.0, -20.0), Vector2(6.0, 0.0),
	]), STONE_LO)
	# A carved bowl near the top, and moss creeping up from the base.
	draw_rect(Rect2(-3.0, -16.0, 6.0, 3.0), BOWL)
	draw_rect(Rect2(-6.0, -4.0, 4.0, 4.0), MOSS)
	draw_rect(Rect2(2.0, -3.0, 4.0, 3.0), MOSS)
