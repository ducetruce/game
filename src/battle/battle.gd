extends Control
## The battle screen. Owns presentation only -- every rule lives in BattleState.
##
## Runs standalone: open scenes/battle/battle.tscn and press F6 for a demo
## fight. The overworld will call configure() before adding it to the tree.

signal finished(outcome: int)

enum Ui { MESSAGE, ACTIONS, MOVES, ITEMS, PARTY, LEARN_ASK, LEARN_PICK, OVER }

## Learning a fifth move asks before it lists, rather than dropping straight
## into the move list. Two reasons, and the second is the load-bearing one:
## five rows do not fit the menu panel, and a one-step prompt would put the
## cursor on a real move, where a player mashing Z through the post-battle
## messages would forget it without ever reading the question.
const LEARN_ASK_LABELS := ["Make room for it", "Keep the four I have"]
const LEARN_ASK_DECLINE := 1

const ACTION_LABELS := ["Fight", "Still", "Item", "Party", "Run"]
const CREATURE_SPRITE_DIR := "res://assets/sprites/creatures/"

const COLOR_TEXT := "cfd6e0"
const COLOR_DIM := "5d6878"
const COLOR_SELECTED := "e8c37a"
const COLOR_SPENT := "8a5a5a"

const HP_BAR_WIDTH := 118.0
const HP_GOOD := Color("6fae74")
const HP_WARN := Color("d2b45c")
const HP_LOW := Color("c4614f")
const BOND_BAR_WIDTH := 118.0
const BOND_COLOR := Color("d9a85c")

var _state: BattleState = null
var _ui := Ui.MESSAGE
var _cursor := 0
var _pending := PackedStringArray()

## True while the player owes us a replacement for a fainted creature. Backing
## out of the party menu is refused until it is satisfied.
var _forced_switch := false

var _party_creatures: Array = []
var _wild_creature: Creature = null
var _coin_reward := Vector2i.ZERO

@onready var _foe_name: Label = $FoePanel/CreatureName
@onready var _foe_fill: ColorRect = $FoePanel/HealthFill
@onready var _bond_fill: ColorRect = $FoePanel/BondFill
@onready var _foe_sprite: TextureRect = $FoeSprite
@onready var _player_name: Label = $PlayerPanel/CreatureName
@onready var _player_fill: ColorRect = $PlayerPanel/HealthFill
@onready var _player_hp: Label = $PlayerPanel/HealthText
@onready var _player_sprite: TextureRect = $PlayerSprite
@onready var _message: RichTextLabel = $BottomPanel/MessageText
@onready var _menu: RichTextLabel = $BottomPanel/MenuText


## Called by the overworld before this scene enters the tree. coin_reward is
## the active map's bracket -- see BattleState.coin_award().
func configure(party: Array, wild: Creature, coin_reward: Vector2i = Vector2i.ZERO) -> void:
	_party_creatures = party
	_wild_creature = wild
	_coin_reward = coin_reward


func _ready() -> void:
	if _wild_creature == null:
		_build_demo()
	_state = BattleState.create(_party_creatures, _wild_creature)
	_state.coin_reward = _coin_reward
	_refresh_panels()
	_queue(PackedStringArray([
		"A wild %s comes out of the bracken." % _state.foe.creature.display_name(),
		"Go on, %s." % _state.active().creature.display_name(),
	]))
	_show_next_message()


## A type disadvantage on the lead, on purpose: mire beats beast, so the demo
## opens by inviting a switch rather than a brawl.
func _build_demo() -> void:
	_party_creatures = [
		Creature.create("moorhound", 14),
		Creature.create("thistlecalf", 13),
		Creature.create("emberwick", 12),
	]
	_wild_creature = Creature.create("sloughback", 14)
	# The demo has no map behind it, so it carries its own bracket rather than
	# paying nothing and reading as if the economy were broken.
	_coin_reward = Vector2i(10, 18)


# --- message queue ---------------------------------------------------------

func _queue(lines: PackedStringArray) -> void:
	for line in lines:
		_pending.append(line)


