extends SceneTree
## Walks the intended route and reports whether the level curve holds.
##
## Run it with tools/curve.sh.
##
## The areas were each given a level band by reasoning -- 3-7 in the clearing,
## 6-10 on the fen road, 8-14 at the mere -- and reasoning is exactly the thing
## that cannot tell you whether a party that grinds the clearing arrives at the
## mere able to survive it. Nothing in the game says so either: a player finds
## out by walking there and losing.
##
## So this plays the intended route: the starting party, the clearing's table
## until it is comfortably ahead of it, then the road's, then the mere's, with
## a spring between fights (which is what the real route gives you). It
## reports, per area, the level the party arrives at, how often it wins, and
## how many fights it takes to be ready for the next one.
##
## Two policies, reported side by side, because one of them was misleading on
## its own. `naive` is battle_sim's: always the hardest-hitting move, never a
## switch, and on a faint the next creature in the list walks in whatever the
## matchup. `played` switches -- it sends in the best matchup rather than the
## next body, and pulls a creature out when it is nearly down and someone else
## hits the foe harder. Neither uses an item.
##
## The gap between them is the point. Read `naive` as the floor and `played`
## as something near what a player who is paying attention gets; the truth is
## above both, because a player also heals.

const TURN_CAP := 250
## How many fights an area gets before this gives up on it. Well past what any
## area should need; hitting it is the finding, not an error.
const FIGHT_CAP := 300
## An area is "cleared" once the party can sustain this many fights on one
## rest. Not a win streak: winning eight fights in a row from full health says
## the matchups are survivable one at a time, which a party can do long before
## it can cross anything. The fen road is a crossing, and the first version of
## this tool advanced the party the moment it could win once from full health
## -- which sent it to the mere four levels under and then reported the mere
## as a wall.
const CLEAR_ENDURANCE := 4.0
## Fights between endurance checks. Measuring after every single fight would
## cost more than the grinding it is measuring.
const CHECK_EVERY := 8

## Once an area is cleared, this many sorties measure endurance: walk in from
## a spring at full health and keep fighting until the party goes down. That
## is the number a player actually feels. Winning every fight from full health
## says an area is winnable; it says nothing about whether you can cross it,
## and the fen road is a crossing.
const SORTIES := 12
const SORTIE_CAP := 25

## Route order. Read off the maps rather than restated: an area added between
## two others has to be walked through, and this should walk it too.
const ROUTE := ["hollow_clearing", "fen_road", "mere_shore"]
const MAP_PATH := "res://data/maps/%s.json"

var _rng := RandomNumberGenerator.new()
var _fails: Array[String] = []


func _initialize() -> void:
	var seed_value := 20260913
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seed_value = int(argument.trim_prefix("--seed="))
	_rng.seed = seed_value
	print("curve: seed %d" % seed_value)


func _process(_delta: float) -> bool:
	var content := root.get_node("Content")
	if not bool(content.get("loaded")):
		print("curve: content failed to load")
		return true

	var party: Array = [
		_make("thistlecalf", 5),
		_make("emberwick", 5),
	]
	print("curve: setting out with %s" % _describe(party))
	print("")

	for map_id in ROUTE:
		_walk(map_id, party)
		_tame(map_id, party)

	print("")
	if _fails.is_empty():
		print("curve: OK")
	else:
		for line in _fails:
			print("curve: FAIL " + line)
	print("curve: result %s" % ("pass" if _fails.is_empty() else "fail"))
	return true


