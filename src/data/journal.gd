extends Node
## Every quest the player has taken up, how far each has got, and what the
## world has seen them do.
##
## Registered as the `Journal` autoload, so it deliberately has no class_name.
## Must come after Content, which parses the quest list.
##
## A quest is an ordered list of steps and the player's position in it -- the
## same model the single main story used before there were quests, and for the
## same reason: every question asked of a quest is "has the player got at least
## this far", and a position answers all of them without anyone reasoning about
## which combinations of flags are possible. What changed is that there are now
## many of them at once, so the position lives in a dictionary keyed by quest
## id rather than in one variable. See docs/DESIGN.md § 34.
##
## Quests never move backwards. Re-reading a sign is a normal thing to do and
## must not undo progress, so advancing to a step at or behind the current one
## is ignored rather than treated as an error.
##
## It also keeps a tally of what the player has defeated, because "slay this
## thing" is a quest shape and a step that asks for it needs somewhere to
## count. That is the only piece of state here that is not a quest position,
## and quests are its only reader.

signal quest_started(quest_id: String)
signal quest_advanced(quest_id: String, step_id: String)
signal quest_completed(quest_id: String)
## A tamer the player has already beaten has become due for a rematch. The
## overworld turns this into a letter.
signal rematch_due(tamer_id: String)

## How much play between beating a tamer and them coming looking for you.
## Twenty minutes is long enough that it is never the thing you are doing and
## short enough to happen inside one session.
const REMATCH_AFTER_SECONDS := 1200.0

## quest id -> index of the step the player is on.
var _step := {}
## quest ids finished, with their rewards paid.
var _done := {}
## species id -> how many of them the player has put down.
var _defeats := {}

## Seconds of play. Not wall-clock time and not time since the save was
## written: a player who leaves the game running overnight has not earned a
## rematch, and one who plays an hour a week has. Ticked by the overworld,
## which is the only place time passing means anything.
var playtime := 0.0

## tamer id -> the playtime reading when they were beaten. A tamer in here is
## beaten; one whose reading is more than REMATCH_AFTER_SECONDS behind is
## beaten and wants another go.
var _beaten_tamers := {}
## Tamers already announced as wanting a rematch, so the pigeon comes once.
var _challenges_sent := {}

## See debug_force_gauntlet_unlock().
var _debug_gauntlet_override := false


func _ready() -> void:
	reset_for_new_game()


func reset_for_new_game() -> void:
	_step.clear()
	_done.clear()
	_defeats.clear()
	playtime = 0.0
	_beaten_tamers.clear()
	_challenges_sent.clear()
	gauntlet_stage = 0
	_debug_gauntlet_override = false
	_visited_springs.clear()


# --- asking -----------------------------------------------------------------

func has_started(quest_id: String) -> bool:
	return _step.has(quest_id) or _done.has(quest_id)


func is_active(quest_id: String) -> bool:
	return _step.has(quest_id) and not _done.has(quest_id)


func is_complete(quest_id: String) -> bool:
	return _done.has(quest_id)


## Index of the step the player is on, or -1 if the quest has not begun. A
## finished quest reports its last step rather than -1: it is behind them, not
## ahead of them, and every `reached` test should keep passing.
func step_index(quest_id: String) -> int:
	if _done.has(quest_id):
		return maxi(0, _steps_of(quest_id).size() - 1)
	return int(_step.get(quest_id, -1))


func step_id(quest_id: String) -> String:
	var steps := _steps_of(quest_id)
	var index := step_index(quest_id)
	if index < 0 or index >= steps.size():
		return ""
	return str(steps[index].get("id", ""))


## True once the player is at `step` in `quest_id` or anywhere past it, a
## finished quest included. False for a quest not yet begun.
func reached(quest_id: String, step: String) -> bool:
	var wanted := _index_of_step(quest_id, step)
	if wanted < 0:
		push_error("Journal: quest '%s' has no step '%s'." % [quest_id, step])
		return false
	return step_index(quest_id) >= wanted


