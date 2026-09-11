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
	WON,        ## foe fainted outright -- possible whether or not Restrained
	LOST,
	FLED,       ## the player broke off
	ATTUNED,    ## Resonance reached the capture threshold -- foe joins the party
	FOE_FLED,   ## Resonance stalled too long -- the foe broke off instead
}

enum Side { PLAYER, FOE }

const ACTION_MOVE := "move"
const ACTION_STILL := "still"
const ACTION_SWITCH := "switch"
const ACTION_FLEE := "flee"
const ACTION_ITEM := "item"

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

## Party slots that were sent out at any point. Only these share the reward, so
## experience follows the risk rather than being handed to the whole party.
var participants := PackedInt32Array()

## True once a restrain_hit item has been used this battle. Applies only to
## damage the player deals to a wild foe: it caps a single hit, it does not
## prevent the foe being finished off over several. See docs/DESIGN.md
## section 13.
var restrained := false
var _restrain_cap_ratio := 1.0

## Set for the one turn the foe heals itself, so the passive Feral check can
## tell "restored" apart from merely "took less damage than usual".
var _foe_healed_this_turn := false

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
	state._mark_participant(state.active_index)
	return state


func active() -> Combatant:
	return party[active_index]


func is_over() -> bool:
	return (
		phase == Phase.WON
		or phase == Phase.LOST
		or phase == Phase.FLED
		or phase == Phase.ATTUNED
		or phase == Phase.FOE_FLED
	)


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