func _show_next_message() -> void:
	if _pending.is_empty():
		_after_messages()
		return
	_ui = Ui.MESSAGE
	_menu.text = ""
	_message.text = "[color=#%s]%s[/color]" % [COLOR_TEXT, _pending[0]]
	_pending.remove_at(0)
	_refresh_bars()


func _after_messages() -> void:
	_refresh_panels()
	# Before the outcome screen on purpose: a move earned by the winning blow
	# still gets offered rather than vanishing with the battle.
	if not _state.pending_learns.is_empty():
		_open(Ui.LEARN_ASK)
		return
	if _state.is_over():
		_ui = Ui.OVER
		_menu.text = ""
		_message.text = "[color=#%s]%s[/color]\n[color=#%s]— press Z —[/color]" % [
			COLOR_TEXT, _outcome_text(), COLOR_DIM,
		]
		return
	if _state.phase == BattleState.Phase.REPLACING:
		_forced_switch = true
		_open(Ui.PARTY)
		return
	_open(Ui.ACTIONS)


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var handled := true
	match _ui:
		Ui.MESSAGE:
			if event.is_action("interact") or event.is_action("cancel"):
				_show_next_message()
			else:
				handled = false
		Ui.OVER:
			if event.is_action("interact"):
				_finish()
			else:
				handled = false
		_:
			handled = _menu_input(event)
	if handled:
		get_viewport().set_input_as_handled()


func _menu_input(event: InputEvent) -> bool:
	var count := _menu_length()
	if count <= 0:
		return false
	if event.is_action("move_down"):
		_cursor = wrapi(_cursor + 1, 0, count)
		_render_menu()
	elif event.is_action("move_up"):
		_cursor = wrapi(_cursor - 1, 0, count)
		_render_menu()
	elif event.is_action("interact"):
		_confirm()
	elif event.is_action("cancel"):
		if _ui == Ui.LEARN_PICK:
			_open(Ui.LEARN_ASK)  # back to the question, not out of it
		elif _ui == Ui.LEARN_ASK:
			# Backing out of "make room for it?" is a real answer: no.
			# Escaping to the action menu would strand the prompt, and the
			# battle may already be over.
			_queue(_state.resolve_pending_learn(-1))
			_show_next_message()
		elif not _forced_switch and _ui != Ui.ACTIONS:
			_open(Ui.ACTIONS)
	else:
		return false
	return true


func _open(ui: Ui) -> void:
	_ui = ui
	if ui == Ui.PARTY:
		_cursor = _state.active_index
	elif ui == Ui.LEARN_ASK:
		# Starts on "keep the four I have". Forgetting a move cannot be undone,
		# and this prompt lands in the middle of a run of messages the player
		# is very likely mashing Z through -- the same hazard as the menu
		# debounce in § 15, answered by making the mashed outcome harmless.
		_cursor = LEARN_ASK_DECLINE
	else:
		_cursor = 0
	_render_menu()


func _menu_length() -> int:
	match _ui:
		Ui.ACTIONS:
			return ACTION_LABELS.size()
		Ui.MOVES:
			return _state.move_options().size()
		Ui.ITEMS:
			return maxi(1, _state.item_options().size())  # 1 for the "nothing to use" row
		Ui.PARTY:
			return _state.party.size()
		Ui.LEARN_ASK:
			return LEARN_ASK_LABELS.size()
		Ui.LEARN_PICK:
			return _learn_creature_moves().size()
		_:
			return 0


## The move list the forget-a-move prompt is choosing from.
func _learn_creature_moves() -> PackedStringArray:
	var entry := _state.next_pending_learn()
	if entry.is_empty():
		return PackedStringArray()
	var creature: Creature = entry["creature"]
	return creature.moves