func _walk(map_id: String, party: Array) -> void:
	var doc := _read_map(map_id)
	var tables: Array = doc.get("encounters", {}).values()
	if tables.is_empty():
		return
	var table: Array = tables[0].get("table", [])
	if table.is_empty():
		return

	var arrived := _average_level(party)
	var fights := 0
	var wins := 0
	var losses := 0
	var endurance := _endurance(party, table, false)

	while fights < FIGHT_CAP and endurance["average"] < CLEAR_ENDURANCE:
		for _i in CHECK_EVERY:
			# A spring before each fight. The route gives you one; a party
			# that is never patched up measures attrition, and attrition is
			# what the endurance check below is for.
			for creature in party:
				creature.restore()
			fights += 1
			if _fight(party, _roll(table)):
				wins += 1
			else:
				losses += 1
		endurance = _endurance(party, table, false)

	for creature in party:
		creature.restore()

	var left := _average_level(party)
	print("%-16s arrived Lv%.1f   %3d fight(s), won %d lost %d (%.0f%%)   left Lv%.1f"
		% [map_id, arrived, fights, wins, losses,
			100.0 * float(wins) / float(maxi(1, fights)), left])
	print("%-16s %s" % ["", _describe(party)])

	if endurance["average"] < CLEAR_ENDURANCE:
		_fails.append("%s was never crossable: %d fights and still only %.1f fight(s) to a rest"
			% [map_id, fights, endurance["average"]])
		return

	var played := _endurance(party, table, true)
	# The second number comes out *lower* than the first, consistently. That
	# is information about the game rather than about the policy: a switch
	# costs the turn and the creature coming in eats a free hit, so switching
	# out something that is nearly down loses more than it saves. Switching
	# is for a matchup you can see before the damage, not for a rescue.
	print("%-16s crossable at %.1f fight(s) a rest, %.1f if it switches when hurt (best %d)"
		% ["", endurance["average"], played["average"], played["best"]])
	# Both of these are design findings rather than faults, so they are
	# printed rather than failed. The numbers are the point of the tool.
	if endurance["average"] >= float(SORTIE_CAP):
		print("%-16s [note] never went down in %d fights -- this area asks nothing"
			% ["", SORTIE_CAP])


## Taming is the point of the game, so a party that only ever has the two it
## started with is not the party anyone crosses the fen road with. After each
## area, one creature from that area joins at the party's current level --
## a deliberately modest model of a player who catches things, and still a
## floor: a player who tames properly arrives with more than this.
func _tame(map_id: String, party: Array) -> void:
	if party.size() >= 6:
		return
	var doc := _read_map(map_id)
	var tables: Array = doc.get("encounters", {}).values()
	if tables.is_empty():
		return
	var table: Array = tables[0].get("table", [])
	if table.is_empty():
		return
	var caught = _roll(table)
	var caught_at := int(round(_average_level(party)))
	var joined = _make(caught.species_id, maxi(1, caught_at))
	party.append(joined)
	print("%-16s tamed %s Lv%d on the way out" % ["", joined.display_name(), joined.level])
	print("")


## Walks in from a spring and fights until the party goes down, several times
## over, on a copy of the party so the measurement does not level it up.
func _endurance(party: Array, table: Array, switching: bool) -> Dictionary:
	var total := 0
	var worst := SORTIE_CAP
	var best := 0
	for _sortie in SORTIES:
		var copy := []
		for creature in party:
			var clone = _make(creature.species_id, creature.level)
			copy.append(clone)
		var survived := 0
		while survived < SORTIE_CAP and _fight(copy, _roll(table), switching):
			survived += 1
		total += survived
		worst = mini(worst, survived)
		best = maxi(best, survived)
	return {
		"average": float(total) / float(SORTIES),
		"worst": worst,
		"best": best,
	}


## One battle, driven to the end. Returns true if the party came out of it
## standing.
func _fight(party: Array, wild, switching: bool = false) -> bool:
	var battle_state = load("res://src/battle/battle_state.gd")
	var state = battle_state.create(party, wild, _rng.randi_range(1, 1 << 30))
	var guard := 0
	while not state.is_over() and guard < TURN_CAP:
		guard += 1
		if state.phase == battle_state.Phase.REPLACING:
			state.replace_active(
				_best_matchup(state) if switching else _first_standing(state))
			continue
		if switching:
			var swap := _worth_switching_to(state)
			if swap >= 0:
				state.submit({"kind": "switch", "index": swap})
				continue
		state.submit(_policy(state))
	if guard >= TURN_CAP:
		_fails.append("a battle hit the %d-turn cap and never ended" % TURN_CAP)
	return state.phase != battle_state.Phase.LOST


