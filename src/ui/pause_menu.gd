extends CanvasLayer
## The overworld's pause menu: resume, look at the party, save, or leave for
## the title screen.
##
## Owns no game state. Saving needs the player's position and the active map,
## which only the Overworld knows, so this emits and lets the Overworld act --
## the same division every other menu here uses.

signal opened
signal closed
signal party_requested
signal save_requested
signal quit_to_title_requested

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_GOOD := "6fae74"
const COLOR_BAD := "c4614f"

enum Entry { RESUME, PARTY, SAVE, QUIT }

const ENTRIES := [Entry.RESUME, Entry.PARTY, Entry.SAVE, Entry.QUIT]

var _cursor := 0

@onready var _panel: Panel = $Panel
@onready var _menu: RichTextLabel = $Panel/Menu
@onready var _status: RichTextLabel = $Panel/Status


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
	_refresh()
	set_process_unhandled_input(true)
	opened.emit()


## Feedback for the Save entry, reported back by whoever actually wrote the
## file -- this menu has no way to know whether it worked.
func report_saved(ok: bool) -> void:
	if ok:
		_status.text = "[center][color=#%s]Saved.[/color][/center]" % COLOR_GOOD
	else:
		_status.text = "[center][color=#%s]Could not save.[/color][/center]" % COLOR_BAD


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not _handles(event):
		return
	# Consumed before acting: leaving for the title screen frees this node,
	# and get_viewport() is null once it is out of the tree. Same ordering as
	# TitleScreen, and for the same reason -- see docs/DESIGN.md § 17.
	get_viewport().set_input_as_handled()
	_act_on(event)


func _handles(event: InputEvent) -> bool:
	return event.is_action("move_up") or event.is_action("move_down") \
		or event.is_action("interact") or event.is_action("cancel")


func _act_on(event: InputEvent) -> void:
	if event.is_action("move_down"):
		_cursor = wrapi(_cursor + 1, 0, ENTRIES.size())
		_refresh()
	elif event.is_action("move_up"):
		_cursor = wrapi(_cursor - 1, 0, ENTRIES.size())
		_refresh()
	elif event.is_action("cancel"):
		_close()
	else:
		_choose()


func _choose() -> void:
	match ENTRIES[_cursor]:
		Entry.RESUME:
			_close()
		Entry.PARTY:
			# Hidden without emitting `closed`: the party screen is taking
			# over, so input must not go back to the player in between.
			_hide_panel()
			party_requested.emit()
		Entry.SAVE:
			save_requested.emit()
		Entry.QUIT:
			_hide_panel()
			quit_to_title_requested.emit()


func _refresh() -> void:
	var rows := PackedStringArray()
	for i in ENTRIES.size():
		var selected := i == _cursor
		var colour := COLOR_SELECTED if selected else COLOR_TEXT
		rows.append("[center][color=#%s]%s%s%s[/color][/center]" % [
			colour, "> " if selected else "", _label_for(ENTRIES[i]), " <" if selected else "",
		])
	_menu.text = "\n".join(rows)
	_status.text = "[center][color=#%s]W/S move   Z pick   X back[/color][/center]" % COLOR_DIM


func _label_for(entry: int) -> String:
	match entry:
		Entry.RESUME:
			return "Resume"
		Entry.PARTY:
			return "Party"
		Entry.SAVE:
			return "Save"
		_:
			return "Quit to Title"


func _hide_panel() -> void:
	_panel.hide()
	set_process_unhandled_input(false)


func _close() -> void:
	_hide_panel()
	await get_tree().physics_frame
	closed.emit()