func _confirm() -> void:
	match _ui:
		Ui.ACTIONS:
			match _cursor:
				0:
					_open(Ui.MOVES)
				1:
					_submit({"kind": BattleState.ACTION_STILL})
				2:
					_open(Ui.ITEMS)
				3:
					_open(Ui.PARTY)
				4:
					_submit({"kind": BattleState.ACTION_FLEE})
		Ui.MOVES:
			var options := _state.move_options()
			if _cursor >= options.size():
				return
			var option: Dictionary = options[_cursor]
			if int(option["uses"]) <= 0:
				_notice("There is nothing left of that one.")
				return
			_submit({"kind": BattleState.ACTION_MOVE, "move": str(option["id"])})
		Ui.ITEMS:
			var items := _state.item_options()
			if _cursor >= items.size():
				return
			_submit({"kind": BattleState.ACTION_ITEM, "item": str(items[_cursor]["id"])})
		Ui.PARTY:
			_confirm_party()
		Ui.LEARN_ASK:
			if _cursor == LEARN_ASK_DECLINE:
				_queue(_state.resolve_pending_learn(-1))
				_show_next_message()
			else:
				_open(Ui.LEARN_PICK)
		Ui.LEARN_PICK:
			_queue(_state.resolve_pending_learn(_cursor))
			_show_next_message()


func _confirm_party() -> void:
	var chosen: Creature = _state.party[_cursor].creature
	if chosen.is_fainted():
		_notice("%s cannot stand." % chosen.display_name())
		return
	if _forced_switch:
		_forced_switch = false
		_queue(_state.replace_active(_cursor))
		_show_next_message()
		return
	if _cursor == _state.active_index:
		_notice("%s is already out." % chosen.display_name())
		return
	_submit({"kind": BattleState.ACTION_SWITCH, "index": _cursor})


func _submit(action: Dictionary) -> void:
	_queue(_state.submit(action))
	if _pending.is_empty():
		_queue(PackedStringArray(["Nothing comes of it."]))
	_show_next_message()


## A refusal that does not cost the turn -- the menu stays open.
func _notice(text: String) -> void:
	_message.text = "[color=#%s]%s[/color]" % [COLOR_SPENT, text]


# --- rendering -------------------------------------------------------------

func _render_menu() -> void:
	match _ui:
		Ui.ACTIONS:
			_render_actions()
		Ui.MOVES:
			_render_moves()
		Ui.ITEMS:
			_render_items()
		Ui.PARTY:
			_render_party()
		Ui.LEARN_ASK:
			_render_learn_ask()
		Ui.LEARN_PICK:
			_render_learn_pick()


func _render_actions() -> void:
	var rows := PackedStringArray()
	for i in ACTION_LABELS.size():
		rows.append(_row(ACTION_LABELS[i], i == _cursor))
	_menu.text = "\n".join(rows)
	_message.text = "[color=#%s]What will you do?[/color]" % COLOR_DIM


func _render_moves() -> void:
	var options := _state.move_options()
	var rows := PackedStringArray()
	for i in options.size():
		var option: Dictionary = options[i]
		var spent := int(option["uses"]) <= 0
		rows.append(_row("%s  %d/%d" % [
			option["name"], int(option["uses"]), int(option["max_uses"]),
		], i == _cursor, spent))
	_menu.text = "\n".join(rows)

	if _cursor < options.size():
		var move := Content.get_move(str(options[_cursor]["id"]))
		if move != null:
			_message.text = "[color=#%s]%s[/color]\n[color=#%s]%s[/color]" % [
				COLOR_SELECTED, move.type, COLOR_DIM, move.description,
			]


func _render_items() -> void:
	var items := _state.item_options()
	if items.is_empty():
		_menu.text = _row("nothing to use", false)
		_message.text = "[color=#%s]Your pack is empty. X to go back.[/color]" % COLOR_DIM
		return

	var rows := PackedStringArray()
	for i in items.size():
		var entry: Dictionary = items[i]
		rows.append(_row("%s  x%d" % [entry["name"], int(entry["count"])], i == _cursor))
	_menu.text = "\n".join(rows)

	if _cursor < items.size():
		_message.text = "[color=#%s]%s[/color]" % [COLOR_DIM, items[_cursor]["description"]]


func _render_party() -> void:
	var rows := PackedStringArray()
	for i in _state.party.size():
		var creature := _state.party[i].creature
		var marker := "*" if i == _state.active_index else " "
		rows.append(_row("%s%s %d/%d" % [
			marker, creature.display_name(), creature.current_hp, creature.max_hp(),
		], i == _cursor, creature.is_fainted()))
	_menu.text = "\n".join(rows)
	_message.text = "[color=#%s]%s[/color]" % [
		COLOR_DIM,
		"Who stands in its place?" if _forced_switch else "Send out whom? (X to go back)",
	]