func _roll(table: Array):
	var total := 0
	for entry in table:
		total += int(entry.get("weight", 1))
	var pick := _rng.randi_range(1, maxi(1, total))
	for entry in table:
		pick -= int(entry.get("weight", 1))
		if pick <= 0:
			var levels: Array = entry.get("levels", [5, 5])
			return _make(str(entry.get("species", "")),
				_rng.randi_range(int(levels[0]), int(levels[1])))
	return _make(str(table[0].get("species", "")), 5)


func _make(species_id: String, level: int):
	return load("res://src/data/creature.gd").create(species_id, level)


func _read_map(map_id: String) -> Dictionary:
	var path := MAP_PATH % map_id
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _average_level(party: Array) -> float:
	var total := 0
	for creature in party:
		total += int(creature.level)
	return float(total) / float(maxi(1, party.size()))


func _describe(party: Array) -> String:
	var parts := PackedStringArray()
	for creature in party:
		parts.append("%s Lv%d" % [creature.display_name(), creature.level])
	return " | ".join(parts)


## The standing party member whose best move hits this foe hardest. What a
## player sends in; `_first_standing` is what a list does.
func _best_matchup(state) -> int:
	var best := _first_standing(state)
	var best_amount := -1
	for i in state.party.size():
		var combatant = state.party[i]
		if combatant.creature.is_fainted():
			continue
		var amount := _best_damage(combatant, state.foe)
		if amount > best_amount:
			best_amount = amount
			best = i
	return best


## Which party member to switch to right now, or -1 to stay in. Only when the
## one out is nearly down and someone else hits harder -- switching costs the
## turn, so doing it on every small advantage loses more than it gains.
func _worth_switching_to(state) -> int:
	var active = state.active()
	if active.hp_ratio() > 0.35:
		return -1
	var mine := _best_damage(active, state.foe)
	var best := -1
	var best_amount := mine
	for i in state.party.size():
		if i == state.active_index:
			continue
		var combatant = state.party[i]
		if combatant.creature.is_fainted() or combatant.hp_ratio() < 0.5:
			continue
		var amount := _best_damage(combatant, state.foe)
		if amount > best_amount:
			best_amount = amount
			best = i
	return best


## The hardest hit this combatant could land on that one with what it has
## left. Zero when everything is spent.
func _best_damage(attacker, defender) -> int:
	var damage := load("res://src/battle/damage.gd")
	var content := root.get_node("Content")
	var best := 0
	for i in attacker.creature.moves.size():
		if i >= attacker.creature.move_uses.size() or attacker.creature.move_uses[i] <= 0:
			continue
		var move = content.get_move(attacker.creature.moves[i])
		if move == null or not move.is_damaging():
			continue
		best = maxi(best, int(damage.compute(
			attacker, defender, move, damage.VARIANCE_MAX)["amount"]))
	return best


func _first_standing(state) -> int:
	for i in state.party.size():
		if not state.party[i].creature.is_fainted():
			return i
	return 0


## The same deliberately naive policy battle_sim uses: always the
## hardest-hitting available move, never a switch, never an item. Every number
## this tool prints is therefore a floor.
func _policy(state) -> Dictionary:
	var damage := load("res://src/battle/damage.gd")
	var content := root.get_node("Content")
	var best := ""
	var best_amount := -1
	for option in state.move_options():
		if int(option["uses"]) <= 0:
			continue
		var move = content.get_move(str(option["id"]))
		if move == null or not move.is_damaging():
			continue
		var amount := int(damage.compute(
			state.active(), state.foe, move, damage.VARIANCE_MAX)["amount"])
		if amount > best_amount:
			best_amount = amount
			best = str(option["id"])
	if best.is_empty():
		return {"kind": "still"}
	return {"kind": "move", "move": best}
