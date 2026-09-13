extends CanvasLayer
## Using an item outside a battle: pick the item, then who it goes on.
##
## Opened from the pause menu. Until this existed, every item in the game was
## unreachable except mid-fight, which made a revive impossible to define --
## a fainted creature is never the active one. See docs/DESIGN.md § 23.
##
## Owns no game state. Inventory is the source of truth for what is carried and
## Party for who is carrying it, exactly as ShopMenu leaves coin to Inventory.

signal opened
signal closed

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_UNUSABLE := "8a5a5a"
const COLOR_GOOD := "6fae74"

enum Step { ITEMS, TARGET }

var _step: Step = Step.ITEMS
## Rows the list box holds at once.
const VISIBLE_ROWS := 6

var _cursor := 0
## First row of the list window, when there are more items than fit.
var _scroll := 0
var _items := PackedStringArray()
## Index into _items picked on the first step. Kept separate from _cursor,
## which moves on to the party list once a target is being chosen.
var _chosen := 0
## Set while a message is showing instead of a list, so the next press clears
## it rather than acting on a cursor the player cannot see.
var _notice := ""

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
	_step = Step.ITEMS
	_cursor = 0
	_notice = ""
	_refresh_items()
	_panel.show()
	_render()
	set_process_unhandled_input(true)
	opened.emit()


## Items that can do anything out here. A Tempering Draught is real and owned,
## but it only means something mid-fight, so it is not offered.
func _refresh_items() -> void:
	_items = PackedStringArray()
	for item_id in Inventory.owned_item_ids():
		var item := Content.get_item(item_id)
		if item == null:
			continue
		var kind := str(item.effect.get("kind", ""))
		if kind in [ItemData.EFFECT_HEAL, ItemData.EFFECT_REVIVE,
				ItemData.EFFECT_RESTORE_USES]:
			_items.append(item_id)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not _handles(event):
		return
	get_viewport().set_input_as_handled()

	if not _notice.is_empty():
		_notice = ""
		_render()
		return

	if event.is_action("move_down"):
		_move(1)
	elif event.is_action("move_up"):
		_move(-1)
	elif event.is_action("interact"):
		_confirm()
	else:
		_back()


func _handles(event: InputEvent) -> bool:
	return event.is_action("move_up") or event.is_action("move_down") \
		or event.is_action("interact") or event.is_action("cancel")


func _move(delta: int) -> void:
	var count := _count()
	if count <= 0:
		return
	_cursor = wrapi(_cursor + delta, 0, count)
	_render()


func _count() -> int:
	if _step == Step.ITEMS:
		return _items.size()
	return Party.size()


func _back() -> void:
	if _step == Step.TARGET:
		_step = Step.ITEMS
		_cursor = 0
		_scroll = 0
		_render()
		return
	_close()


func _confirm() -> void:
	if _count() <= 0:
		_close()
		return
	if _step == Step.ITEMS:
		_chosen = _cursor
		_step = Step.TARGET
		_cursor = 0
		_scroll = 0
		_render()
		return
	_use_on(Party.members[_cursor])


func _use_on(creature: Creature) -> void:
	var item := Content.get_item(_chosen_item_id())
	if item == null:
		return
	var kind := str(item.effect.get("kind", ""))
	var percent := float(item.effect.get("percent", 0))
	var amount := maxi(1, int(roundf(float(creature.max_hp()) * percent / 100.0)))

	# Refused before the charge is spent, same rule as in battle: being told an
	# item did nothing *after* it is gone teaches the player to distrust the
	# menu. See docs/DESIGN.md § 19.
	if kind == ItemData.EFFECT_REVIVE and not creature.is_fainted():
		_say("%s is already standing." % creature.display_name())
		return
	if kind == ItemData.EFFECT_HEAL:
		if creature.is_fainted():
			_say("%s cannot be roused by that." % creature.display_name())
			return
		if creature.current_hp >= creature.max_hp():
			_say("%s is not hurt." % creature.display_name())
			return
	if kind == ItemData.EFFECT_RESTORE_USES:
		# Deliberately allowed on a fainted creature: topping its moves up
		# while it is down is exactly what you would want to do before
		# reviving it, and refusing would only mean using the two in a
		# particular order.
		if creature.spent_uses() <= 0:
			_say("%s has spent nothing." % creature.display_name())
			return

	Inventory.consume(item.id)
	if kind == ItemData.EFFECT_REVIVE:
		creature.current_hp = mini(amount, creature.max_hp())
		_say("%s comes back round." % creature.display_name(), true)
	elif kind == ItemData.EFFECT_RESTORE_USES:
		var given := creature.restore_uses(int(item.effect.get("uses", 0)))
		_say("%s finds %d more in itself." % [creature.display_name(), given], true)
	else:
		_say("%s knits back %d." % [creature.display_name(), creature.heal(amount)], true)

	# The last one may have just been used up.
	_refresh_items()
	if _chosen >= _items.size():
		_step = Step.ITEMS
		_chosen = 0
		_cursor = 0
		_scroll = 0


