class_name TileLegend
extends RefCounted
## Maps the single characters used in `data/maps/*.json` to atlas coordinates
## in the placeholder tileset.
##
## This exists because maps are authored as plain-text grids for now. Once real
## tilesets land the maps get painted in Godot's TileMapLayer editor instead and
## this whole file goes away -- see docs/DESIGN.md § 7.

const SOURCE_ID := 0

## Painted into the Ground layer. No collision.
const GROUND := {
	"G": Vector2i(0, 0),  # grass
	"g": Vector2i(1, 0),  # grass, tufted
	"P": Vector2i(2, 0),  # packed dirt path
	"p": Vector2i(3, 0),  # worn path
	"b": Vector2i(4, 0),  # bracken -- walkable, and where encounters happen
}

## Painted into the Obstacles layer, which carries the tileset's physics layer.
## Every solid tile still gets grass underneath so edges never show the void.
const SOLID := {
	"W": Vector2i(0, 1),  # water
	"R": Vector2i(1, 1),  # rock
	"T": Vector2i(2, 1),  # tree
	"F": Vector2i(3, 1),  # fence
}


static func is_solid(symbol: String) -> bool:
	return SOLID.has(symbol)


## Ground tile drawn beneath a symbol. Solid props sit on grass.
static func ground_for(symbol: String) -> Vector2i:
	if GROUND.has(symbol):
		return GROUND[symbol]
	return GROUND["G"]
