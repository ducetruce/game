extends CanvasLayer
## A read-only look at the player's party: who's in it, how hurt they are,
## and what they know. Opened from the overworld with the `menu` action.
##
## Deliberately a viewer only, not an editor -- no reordering, no releasing,
## no move-forgetting. Those need their own confirmation flows and belong in
## a later pass once there's a reason to need them (see docs/DESIGN.md).

signal opened
signal closed

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_FAINTED := "8a5a5a"
const COLOR_XP := "6d8fae"

const HP_BAR_WIDTH := 96.0
const HP_GOOD := Color("6fae74")
const HP_WARN := Color("d2b45c")
const HP_LOW := Color("c4614f")
const XP_BAR_WIDTH := 96.0

var _cursor := 0

@onready var _panel: Panel = $Panel
@onready var _roster: RichTextLabel = $Panel/Roster
@onready var _name_label: Label = $Panel/DetailName
@onready var _hp_fill: ColorRect = $Panel/HpFill
@onready var _hp_text: Label = $Panel/HpText
@onready var _xp_fill: ColorRect = $Panel/XpFill
@onready var _moves: RichTextLabel = $Panel/Moves
@onready var _footer: RichTextLabel = $Panel/Footer


func _ready() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	_footer.text = "[color=#%s]W/S select    X or M to close[/color]" % COLOR_DIM


func is_open() -> bool:
	return _panel.visible


func open_menu() -> void:
	if is_open() or not Party.has_any():
		return
	_cursor = 0
	_panel.show()
	_refresh()
	set_process_unhandled_input(true)
	opened.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("move_down"):
		_cursor = wrapi(_cursor + 1, 0, Party.size())
		_refresh()
	elif event.is_action("move_up"):
		_cursor = wrapi(_cursor - 1, 0, Party.size())
		_refresh()
	elif event.is_action("cancel") or event.is_action("menu"):
		_close()
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	var rows := PackedStringArray()
	for i in Party.size():
		var creature := Party.members[i]
		var colour := COLOR_SELECTED if i == _cursor else (
			COLOR_FAINTED if creature.is_fainted() else COLOR_TEXT
		)
		rows.append("[color=#%s]%s %-14s Lv%-3d %3d/%3d[/color]" % [
			colour, ">" if i == _cursor else " ", creature.display_name(),
			creature.level, creature.current_hp, creature.max_hp(),
		])
	_roster.text = "\n".join(rows)

	if _cursor >= Party.size():
		return
	var shown := Party.members[_cursor]
	_render_detail(shown)


func _render_detail(creature: Creature) -> void:
	var species := creature.species()
	var types := " / ".join(Array(creature.types())) if species != null else "?"
	_name_label.text = "%s  Lv%d  (%s)" % [creature.display_name(), creature.level, types]

	var hp_ratio := 0.0 if creature.max_hp() <= 0 else float(creature.current_hp) / float(creature.max_hp())
	_hp_fill.size.x = maxf(0.0, HP_BAR_WIDTH * hp_ratio)
	_hp_fill.color = HP_GOOD if hp_ratio > 0.5 else (HP_WARN if hp_ratio > 0.2 else HP_LOW)
	_hp_text.text = "HP %d/%d" % [creature.current_hp, creature.max_hp()]

	_xp_fill.size.x = maxf(0.0, XP_BAR_WIDTH * _level_progress(creature))

	var rows := PackedStringArray()
	for i in creature.moves.size():
		var move := Content.get_move(creature.moves[i])
		if move == null:
			continue
		var uses := creature.move_uses[i] if i < creature.move_uses.size() else 0
		var spent := uses <= 0
		var colour := COLOR_FAINTED if spent else COLOR_TEXT
		rows.append("[color=#%s]%-14s %-7s %2d/%-2d[/color]" % [
			colour, move.display_name, move.type, uses, move.uses,
		])
	if rows.is_empty():
		rows.append("[color=#%s]knows nothing[/color]" % COLOR_DIM)
	_moves.text = "\n".join(rows)


## How far into the current level the creature's experience sits, 0-1. At the
## level cap this reads as full rather than divide-by-zero empty.
func _level_progress(creature: Creature) -> float:
	if creature.level >= SpeciesData.MAX_LEVEL:
		return 1.0
	var floor_xp := Creature.experience_for_level(creature.level)
	var ceil_xp := Creature.experience_for_level(creature.level + 1)
	var span := ceil_xp - floor_xp
	if span <= 0:
		return 1.0
	return clampf(float(creature.experience - floor_xp) / float(span), 0.0, 1.0)


func _close() -> void:
	_panel.hide()
	set_process_unhandled_input(false)
	await get_tree().physics_frame
	closed.emit()
