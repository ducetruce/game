extends SceneTree
## Plays the game at random for a long time and complains if it gets stuck.
##
## Run it with tools/soak.sh, which also fails the run on any engine error the
## play-through prints.
##
## Every menu bug this project has shipped had the same shape: input goes away
## and never comes back, or a menu reopens on the frame it closed and no key
## gets you out. Both are invisible to a unit test that calls open_menu() and
## close_menu() in sequence, and both are obvious within seconds to anyone
## holding a key down. So this holds keys down -- real InputEventKey presses,
## the same ones a keyboard sends -- and watches for the player losing control
## of the game for longer than any menu could justify.
##
## It asserts almost nothing about *what* happens, on purpose. A soak test that
## demands specific outcomes from random input is a soak test that gets
## loosened until it passes. This one demands only that the game keeps
## responding, and reports what the run actually did so a pass that did nothing
## is visible as one.

const OVERWORLD := "res://scenes/overworld/overworld.tscn"
const SAVE_PATH := "user://savegame.json"

## Counted in physics frames, which is what the game itself runs on. A -s
## script's own _process is called as fast as the machine can loop, so an
## earlier version of this counted its own iterations and "3000 frames" bought
## four seconds of walking -- the run looked long and covered nothing.
## Overridable from the command line for a longer soak.
const DEFAULT_FRAMES := 12000

## Headless still steps physics against the wall clock, so a soak of any
## useful length would run in real time. Raising the tick rate and scaling
## time by the same factor fast-forwards the whole simulation: four times as
## many steps per second, each one still a normal 1/60s step as far as every
## piece of game code is concerned.
const SPEEDUP := 4
const BASE_TICKS_PER_SECOND := 60

## How long the player may legitimately have no control. Menus are the common
## case and every one of them closes on a single cancel press, which the input
## stream sends constantly -- so anything past a few seconds of frames is a
## lockout, not a menu. Battles get their own, far looser budget: a battle
## legitimately holds the overworld for as long as it lasts, and its own
## termination is battle_sim's job, not this one's.
const MENU_STUCK_FRAMES := 400
const BATTLE_STUCK_FRAMES := 30000

## A battle under constant mashing should be over well inside this. The
## generous lockout budget above exists because a battle legitimately holds
## the overworld for as long as it lasts, but it is so generous that a battle
## which cannot progress at all hides under it: a forced-switch menu that
## opened its cursor on the creature that had just fainted, so that confirm
## refused forever, ran 7794 frames and passed. With that fixed, battles finish inside 250
## frames under mashing, so this sits ten times clear of them. It is the
## narrower question
## -- not "is the player locked out" but "is this battle getting anywhere".
const BATTLE_LENGTH_CAP := 2500

## Keys, by physical keycode, weighted the way a player's hands are: mostly
## walking, with confirm and cancel mixed in often enough to work every menu
## the walking opens. Only one direction is held at a time; the diagonal case
## is movement's problem, not this test's.
const KEY_W := 87
const KEY_S := 83
const KEY_A := 65
const KEY_D := 68
const KEY_Z := 90
const KEY_X := 88
const KEY_M := 77
const KEY_SHIFT := 4194325
const KEY_F1 := 4194332

const WEIGHTED_KEYS := [
	KEY_W, KEY_W, KEY_W, KEY_W, KEY_W, KEY_W,
	KEY_S, KEY_S, KEY_S, KEY_S, KEY_S, KEY_S,
	KEY_A, KEY_A, KEY_A, KEY_A, KEY_A,
	KEY_D, KEY_D, KEY_D, KEY_D, KEY_D,
	KEY_SHIFT, KEY_SHIFT, KEY_SHIFT,
	KEY_Z, KEY_Z, KEY_Z,
	KEY_X,
	KEY_M,
	KEY_F1,
]

## How long the soak waits for its own shuffle to throw up a back-out key
## before pressing one deliberately. Left to chance, a run spends most of its
## time sitting in a menu waiting for X to come around, which buys no coverage
## and forces the lockout budget above to be so slack that a real lockout fits
## comfortably inside it. Nudging alternates cancel and confirm, since some
## screens only leave on one of them -- mostly confirm, because two screens
## that each back out into the other would oscillate forever on a strict
## alternation and the battle's Fight / move pair is exactly that shape.
const NUDGE_AFTER_FRAMES := 45
const NUDGE_CANCEL_EVERY := 4

