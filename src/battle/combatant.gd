class_name Combatant
extends RefCounted
## A creature as it exists inside one battle: the persistent Creature, plus
## everything that evaporates when the battle ends.
##
## Damage calculations take Combatants rather than Creatures precisely so that
## stat stages are impossible to forget -- there is no way to ask this for an
## attack value and silently get the unmodified one.

const MIN_STAGE := -6
const MAX_STAGE := 6

var creature: Creature = null
var is_wild := false

## Attunement's meter, 0-100. Only meaningful for a wild Combatant.
var resonance := 0.0

## Turns since Resonance last increased. A universal safety valve: whatever
## the temperament, pushing the wrong action long enough ends the attempt.
var stall_turns := 0

var level: int:
	get:
		return creature.level if creature != null else 1

var _stages := {}


static func of(p_creature: Creature, p_is_wild: bool = false) -> Combatant:
	var combatant := Combatant.new()
	combatant.creature = p_creature
	combatant.is_wild = p_is_wild
	return combatant


## Standard stage curve: +1 is x1.5, -1 is x0.67, saturating at +-6.
static func stage_multiplier(stage_value: int) -> float:
	var clamped := clampi(stage_value, MIN_STAGE, MAX_STAGE)
	if clamped >= 0:
		return (2.0 + float(clamped)) / 2.0
	return 2.0 / (2.0 - float(clamped))


## Battle-effective value of a stat. HP is never staged.
func stat(stat_name: String) -> int:
	var raw := creature.stat(stat_name)
	if stat_name == "hp":
		return raw
	return maxi(1, int(floorf(float(raw) * stage_multiplier(stage(stat_name)))))


func stage(stat_name: String) -> int:
	return int(_stages.get(stat_name, 0))


## Returns how many stages actually moved, so the log can say "it will not
## shift further" instead of claiming a change that did not happen.
func adjust_stage(stat_name: String, delta: int) -> int:
	var before := stage(stat_name)
	var after := clampi(before + delta, MIN_STAGE, MAX_STAGE)
	_stages[stat_name] = after
	return after - before


func clear_stages() -> void:
	_stages.clear()


func types() -> PackedStringArray:
	return creature.types()


func hp_ratio() -> float:
	var maximum := creature.max_hp()
	return 0.0 if maximum <= 0 else clampf(float(creature.current_hp) / float(maximum), 0.0, 1.0)


## Name as it appears in the battle log. Wild creatures are never on
## first-name terms.
func log_name() -> String:
	if is_wild:
		return "The wild %s" % creature.display_name()
	return creature.display_name()


## Species' temperament, or "" if this combatant is not wild / has no species.
func temperament() -> String:
	var data := creature.species() if creature != null else null
	return data.temperament if data != null else ""
