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

## Same debounce problem as Player's interact lock, same fix: closing the
## party menu via the "menu" key is itself a "menu" press, and with nothing
## to suppress it, mashing the key never lets the menu close -- it reopens on
## the very next press, every time. See Player.lock_interact().
const MENU_LOCK_SECONDS := 0.3

## Map loaded when there is no save to say otherwise, and the fallback if a
## save or a warp names a map id with no matching scene.
const DEFAULT_MAP_ID := "hollow_clearing"
const MAP_SCENE_PATH_FORMAT := "res://scenes/overworld/maps/%s.tscn"
const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"

@onready var _map_container: Node2D = $MapContainer
@onready var _player: Player = $Player
@onready var _dialogue: DialogueBox = $DialogueBox
@onready var _shop: Node = $ShopMenu
@onready var _party_menu: Node = $PartyMenu
@onready var _pause_menu: Node = $PauseMenu
@onready var _camera: Camera2D = $Player/Camera
@onready var _battle_layer: CanvasLayer = $BattleLayer
@onready var _fade: ColorRect = $FadeLayer/Fade

## The map currently hosted under _map_container. Never a fixed scene-tree
## child -- travelling between maps frees this and instantiates another, so
## nothing outside _load_map may assume it stays the same node across a
## warp.
var _map: GameMap = null

var _tracker := EncounterTracker.new()
var _rng := RandomNumberGenerator.new()
## Untyped on purpose: statically typing this as Node makes GDScript reject
## the configure() call, which only exists on the battle scene's script.
var _battle = null
var _last_position := Vector2.ZERO

## Set while a transition is running, so a second encounter cannot start on top
## of the one already fading in.
var _busy := false

var _menu_lock := 0.0

## Set while the party screen was opened from the pause menu, so closing it
## goes back there instead of dropping the player into the world.
var _party_from_pause := false


func _ready() -> void:
	_rng.randomize()
	_dialogue.opened.connect(_on_ui_opened)
	_dialogue.closed.connect(_on_ui_closed)
	_shop.opened.connect(_on_ui_opened)
	_shop.closed.connect(_on_ui_closed)
	_party_menu.opened.connect(_on_ui_opened)
	_party_menu.closed.connect(_on_party_closed)
	_pause_menu.opened.connect(_on_ui_opened)
	_pause_menu.closed.connect(_on_ui_closed)
	_pause_menu.party_requested.connect(_on_pause_party_requested)
	_pause_menu.save_requested.connect(_on_pause_save_requested)
	_pause_menu.quit_to_title_requested.connect(_on_pause_quit_requested)
	_fade.color.a = 0.0

	var map_id := DEFAULT_MAP_ID
	var start_position: Variant = null
	if SaveGame.has_save:
		var world := SaveGame.load_and_apply()
		map_id = str(world.get("map_id", DEFAULT_MAP_ID))
		start_position = world.get("position", null)

	_load_map(map_id, start_position)


## Frees whatever map is currently loaded (if any) and instantiates `map_id`
## in its place, positioning the player and re-fitting the camera. `target`
## says where the player should end up: a Vector2i tile (as a warp gives),
## a Vector2 world position (as a restored save gives), or null -- any of
## these falls back to the new map's own spawn point if it does not land on
## walkable ground, since a map can change shape after a save was written,
## and a warp's target tile is only ever as trustworthy as the map data that
## named it.
func _load_map(map_id: String, target: Variant) -> void:
	if _map != null:
		# Taken out of the tree immediately, not just queued for deletion:
		# queue_free() does not take effect until the end of the frame, which
		# leaves the outgoing map's collision live in the physics space at the
		# same world coordinates the player is about to be placed at. Arriving
		# on a tile the *old* map had a wall on then depenetrates the player
		# several pixels off the tile the warp named, and they stay there.
		# Godot disconnects a freed node's signals on its own, so there is
		# nothing to unhook here first.
		_map_container.remove_child(_map)
		_map.queue_free()
		_map = null

	var scene_path := MAP_SCENE_PATH_FORMAT % map_id
	if not ResourceLoader.exists(scene_path):
		push_error("Overworld: no map scene for id '%s', falling back to '%s'." % [
			map_id, DEFAULT_MAP_ID,
		])
		scene_path = MAP_SCENE_PATH_FORMAT % DEFAULT_MAP_ID

	var map_scene: PackedScene = load(scene_path)
	_map = map_scene.instantiate()
	_map_container.add_child(_map)

	_map.dialogue_requested.connect(_dialogue.show_pages)
	_map.shop_requested.connect(_shop.open_with)
	_map.checkpoint_reached.connect(_autosave)

	var position := _map.player_spawn_position()
	if target is Vector2i:
		var candidate := _map.tile_to_world(target)
		if _map.is_walkable(candidate):
			position = candidate
	elif target is Vector2 and _map.is_walkable(target):
		position = target

	_player.global_position = position
	_last_position = position
	_apply_camera_limits()


func _autosave() -> bool:
	return SaveGame.save(_map.id, _player.global_position)


# --- pause menu ------------------------------------------------------------

func _on_pause_party_requested() -> void:
	# The pause menu has already hidden itself expecting the party screen to
	# take over. If it cannot open, put the pause menu back rather than
	# leaving the player with no menu and no input.
	if not Party.has_any():
		_pause_menu.open_menu()
		return
	_party_from_pause = true
	_party_menu.open_menu()


func _on_party_closed() -> void:
	if _party_from_pause:
		_party_from_pause = false
		_pause_menu.open_menu()
		return
	_on_ui_closed()


func _on_pause_save_requested() -> void:
	_pause_menu.report_saved(_autosave())


## Saves on the way out, matching what closing the window does -- leaving for
## the title screen should never be the one exit that loses progress.
func _on_pause_quit_requested() -> void:
	_autosave()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()
		get_tree().quit()


func _physics_process(delta: float) -> void:
	_menu_lock = maxf(0.0, _menu_lock - delta)

	if _busy or _battle != null or not _player.input_enabled:
		# Keep the anchor current so pausing does not bank distance.
		_last_position = _player.global_position
		return

	if _menu_lock <= 0.0 and Input.is_action_just_pressed("menu"):
		_party_menu.open_menu()
		return

	if _menu_lock <= 0.0 and Input.is_action_just_pressed("cancel"):
		_pause_menu.open_menu()
		return

	var moved := _player.global_position.distance_to(_last_position)
	_last_position = _player.global_position
	if moved <= 0.0:
		return

	var warp := _map.warp_at(_player.global_position)
	if not warp.is_empty():
		_begin_warp(warp)
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


# --- travel ------------------------------------------------------------

func _begin_warp(warp: Dictionary) -> void:
	_busy = true
	_player.input_enabled = false
	await _fade_to(1.0)

	_load_map(str(warp.get("target_map", "")), warp.get("target_tile", Vector2i.ZERO))
	# A fresh map means a fresh grace period, same as stepping out of a
	# battle -- otherwise the tracker can roll an encounter on the very tile
	# the player just arrived on.
	_tracker.start_grace()
	_autosave()

	await _fade_to(0.0)
	_player.input_enabled = true
	_busy = false


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
	_battle.configure(Party.members, wild, _map.coin_reward)
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
	# Dialogue, the shop, and the party menu only ever open while the
	# overworld owns input, so it is safe to hand it straight back. Both
	# locks are armed regardless of which action actually closed things --
	# cheap, and it covers every case uniformly rather than tracking which
	# key triggered which close.
	_player.input_enabled = true
	_player.lock_interact()
	_menu_lock = MENU_LOCK_SECONDS
	_last_position = _player.global_position