## Random walking finds warps about as often as it finds anything else, which
## is to say rarely: three seeds in a row never left the first map. So the
## soak moves itself on periodically, through the same debug command the F1
## menu uses. The map list is read off disk rather than named here, so a map
## added later is soaked without anyone remembering to add it.
const TRAVEL_EVERY_FRAMES := 1500
const MAPS_DIR := "res://scenes/overworld/maps"

## A burst is one key held for a few frames, then released. Short bursts mash;
## long ones walk somewhere.
## Long enough to actually cross a map: at walking pace a 40-frame burst is
## four tiles, and a random walk in four-tile steps never leaves the corner it
## started in. An earlier version of this walked 5000px without once reaching
## the bracken, and reported a clean run for a game it had never seen fight.
const BURST_MIN := 6
const BURST_MAX := 150

var _rng := RandomNumberGenerator.new()
var _overworld: Node = null
var _player: Node = null

var _frames := 0
var _total_frames := DEFAULT_FRAMES
var _last_physics_frame := -1
var _held := 0
var _burst_left := 0

var _frozen_for := 0
var _nudges := 0
var _returns_to_title := 0
var _map_ids := PackedStringArray()
var _travels := 0
## Trips that have come due and not yet happened. A count rather than a flag:
## the moment one falls on is as likely as not to be mid-battle, and a long
## battle can span three due points -- which a flag collapses into one trip,
## leaving maps unvisited through no fault of the game.
var _travels_due := 0
var _reported := false
var _worst_freeze := 0
var _failures: Array[String] = []

var _distance := 0.0
var _last_position := Vector2.ZERO
var _maps_seen := {}
var _battles := 0
var _in_battle := false
var _battle_frames := 0
var _worst_battle := 0
var _menu_frames := 0

## Which screens the player spent frames locked behind, so a run that spends
## most of its time stuck in one menu says which one rather than just
## reporting a large number.
const MENU_NODES := [
	"DialogueBox", "ShopMenu", "PartyMenu", "PauseMenu",
	"BagMenu", "StorageMenu", "DebugMenu",
]
var _menu_tally := {}
var _menu_opens := 0
var _last_menu := ""


func _initialize() -> void:
	var seed_value := int(Time.get_unix_time_from_system())
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			_total_frames = maxi(1, int(argument.trim_prefix("--frames=")))
		elif argument.begins_with("--seed="):
			seed_value = int(argument.trim_prefix("--seed="))
	_rng.seed = seed_value
	Engine.physics_ticks_per_second = BASE_TICKS_PER_SECOND * SPEEDUP
	Engine.time_scale = SPEEDUP
	print("soak: %d physics frames (%.0fs of play), seed %d"
		% [_total_frames, float(_total_frames) / BASE_TICKS_PER_SECOND, seed_value])


## Deliberately not done in _initialize(): a -s script runs that before the
## autoloads' _ready, so Content has parsed nothing yet and seeding a party
## there fails with "No creature with id" on every starter. By the first
## processed frame they are all up.
func _start() -> void:
	# A save left by an earlier run would boot this one into whatever map that
	# run wandered into, which quietly makes two soaks test the same half of
	# the game. Start every run from a new game.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	var save_game := root.get_node_or_null("SaveGame")
	if save_game != null:
		save_game.has_save = false
	root.get_node("Party").reset_for_new_game()
	root.get_node("Storage").reset_for_new_game()
	root.get_node("Inventory").reset_for_new_game()
	root.get_node("Journal").reset_for_new_game()

	_map_ids = _read_map_ids()
	print("soak: %d map(s) to visit: %s" % [_map_ids.size(), ", ".join(_map_ids)])
	_enter_overworld()


func _enter_overworld() -> void:
	# Whatever scene is up (the title, on the way back in) goes first, or two
	# scenes process input at once and the soak drives both.
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.free()
	var packed: PackedScene = load(OVERWORLD)
	_overworld = packed.instantiate()
	root.add_child(_overworld)
	# UiFit and anything else that walks the active scene needs this set; a
	# scene merely parented to the root is not the current one.
	current_scene = _overworld
	_player = _overworld.get_node("Player")
	_last_position = _player.global_position
	_frozen_for = 0
	if _held != 0:
		_send(_held, false)
		_held = 0
	_burst_left = 1