func _render_learn_ask() -> void:
	var entry := _state.next_pending_learn()
	if entry.is_empty():
		return
	var creature: Creature = entry["creature"]
	var learning := Content.get_move(str(entry["move_id"]))
	var learning_name := learning.display_name if learning != null else str(entry["move_id"])

	var rows := PackedStringArray()
	for i in LEARN_ASK_LABELS.size():
		rows.append(_row(LEARN_ASK_LABELS[i], i == _cursor))
	_menu.text = "\n".join(rows)

	_message.text = "[color=#%s]%s can learn %s, but already knows four.[/color]\n[color=#%s]%s[/color]" % [
		COLOR_TEXT, creature.display_name(), learning_name, COLOR_DIM,
		"Forgetting one cannot be undone.",
	]


func _render_learn_pick() -> void:
	var entry := _state.next_pending_learn()
	if entry.is_empty():
		return
	var creature: Creature = entry["creature"]
	var learning := Content.get_move(str(entry["move_id"]))
	var learning_name := learning.display_name if learning != null else str(entry["move_id"])

	var rows := PackedStringArray()
	for i in creature.moves.size():
		var known := Content.get_move(creature.moves[i])
		var known_name := known.display_name if known != null else creature.moves[i]
		var known_type := known.type if known != null else "?"
		rows.append(_row("%-13s %s" % [known_name, known_type], i == _cursor))
	_menu.text = "\n".join(rows)

	_message.text = "[color=#%s]Give up which one for %s?[/color]\n[color=#%s]%s[/color]" % [
		COLOR_TEXT, learning_name, COLOR_DIM, "X to go back.",
	]


func _row(text: String, selected: bool, spent: bool = false) -> String:
	var colour := COLOR_SELECTED if selected else (COLOR_SPENT if spent else COLOR_TEXT)
	return "[color=#%s]%s %s[/color]" % [colour, ">" if selected else " ", text]


func _refresh_panels() -> void:
	var mine := _state.active()
	var theirs := _state.foe
	_player_name.text = "%s  Lv%d" % [mine.creature.display_name(), mine.creature.level]
	_foe_name.text = "%s  Lv%d" % [theirs.creature.display_name(), theirs.creature.level]
	_player_sprite.texture = _sprite_for(mine.creature.species_id)
	_foe_sprite.texture = _sprite_for(theirs.creature.species_id)
	_refresh_bars()


func _refresh_bars() -> void:
	_set_bar(_player_fill, _state.active().hp_ratio())
	_set_bar(_foe_fill, _state.foe.hp_ratio())
	var mine := _state.active().creature
	_player_hp.text = "%d/%d" % [mine.current_hp, mine.max_hp()]
	_bond_fill.size.x = maxf(0.0, BOND_BAR_WIDTH * (_state.foe.resonance / 100.0))


func _set_bar(bar: ColorRect, ratio: float) -> void:
	bar.size.x = maxf(0.0, HP_BAR_WIDTH * ratio)
	bar.color = HP_GOOD if ratio > 0.5 else (HP_WARN if ratio > 0.2 else HP_LOW)


func _sprite_for(species_id: String) -> Texture2D:
	var path := CREATURE_SPRITE_DIR + species_id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _outcome_text() -> String:
	match _state.phase:
		BattleState.Phase.WON:
			return "The %s breaks and is gone." % _state.foe.creature.display_name()
		BattleState.Phase.LOST:
			return "Nothing of yours is still standing."
		BattleState.Phase.FLED:
			return "You put ground between you and it."
		BattleState.Phase.ATTUNED:
			return "%s is yours now." % _state.foe.creature.display_name()
		BattleState.Phase.FOE_FLED:
			return "%s slips away, out of reach." % _state.foe.creature.display_name()
		_:
			return ""


func _finish() -> void:
	finished.emit(_state.phase)
	# Standalone: loop straight back into another demo fight.
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()
