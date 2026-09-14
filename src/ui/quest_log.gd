extends CanvasLayer
## What the player has been asked to do, what they are doing, and how close
## they are to the Elder's Gauntlet.
##
## Read-only, like the party screen: a quest moves because the player went
## somewhere or talked to someone, never because they pressed a button on a
## list of them. See docs/DESIGN.md § 34.

signal opened
signal closed

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_DONE := "6fae74"
const COLOR_HEAD := "8fb4d9"

## Rows the list box holds at once. There will eventually be more quests than
## this, so it windows rather than assuming they fit -- the fifth screen to
## need that treatment (§ 29).
const VISIBLE_ROWS := 5

var _cursor := 0
var _scroll := 0
## Quest ids in the order shown: everything running, then everything finished.
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
	_refresh_quests()
	_cursor = 0
	_scroll = 0
	_panel.show()
	_render()
	set_process_unhandled_input(true)
	opened.emit()


## Running quests first, then finished ones, each in the order the data
## declares them. Quests never taken up are not listed at all: a log of things
## nobody has mentioned to you yet is a spoiler, not a log.
func _refresh_quests() -> void:
	_shown = PackedStringArray()
	for quest in Content.quests:
		var quest_id := str(quest.get("id", ""))
		if Journal.is_active(quest_id):
			_shown.append(quest_id)
	for quest in Content.quests:
		var quest_id := str(quest.get("id", ""))
		if Journal.is_complete(quest_id):
			_shown.append(quest_id)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("move_down"):
		_move(1)
	elif event.is_action("move_up"):
		_move(-1)
	elif event.is_action("cancel") or event.is_action("interact") \
			or event.is_action("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()


func _move(delta: int) -> void:
	if _shown.is_empty():
		return
	_cursor = wrapi(_cursor + delta, 0, _shown.size())
	_render()


func _render() -> void:
	var done := Journal.completed_count()
	var needed := Content.gauntlet_requirement
	_title.text = "Quests  —  %d of %d toward the gauntlet" % [done, needed]

	if _shown.is_empty():
		_list.text = "[color=#%s]Nobody has asked you for anything yet.[/color]" % COLOR_DIM
		_detail.text = "[color=#%s]%s[/color]" % [COLOR_DIM, Journal.idle_objective()]
		_footer.text = "[color=#%s]X to close[/color]" % COLOR_DIM
		return

	var rows := PackedStringArray()
	for i in _shown.size():
		var quest_id := _shown[i]
		var finished := Journal.is_complete(quest_id)
		var colour := COLOR_SELECTED if i == _cursor else (
			COLOR_DONE if finished else COLOR_TEXT)
		rows.append("[color=#%s]%s %-24s %s[/color]" % [
			colour, ">" if i == _cursor else " ", _name_of(quest_id),
			"done" if finished else _area_of(quest_id),
		])
	_set_list(rows)

	_detail.text = _detail_for(_shown[_cursor])
	_footer.text = "[color=#%s]W/S read    X close[/color]" % COLOR_DIM


func _detail_for(quest_id: String) -> String:
	var lines := PackedStringArray()
	lines.append("[color=#%s]%s[/color]" % [COLOR_DIM, _summary_of(quest_id)])
	if Journal.is_complete(quest_id):
		lines.append("[color=#%s]Finished.[/color]" % COLOR_DONE)
	else:
		lines.append("[color=#%s]%s[/color]" % [COLOR_HEAD, Journal.objective(quest_id)])
	return "\n".join(lines)


## Same windowing as the bag and the battle menu: show what fits, follow the
## cursor, and mark the rows being hidden.
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


func _quest(quest_id: String) -> Dictionary:
	for quest in Content.quests:
		if str(quest.get("id", "")) == quest_id:
			return quest
	return {}


func _name_of(quest_id: String) -> String:
	return str(_quest(quest_id).get("name", quest_id))


func _summary_of(quest_id: String) -> String:
	return str(_quest(quest_id).get("summary", ""))


func _area_of(quest_id: String) -> String:
	return Content.map_name(str(_quest(quest_id).get("area", "")))


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	await get_tree().physics_frame
	closed.emit()