## Draws `rows` into the list box: all of them if they fit, otherwise a window
## of VISIBLE_ROWS following the cursor, marking the rows it hides. The bag
## holds every item the catalog ever grows to, so a box sized to today's list
## is a box that breaks on the next item added. Same treatment as the battle
## menu and the storage screen -- see docs/DESIGN.md § 29.
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


func _chosen_item_id() -> String:
	return _items[_chosen] if _chosen < _items.size() else ""


func _say(text: String, good: bool = false) -> void:
	_notice = "[color=#%s]%s[/color]" % [COLOR_GOOD if good else COLOR_UNUSABLE, text]
	_render()


func _render() -> void:
	if not _notice.is_empty():
		_title.text = "Bag"
		_list.text = _notice
		_detail.text = ""
		_footer.text = "[color=#%s]Z to go on[/color]" % COLOR_DIM
		return

	if _step == Step.ITEMS:
		_render_items()
	else:
		_render_targets()


func _render_items() -> void:
	_title.text = "Bag"
	if _items.is_empty():
		_list.text = "[color=#%s]Nothing here worth using out of a fight.[/color]" % COLOR_DIM
		_detail.text = ""
		_footer.text = "[color=#%s]X to close[/color]" % COLOR_DIM
		return

	var rows := PackedStringArray()
	for i in _items.size():
		var item := Content.get_item(_items[i])
		if item == null:
			continue
		var colour := COLOR_SELECTED if i == _cursor else COLOR_TEXT
		rows.append("[color=#%s]%s %-20s x%d[/color]" % [
			colour, ">" if i == _cursor else " ", item.display_name,
			Inventory.count(item.id),
		])
	_set_list(rows)

	var chosen := Content.get_item(_items[_cursor]) if _cursor < _items.size() else null
	_detail.text = "[color=#%s]%s[/color]" % [COLOR_DIM, chosen.description if chosen != null else ""]
	_footer.text = "[color=#%s]W/S choose    Z use    X close[/color]" % COLOR_DIM


func _render_targets() -> void:
	var item := Content.get_item(_chosen_item_id())
	_title.text = "Use %s on" % (item.display_name if item != null else "it")

	var reviving := item != null and str(item.effect.get("kind", "")) == ItemData.EFFECT_REVIVE
	var rows := PackedStringArray()
	for i in Party.size():
		var creature := Party.members[i]
		# Greyed rather than hidden: a party list that changes shape depending
		# on the item is harder to read than one that is always the same list.
		var applies := creature.is_fainted() if reviving else not creature.is_fainted()
		var colour := COLOR_SELECTED if i == _cursor else (COLOR_TEXT if applies else COLOR_UNUSABLE)
		rows.append("[color=#%s]%s %-14s Lv%-3d %3d/%3d[/color]" % [
			colour, ">" if i == _cursor else " ", creature.display_name(),
			creature.level, creature.current_hp, creature.max_hp(),
		])
	_set_list(rows)
	_detail.text = "[color=#%s]%s[/color]" % [
		COLOR_DIM, "Who has gone down?" if reviving else "Who needs it?",
	]
	_footer.text = "[color=#%s]W/S choose    Z use    X back[/color]" % COLOR_DIM


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	await get_tree().physics_frame
	closed.emit()
