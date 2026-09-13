extends Control
## The game's front door: Continue, New Game, Quit.
##
## This exists mostly so starting over is reachable without deleting a file by
## hand. The overworld still decides for itself whether to load a save (see
## Overworld._ready) -- all this screen does is decide whether a save should
## still be there when it looks, and reset the autoloads that outlive a scene
## change when it should not be.

const OVERWORLD_SCENE := "res://scenes/overworld/overworld.tscn"

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_WARN := "c4614f"

## Background palette. Placeholder art, drawn in code like the rest of it
## until real art lands -- see docs/DESIGN.md § 6.
const SKY_TOP := Color("11141c")
const SKY_LOW := Color("1d2230")
const WATER := Color("161b26")
const WATER_GLINT := Color("2a3446")
const TREELINE := Color("0b0d13")
const HORIZON := 118.0

enum Mode { MAIN, CONFIRM_NEW }
enum Choice { CONTINUE, NEW_GAME, QUIT }

var _mode: Mode = Mode.MAIN
var _cursor := 0
## Choice values, built at _ready: Continue only exists if a save does.
var _choices: Array[int] = []
## Starts on the answer that changes nothing. A destructive action should
## never be one keypress away from a player who is mashing to skip.
var _confirm_cursor := 1

@onready var _menu: RichTextLabel = $Menu
@onready var _prompt: RichTextLabel = $Prompt
@onready var _footer: RichTextLabel = $Footer


func _ready() -> void:
	_build_choices()
	_refresh()


func _build_choices() -> void:
	_choices.clear()
	if SaveGame.has_save:
		_choices.append(Choice.CONTINUE)
	_choices.append(Choice.NEW_GAME)
	_choices.append(Choice.QUIT)
	_cursor = 0


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not _handles(event):
		return
	# Marked handled *before* acting on it: confirming a choice changes the
	# scene, and get_viewport() is null the moment this node leaves the tree.
	get_viewport().set_input_as_handled()
	_act_on(event)


func _handles(event: InputEvent) -> bool:
	if event.is_action("move_up") or event.is_action("move_down"):
		return true
	if event.is_action("interact"):
		return true
	return _mode == Mode.CONFIRM_NEW and event.is_action("cancel")


func _act_on(event: InputEvent) -> void:
	if _mode == Mode.MAIN:
		if event.is_action("move_down"):
			_cursor = wrapi(_cursor + 1, 0, _choices.size())
			_refresh()
		elif event.is_action("move_up"):
			_cursor = wrapi(_cursor - 1, 0, _choices.size())
			_refresh()
		else:
			_activate()
		return

	if event.is_action("cancel"):
		_leave_confirm()
	elif event.is_action("interact"):
		_answer_confirm()
	else:
		_confirm_cursor = 1 - _confirm_cursor
		_refresh()


func _activate() -> void:
	match _choices[_cursor]:
		Choice.CONTINUE:
			_enter_overworld()
		Choice.NEW_GAME:
			# Only destructive if there is something to destroy.
			if SaveGame.has_save:
				_mode = Mode.CONFIRM_NEW
				_confirm_cursor = 1
				_refresh()
			else:
				_begin_new_game()
		Choice.QUIT:
			get_tree().quit()


func _answer_confirm() -> void:
	if _confirm_cursor == 0:
		_begin_new_game()
	else:
		_leave_confirm()


func _leave_confirm() -> void:
	_mode = Mode.MAIN
	_refresh()


## Party and Inventory are autoloads, so they survive the scene change into
## the overworld and would otherwise carry the previous run's creatures and
## coin into a "new" game. Erasing the save file alone is not enough.
func _begin_new_game() -> void:
	SaveGame.erase()
	Party.reset_for_new_game()
	Inventory.reset_for_new_game()
	_enter_overworld()


func _enter_overworld() -> void:
	get_tree().change_scene_to_file(OVERWORLD_SCENE)


func _refresh() -> void:
	if _mode == Mode.MAIN:
		_prompt.text = ""
		_footer.text = _centered("W/S select     Z confirm", COLOR_DIM)
		var rows := PackedStringArray()
		for i in _choices.size():
			rows.append(_row(_label_for(_choices[i]), i == _cursor))
		_menu.text = "\n".join(rows)
		return

	_prompt.text = "%s\n%s" % [
		_centered("This erases your saved game.", COLOR_WARN),
		_centered("There is only one, and it cannot be undone.", COLOR_DIM),
	]
	_footer.text = _centered("W/S select     Z confirm     X back", COLOR_DIM)
	_menu.text = "\n".join(PackedStringArray([
		_row("Erase it and start over", _confirm_cursor == 0),
		_row("Keep my game", _confirm_cursor == 1),
	]))


func _label_for(choice: int) -> String:
	match choice:
		Choice.CONTINUE:
			return "Continue"
		Choice.NEW_GAME:
			return "New Game"
		_:
			return "Quit"


func _row(label: String, selected: bool) -> String:
	if selected:
		return _centered("> %s <" % label, COLOR_SELECTED)
	return _centered(label, COLOR_TEXT)


func _centered(text: String, colour: String) -> String:
	return "[center][color=#%s]%s[/color][/center]" % [colour, text]


func _draw() -> void:
	var w := size.x
	var h := size.y

	# Flat bands rather than a true gradient: it reads cleaner at 320x180 and
	# matches the flat-shaded look of the tile art.
	var bands := 10
	for i in bands:
		var t := float(i) / float(bands - 1)
		draw_rect(
			Rect2(0.0, HORIZON * float(i) / float(bands), w, HORIZON / float(bands) + 1.0),
			SKY_TOP.lerp(SKY_LOW, t))

	draw_rect(Rect2(0.0, HORIZON, w, h - HORIZON), WATER)

	# Fixed seed so the shoreline is the same every boot.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260913

	for i in 16:
		draw_rect(Rect2(
			rng.randf() * w,
			HORIZON + 4.0 + rng.randf() * (h - HORIZON - 8.0),
			6.0 + rng.randf() * 24.0,
			1.0), WATER_GLINT)

	for i in 44:
		var tx := -4.0 + float(i) * (w + 8.0) / 44.0
		var tall := 9.0 + rng.randf() * 15.0
		var wide := 5.0 + rng.randf() * 4.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(tx - wide * 0.5, HORIZON),
			Vector2(tx, HORIZON - tall),
			Vector2(tx + wide * 0.5, HORIZON),
		]), TREELINE)