## Item rows for the battle menu: only items usable in battle that the player
## actually owns.
func item_options() -> Array:
	var options := []
	for item_id in Inventory.owned_item_ids():
		var item := Content.get_item(item_id)
		if item == null or not item.usable_in_battle:
			continue
		options.append({
			"id": item.id,
			"name": item.display_name,
			"description": item.description,
			"count": Inventory.count(item_id),
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
	_foe_healed_this_turn = false
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

	if phase == Phase.CHOOSING and foe.temperament() == "feral":
		_tick_feral_resonance()

	return log_lines


## Swaps in a replacement after a faint. Also used by the party menu mid-battle,
## where it costs the turn instead.
func replace_active(index: int) -> PackedStringArray:
	log_lines = PackedStringArray()
	if index < 0 or index >= party.size() or party[index].creature.is_fainted():
		return log_lines
	active_index = index
	active().clear_stages()
	_mark_participant(index)
	log_lines.append("%s steps up." % active().creature.display_name())
	if phase == Phase.REPLACING:
		phase = Phase.CHOOSING
	return log_lines


func _perform(side: Side, action: Dictionary) -> void:
	var me := _combatant(side)
	var them := _combatant(Side.FOE if side == Side.PLAYER else Side.PLAYER)
	var kind := str(action.get("kind", ACTION_MOVE))
	var move_result := {}

	match kind:
		ACTION_SWITCH:
			_do_switch(side, int(action.get("index", -1)))
		ACTION_FLEE:
			_do_flee(side)
		ACTION_STILL:
			log_lines.append("%s holds still." % me.creature.display_name())
		ACTION_ITEM:
			_do_item(side, str(action.get("item", "")))
		_:
			move_result = _do_move(me, them, str(action.get("move", "")))

	# Only the player's actions toward the wild foe read as anything to it --
	# what it does to you tells it nothing about you.
	if side == Side.PLAYER and phase == Phase.CHOOSING:
		_tick_reactive_resonance(kind, move_result)


## Returns {hit: bool, dealt: int, type_multiplier: float, hp_ratio_before:
## float} describing what happened to the target, so the caller can drive
## Resonance from it. hit is false on a miss or an empty/unusable move.
func _do_move(user: Combatant, target: Combatant, move_id: String) -> Dictionary:
	var empty_result := {"hit": false, "dealt": 0, "type_multiplier": 1.0, "hp_ratio_before": target.hp_ratio()}
	var move := Content.get_move(move_id)
	if move == null:
		log_lines.append("%s hesitates." % user.log_name())
		return empty_result
	if not user.creature.spend_use(move_id):
		log_lines.append("%s has nothing left of %s." % [user.log_name(), move.display_name])
		return empty_result

	log_lines.append("%s uses %s." % [user.log_name(), move.display_name])

	if rng.randi_range(1, 100) > move.accuracy:
		log_lines.append("It goes wide.")
		return empty_result

	if not move.is_damaging():
		_apply_effect(user, target, move)
		return empty_result

	var hp_ratio_before := target.hp_ratio()
	var result := Damage.compute(user, target, move, Damage.roll_variance(rng))
	var amount := int(result["amount"])
	if restrained and target.is_wild:
		# A single hit can never end the fight outright -- it can still be
		# finished off over several, if the player keeps swinging regardless.
		amount = mini(amount, maxi(1, int(float(target.creature.max_hp()) * _restrain_cap_ratio)))
	var dealt := target.creature.take_damage(amount)
	var note := Damage.effectiveness_text(float(result["type_multiplier"]))
	if not note.is_empty():
		log_lines.append(note)
	log_lines.append("%s takes %d." % [target.log_name(), dealt])
	return {
		"hit": true,
		"dealt": dealt,
		"type_multiplier": float(result["type_multiplier"]),
		"hp_ratio_before": hp_ratio_before,
	}


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
				if receiver == foe:
					_foe_healed_this_turn = true
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
	_mark_participant(index)
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


func _do_item(side: Side, item_id: String) -> void:
	if side != Side.PLAYER:
		return  # a wild creature carries nothing
	var item := Content.get_item(item_id)
	if item == null or not item.usable_in_battle or not Inventory.consume(item_id):
		log_lines.append("Nothing comes of it.")
		return

	log_lines.append("You use the %s." % item.display_name)
	match str(item.effect.get("kind", "")):
		ItemData.EFFECT_RESTRAIN_HIT:
			if restrained:
				log_lines.append("You are already holding back.")
			else:
				restrained = true
				_restrain_cap_ratio = float(item.effect.get("cap_ratio", 1.0))
				log_lines.append("You steady your hand. Nothing you do now can end this in one blow.")
		_:
			log_lines.append("Nothing comes of it.")


# --- Attunement --------------------------------------------------------
# docs/DESIGN.md section 13. Reactive temperaments (skittish, proud) are
# ticked from _perform right after the player's action resolves. Feral is
# passive and is ticked once at the end of submit(), from current HP state,
# so a foe's own mid-turn self-heal is reflected before the check runs.

func _tick_reactive_resonance(action_kind: String, move_result: Dictionary) -> void:
	var temperament := foe.temperament()
	var rules := Content.temperament_rules(temperament)
	if rules.is_empty():
		return

	# A landed, damaging hit -- the one fact both reactive temperaments care
	# about, computed once so neither branch below has to spell it out twice.
	var landed_hit := (
		action_kind == ACTION_MOVE
		and bool(move_result.get("hit", false))
		and int(move_result.get("dealt", 0)) > 0
	)

	var delta := 0.0
	var flavor_state := "stalled"

	match temperament:
		"skittish":
			if action_kind == ACTION_STILL:
				delta = float(rules.get("still_gain", 0)) * foe.creature.species().attunement_rate
				flavor_state = "gain"
			elif landed_hit:
				foe.resonance = 0.0
				flavor_state = "reset"
			# else: a miss, a self-buff, switching, fleeing, an item -- nothing
			# earned, nothing reset, but patience still erodes (see the stall
			# handling in _apply_resonance_delta).
		"proud":
			if action_kind == ACTION_STILL:
				delta = -float(rules.get("still_penalty", 0))
				flavor_state = "penalty_still"
			elif landed_hit:
				if float(move_result.get("hp_ratio_before", 0.0)) <= float(rules.get("healthy_ratio", 0.5)):
					pass  # already hurt -- nothing reads either way
				elif float(move_result.get("type_multiplier", 1.0)) > 1.0:
					delta = -float(rules.get("disrespect_penalty", 0))
					flavor_state = "penalty_disrespect"
				else:
					delta = float(rules.get("hit_gain", 0)) * foe.creature.species().attunement_rate
					flavor_state = "gain"
		_:
			return  # feral: handled passively, not from a specific action

	_apply_resonance_delta(delta, flavor_state, rules)


func _tick_feral_resonance() -> void:
	var rules := Content.temperament_rules("feral")
	if rules.is_empty():
		return

	if _foe_healed_this_turn and foe.resonance > 0.0:
		_apply_resonance_delta(-float(rules.get("healed_penalty", 0)), "healed", rules)
		return

	if foe.hp_ratio() <= float(rules.get("low_ratio", 0.3)):
		var gain := float(rules.get("low_gain", 0)) * foe.creature.species().attunement_rate
		_apply_resonance_delta(gain, "gain", rules)
	else:
		_apply_resonance_delta(0.0, "stalled", rules)


## Applies a Resonance change, logs the flavour line for it, updates the stall
## counter, and resolves capture or the foe fleeing if either threshold is
## crossed. The single place all three temperaments funnel through.
func _apply_resonance_delta(delta: float, flavor_state: String, rules: Dictionary) -> void:
	var before := foe.resonance
	foe.resonance = clampf(foe.resonance + delta, 0.0, 100.0)
	var actual_gain := foe.resonance - before

	if not flavor_state.is_empty():
		log_lines.append(_flavor_line(foe.temperament(), flavor_state))

	if foe.resonance >= float(Content.temperaments.get("capture_threshold", 100)):
		# Priority over a simultaneous faint: the hit that finally earns
		# capture should never read as the hit that killed it.
		_attune()
		return

	if actual_gain > 0.0:
		foe.stall_turns = 0
	else:
		foe.stall_turns += 1
		# A faint from this same hit is _resolve_faints()'s to report, not a
		# flee -- it takes priority. This can only be reached from a landed
		# hit (Still and misses never faint anything), so the check is cheap
		# and only matters on the rare turn both conditions line up.
		if foe.stall_turns >= int(Content.temperaments.get("stall_flee_turns", 6)) \
				and not foe.creature.is_fainted():
			log_lines.append("%s has had enough of this. It breaks and is gone." % foe.log_name())
			phase = Phase.FOE_FLED


func _attune() -> void:
	log_lines.append("Something in %s gives way, and settles toward you." % foe.creature.display_name())
	phase = Phase.ATTUNED
	if not Party.add(foe.creature):
		log_lines.append("There is no room to carry it yet, and it slips away regardless.")


func _flavor_line(temperament: String, state: String) -> String:
	var lines: Array = Content.temperament_rules(temperament).get("flavor", {}).get(state, [])
	if lines.is_empty():
		return ""
	return str(lines[rng.randi_range(0, lines.size() - 1)])


func _resolve_faints() -> void:
	# A single hit can, in principle, both be lethal and be the hit that
	# crosses the capture threshold (resonance was already close to 100, the
	# player wasn't Restrained, and the roll ran hot). _tick_reactive_resonance
	# runs first and would already have set ATTUNED -- that outcome wins; a
	# capture should never be silently overwritten by a faint from the same
	# blow.
	if phase != Phase.CHOOSING:
		return
	if foe.creature.is_fainted():
		log_lines.append("%s goes down." % foe.log_name())
		phase = Phase.WON
		_grant_experience()
		return
	if active().creature.is_fainted():
		log_lines.append("%s goes down." % active().creature.display_name())
		phase = Phase.REPLACING if _has_healthy_reserve() else Phase.LOST


func _mark_participant(index: int) -> void:
	if index >= 0 and not participants.has(index):
		participants.append(index)


## What the defeated creature is worth. Scales with its level and with how
## strong its species is, so a rare heavy hitter pays better than a common one
## at the same level.
func experience_award() -> int:
	var species := foe.creature.species()
	if species == null:
		return 1
	var total := 0
	for stat_name in SpeciesData.STATS:
		total += int(species.base_stats.get(stat_name, 0))
	return maxi(1, int(float(foe.creature.level) * float(total) / 55.0))


func _grant_experience() -> void:
	var award := experience_award()
	for index in participants:
		if index < 0 or index >= party.size():
			continue
		var creature := party[index].creature
		# A creature that went down does not get paid for it.
		if creature.is_fainted():
			continue
		var before := creature.level
		var levels := creature.gain_experience(award)
		log_lines.append("%s gains %d." % [creature.display_name(), award])
		if levels > 0:
			log_lines.append("%s reaches level %d." % [creature.display_name(), creature.level])
			_learn_new_moves(creature, before)


## Moves learned by levelling. With a full list the move is announced and
## skipped rather than silently replacing something -- choosing what to forget
## needs a prompt, which does not exist yet.
func _learn_new_moves(creature: Creature, from_level: int) -> void:
	var species := creature.species()
	if species == null:
		return
	for level in range(from_level + 1, creature.level + 1):
		for move_id in species.moves_learned_at(level):
			if creature.moves.has(move_id):
				continue
			var move := Content.get_move(move_id)
			var move_name := move.display_name if move != null else move_id
			if creature.moves.size() >= Creature.MAX_MOVES:
				log_lines.append("%s could learn %s, but has no room." % [
					creature.display_name(), move_name,
				])
				continue
			creature.moves.append(move_id)
			creature.move_uses.append(move.uses if move != null else 0)
			log_lines.append("%s learns %s." % [creature.display_name(), move_name])


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