## What the player is meant to be doing in this quest, or "" if it is finished
## or unbegun.
func objective(quest_id: String) -> String:
	if not is_active(quest_id):
		return ""
	var steps := _steps_of(quest_id)
	var index := step_index(quest_id)
	if index < 0 or index >= steps.size():
		return ""
	return str(steps[index].get("objective", ""))


## Every quest the player is in the middle of, in the order the data declares
## them, as their ids.
func active_quests() -> PackedStringArray:
	var ids := PackedStringArray()
	for quest in Content.quests:
		var quest_id := str(quest.get("id", ""))
		if is_active(quest_id):
			ids.append(quest_id)
	return ids


func completed_count() -> int:
	return _done.size()


## The one line to show when no quest is telling the player what to do.
func idle_objective() -> String:
	return Content.default_objective


## What to put in front of the player at a glance: the first active quest's
## objective, or the idle line when nothing is running. "First" is declaration
## order, which is also roughly the order the world hands quests out.
func current_objective() -> String:
	for quest_id in active_quests():
		var line := objective(quest_id)
		if not line.is_empty():
			return line
	return idle_objective()


func gauntlet_unlocked() -> bool:
	return _debug_gauntlet_override or completed_count() >= Content.gauntlet_requirement


## Debug-menu only (its caller is itself gated on OS.is_debug_build()) --
## forces gauntlet_unlocked() true without touching _done, so there is no need
## to invent placeholder quest ids to pad the count and nothing here survives
## a save: this is a session-only escape hatch for testing the gauntlet before
## ten real quests exist to finish. See docs/DESIGN.md § 39.
func debug_force_gauntlet_unlock() -> void:
	_debug_gauntlet_override = true


# --- the gauntlet -------------------------------------------------------------
# A separate, much smaller state machine from quests, on purpose: the trials
# are strictly ordered (no skipping one, no revisiting a passed one out of
# curiosity) and there is no text variation to key off a step id the way a
# quest's dialogue does, so a single index is all there is. See
## docs/DESIGN.md § 39.

signal gauntlet_trial_passed(trial_id: String)
signal gauntlet_finished

## Saved in place of an index when every trial has been passed -- there is no
## "next trial" id to save at that point.
const GAUNTLET_COMPLETE_SENTINEL := "__complete__"

## Index into Content.gauntlet_trials of the trial still to be attempted.
## Equal to Content.gauntlet_trials.size() once every trial is behind the
## player, which is what gauntlet_finished() reads.
var gauntlet_stage := 0


## True once the trial at `index` has already been passed.
func gauntlet_trial_passed_at(index: int) -> bool:
	return index < gauntlet_stage


## True once the last trial has been passed. False on an empty trial list --
## nothing has been cleared if there was nothing to clear.
func gauntlet_finished_check() -> bool:
	return not Content.gauntlet_trials.is_empty() 		and gauntlet_stage >= Content.gauntlet_trials.size()


## Records trial `index` as passed. Ignored if `index` is not the trial
## actually waiting -- out of order is a caller bug, not a state to reach --
## so this can never be driven into skipping one or double-counting another.
## Emits gauntlet_finished once the trial that clears was the last one.
func advance_gauntlet(index: int) -> bool:
	if index != gauntlet_stage:
		return false
	var trial_id := ""
	if index < Content.gauntlet_trials.size():
		trial_id = str(Content.gauntlet_trials[index].get("id", ""))
	gauntlet_stage += 1
	gauntlet_trial_passed.emit(trial_id)
	if gauntlet_finished_check():
		gauntlet_finished.emit()
	return true


# --- fast travel ---------------------------------------------------------------
# Every rest spring the player has actually stood at and used, by id. A flat
# set rather than anything ordered: unlike a quest or the gauntlet, there is
# no sequence to a spring being reached, only whether it has been. See
# docs/DESIGN.md § 41.

var _visited_springs := {}


func has_visited_spring(spring_id: String) -> bool:
	return _visited_springs.has(spring_id)


