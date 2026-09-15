extends CanvasLayer
## Fast travel: every rest spring the player has ever reached, free and
## instant. See docs/DESIGN.md § 41.
##
## Unlike the quest log, this one acts: confirming a row does not just show
## detail, it leaves. The actual warp is the overworld's to carry out (same
## division every screen here uses -- this emits, Overworld owns _begin_warp)
## so this never touches _map or _player directly.

signal opened
signal closed
## Emitted on confirm. Overworld looks the id up in Content.springs for the
## map and tile, since this screen has no reason to know either.
signal travel_requested(spring_id: String)

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_HEAD := "8fb4d9"

## Rows the list box holds at once -- same windowing every list screen in the
## game uses once its contents can outgrow a fixed box (§ 29). Matches the
## quest log's own box size, copied as-is from quest_log.tscn.
const VISIBLE_ROWS := 5

var _cursor := 0
var _scroll := 0
## Spring ids in the order shown, which is Content.springs' own declaration
## order (stable, and the same order the data was authored in) filtered down
## to the ones actually reached.
var _shown := PackedStringArray()

@onready var _panel: Panel = $Panel
@onready var _title: Label = $Panel/Title
@onready var _list: RichTextLabel = $Panel/ListText
@onready var _detail: RichTextLabel = $Panel/DetailText
@onready var _footer: RichTextLabel = $Panel/Footer


func _ready() -> void:
	_panel.hide()
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _panel.visible


func open_menu() -> void:
	if is_open():
		return
	_shown = Journal.visited_spring_ids()
	_cursor = 0
	_scroll = 0
	_panel.show()
	_render()
	set_process_unhandled_input(true)
	opened.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("move_down"):
		_move(1)
	elif event.is_action("move_up"):
		_move(-1)
	elif event.is_action("interact"):
		_confirm()
	elif event.is_action("cancel") or event.is_action("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	if _shown.is_empty():
		return
	_cursor = wrapi(_cursor + delta, 0, _shown.size())
	_render()


func _confirm() -> void:
	if _shown.is_empty():
		return
	var spring_id := _shown[_cursor]
	_panel.hide()
	set_process_unhandled_input(false)
	# No closed signal here: unlike backing out, this hands off to a warp
	# already underway rather than to the screen it was opened from, and
	# Overworld's own transition takes input back on its own schedule.
	travel_requested.emit(spring_id)


func _render() -> void:
	_title.text = "Travel"

	if _shown.is_empty():
		_list.text = "[color=#%s]Nowhere you've rested is still standing behind you.[/color]" % COLOR_DIM
		_detail.text = "[color=#%s]Find a spring, and you can come back to it from here.[/color]" % COLOR_DIM
		_footer.text = "[color=#%s]X to close[/color]" % COLOR_DIM
		return

	var rows := PackedStringArray()
	for i in _shown.size():
		var spring_id := _shown[i]
		var colour := COLOR_SELECTED if i == _cursor else COLOR_TEXT
		rows.append("[color=#%s]%s %-20s %s[/color]" % [
			colour, ">" if i == _cursor else " ", _name_of(spring_id),
			Content.map_name(_map_of(spring_id)),
		])
	_set_list(rows)

	_detail.text = "[color=#%s]Go there now.[/color]" % COLOR_HEAD
	_footer.text = "[color=#%s]W/S choose    Z travel    X close[/color]" % COLOR_DIM


## Same windowing as the bag, the quest log, and the battle menu: show what
## fits, follow the cursor, mark the rows being hidden.
func _set_list(rows: PackedStringArray) -> void:
	if rows.size() <= VISIBLE_ROWS:
		_scroll = 0
		_list.text = "\n".join(rows)
		return

	if _cursor < _scroll:
		_scroll = _cursor
	elif _cursor >= _scroll + VISIBLE_ROWS:
		_scroll = _cursor - VISIBLE_ROWS + 1
	_scroll = clampi(_scroll, 0, rows.size() - VISIBLE_ROWS)

	var shown := PackedStringArray()
	for i in range(_scroll, _scroll + VISIBLE_ROWS):
		shown.append(rows[i])
	if _scroll > 0:
		shown[0] += " [color=#%s]^[/color]" % COLOR_DIM
	if _scroll + VISIBLE_ROWS < rows.size():
		shown[VISIBLE_ROWS - 1] += " [color=#%s]v[/color]" % COLOR_DIM
	_list.text = "\n".join(shown)


func _spring(spring_id: String) -> Dictionary:
	for spring in Content.springs:
		if str(spring.get("id", "")) == spring_id:
			return spring
	return {}


func _name_of(spring_id: String) -> String:
	var name := str(_spring(spring_id).get("name", ""))
	return name if not name.is_empty() else spring_id


func _map_of(spring_id: String) -> String:
	return str(_spring(spring_id).get("map_id", ""))


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	await get_tree().physics_frame
	closed.emit()
