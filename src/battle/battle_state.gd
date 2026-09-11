class_name BattleState
extends RefCounted
## One whole battle, with no nodes in it.
##
## The battle scene drives this by submitting an action and reading back the log
## it produced. Keeping it headless is what lets scenes/debug/battle_sim.tscn
## run thousands of battles to completion without any UI existing.

enum Phase {
	CHOOSING,   ## waiting for the player's action
	REPLACING,  ## player's creature fainted and must be swapped out
	WON,
	LOST,
	FLED,
}

enum Side { PLAYER, FOE }

const ACTION_MOVE := "move"
const ACTION_STILL := "still"
const ACTION_SWITCH := "switch"
const ACTION_FLEE := "flee"

## Switching out and running both happen before any move, whatever the speeds.
const PRIORITY_ACT_FIRST := 10
const PRIORITY_NORMAL := 0

## How often the wild creature picks its single best damaging option. A
## perfectly optimal opponent is both harder to read and less interesting than
## one that sometimes does something else.
const AI_BEST_MOVE_CHANCE := 0.7

var party: Array[Combatant] = []
var active_index := 0
var foe: Combatant = null

var phase := Phase.CHOOSING
var turn := 0
var log_lines := PackedStringArray()
var rng := RandomNumberGenerator.new()

var _flee_attempts := 0


static func create(party_creatures: Array, wild_creature: Creature, seed_value: int = 0) -> BattleState:
	var state := BattleState.new()
	if seed_value == 0:
		state.rng.randomize()
	else:
		state.rng.seed = seed_value
	for creature in party_creatures:
		state.party.append(Combatant.of(creature, false))
	state.foe = Combatant.of(wild_creature, true)
	for i in state.party.size():
		if not state.party[i].creature.is_fainted():
			state.active_index = i
			break
	return state


func active() -> Combatant:
	return party[active_index]


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST or phase == Phase.FLED


## Move rows for the selection menu, including remaining uses.
func move_options() -> Array:
	var options := []
	var creature := active().creature
	for i in creature.moves.size():
		var move := Content.get_move(creature.moves[i])
		if move == null:
			continue
		options.append({
			"id": move.id,
			"name": move.display_name,
			"type": move.type,
			"uses": creature.move_uses[i] if i < creature.move_uses.size() else 0,
			"max_uses": move.uses,
		})
	return options


func can_switch_to(index: int) -> bool:
	return (
		index >= 0
		and index < party.size()
		and index != active_index
		and not party[index].creature.is_fainted()
	)


# --- the turn --------------------------------------------------------------

## Runs one full turn and returns everything that happened, in order.
func submit(action: Dictionary) -> PackedStringArray:
	log_lines = PackedStringArray()
	if phase != Phase.CHOOSING:
		return log_lines

	turn += 1
	var foe_action := _choose_foe_action()
	var order := (
		[[Side.PLAYER, action], [Side.FOE, foe_action]]
		if _player_acts_first(action, foe_action)
		else [[Side.FOE, foe_action], [Side.PLAYER, action]]
	)

	for entry in order:
		# A faint mid-turn ends the turn: whoever went down does not also act.
		if phase != Phase.CHOOSING:
			break
		var side: Side = entry[0]
		if _combatant(side).creature.is_fainted():
			continue
		_perform(side, entry[1])
		_resolve_faints()

	return log_lines


## Swaps in a replacement after a faint. Also used by the party menu mid-battle,
## where it costs the turn instead.
func replace_active(index: int) -> PackedStringArray:
	log_lines = PackedStringArray()
	if index < 0 or index >= party.size() or party[index].creature.is_fainted():
		return log_lines
	active_index = index
	active().clear_stages()
	log_lines.append("%s steps up." % active().creature.display_name())
	if phase == Phase.REPLACING:
		phase = Phase.CHOOSING
	return log_lines


func _perform(side: Side, action: Dictionary) -> void:
	var me := _combatant(side)
	var them := _combatant(Side.FOE if side == Side.PLAYER else Side.PLAYER)

	match str(action.get("kind", ACTION_MOVE)):
		ACTION_SWITCH:
			_do_switch(side, int(action.get("index", -1)))
		ACTION_FLEE:
			_do_flee(side)
		ACTION_STILL:
			# Attunement reads this in step 5. For now it simply costs the turn,
			# which is exactly what makes it a real decision later.
			log_lines.append("%s holds still." % me.creature.display_name())
		_:
			_do_move(me, them, str(action.get("move", "")))


func _do_move(user: Combatant, target: Combatant, move_id: String) -> void:
	var move := Content.get_move(move_id)
	if move == null:
		log_lines.append("%s hesitates." % user.log_name())
		return
	if not user.creature.spend_use(move_id):
		log_lines.append("%s has nothing left of %s." % [user.log_name(), move.display_name])
		return

	log_lines.append("%s uses %s." % [user.log_name(), move.display_name])

	if rng.randi_range(1, 100) > move.accuracy:
		log_lines.append("It goes wide.")
		return

	if not move.is_damaging():
		_apply_effect(user, target, move)
		return

	var result := Damage.compute(user, target, move, Damage.roll_variance(rng))
	var dealt := target.creature.take_damage(int(result["amount"]))
	var note := Damage.effectiveness_text(float(result["type_multiplier"]))
	if not note.is_empty():
		log_lines.append(note)
	log_lines.append("%s takes %d." % [target.log_name(), dealt])


