class_name Player
extends CharacterBody2D
## Free-roaming top-down controller.
##
## Movement is fully analogue -- the player is never snapped to the tile grid.
## That means "which tile am I facing" is not something we can read off the
## player's position, so facing is tracked explicitly from input and drives an
## interaction probe box in front of the body. See docs/DESIGN.md § 7.

## Frame order in the sprite sheet matches these values exactly.
enum Facing { DOWN, UP, LEFT, RIGHT }

## First tuned blind, before the game had ever been played; bumped ~45%
## after actual playtesting reported walking as sluggish. Crossing the base
## 320px-wide viewport now takes about 3.8s walking, 2.1s running.
const WALK_SPEED := 84.0
const RUN_SPEED := 150.0
## High enough that input feels instant, low enough to take the edge off
## direction changes. Pure snap movement reads as slippery at this tile size.
const ACCELERATION := 720.0
const FRICTION := 900.0

## How far in front of the body the interaction box sits, and how high up it
## is relative to the feet-origin. Tuned so a tile-adjacent object is reachable
## from any approach angle.
const PROBE_REACH := 10.0
const PROBE_HEIGHT := -8.0

## How long a fresh interact press is ignored right after a dialogue or menu
## closes. Without this, closing a signpost's last page while still standing
## in its interaction box is itself a fresh interact press -- reopening it
## immediately, every time, for as long as the player keeps pressing the
## button. Comfortably longer than one physics frame: real button-mashing is
## fast enough to land a new press before the very next tick.
const INTERACT_LOCK_SECONDS := 0.3

## Cleared while a dialogue box or menu owns input.
var input_enabled := true

var facing: Facing = Facing.DOWN

var _interact_lock := 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _probe: Area2D = $InteractionProbe


func _physics_process(delta: float) -> void:
	var direction := _read_direction()

	if direction != Vector2.ZERO:
		_set_facing_from(direction)
		var speed := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED
		velocity = velocity.move_toward(direction * speed, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

	move_and_slide()
	_probe.position = facing_vector() * PROBE_REACH + Vector2(0.0, PROBE_HEIGHT)

	_interact_lock = maxf(0.0, _interact_lock - delta)
	if input_enabled and _interact_lock <= 0.0 and Input.is_action_just_pressed("interact"):
		_try_interact()


func facing_vector() -> Vector2:
	match facing:
		Facing.UP:
			return Vector2.UP
		Facing.LEFT:
			return Vector2.LEFT
		Facing.RIGHT:
			return Vector2.RIGHT
		_:
			return Vector2.DOWN


func _read_direction() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	# get_vector normalises, so a diagonal is not faster than a straight line.
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _set_facing_from(direction: Vector2) -> void:
	# On an exact diagonal the horizontal axis wins. Arbitrary, but it has to be
	# deterministic or facing flickers while walking diagonally.
	if absf(direction.x) >= absf(direction.y):
		facing = Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	else:
		facing = Facing.DOWN if direction.y > 0.0 else Facing.UP
	_sprite.frame = facing


func _try_interact() -> void:
	for body in _probe.get_overlapping_bodies():
		if body.is_in_group("interactable") and body.has_method("interact"):
			body.interact(self)
			return


## Suppresses the next interact press for a moment. Call this when handing
## input back after a dialogue or menu closes.
func lock_interact() -> void:
	_interact_lock = INTERACT_LOCK_SECONDS
