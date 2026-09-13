extends Node
## How far the player has got in the one story the game tells.
##
## Registered as the `Journal` autoload, so it deliberately has no class_name.
## Must come after Content, which parses the stage list.
##
## The model is a single ordered position, not a set of flags. Every question
## the game asks of the story is "has the player got at least this far" --
## which line an NPC says, whether a road is worth mentioning, what the pause
## menu shows as the current objective -- and a position answers all of those
## without anyone having to reason about which combinations of flags are
## possible. It also cannot be corrupted into a state the writing does not
## cover, which a bag of booleans can and eventually does.
##
## Moving backwards is not possible: advance_to() on an earlier stage is
## ignored rather than treated as an error, because walking back into a map
## and re-reading a sign is a normal thing to do and must not undo progress.
## See docs/DESIGN.md § 30.

signal advanced(stage_id: String)

## Position in Content.story_stages. Zero is the beginning, never "unset".
var stage := 0


func _ready() -> void:
	reset_for_new_game()


func reset_for_new_game() -> void:
	stage = 0


## The stage the player is currently on.
func stage_id() -> String:
	return _id_at(stage)


## What the player is meant to be doing now, for the pause menu to show.
func objective() -> String:
	if stage < 0 or stage >= Content.story_stages.size():
		return ""
	return str(Content.story_stages[stage].get("objective", ""))


## Position of a stage id, or -1 if no such stage exists. An unknown id is a
## content error -- a typo in a map file -- so it says so rather than quietly
## behaving as though the stage were in the past or the future.
func index_of(stage_id_: String) -> int:
	for i in Content.story_stages.size():
		if str(Content.story_stages[i].get("id", "")) == stage_id_:
			return i
	return -1


## True once the player is at `stage_id_` or anywhere past it.
func reached(stage_id_: String) -> bool:
	var index := index_of(stage_id_)
	if index < 0:
		push_error("Journal: no story stage with id '%s'." % stage_id_)
		return false
	return stage >= index


## Moves the story forward to `stage_id_`, if that is forward. Returns true
## only when something actually changed, so callers can show the new objective
## exactly once rather than every time the player re-reads the same sign.
func advance_to(stage_id_: String) -> bool:
	var index := index_of(stage_id_)
	if index < 0:
		push_error("Journal: cannot advance to unknown story stage '%s'." % stage_id_)
		return false
	if index <= stage:
		return false
	stage = index
	advanced.emit(stage_id_)
	return true


func to_dict() -> Dictionary:
	# Saved by id, not by index: inserting a stage in the middle would
	# otherwise silently move every existing save to the wrong place in the
	# story.
	return {"stage": stage_id()}


func from_dict(data: Dictionary) -> void:
	var saved := str(data.get("stage", ""))
	if saved.is_empty():
		stage = 0
		return
	var index := index_of(saved)
	if index < 0:
		# A save written before a stage was renamed or removed. Starting the
		# story over is wrong, but so is guessing; the beginning is at least a
		# state the writing covers.
		push_warning("Journal: save names unknown story stage '%s'; starting over." % saved)
		index = 0
	stage = index


func _id_at(index: int) -> String:
	if index < 0 or index >= Content.story_stages.size():
		return ""
	return str(Content.story_stages[index].get("id", ""))