func _process(_delta: float) -> bool:
	if _overworld == null:
		_start()
		return false
	if not is_instance_valid(_overworld) or not is_instance_valid(_player):
		# Not a failure: "quit to title" is a real menu option and random
		# input finds it. Walk back in and keep playing, rather than ending
		# the run early and calling the two minutes it did manage a pass.
		_returns_to_title += 1
		_enter_overworld()
		return false

	# One tick per physics frame, not per loop iteration: the game moves,
	# times out menus and rolls encounters on physics frames, so a burst
	# measured in anything else is a burst of unpredictable length.
	var physics := Engine.get_physics_frames()
	if physics == _last_physics_frame:
		return false
	_last_physics_frame = physics

	_frames += 1
	_drive_input()
	_observe()
	if _frames % TRAVEL_EVERY_FRAMES == 0:
		_travels_due += 1
	if _travels_due > 0:
		_travel()

	if _frames >= _total_frames:
		_report()
		return true
	return false


## One key at a time, held for a burst of frames and then released. Holding is
## the point: an InputEventAction sets "just pressed" but never leaves the
## Input singleton in a held state, so a test built on those never walks
## anywhere and never reproduces anything that needs sustained movement.
func _drive_input() -> void:
	if _frozen_for > NUDGE_AFTER_FRAMES:
		_nudge()
		return
	if _burst_left > 0:
		_burst_left -= 1
		return
	if _held != 0:
		_send(_held, false)
		_held = 0
		# One idle frame between bursts, so a press and its release are never
		# collapsed into the same input flush.
		_burst_left = 1
		return
	_held = WEIGHTED_KEYS[_rng.randi_range(0, WEIGHTED_KEYS.size() - 1)]
	_send(_held, true)
	_burst_left = _rng.randi_range(BURST_MIN, BURST_MAX)


## Releases whatever is held and taps a back-out key. Repeats for as long as
## the player has no control, which is exactly the hammering a menu that
## reopens on the frame it closes needs to be caught by.
func _nudge() -> void:
	if _held != 0:
		_send(_held, false)
		_held = 0
		_burst_left = 1
		return
	if _burst_left > 0:
		_burst_left -= 1
		return
	_nudges += 1
	_held = KEY_X if _nudges % NUDGE_CANCEL_EVERY == 0 else KEY_Z
	_send(_held, true)
	_burst_left = 3


## Jumps to another map, but only from a clean standing start: mid-battle or
## mid-fade the overworld is in the middle of something, and yanking the map
## out from under it would be testing a situation the game cannot be put into
## by playing.
func _travel() -> void:
	if _map_ids.is_empty() or _in_battle or not bool(_player.get("input_enabled")):
		return
	# Somewhere not yet seen, if there is one. Picking uniformly at random
	# made "every map was visited" a coin flip rather than an assertion: four
	# random draws over four maps miss one more often than not.
	var unseen := PackedStringArray()
	for map_id in _map_ids:
		if not _maps_seen.has(map_id):
			unseen.append(map_id)
	var pool := unseen if not unseen.is_empty() else _map_ids
	var pick := pool[_rng.randi_range(0, pool.size() - 1)]
	if pick == _map_id():
		return
	_travels_due -= 1
	_travels += 1
	_overworld.call("_on_debug_command", "goto_" + pick)


func _read_map_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return ids
	for file_name in dir.get_files():
		# Exported projects hand back the imported name; strip either.
		var base := file_name.trim_suffix(".remap").trim_suffix(".tscn")
		if not base.is_empty():
			ids.append(base)
	return ids