func record_spring_visited(spring_id: String) -> void:
	if not spring_id.is_empty():
		_visited_springs[spring_id] = true


## Ids of every spring reached so far, in Content.springs' own order --
## stable and matching the order the travel screen lists everything else in.
func visited_spring_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for spring in Content.springs:
		var spring_id := str(spring.get("id", ""))
		if has_visited_spring(spring_id):
			ids.append(spring_id)
	return ids


# --- moving ------------------------------------------------------------------

## Moves `quest_id` to `step`, starting it if it had not begun. Returns true
## only when something actually changed, so a caller can announce the new
## objective exactly once rather than every time the player re-reads a sign.
func advance(quest_id: String, step: String) -> bool:
	var wanted := _index_of_step(quest_id, step)
	if wanted < 0:
		push_error("Journal: cannot advance quest '%s' to unknown step '%s'."
			% [quest_id, step])
		return false
	if _done.has(quest_id):
		return false
	var current := int(_step.get(quest_id, -1))
	if wanted <= current:
		return false

	var starting := current < 0
	_step[quest_id] = wanted
	if starting:
		quest_started.emit(quest_id)
	quest_advanced.emit(quest_id, step)
	return true


## Finishes `quest_id` and returns what it paid, or an empty dictionary if it
## was not there to be finished. Paying happens here rather than in the caller
## so a quest cannot be completed twice for twice the coin.
func complete(quest_id: String) -> Dictionary:
	if _done.has(quest_id) or not _step.has(quest_id):
		return {}
	# Only from the last step. The object that finishes a quest is usually the
	# one that started it -- the person who sent you is the person you report
	# back to -- so without this, talking to them the first time would finish
	# the quest on the spot and pay for it.
	if step_index(quest_id) < _steps_of(quest_id).size() - 1:
		return {}
	_done[quest_id] = true
	_step.erase(quest_id)

	var reward: Dictionary = _quest(quest_id).get("reward", {})
	var coin := int(reward.get("coin", 0))
	if coin > 0:
		Inventory.coin += coin
	var items := PackedStringArray()
	for item_id in reward.get("items", []):
		Inventory.add(str(item_id))
		items.append(str(item_id))
	quest_completed.emit(quest_id)
	return {"coin": coin, "items": items}


## Records that the player put one of these down. Called once per won battle.
func record_defeat(species_id: String) -> void:
	if species_id.is_empty():
		return
	_defeats[species_id] = int(_defeats.get(species_id, 0)) + 1


func defeats_of(species_id: String) -> int:
	return int(_defeats.get(species_id, 0))


# --- tamers ------------------------------------------------------------------

## Advances the clock and announces any tamer who has become due. Called by
## the overworld once per physics frame; nowhere else has a reason to.
func tick(delta: float) -> void:
	playtime += delta
	for tamer_id in _beaten_tamers:
		if _challenges_sent.has(tamer_id) or not wants_rematch(tamer_id):
			continue
		_challenges_sent[tamer_id] = true
		rematch_due.emit(tamer_id)


func has_beaten(tamer_id: String) -> bool:
	return _beaten_tamers.has(tamer_id)


## True for a tamer who has been beaten and has had long enough to want
## another go. False for one never beaten -- they want a *first* go, which is
## a different question and is just `not has_beaten`.
func wants_rematch(tamer_id: String) -> bool:
	if not _beaten_tamers.has(tamer_id):
		return false
	return playtime - float(_beaten_tamers[tamer_id]) >= REMATCH_AFTER_SECONDS


## True when this tamer will fight right now: never beaten, or beaten and due.
func will_fight(tamer_id: String) -> bool:
	return not has_beaten(tamer_id) or wants_rematch(tamer_id)


func record_tamer_beaten(tamer_id: String) -> void:
	if tamer_id.is_empty():
		return
	_beaten_tamers[tamer_id] = playtime
	# The clock restarts, so the next letter is a new one rather than the old
	# one still standing.
	_challenges_sent.erase(tamer_id)


# --- saving ------------------------------------------------------------------

