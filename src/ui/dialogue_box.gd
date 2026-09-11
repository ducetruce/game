class_name DialogueBox
extends CanvasLayer
## Minimal text box. Shows one page at a time; interact or cancel advances.
##
## Owns no game state -- it is handed pages and reports when it opens and
## closes so whoever is driving can suspend input.

signal opened
signal closed

var _pages := PackedStringArray()
var _index := 0

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Margin/Text
@onready var _more: Label = $Panel/More


func _ready() -> void:
	_panel.hide()
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _panel.visible


func show_pages(pages: PackedStringArray) -> void:
	if pages.is_empty() or is_open():
		return
	_pages = pages
	_index = 0
	_panel.show()
	_refresh()
	set_process_unhandled_input(true)
	opened.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("interact") or event.is_action("cancel"):
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	_index += 1
	if _index >= _pages.size():
		_close()
	else:
		_refresh()


func _refresh() -> void:
	_label.text = _pages[_index]
	_more.visible = _index < _pages.size() - 1


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	# The keypress that closed the box is still "just pressed" for the rest of
	# this frame. Handing input back now would re-trigger the interaction that
	# opened it, so wait for the physics step to roll over first.
	await get_tree().physics_frame
	closed.emit()
