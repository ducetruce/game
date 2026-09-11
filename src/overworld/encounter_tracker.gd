class_name EncounterTracker
extends RefCounted
## Turns distance travelled into encounter checks.
##
## Grid-locked movement counts steps. Free movement has no steps to count, so
## this accumulates world distance instead and rolls once every STRIDE pixels
## covered inside an encounter zone.
##
## The consequence is deliberate: risk is per distance, not per second. Running
## through bracken does not dodge encounters, it just meets the same number of
## them sooner. Creeping is safer per second and identical per tile.

## Tuned with the map's chance so a check lands roughly every 14 tiles: about
## four seconds at a walk, a little over two at a run.
const STRIDE := 28.0

## Travel required after a battle before checks resume, so walking out of the
## bracken you just fought in does not immediately drop you into another fight.
const GRACE := 56.0

var _travelled := 0.0
var _grace_left := 0.0


func start_grace() -> void:
	_grace_left = GRACE
	_travelled = 0.0


## Feed one frame of movement. Returns true when a check fires and passes.
func advance(distance: float, chance: float, rng: RandomNumberGenerator) -> bool:
	if distance <= 0.0:
		return false
	if _grace_left > 0.0:
		_grace_left -= distance
		return false
	if chance <= 0.0:
		# Outside a zone. Progress resets, so crossing a corner of bracken
		# repeatedly cannot bank a check.
		_travelled = 0.0
		return false
	_travelled += distance
	if _travelled < STRIDE:
		return false
	_travelled -= STRIDE
	return rng.randf() < chance
