extends CanvasLayer
## The shrine: move creatures between the party and storage.
##
## Reachable only from the shrine object in Aldenmere, never from the pause
## menu. Having to walk back is what makes the six you carry a commitment
## rather than a loadout re-picked before every fight. See docs/DESIGN.md § 24.
##
## Owns no game state beyond the cursor. Party and Storage are the truth.

signal opened
signal closed

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_FAINTED := "8a5a5a"
const COLOR_BAD := "c4614f"
const COLOR_GOOD := "6fae74"

## How many stored rows are visible at once. Storage holds far more, so the
## window scrolls with the cursor rather than paging by hand.
const VISIBLE_STORED := 8

## Named Pane, not Side: a bare `Side` collides with BattleState.Side, and
## GDScript then refuses to assign this script's own enum to a variable
## annotated with it. Left inferred below for the same reason -- see § 21's
## note on the same quirk biting the battle code.
enum Pane { PARTY, STORED }

var _pane := Pane.PARTY
var _party_cursor := 0
var _stored_cursor := 0
var _scroll := 0
## Shown instead of the footer hint for one action, then cleared on the next
## press so it cannot linger over stale state.
var _notice := ""
## A refusal has to look different from a success, or the footer reads as
## confirmation whatever it actually says.
var _notice_colour := COLOR_GOOD

@onready var _panel: Panel = $Panel
@onready var _party_list: RichTextLabel = $Panel/PartyList
@onready var _stored_list: RichTextLabel = $Panel/StoredList
@onready var _party_head: Label = $Panel/PartyHeading
@onready var _stored_head: Label = $Panel/StoredHeading
@onready var _footer: RichTextLabel = $Panel/Footer


func _ready() -> void:
	_panel.hide()
	set_process_unhandled_input(false)


func is_open() -> bool:
	return _panel.visible


func open_menu() -> void:
	if is_open():
		return
	_pane = Pane.PARTY
	_party_cursor = 0
	_stored_cursor = 0
	_scroll = 0
	_notice = ""
	_panel.show()
	_render()
	set_process_unhandled_input(true)
	opened.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if not _handles(event):
		return
	get_viewport().set_input_as_handled()
	_notice = ""

	if event.is_action("move_down"):
		_step(1)
	elif event.is_action("move_up"):
		_step(-1)
	elif event.is_action("move_left") or event.is_action("move_right"):
		_swap_pane()
	elif event.is_action("interact"):
		_transfer()
	else:
		_close()
		return
	_render()


func _handles(event: InputEvent) -> bool:
	return (event.is_action("move_up") or event.is_action("move_down")
		or event.is_action("move_left") or event.is_action("move_right")
		or event.is_action("interact") or event.is_action("cancel"))


func _step(delta: int) -> void:
	if _pane == Pane.PARTY:
		if Party.size() > 0:
			_party_cursor = wrapi(_party_cursor + delta, 0, Party.size())
		return
	if Storage.count() > 0:
		_stored_cursor = wrapi(_stored_cursor + delta, 0, Storage.count())
	_follow_cursor()


## Keeps the scrolling window around the stored cursor, including when it
## wraps from one end of the list to the other.
func _follow_cursor() -> void:
	if _stored_cursor < _scroll:
		_scroll = _stored_cursor
	elif _stored_cursor >= _scroll + VISIBLE_STORED:
		_scroll = _stored_cursor - VISIBLE_STORED + 1
	_scroll = clampi(_scroll, 0, maxi(0, Storage.count() - VISIBLE_STORED))


func _swap_pane() -> void:
	# Switching into an empty side would leave the cursor pointing at nothing
	# and every action refusing, which reads as the menu being broken.
	if _pane == Pane.PARTY:
		if Storage.count() == 0:
			_refuse("Nothing is kept here yet.")
			return
		_pane = Pane.STORED
	else:
		_pane = Pane.PARTY
	_clamp_cursors()


func _clamp_cursors() -> void:
	_party_cursor = clampi(_party_cursor, 0, maxi(0, Party.size() - 1))
	_stored_cursor = clampi(_stored_cursor, 0, maxi(0, Storage.count() - 1))
	_follow_cursor()


func _transfer() -> void:
	if _pane == Pane.PARTY:
		_deposit()
	else:
		_withdraw()
	_clamp_cursors()


func _deposit() -> void:
	if _party_cursor >= Party.size():
		return
	# The one rule worth enforcing: walking out of here with nothing would
	# leave the player unable to fight anything, with no way back but here.
	if Party.size() <= 1:
		_refuse("You cannot leave with nothing.")
		return
	if not Storage.has_room():
		_refuse("The shrine will hold no more.")
		return

	var creature: Creature = Party.members[_party_cursor]
	Party.members.remove_at(_party_cursor)
	Storage.deposit(creature)
	_report("%s settles in to wait." % creature.display_name())


func _withdraw() -> void:
	if _stored_cursor >= Storage.count():
		return
	if Party.size() >= Party.MAX_SIZE:
		_refuse("You can carry six.")
		return

	var creature := Storage.withdraw(_stored_cursor)
	if creature == null:
		return
	Party.add(creature)
	_report("%s comes along." % creature.display_name())
	if Storage.count() == 0:
		_pane = Pane.PARTY


func _refuse(text: String) -> void:
	_notice = text
	_notice_colour = COLOR_BAD


func _report(text: String) -> void:
	_notice = text
	_notice_colour = COLOR_GOOD


func _render() -> void:
	_party_head.text = "Carried  %d/%d" % [Party.size(), Party.MAX_SIZE]
	_stored_head.text = "Kept  %d" % Storage.count()

	var party_rows := PackedStringArray()
	for i in Party.size():
		party_rows.append(_row(Party.members[i], i == _party_cursor and _pane == Pane.PARTY))
	if party_rows.is_empty():
		party_rows.append("[color=#%s]nobody[/color]" % COLOR_DIM)
	_party_list.text = "\n".join(party_rows)

	var stored_rows := PackedStringArray()
	var last := mini(Storage.count(), _scroll + VISIBLE_STORED)
	for i in range(_scroll, last):
		stored_rows.append(_row(Storage.creatures[i], i == _stored_cursor and _pane == Pane.STORED))
	if stored_rows.is_empty():
		stored_rows.append("[color=#%s]nothing yet[/color]" % COLOR_DIM)
	elif last < Storage.count():
		stored_rows.append("[color=#%s]   %d more below[/color]" % [
			COLOR_DIM, Storage.count() - last,
		])
	_stored_list.text = "\n".join(stored_rows)

	if not _notice.is_empty():
		_footer.text = "[color=#%s]%s[/color]" % [_notice_colour, _notice]
		return
	var verb := "Z put away" if _pane == Pane.PARTY else "Z take along"
	_footer.text = "[color=#%s]W/S choose   A/D switch   %s   X leave[/color]" % [COLOR_DIM, verb]


func _row(creature: Creature, selected: bool) -> String:
	var colour := COLOR_SELECTED if selected else (
		COLOR_FAINTED if creature.is_fainted() else COLOR_TEXT
	)
	return "[color=#%s]%s %-12s Lv%-3d %3d/%-3d[/color]" % [
		colour, ">" if selected else " ", creature.display_name(),
		creature.level, creature.current_hp, creature.max_hp(),
	]


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	await get_tree().physics_frame
	closed.emit()
