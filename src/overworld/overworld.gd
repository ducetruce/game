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
@onready var _bag_menu: Node = $BagMenu
@onready var _storage_menu: Node = $StorageMenu
@onready var _debug_menu: Node = $DebugMenu
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

## Set while a screen was opened *from* the pause menu, so closing it goes
## back there instead of dropping the player into the world.
var _returns_to_pause := false

## The tile a warp last put the player on, and whether warps there are still
## being ignored. A two-way doorway naturally puts one map's arrival tile on
## top of the other map's trigger tile, and without this the pair fires on the
## first frame of movement and bounces the player straight back -- forever.
## Cleared the moment they step off it, so the door still works when re-entered.
var _warp_arrival := Vector2i.ZERO
var _warp_locked := false


func _ready() -> void:
	_rng.randomize()
	_dialogue.opened.connect(_on_ui_opened)
	_dialogue.closed.connect(_on_ui_closed)
	_shop.opened.connect(_on_ui_opened)
	_shop.closed.connect(_on_ui_closed)
	_party_menu.opened.connect(_on_ui_opened)
	_party_menu.closed.connect(_on_sub_screen_closed)
	_bag_menu.opened.connect(_on_ui_opened)
	_bag_menu.closed.connect(_on_sub_screen_closed)
	_storage_menu.opened.connect(_on_ui_opened)
	_storage_menu.closed.connect(_on_ui_closed)
	_pause_menu.opened.connect(_on_ui_opened)
	_pause_menu.closed.connect(_on_ui_closed)
	_pause_menu.party_requested.connect(_on_pause_party_requested)
	_pause_menu.bag_requested.connect(_on_pause_bag_requested)
	_pause_menu.save_requested.connect(_on_pause_save_requested)
	_pause_menu.quit_to_title_requested.connect(_on_pause_quit_requested)
	# Absent from a release export rather than merely hidden: a key nobody
	# documented is still a key someone finds.
	if OS.is_debug_build():
		_debug_menu.opened.connect(_on_ui_opened)
		_debug_menu.closed.connect(_on_ui_closed)
		_debug_menu.command_chosen.connect(_on_debug_command)
	else:
		_debug_menu.queue_free()
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
	_map.storage_requested.connect(_storage_menu.open_menu)
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
	_warp_arrival = _map.tile_at(position)
	_warp_locked = true
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
	_returns_to_pause = true
	_party_menu.open_menu()


func _on_pause_bag_requested() -> void:
	_returns_to_pause = true
	_bag_menu.open_menu()


## Shared by the party and bag screens: either can be reached straight from
## the world (the party screen has its own key) or from the pause menu, and
## closing has to go back wherever it came from.
func _on_sub_screen_closed() -> void:
	if _returns_to_pause:
		_returns_to_pause = false
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


# --- debug menu ------------------------------------------------------------
# Everything below is developer convenience and never runs in a release build.

## What the overworld currently believes, for the debug readout. Built here
## rather than reached for, so the menu stays a menu.
func _debug_state() -> Dictionary:
	var symbol := _map.terrain_at(_player.global_position)
	var hp := PackedStringArray()
	for creature in Party.members:
		hp.append("%s %d/%d" % [creature.display_name(), creature.current_hp, creature.max_hp()])
	return {
		"map": _map.id,
		"tile": str(_map.tile_at(_player.global_position)),
		"terrain": symbol,
		"chance": "%.0f%%" % (_map.encounter_chance(symbol) * 100.0),
		"reward": str(_map.coin_reward),
		"coin": str(Inventory.coin),
		"party": " | ".join(hp) if not hp.is_empty() else "empty",
	}


func _on_debug_command(id: String) -> void:
	match id:
		"restore":
			Party.restore_all()
		"coin":
			Inventory.coin += 200
		"items":
			for item_id in ["tempering_draught", "knitbone_salve", "waking_root"]:
				Inventory.add(item_id, 5)
		"recruit":
			_debug_recruit()
		"level":
			_debug_level_up()
		"encounter":
			_debug_encounter()
			return  # the encounter closes the menu itself
		_:
			if id.begins_with("goto_"):
				_debug_goto(id.trim_prefix("goto_"))
				return
	_debug_menu.show_state(_debug_state())


## Cycles through the roster so repeated presses build a varied party rather
## than six of the same thing.
func _debug_recruit() -> void:
	var roster := Content.species_ids()
	if roster.is_empty():
		return
	var pick := roster[Party.size() % roster.size()]
	var creature := Creature.create(pick, 12)
	if not Party.add(creature):
		Storage.deposit(creature)


func _debug_level_up() -> void:
	for creature in Party.members:
		var target := Creature.experience_for_level(mini(creature.level + 3, SpeciesData.MAX_LEVEL))
		creature.gain_experience(maxi(0, target - creature.experience))


## Uses whatever is under the player if it spawns anything, else the first
## terrain this map declares -- so it works standing on a path.
func _debug_encounter() -> void:
	var symbol := _map.terrain_at(_player.global_position)
	if _map.encounter_chance(symbol) <= 0.0:
		var declared := _map.encounter_symbols()
		if declared.is_empty():
			_debug_menu.show_state(_debug_state())
			return
		symbol = declared[0]
	_debug_menu.dismiss()
	# Handed back first: _begin_encounter takes it again if a fight actually
	# starts, and bails early if it cannot -- leaving the player frozen with
	# the menu already gone if input were left disabled.
	_player.input_enabled = true
	_last_position = _player.global_position
	_begin_encounter(symbol)


func _debug_goto(map_id: String) -> void:
	_debug_menu.dismiss()
	_load_map(map_id, null)
	_player.input_enabled = true
	_tracker.start_grace()


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

	# Gated on the menu lock like the two above it. Without that, closing with
	# F1 re-enables input in the same physics frame the press is still "just
	# pressed" in, and the menu reopens instantly -- § 15's debounce bug, in a
	# third place, because a new menu was added without applying the rule.
	if OS.is_debug_build() and _menu_lock <= 0.0 \
			and Input.is_action_just_pressed("debug_menu"):
		_debug_menu.show_state(_debug_state())
		_debug_menu.open_menu()
		return

	var moved := _player.global_position.distance_to(_last_position)
	_last_position = _player.global_position
	if moved <= 0.0:
		return

	if _warp_locked and _map.tile_at(_player.global_position) != _warp_arrival:
		_warp_locked = false
	if not _warp_locked:
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
		# Deliberately *not* restored. Losing used to hand back full health and
		# refilled moves, which made a defeat cost nothing you could feel --
		# the coin penalty was invisible and everything else was undone by the
		# time you looked. Your creatures stay down; a spring is free and an
		# encounter cannot start while the whole party is fainted, so the walk
		# back is always safe. See docs/DESIGN.md § 27.
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
			"What you carry is still down, and lighter by whatever it cost to drag you here.",
			"There is water not far off. There usually is.",
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