func _send(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _observe() -> void:
	var position: Vector2 = _player.global_position
	_distance += position.distance_to(_last_position)
	_last_position = position

	var map = _overworld.get("_map")
	if map != null and is_instance_valid(map):
		_maps_seen[map.id] = true

	var battle = _overworld.get("_battle")
	var fighting := battle != null and is_instance_valid(battle)
	if fighting and not _in_battle:
		_battles += 1
	if fighting:
		_battle_frames += 1
		_worst_battle = maxi(_worst_battle, _battle_frames)
		if _battle_frames == BATTLE_LENGTH_CAP:
			_fail("a battle has run %d frames without ending (frame %d, map %s)"
				% [_battle_frames, _frames, _map_id()])
	if fighting != _in_battle:
		_battle_frames = 0
		# The two states have very different budgets below, so a freeze that
		# began in one must not be judged against the other's. Without this a
		# long battle "fails" the instant it ends, because its frames are
		# still on the counter when the menu budget takes over.
		_frozen_for = 0
	_in_battle = fighting

	if bool(_player.get("input_enabled")):
		_frozen_for = 0
		return

	if not fighting:
		_menu_frames += 1
		var name := _open_menu_name()
		_menu_tally[name] = int(_menu_tally.get(name, 0)) + 1
		if name != _last_menu:
			_menu_opens += 1
		_last_menu = name
	else:
		_last_menu = ""
	_frozen_for += 1
	_worst_freeze = maxi(_worst_freeze, _frozen_for)
	var budget := BATTLE_STUCK_FRAMES if fighting else MENU_STUCK_FRAMES
	if _frozen_for > budget:
		_fail("the player has had no control for %d frames (frame %d, map %s, %s)"
			% [_frozen_for, _frames, _map_id(),
				"in a battle" if fighting else "not in a battle"])
		# Reset rather than reporting the same lockout once per frame for the
		# rest of the run.
		_frozen_for = 0


## The first open screen, or a marker for "nobody is admitting to being open",
## which is itself worth seeing: it means input was taken away by something
## other than a menu and not given back.
func _open_menu_name() -> String:
	for node_name in MENU_NODES:
		var node := _overworld.get_node_or_null(node_name)
		if node != null and node.has_method("is_open") and node.is_open():
			return node_name
	return "<no menu open>"


func _map_id() -> String:
	var map = _overworld.get("_map")
	if map == null or not is_instance_valid(map):
		return "<none>"
	return str(map.id)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("soak: " + message)


## Called on every exit path, including the ones the soak does not choose:
## the title screen's Quit ends the process outright, and a run that dies
## there without a word looks exactly like a run that passed.
func _finalize() -> void:
	_report()


## Whether every map was visited -- but only when the run actually had the
## chances to. Asserted unconditionally, a short soak fails for being short;
## skipped silently, a short soak claims a coverage it never attempted, so
## both cases say so out loud.
##
## Its own function rather than a block inside the report, because as a block
## it returned early on the "not checked" path and skipped printing the
## result line -- which the wrapper reads, so a run that was merely short
## looked like a run that crashed.
func _check_coverage() -> void:
	if _total_frames < TRAVEL_EVERY_FRAMES * _map_ids.size():
		print("soak: too short to expect every map (needs %d frames); coverage not checked"
			% (TRAVEL_EVERY_FRAMES * _map_ids.size()))
		return
	if _travels + 1 < _map_ids.size():
		print("soak: only %d trip(s) happened, most of the run went elsewhere; coverage not checked"
			% _travels)
		return
	for map_id in _map_ids:
		if not _maps_seen.has(map_id):
			_fail("never set foot in '%s'" % map_id)


func _report() -> void:
	if _reported:
		return
	_reported = true
	if _frames < _total_frames:
		_fail("the run ended on frame %d of %d" % [_frames, _total_frames])
	var maps: Array = _maps_seen.keys()
	maps.sort()
	print("soak: walked %.0fpx across %d map(s) (%s), %d deliberate trip(s)"
		% [_distance, maps.size(), ", ".join(maps), _travels])
	_check_coverage()
	print("soak: %d battle(s), longest %d frame(s); %d frame(s) with a menu up, longest freeze %d"
		% [_battles, _worst_battle, _menu_frames, _worst_freeze])
	print("soak: %d screen opening(s), %d nudge(s) to get back out, %d trip(s) to the title"
		% [_menu_opens, _nudges, _returns_to_title])
	var tally: Array = _menu_tally.keys()
	tally.sort()
	for node_name in tally:
		print("soak:   %6d frame(s) behind %s" % [int(_menu_tally[node_name]), node_name])
	if _failures.is_empty():
		print("soak: OK")
	else:
		for message in _failures:
			print("soak: FAIL " + message)
	# Communicated through the log rather than an exit code: a -s script's
	# return value is not the process's, and tools/soak.sh reads for this.
	print("soak: result %s" % ("pass" if _failures.is_empty() else "fail"))
