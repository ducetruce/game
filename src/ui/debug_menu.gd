extends CanvasLayer
## A developer menu: jump between maps, patch the party up, force a fight,
## and see what the overworld thinks is under your feet.
##
## Exists because every bug found so far was found by playing, and playing to
## the part you want to test meant walking three maps and grinding levels
## first. Shortening that loop finds more bugs than any amount of staring.
##
## Gated on OS.is_debug_build(), so it is simply absent from a release export
## rather than hidden behind a key someone might find. Owns no game state:
## it emits a command and the Overworld carries it out, like every other menu
## here.

signal opened
signal closed
signal command_chosen(id: String)

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_HEAD := "8fb4d9"

## id, label. Order is the order they appear.
const COMMANDS := [
	["goto_hollow_clearing", "Go to the Hollow Clearing"],
	["goto_village_square", "Go to Aldenmere"],
	["goto_mere_shore", "Go to the Hollowmere"],
	["restore", "Patch the party up"],
	["encounter", "Force an encounter"],
	["coin", "+200 coin"],
	["items", "Five of every item"],
	["recruit", "Add a Lv12 creature"],
	["level", "Party +3 levels"],
]

var _cursor := 0
var _state := {}

@onready var _panel: Panel = $Panel
@onready var _readout: RichTextLabel = $Panel/Readout
@onready var _menu: RichTextLabel = $Panel/Menu
@onready var _footer: RichTextLabel = $Panel/Footer


func _ready() -> void:
	_panel.hide()
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _panel.visible


func open_menu() -> void:
	if is_open():
		return
	_cursor = 0
	_panel.show()
	_render()
	set_process_unhandled_input(true)
	opened.emit()


## The overworld hands its own view of the world in, rather than this reaching
## across into it. Refreshed after every command so the readout never lags
## behind what the command just did.
func show_state(state: Dictionary) -> void:
	_state = state
	if is_open():
		_render()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not _handles(event):
		return
	get_viewport().set_input_as_handled()

	if event.is_action("move_down"):
		_cursor = wrapi(_cursor + 1, 0, COMMANDS.size())
		_render()
	elif event.is_action("move_up"):
		_cursor = wrapi(_cursor - 1, 0, COMMANDS.size())
		_render()
	elif event.is_action("interact"):
		command_chosen.emit(str(COMMANDS[_cursor][0]))
	else:
		_close()


func _handles(event: InputEvent) -> bool:
	return (event.is_action("move_up") or event.is_action("move_down")
		or event.is_action("interact") or event.is_action("cancel")
		or event.is_action("debug_menu"))


func _render() -> void:
	var rows := PackedStringArray()
	for i in COMMANDS.size():
		var selected := i == _cursor
		rows.append("[color=#%s]%s %s[/color]" % [
			COLOR_SELECTED if selected else COLOR_TEXT,
			">" if selected else " ", COMMANDS[i][1],
		])
	_menu.text = "\n".join(rows)

	_readout.text = "\n".join(PackedStringArray([
		"[color=#%s]%s[/color]  [color=#%s]tile %s   under foot '%s'[/color]" % [
			COLOR_HEAD, _state.get("map", "?"), COLOR_DIM,
			_state.get("tile", "?"), _state.get("terrain", "?"),
		],
		"[color=#%s]encounter here %s   pays %s   coin %s[/color]" % [
			COLOR_DIM, _state.get("chance", "?"),
			_state.get("reward", "?"), _state.get("coin", "?"),
		],
		"[color=#%s]party %s[/color]" % [COLOR_DIM, _state.get("party", "?")],
	]))
	_footer.text = "[color=#%s]W/S choose   Z run   X or F1 close[/color]" % COLOR_DIM


## Hides without emitting `closed`, for commands that take input over
## themselves -- a forced encounter or a jump between maps. Emitting would
## hand input back to the player in the frame before the command takes it.
func dismiss() -> void:
	_panel.hide()
	set_process_unhandled_input(false)


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	await get_tree().physics_frame
	closed.emit()
