extends Node2D
## Hosts the active map, the player, the overworld UI, and any battle in
## progress.
##
## Battles are overlaid on a CanvasLayer rather than swapped in as a scene, so
## the map stays loaded and the player comes back exactly where they were
## standing. This is also the seam map-to-map travel will go through: nothing
## inside a map holds a reference to the player, the UI, or the party.

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")
const FADE_SECONDS := 0.28

@onready var _map: GameMap = $Map
@onready var _player: Player = $Player
@onready var _dialogue: DialogueBox = $DialogueBox
@onready var _shop: Node = $ShopMenu
@onready var _camera: Camera2D = $Player/Camera
@onready var _battle_layer: CanvasLayer = $BattleLayer
@onready var _fade: ColorRect = $FadeLayer/Fade

var _tracker := EncounterTracker.new()
var _rng := RandomNumberGenerator.new()
## Untyped on purpose: statically typing this as Node makes GDScript reject
## the configure() call, which only exists on the battle scene's script.
var _battle = null
var _last_position := Vector2.ZERO

## Set while a transition is running, so a second encounter cannot start on top
## of the one already fading in.
var _busy := false


func _ready() -> void:
	_rng.randomize()
	_map.dialogue_requested.connect(_dialogue.show_pages)
	_dialogue.opened.connect(_on_ui_opened)
	_dialogue.closed.connect(_on_ui_closed)
	_map.shop_requested.connect(_shop.open_with)
	_shop.opened.connect(_on_ui_opened)
	_shop.closed.connect(_on_ui_closed)
	_map.checkpoint_reached.connect(_autosave)

	_player.global_position = _resolve_start_position()
	_last_position = _player.global_position
	_apply_camera_limits()
	_fade.color.a = 0.0


## Loads Party and Inventory from a save, if one exists, and returns where the
## player should stand. Falls back to the map's own spawn point if there is no
## save, the load failed, the save names a different map (no multi-map loading
## exists yet to honour that), or the saved position no longer lands on
## walkable ground -- the map may have changed shape since the save was
## written, and standing a returning player inside a wall is worse than
## ignoring a stale position.
func _resolve_start_position() -> Vector2:
	if not SaveGame.has_save:
		return _map.player_spawn_position()

	var world := SaveGame.load_and_apply()
	var position: Variant = world.get("position", null)
	var map_id := str(world.get("map_id", ""))

	if map_id == _map.id and position is Vector2 and _map.is_walkable(position):
		return position
	return _map.player_spawn_position()


func _autosave() -> void:
	SaveGame.save(_map.id, _player.global_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()
		get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _busy or _battle != null or not _player.input_enabled:
		# Keep the anchor current so pausing does not bank distance.
		_last_position = _player.global_position
		return

	var moved := _player.global_position.distance_to(_last_position)
	_last_position = _player.global_position
	if moved <= 0.0:
		return

	var symbol := _map.terrain_at(_player.global_position)
	if _tracker.advance(moved, _map.encounter_chance(symbol), _rng):
		_begin_encounter(symbol)


func _apply_camera_limits() -> void:
	var bounds := _map.world_bounds()
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	# Without this the camera lerps in from the origin on the first frame.
	_camera.reset_smoothing()


# --- encounters ------------------------------------------------------------

func _begin_encounter(symbol: String) -> void:
	if not Party.has_any() or Party.all_fainted():
		return
	var wild := _map.roll_encounter(symbol, _rng)
	if wild == null:
		return

	_busy = true
	_player.input_enabled = false
	await _fade_to(1.0)

	_battle = BATTLE_SCENE.instantiate()
	# The party is passed by reference, so damage and experience stick.
	_battle.configure(Party.members, wild)
	_battle.finished.connect(_on_battle_finished)
	_battle_layer.add_child(_battle)

	await _fade_to(0.0)
	_busy = false


func _on_battle_finished(outcome: int) -> void:
	_busy = true
	await _fade_to(1.0)

	if _battle != null:
		_battle.queue_free()
		_battle = null

	var lost := outcome == BattleState.Phase.LOST
	if lost:
		Party.restore_all()
		_player.global_position = _map.player_spawn_position()
		_camera.reset_smoothing()

	_last_position = _player.global_position
	_tracker.start_grace()
	_autosave()

	await _fade_to(0.0)
	_player.input_enabled = true
	_busy = false

	if lost:
		_dialogue.show_pages(PackedStringArray([
			"You come to on the path, further back than you remember walking.",
			"Everything you carry is standing again. You are not certain by whose doing.",
		]))


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_SECONDS)
	await tween.finished


func _on_ui_opened() -> void:
	_player.input_enabled = false


func _on_ui_closed() -> void:
	# Dialogue and the shop menu only ever open while the overworld owns
	# input, so it is safe to hand it straight back.
	_player.input_enabled = true
	_last_position = _player.global_position