func _apply_effect(user: Combatant, target: Combatant, move: MoveData) -> void:
	if move.effect.is_empty():
		log_lines.append("Nothing comes of it.")
		return

	var receiver := user if str(move.effect.get("target", "self")) == "self" else target

	match str(move.effect.get("kind", "")):
		"stat_stage":
			var stat_name := str(move.effect.get("stat", ""))
			var delta := int(move.effect.get("stages", 0))
			var moved := receiver.adjust_stage(stat_name, delta)
			if moved == 0:
				log_lines.append("%s's %s will not shift further." % [
					receiver.creature.display_name(), stat_name,
				])
			else:
				log_lines.append("%s's %s %s." % [
					receiver.creature.display_name(),
					stat_name,
					"rises" if delta > 0 else "drops",
				])
		"heal":
			var percent := float(move.effect.get("percent", 0))
			var amount := int(roundf(float(receiver.creature.max_hp()) * percent / 100.0))
			var healed := receiver.creature.heal(amount)
			if healed <= 0:
				log_lines.append("%s is already whole." % receiver.creature.display_name())
			else:
				log_lines.append("%s knits back %d." % [receiver.creature.display_name(), healed])
		_:
			log_lines.append("Nothing comes of it.")


func _do_switch(side: Side, index: int) -> void:
	if side != Side.PLAYER:
		return  # a wild creature has nothing to switch to
	if not can_switch_to(index):
		log_lines.append("There is nothing to send out.")
		return
	log_lines.append("%s is called back." % active().creature.display_name())
	active_index = index
	active().clear_stages()
	log_lines.append("%s steps up." % active().creature.display_name())


func _do_flee(side: Side) -> void:
	if side != Side.PLAYER:
		return
	_flee_attempts += 1
	# Speed matters, but repeated attempts matter more, so a slow party is never
	# permanently trapped by something fast.
	var speed_edge := float(active().stat("speed")) / maxf(1.0, float(foe.stat("speed"))) - 1.0
	var odds := clampf(0.35 + 0.15 * float(_flee_attempts) + 0.3 * speed_edge, 0.15, 0.95)
	if rng.randf() < odds:
		log_lines.append("You break away.")
		phase = Phase.FLED
	else:
		log_lines.append("It cuts you off.")


func _resolve_faints() -> void:
	if foe.creature.is_fainted():
		log_lines.append("%s goes down." % foe.log_name())
		phase = Phase.WON
		return
	if active().creature.is_fainted():
		log_lines.append("%s goes down." % active().creature.display_name())
		phase = Phase.REPLACING if _has_healthy_reserve() else Phase.LOST


func _has_healthy_reserve() -> bool:
	for i in party.size():
		if i != active_index and not party[i].creature.is_fainted():
			return true
	return false


func _player_acts_first(player_action: Dictionary, foe_action: Dictionary) -> bool:
	var mine := _priority_of(player_action)
	var theirs := _priority_of(foe_action)
	if mine != theirs:
		return mine > theirs
	var my_speed := active().stat("speed")
	var their_speed := foe.stat("speed")
	if my_speed != their_speed:
		return my_speed > their_speed
	return rng.randf() < 0.5


func _priority_of(action: Dictionary) -> int:
	var kind := str(action.get("kind", ACTION_MOVE))
	if kind == ACTION_SWITCH or kind == ACTION_FLEE:
		return PRIORITY_ACT_FIRST
	return PRIORITY_NORMAL


func _combatant(side: Side) -> Combatant:
	return active() if side == Side.PLAYER else foe


# --- the wild creature's decision ------------------------------------------

func _choose_foe_action() -> Dictionary:
	var usable := PackedStringArray()
	for i in foe.creature.moves.size():
		if i < foe.creature.move_uses.size() and foe.creature.move_uses[i] > 0:
			usable.append(foe.creature.moves[i])
	if usable.is_empty():
		# Out of everything. Standing there is at least honest.
		return {"kind": ACTION_STILL}

	if rng.randf() < AI_BEST_MOVE_CHANCE:
		var best := ""
		var best_amount := -1
		for move_id in usable:
			var move := Content.get_move(move_id)
			if move == null or not move.is_damaging():
				continue
			var amount := int(Damage.compute(foe, active(), move, Damage.VARIANCE_MAX)["amount"])
			if amount > best_amount:
				best_amount = amount
				best = move_id
		if not best.is_empty():
			return {"kind": ACTION_MOVE, "move": best}

	return {"kind": ACTION_MOVE, "move": usable[rng.randi_range(0, usable.size() - 1)]}
