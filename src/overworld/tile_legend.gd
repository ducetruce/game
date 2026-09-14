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
	"c": Vector2i(5, 0),  # plaza -- walkable, flagstone village ground
	"r": Vector2i(7, 0),  # reeds -- walkable, encounter terrain at the water
	"s": Vector2i(6, 0),  # worked stone floor -- walkable, interiors
}

## Painted into the Obstacles layer, which carries the tileset's physics layer.
## Every solid tile still gets grass underneath so edges never show the void,
## though the two are fully opaque themselves and never actually let it show.
const SOLID := {
	"W": Vector2i(0, 1),  # water
	"R": Vector2i(1, 1),  # rock
	"T": Vector2i(2, 1),  # tree
	"F": Vector2i(3, 1),  # fence
	"H": Vector2i(5, 1),  # wall -- a building's ground floor
	"V": Vector2i(6, 1),  # roof -- goes directly above an H tile
	"M": Vector2i(4, 1),  # machinery -- solid, what an interior is full of
}


## What a battle's opening line calls the ground a creature came out of.
## Only the encounter terrains need one; anything else falls back to something
## true of every map, since a forced encounter can start on a path.
const TERRAIN_NAMES := {
	"b": "the bracken",
	"r": "the reeds",
	"G": "the long grass",
	"g": "the long grass",
	"s": "the dark under the gearing",
}
const DEFAULT_TERRAIN_NAME := "cover"


static func terrain_name(symbol: String) -> String:
	return TERRAIN_NAMES.get(symbol, DEFAULT_TERRAIN_NAME)


static func is_solid(symbol: String) -> bool:
	return SOLID.has(symbol)


## Ground tile drawn beneath a symbol. Solid props sit on grass.
static func ground_for(symbol: String) -> Vector2i:
	if GROUND.has(symbol):
		return GROUND[symbol]
	return GROUND["G"]