func to_dict() -> Dictionary:
	# Steps are saved by id, not index: inserting a step in the middle of a
	# quest would otherwise silently move every existing save to the wrong
	# place in it.
	var steps := {}
	for quest_id in _step:
		steps[quest_id] = step_id(quest_id)
	return {
		"steps": steps,
		"done": _done.keys(),
		"defeats": _defeats.duplicate(),
		"playtime": playtime,
		"tamers": _beaten_tamers.duplicate(),
		"challenged": _challenges_sent.keys(),
		"gauntlet_stage": _gauntlet_stage_id(),
		"springs": _visited_springs.keys(),
	}


## Saved by the *id* of the trial still to come, not the raw index -- the same
## reason a quest step is: inserting a trial in the middle of the gauntlet
## must not silently move every existing save to a different trial.
## GAUNTLET_COMPLETE_SENTINEL covers "every trial is behind me", which has no
## id of its own to save; "" covers an empty trial list, which has no trial to
## name either.
func _gauntlet_stage_id() -> String:
	if gauntlet_finished_check():
		return GAUNTLET_COMPLETE_SENTINEL
	if gauntlet_stage < Content.gauntlet_trials.size():
		return str(Content.gauntlet_trials[gauntlet_stage].get("id", ""))
	return ""


func from_dict(data: Dictionary) -> void:
	reset_for_new_game()
	for quest_id in data.get("done", []):
		if _quest(str(quest_id)).is_empty():
			push_warning("Journal: save names unknown quest '%s'; dropping it." % quest_id)
			continue
		_done[str(quest_id)] = true
	var steps: Dictionary = data.get("steps", {})
	for quest_id in steps:
		var index := _index_of_step(str(quest_id), str(steps[quest_id]))
		if index < 0:
			# A save written before a step was renamed or removed. Dropping the
			# quest back to unbegun is wrong, but so is guessing at a position
			# that no longer exists, and unbegun is at least a state the
			# writing covers.
			push_warning("Journal: save names unknown step '%s' in quest '%s'; "
				% [steps[quest_id], quest_id] + "starting that quest over.")
			continue
		_step[str(quest_id)] = index
	var defeats: Dictionary = data.get("defeats", {})
	for species_id in defeats:
		_defeats[str(species_id)] = int(defeats[species_id])
	playtime = float(data.get("playtime", 0.0))
	var tamers: Dictionary = data.get("tamers", {})
	for tamer_id in tamers:
		_beaten_tamers[str(tamer_id)] = float(tamers[tamer_id])
	for tamer_id in data.get("challenged", []):
		_challenges_sent[str(tamer_id)] = true
	for spring_id in data.get("springs", []):
		_visited_springs[str(spring_id)] = true

	var stage_id := str(data.get("gauntlet_stage", ""))
	if stage_id == GAUNTLET_COMPLETE_SENTINEL:
		gauntlet_stage = Content.gauntlet_trials.size()
	elif not stage_id.is_empty():
		var found := -1
		for i in Content.gauntlet_trials.size():
			if str(Content.gauntlet_trials[i].get("id", "")) == stage_id:
				found = i
				break
		if found < 0:
			# A save written before a trial was renamed, removed, or
			# reordered. Same call as an unknown quest step: guessing at a
			# position that no longer exists is worse than the beginning,
			# which is at least a state the current trial list covers.
			push_warning("Journal: save names unknown gauntlet trial '%s'; "
				% stage_id + "starting the gauntlet over.")
		else:
			gauntlet_stage = found


# --- reading the data --------------------------------------------------------

func _quest(quest_id: String) -> Dictionary:
	for quest in Content.quests:
		if str(quest.get("id", "")) == quest_id:
			return quest
	return {}


func _steps_of(quest_id: String) -> Array:
	return _quest(quest_id).get("steps", [])


func _index_of_step(quest_id: String, step: String) -> int:
	var steps := _steps_of(quest_id)
	for i in steps.size():
		if str(steps[i].get("id", "")) == step:
			return i
	return -1
