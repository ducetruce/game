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
@onready var _quest_log: Node = $QuestLog
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

## What the current battle is against, remembered here because the battle node
## is freed before its outcome is acted on.
var _battle_foe_species := ""

## The tamer the current battle is against, and the letters waiting for a
## quiet moment to be delivered.
var _pending_tamer := ""
## Index into Content.gauntlet_trials of the trial the current battle is for,
## or -1 when the current battle (if any) is not one. See "the gauntlet"
## section below.
var _pending_gauntlet_trial := -1
var _pending_letters: Array[String] = []

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
	_quest_log.opened.connect(_on_ui_opened)
	_quest_log.closed.connect(_on_sub_screen_closed)
	_storage_menu.opened.connect(_on_ui_opened)
	_storage_menu.closed.connect(_on_ui_closed)
	_pause_menu.opened.connect(_on_ui_opened)
	_pause_menu.closed.connect(_on_ui_closed)
	_pause_menu.party_requested.connect(_on_pause_party_requested)
	_pause_menu.bag_requested.connect(_on_pause_bag_requested)
	_pause_menu.quests_requested.connect(_on_pause_quests_requested)
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
	Journal.rematch_due.connect(_on_rematch_due)
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
	_map.quest_completed.connect(_on_quest_completed)
	_map.challenge_requested.connect(_on_challenge_requested)
	_map.gauntlet_challenge_requested.connect(_on_gauntlet_challenge_requested)
	_map.item_received.connect(_on_item_received)

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


func _on_pause_quests_requested() -> void:
	_returns_to_pause = true
	_quest_log.open_menu()


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
			# Read off Content rather than a fixed list -- a hardcoded roster
			# here has drifted stale before (only three of what were by then
			# five items), the same class of bug as an unreachable species.
			for item_id in Content.item_ids():
				Inventory.add(item_id, 5)
		"recruit":
			_debug_recruit()
		"level":
			_debug_level_up()
		"encounter":
			_debug_encounter()
			return  # the encounter closes the menu itself
		"unlock_gauntlet":
			Journal.debug_force_gauntlet_unlock()
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
	# Before every early return below. Play time is time spent in the world,
	# including the time spent standing in a menu deciding something -- what
	# it must not count is a game left running on the title screen, which is
	# why this is here and not in Journal's own _process.
	Journal.tick(delta)

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

	if not _pending_letters.is_empty():
		_deliver_letter()
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


# --- tamers ----------------------------------------------------------------

## Someone walked up to a tamer and pressed Z.
func _on_challenge_requested(tamer_id: String) -> void:
	var spec := _map.tamer_spec(tamer_id)
	if spec.is_empty() or _busy or _battle != null:
		return

	var who := str(spec.get("name", "A tamer"))
	if not Journal.will_fight(tamer_id):
		# Beaten and not yet due. They still have something to say -- a person
		# who beat you and then ignores you is worse than no person at all.
		_dialogue.show_pages(_pages(spec.get("beaten_text", [
			"%s looks up, and looks away again. Not today." % who,
		])))
		return

	var team := _tamer_team(spec)
	if team.is_empty():
		push_error("Overworld: tamer '%s' has no team to fight with." % tamer_id)
		return
	if not Party.has_any() or Party.all_fainted():
		_dialogue.show_pages(PackedStringArray([
			"%s looks at what you are carrying and decides against it." % who,
		]))
		return

	_pending_tamer = tamer_id
	_begin_tamer_battle(spec, team, who)


func _tamer_team(spec: Dictionary) -> Array:
	var team: Array = []
	for entry in spec.get("team", []):
		if not (entry is Dictionary):
			continue
		var creature := Creature.create(
			str(entry.get("species", "")), int(entry.get("level", 5)))
		if creature != null:
			team.append(creature)
	return team


func _begin_tamer_battle(spec: Dictionary, team: Array, who: String) -> void:
	_busy = true
	_player.input_enabled = false
	await _fade_to(1.0)

	var intro := _pages(spec.get("intro", ["%s steps into your way." % who]))
	if Journal.has_beaten(_pending_tamer):
		intro = _pages(spec.get("rematch_intro", [
			"%s is already unrolling a sleeve. They have thought about this." % who,
		]))

	_battle = BATTLE_SCENE.instantiate()
	_battle.configure_tamer(
		Party.members, team, who, int(spec.get("purse", 0)), intro)
	_battle.finished.connect(_on_battle_finished)
	_battle_layer.add_child(_battle)

	await _fade_to(0.0)
	_busy = false


# --- the gauntlet ------------------------------------------------------------
# See docs/DESIGN.md § 39. Trials are strictly ordered; Journal.gauntlet_stage
# is the index of the one still to attempt, and this section is the only
# place that reads or advances it in response to play.

