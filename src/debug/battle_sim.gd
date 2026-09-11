extends Control
## Runs complete battles headlessly and reports the aggregate.
##
## The turn loop is the one part of the game that can fail by never finishing,
## and that failure is invisible in a single playthrough. This drives
## BattleState directly with a simple policy on both sides and reports how long
## battles run, so termination and pacing are checked in bulk rather than by
## playing hundreds of fights by hand.
##
## Open scenes/debug/battle_sim.tscn and press F6. Z re-runs with a new seed.

const BATTLE_COUNT := 400
## Well above any plausible honest battle. Anything hitting this is a loop that
## cannot end -- which is real: if both sides exhaust every move, nothing in the
## rules currently breaks the stalemate.
const TURN_CAP := 250
const PARTY_SIZE := 3
const MIN_LEVEL := 10
const MAX_LEVEL := 20

@onready var _report: RichTextLabel = $Report

var _seed := 20260911


func _ready() -> void:
	_run()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and event.is_action("interact"):
		_seed += 1
		_run()
		get_viewport().set_input_as_handled()


func _run() -> void:
	if not Content.loaded:
		_report.text = "[color=#e0806a]Content failed to load.[/color]"
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var ids := Content.species_ids()

	var wins := 0
	var losses := 0
	var attuned := 0
	var foe_fled := 0
	var stalled := 0
	var turns := PackedInt32Array()
	var shortest := TURN_CAP
	var longest := 0

	for _battle in BATTLE_COUNT:
		var party := []
		for _slot in PARTY_SIZE:
			party.append(Creature.create(
				ids[rng.randi_range(0, ids.size() - 1)],
				rng.randi_range(MIN_LEVEL, MAX_LEVEL)))
		var wild := Creature.create(
			ids[rng.randi_range(0, ids.size() - 1)],
			rng.randi_range(MIN_LEVEL, MAX_LEVEL))

		var state := BattleState.create(party, wild, rng.randi_range(1, 1 << 30))
		var guard := 0
		while not state.is_over() and guard < TURN_CAP:
			guard += 1
			if state.phase == BattleState.Phase.REPLACING:
				state.replace_active(_first_standing(state))
				continue
			state.submit(_policy(state))

		if guard >= TURN_CAP:
			stalled += 1
		elif state.phase == BattleState.Phase.WON:
			wins += 1
		elif state.phase == BattleState.Phase.LOST:
			losses += 1
		elif state.phase == BattleState.Phase.ATTUNED:
			attuned += 1
		elif state.phase == BattleState.Phase.FOE_FLED:
			foe_fled += 1
		turns.append(guard)
		shortest = mini(shortest, guard)
		longest = maxi(longest, guard)

	var total := 0
	for value in turns:
		total += value
	var average := float(total) / float(maxi(1, turns.size()))

	var lines := PackedStringArray()
	lines.append("[b]Battle simulation[/b]  [color=#5d6878]seed %d[/color]" % _seed)
	lines.append("")
	lines.append("%d battles, parties of %d, levels %d-%d" % [
		BATTLE_COUNT, PARTY_SIZE, MIN_LEVEL, MAX_LEVEL])
	lines.append("")
	lines.append("turns   [b]avg %.1f[/b]   min %d   max %d" % [average, shortest, longest])
	lines.append("player  won %d  (%.0f%%)   lost %d" % [
		wins, 100.0 * float(wins) / float(BATTLE_COUNT), losses])
	lines.append("[color=#5d6878]this policy never Stills or uses items, so these are mostly accidental:[/color]")
	lines.append("attuned %d   foe fled %d" % [attuned, foe_fled])

	if stalled > 0:
		lines.append("")
		lines.append("[color=#e0806a]%d battle(s) hit the %d-turn cap — the loop did not terminate[/color]"
			% [stalled, TURN_CAP])
	else:
		lines.append("[color=#8fd19e]every battle terminated[/color]")

	lines.append("")
	lines.append("[color=#5d6878]Z re-runs with a new seed[/color]")
	_report.text = "\n".join(lines)


func _first_standing(state: BattleState) -> int:
	for i in state.party.size():
		if not state.party[i].creature.is_fainted():
			return i
	return 0


## Deliberately naive: always the hardest-hitting available move, never a switch.
## A smarter policy would shorten battles, so this is the pessimistic bound.
func _policy(state: BattleState) -> Dictionary:
	var best := ""
	var best_amount := -1
	for option in state.move_options():
		if int(option["uses"]) <= 0:
			continue
		var move := Content.get_move(str(option["id"]))
		if move == null or not move.is_damaging():
			continue
		var amount := int(Damage.compute(state.active(), state.foe, move, Damage.VARIANCE_MAX)["amount"])
		if amount > best_amount:
			best_amount = amount
			best = str(option["id"])
	if best.is_empty():
		return {"kind": BattleState.ACTION_STILL}
	return {"kind": BattleState.ACTION_MOVE, "move": best}
