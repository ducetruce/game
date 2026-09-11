class_name Damage
extends RefCounted
## Damage calculation.
##
## Lives outside the battle scene so it can be exercised without one --
## scenes/debug/codex.tscn calls straight into it. Variance is passed in rather
## than rolled here, so callers that need a deterministic number (previews,
## tests) can ask for one.

## Tuned so a neutral same-type hit takes about four turns to KO, super
## effective takes two to three, and resisted takes six or more. That spread is
## what makes Attunement viable: a wild fight has to last long enough to read
## the creature and act on it.
const DAMAGE_DIVISOR := 50.0
const LEVEL_DIVISOR := 5.0

## The attacker's stat is divided by the defender's, then raised to this power.
## Below 1.0 it dampens the ratio: doubling your attack stat against a given
## defence multiplies damage by 2^0.75 = 1.68, not 2. Stat advantages still
## matter, they just stop compounding with STAB and a x2 type match into a
## one-shot. Without it, the hardest hitter in the roster one-shots the
## frailest -- which would make a Feral creature (attunable only at low HP)
## impossible to capture at all.
const RATIO_EXPONENT := 0.75
const STAB_MULTIPLIER := 1.5
const VARIANCE_MIN := 0.85
const VARIANCE_MAX := 1.0

## Every hit lands for at least this much. There is deliberately no flat bonus
## added to `base` on top of it: a constant term is negligible against a level
## 50 health pool but enormous against a level 8 one, and it was turning the
## early game -- exactly where the player is learning to tame things -- into
## three-turn fights with one-shots at level parity.
const MINIMUM_DAMAGE := 1


static func roll_variance(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(VARIANCE_MIN, VARIANCE_MAX)


## Takes Combatants, not Creatures, so stat stages are always applied -- there
## is no overload here that quietly skips them.
##
## Returns a breakdown rather than a bare number, because the battle log needs
## to say *why* a hit landed the way it did. `variance` is a multiplier,
## normally from roll_variance; pass VARIANCE_MAX for a deterministic preview.
static func compute(
	attacker: Combatant,
	defender: Combatant,
	move: MoveData,
	variance: float = VARIANCE_MAX
) -> Dictionary:
	var result := {
		"amount": 0,
		"type_multiplier": TypeChart.NEUTRAL,
		"stab": 1.0,
		"attack_stat": 0,
		"defense_stat": 0,
		"is_damaging": move.is_damaging(),
	}
	if not move.is_damaging():
		return result

	var attack := attacker.stat(move.attack_stat())
	var defence := maxi(1, defender.stat(move.defense_stat()))
	result["attack_stat"] = attack
	result["defense_stat"] = defence

	var level_factor := 2.0 * float(attacker.level) / LEVEL_DIVISOR + 2.0
	var ratio := pow(float(attack) / float(defence), RATIO_EXPONENT)
	var base := level_factor * float(move.power) * ratio / DAMAGE_DIVISOR

	var type_multiplier := Content.type_chart.multiplier(move.type, defender.types())
	var stab := STAB_MULTIPLIER if attacker.types().has(move.type) else 1.0
	result["type_multiplier"] = type_multiplier
	result["stab"] = stab

	result["amount"] = maxi(MINIMUM_DAMAGE, int(floorf(base * type_multiplier * stab * variance)))
	return result


## Wording for the battle log. Kept next to the formula so the thresholds and
## the multipliers cannot drift apart.
static func effectiveness_text(type_multiplier: float) -> String:
	if is_equal_approx(type_multiplier, TypeChart.NEUTRAL):
		return ""
	if type_multiplier > TypeChart.NEUTRAL:
		return "It struck something vital."
	return "It barely registered."
