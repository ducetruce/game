extends CanvasLayer
## A buy screen. Lists items an interactable's catalog sells, spends coin from
## Inventory on confirm.
##
## Owns no game state beyond the cursor -- Inventory is the source of truth for
## coin and what the player owns, exactly like DialogueBox owns no game state
## beyond which page is showing.

signal opened
signal closed

var _catalog := PackedStringArray()
var _cursor := 0

@onready var _panel: Panel = $Panel
@onready var _coin_label: Label = $Panel/CoinLabel
@onready var _list: RichTextLabel = $Panel/ListText
@onready var _detail: RichTextLabel = $Panel/DetailText

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_CANT_AFFORD := "8a5a5a"


func _ready() -> void:
	_panel.hide()
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _panel.visible


func open_with(catalog: PackedStringArray) -> void:
	if catalog.is_empty() or is_open():
		return
	_catalog = catalog
	_cursor = 0
	_panel.show()
	_refresh()
	set_process_unhandled_input(true)
	opened.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("move_down"):
		_cursor = wrapi(_cursor + 1, 0, _catalog.size())
		_refresh()
	elif event.is_action("move_up"):
		_cursor = wrapi(_cursor - 1, 0, _catalog.size())
		_refresh()
	elif event.is_action("interact"):
		_buy_selected()
	elif event.is_action("cancel"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()


func _buy_selected() -> void:
	if _cursor >= _catalog.size():
		return
	var item_id := _catalog[_cursor]
	if Inventory.purchase(item_id):
		_refresh()
	else:
		var item := Content.get_item(item_id)
		var name := item.display_name if item != null else item_id
		_detail.text = "[color=#%s]Not enough coin for %s.[/color]" % [COLOR_CANT_AFFORD, name]


func _refresh() -> void:
	_coin_label.text = "%d coin" % Inventory.coin

	var rows := PackedStringArray()
	for i in _catalog.size():
		var item := Content.get_item(_catalog[i])
		if item == null:
			continue
		var affordable := Inventory.coin >= item.price
		var colour := COLOR_SELECTED if i == _cursor else (COLOR_TEXT if affordable else COLOR_CANT_AFFORD)
		rows.append("[color=#%s]%s %-18s %3d coin  (have %d)[/color]" % [
			colour, ">" if i == _cursor else " ", item.display_name, item.price,
			Inventory.count(item.id),
		])
	_list.text = "\n".join(rows)

	if _cursor < _catalog.size():
		var selected := Content.get_item(_catalog[_cursor])
		if selected != null:
			_detail.text = "[color=#%s]%s[/color]" % [COLOR_DIM, selected.description]


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	await get_tree().physics_frame
	closed.emit()