## An elder in the gauntlet hall was approached.
func _on_gauntlet_challenge_requested(trial_id: String) -> void:
	if _busy or _battle != null:
		return
	var index := _gauntlet_trial_index(trial_id)
	if index < 0:
		push_error("Overworld: gauntlet trial '%s' is not in data/gauntlet.json." % trial_id)
		return
	var trial: Dictionary = Content.gauntlet_trials[index]
	var who := str(trial.get("name", "An elder"))

	if Journal.gauntlet_trial_passed_at(index):
		_dialogue.show_pages(_pages(trial.get("passed_text", [
			"%s has nothing more to prove between you." % who,
		])))
		return
	if index != Journal.gauntlet_stage:
		_dialogue.show_pages(_pages(trial.get("waiting_text", [
			"%s will not go before the one ahead of them." % who,
		])))
		return
	if not Party.has_any() or Party.all_fainted():
		_dialogue.show_pages(PackedStringArray([
			"%s looks at what you are carrying and decides against it." % who,
		]))
		return

	_pending_gauntlet_trial = index
	_begin_gauntlet_trial(trial)


func _gauntlet_trial_index(trial_id: String) -> int:
	for i in Content.gauntlet_trials.size():
		if str(Content.gauntlet_trials[i].get("id", "")) == trial_id:
			return i
	return -1


func _begin_gauntlet_trial(trial: Dictionary) -> void:
	_busy = true
	_player.input_enabled = false
	await _fade_to(1.0)

	var who := str(trial.get("name", "An elder"))
	var intro := _pages(trial.get("intro", ["%s is ready for you." % who]))
	var kind := str(trial.get("kind", ""))

	_battle = BATTLE_SCENE.instantiate()
	if kind == "tamer":
		var team := _tamer_team(trial)
		_battle.configure_tamer(
			Party.members, team, who, int(trial.get("purse", 0)), intro)
	else:
		var wild := Creature.create(str(trial.get("species", "")), int(trial.get("level", 5)))
		# Set the same way a roaming encounter sets it: an attune trial is a
		# formal wild encounter, so defeating it (rather than taming it)
		# should count toward a "defeated" quest requirement the same way any
		# other wild win does.
		_battle_foe_species = wild.species_id
		var no_flee_message := str(trial.get("no_flee_message", "There is nowhere to run to."))
		_battle.configure_gauntlet_attune(
			Party.members, wild, _coin_bracket(trial.get("coin_reward", [])),
			intro, no_flee_message)
	_battle.finished.connect(_on_battle_finished)
	_battle_layer.add_child(_battle)

	await _fade_to(0.0)
	_busy = false


## What actually happened at the end of a gauntlet trial, decided from the
## battle's own outcome plus which kind of trial it was: a tamer trial passes
## on WON, an attune trial passes only on ATTUNED -- defeating that one
## outright still ends the battle and still pays as any wild battle does, but
## does not clear the trial. Shows the trial's own text throughout rather than
## the generic wild-encounter lines _on_battle_finished would otherwise show,
## since none of those (a path, water nearby) mean anything inside the hall.
func _finish_gauntlet_trial(outcome: int) -> void:
	var index := _pending_gauntlet_trial
	_pending_gauntlet_trial = -1
	if index < 0 or index >= Content.gauntlet_trials.size():
		return
	var trial: Dictionary = Content.gauntlet_trials[index]
	var kind := str(trial.get("kind", ""))
	var passed := (
		(kind == "tamer" and outcome == BattleState.Phase.WON)
		or (kind == "attune" and outcome == BattleState.Phase.ATTUNED)
	)

	if passed:
		Journal.advance_gauntlet(index)
		_dialogue.append_pages(_pages(trial.get("victory", ["Passed."])))
		if Journal.gauntlet_finished_check():
			_dialogue.append_pages(Content.gauntlet_victory_text)
		return
	if outcome == BattleState.Phase.WON:
		# Only reachable for an attune trial: won by defeating rather than
		# taming, which this trial does not accept.
		_dialogue.append_pages(_pages(trial.get("spared", ["Not what was asked."])))
		return
	if outcome == BattleState.Phase.LOST:
		_dialogue.append_pages(_pages(trial.get("defeat", ["Try again."])))


## A pigeon, when a tamer has had long enough to want another go. Delivered
## wherever the player happens to be standing, because a notification you have
## to go somewhere to collect is not a notification.
func _on_rematch_due(tamer_id: String) -> void:
	_pending_letters.append(tamer_id)


