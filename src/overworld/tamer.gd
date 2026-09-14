class_name Tamer
extends StaticBody2D
## A person who walks a beat and fights you when you reach them.
##
## Wanders rather than standing in a doorway: a tamer you can see coming and
## decide to avoid is a better encounter than a gate you have to pass, and it
## means the same map reads differently depending on where they happen to be.
##
## Solid, like every other interactable, but a *moving* solid body can shove
## the player into a wall or carry them along, so it simply will not step onto
## the tile the player is standing on -- it waits instead. See
## docs/DESIGN.md § 35.

signal challenge_requested(tamer_id: String)

const CLOAK_BASE := Color("6a5a4a")
const SKIN := Color("c6a07e")
const HAIR := Color("2e2a28")
const HAT := Color("3f3a34")

## Tiles a second. Deliberately slower than the player, who walks at about
## four: something that can run you down is a threat, and a tamer is an
## encounter.
const SPEED := 22.0
## How close counts as arrived, in pixels. Any smaller and floating point
## leaves it twitching on the spot.
const ARRIVAL := 1.0
## The player's own half-width plus the tamer's, near enough. Stepping inside
## this is what would shove them.
const KEEP_CLEAR := 12.0
## Beat by beat, a tamer pauses at each end of its walk. Constant motion reads
## as a machine.
const PAUSE_SECONDS := 1.1

var tamer_id := ""
var display_name := "A tamer"
## World positions to walk between, in order, looping. One point (or none)
## means standing still, which is a legitimate way to place a tamer.
var route: PackedVector2Array = PackedVector2Array()
## Set by GameMap: nobody to fight while they are already beaten and not yet
## due for a rematch. They still walk their beat and still talk.
var beaten := false

@export var tint := Color.WHITE

var _leg := 0
var _paused := 0.0
var _player: Node2D = null


func _ready() -> void:
	# The player is found once rather than per frame, and by group rather than
	# by path: the tamer is a child of the map, and the map knows nothing about
	# where the player node lives.
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]


func interact(_who: Node) -> void:
	challenge_requested.emit(tamer_id)


func _physics_process(delta: float) -> void:
	if route.size() < 2:
		return
	if _paused > 0.0:
		_paused = maxf(0.0, _paused - delta)
		return

	var target := route[_leg]
	var to_target := target - global_position
	if to_target.length() <= ARRIVAL:
		_leg = (_leg + 1) % route.size()
		_paused = PAUSE_SECONDS
		return

	var step := to_target.normalized() * SPEED * delta
	# Never step into the player. A static body that moves does not resolve
	# collisions -- it simply occupies the space, and the player's own body
	# then gets pushed out of it, which at best looks broken and at worst
	# posts them through a wall.
	if _player != null and (global_position + step).distance_to(_player.global_position) < KEEP_CLEAR:
		return
	global_position += step


func _draw() -> void:
	var cloak := CLOAK_BASE * tint
	var cloak_hi := cloak.lightened(0.2)
	draw_rect(Rect2(-2.0, -3.0, 4.0, 2.0), Color(0, 0, 0, 0.35))  # ground shadow
	draw_rect(Rect2(-4.0, -14.0, 8.0, 11.0), cloak)
	draw_rect(Rect2(-4.0, -14.0, 8.0, 2.0), cloak_hi)
	draw_rect(Rect2(-3.0, -20.0, 6.0, 6.0), SKIN)
	# A brimmed hat, so a tamer reads as a different kind of person from a
	# villager at a glance and from across the map.
	draw_rect(Rect2(-5.0, -22.0, 10.0, 2.0), HAT)
	draw_rect(Rect2(-3.0, -24.0, 6.0, 3.0), HAT)
	draw_rect(Rect2(-5.0, -11.0, 10.0, 2.0), HAIR)  # a strap across the chest