## Shown at the first safe moment rather than the instant it fires: the player
## may be mid-battle, mid-fade or three pages into a conversation, and a
## pigeon that interrupts any of those is a bug.
func _deliver_letter() -> void:
	if _pending_letters.is_empty() or _busy or _battle != null \
			or not _player.input_enabled or _menu_lock > 0.0:
		return
	var tamer_id: String = _pending_letters[0]
	_pending_letters.remove_at(0)
	var spec := _map.tamer_spec(tamer_id)
	var who := str(spec.get("name", "Someone"))
	var body := _pages(spec.get("letter", [
		"Whatever you did to me, I have been practising against it. Come back. -- %s" % who,
	]))
	var pages := PackedStringArray([
		"A pigeon comes down hard on the fence rail beside you, with a paper on its leg.",
	])
	for line in body:
		pages.append(line)
	_dialogue.show_pages(pages)


## A [low, high] coin bracket from data/gauntlet.json, the same shape a map's
## own coin_reward is in. Zero on anything malformed, which BattleState.
## coin_award() already reads as "pays nothing" rather than erroring.
func _coin_bracket(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i.ZERO


func _pages(value: Variant) -> PackedStringArray:
	var pages := PackedStringArray()
	if value is PackedStringArray:
		return value
	for line in (value if value is Array else []):
		pages.append(str(line))
	return pages


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

	_battle_foe_species = wild.species_id
	_battle = BATTLE_SCENE.instantiate()
	# The party is passed by reference, so damage and experience stick.
	_battle.configure(Party.members, wild, _map.coin_reward,
		TileLegend.terrain_name(symbol))
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

	# Captured before _finish_gauntlet_trial clears it, so the generic
	# messaging below can be skipped for a trial without needing to guess from
	# the outcome alone -- a trial can end in WON, ATTUNED, or LOST, and only
	# the last of those overlaps the ordinary wild-encounter case.
	var was_gauntlet_trial := _pending_gauntlet_trial >= 0

	# Counted before the battle node goes, since the tally is keyed on what was
	# fought. "Slay this thing" is a quest shape and a step that asks for it
	# needs somewhere to count -- see docs/DESIGN.md § 34.
	if outcome == BattleState.Phase.WON and _battle_foe_species != "":
		Journal.record_defeat(_battle_foe_species)
	_battle_foe_species = ""
	if outcome == BattleState.Phase.WON and _pending_tamer != "":
		Journal.record_tamer_beaten(_pending_tamer)
	_pending_tamer = ""

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

	if was_gauntlet_trial:
		# Entirely its own messaging -- a path and water nearby mean nothing
		# standing in the gauntlet hall, and an attune trial can end in a way
		# ("won, but not by taming it") the generic wording below has no
		# concept of at all.
		_finish_gauntlet_trial(outcome)
	elif lost:
		_dialogue.show_pages(PackedStringArray([
			"You come to on the path, further back than you remember walking.",
			"What you carry is still down, and lighter by whatever it cost to drag you here.",
			"There is water not far off. There usually is.",
		]))


## Appends "you now have X" to whatever the object said. Queued onto the open
## dialogue rather than shown as its own box, so the sequence reads as one
## conversation.
func _on_item_received(item_id: String, count: int) -> void:
	var item := Content.get_item(item_id)
	var name := item.display_name if item != null else item_id
	var line := "[ %s -- %d ]" % [name, count] if count > 1 else "[ %s ]" % name
	_dialogue.append_page(line)


## Says what a finished quest paid. The map emits and knows nothing about coin
## or dialogue; this is the only place that puts the two together.
func _on_quest_completed(quest_id: String, reward: Dictionary) -> void:
	var lines := PackedStringArray()
	var coin := int(reward.get("coin", 0))
	var items: PackedStringArray = reward.get("items", PackedStringArray())
	var names := PackedStringArray()
	for item_id in items:
		var item := Content.get_item(str(item_id))
		names.append(item.display_name if item != null else str(item_id))

	var quest_name := quest_id
	for quest in Content.quests:
		if str(quest.get("id", "")) == quest_id:
			quest_name = str(quest.get("name", quest_id))
	lines.append("[ %s -- done ]" % quest_name)
	if coin > 0 and not names.is_empty():
		lines.append("You are %d coin better off, and carrying %s."
			% [coin, " and ".join(names)])
	elif coin > 0:
		lines.append("You are %d coin better off." % coin)
	elif not names.is_empty():
		lines.append("You are carrying %s." % " and ".join(names))

	var done := Journal.completed_count()
	var needed := Content.gauntlet_requirement
	if Journal.gauntlet_unlocked():
		lines.append("That is %d. The elders will hear you now." % done)
	else:
		lines.append("%d of the %d the elders count. %s to go."
			% [done, needed, needed - done])
	# Appended, not shown: the object that finished the quest has just opened
	# a conversation of its own, and show_pages() refuses over an open one.
	_dialogue.append_pages(lines)


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
