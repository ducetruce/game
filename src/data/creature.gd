class_name Creature
extends RefCounted
## A specific creature: a species instance with its own level, damage and move
## list. This is what fills the party, what battles, and what save files
## serialise -- so to_dict/from_dict here define most of the save schema.

const MAX_MOVES := 4


static func create(species_id: String, level: int) -> Creature:
	var creature := Creature.new()
	creature.species_id = species_id
	creature.level = clampi(level, 1, SpeciesData.MAX_LEVEL)
	creature.experience = experience_for_level(creature.level)
	creature.relearn_moves()
	creature.restore()
	return creature


var species_id := ""
var nickname := ""
var level := 1
var experience := 0
var current_hp := 0
var moves := PackedStringArray()
var move_uses := PackedInt32Array()


func species() -> SpeciesData:
	return Content.get_species(species_id)


func display_name() -> String:
	if not nickname.is_empty():
		return nickname
	var data := species()
	return data.display_name if data != null else species_id


func stat(stat_name: String) -> int:
	var data := species()
	if data == null:
		return 1
	return data.stat_at(stat_name, level)


func max_hp() -> int:
	return stat("hp")


func is_fainted() -> bool:
	return current_hp <= 0


func types() -> PackedStringArray:
	var data := species()
	return data.types if data != null else PackedStringArray()


## Full HP and full move uses.
func restore() -> void:
	current_hp = max_hp()
	refill_moves()


func refill_moves() -> void:
	move_uses = PackedInt32Array()
	for move_id in moves:
		var move := Content.get_move(move_id)
		move_uses.append(move.uses if move != null else 0)


## Replace the move list with the most recent MAX_MOVES this species knows at
## its current level. Only used when creating a creature -- levelling up asks
## the player what to forget rather than silently overwriting.
func relearn_moves() -> void:
	var data := species()
	var known := data.moves_known_at(level) if data != null else PackedStringArray()
	moves = PackedStringArray()
	var first := maxi(0, known.size() - MAX_MOVES)
	for i in range(first, known.size()):
		moves.append(known[i])


func take_damage(amount: int) -> int:
	var dealt := clampi(amount, 0, current_hp)
	current_hp -= dealt
	return dealt


func heal(amount: int) -> int:
	var healed := clampi(amount, 0, max_hp() - current_hp)
	current_hp += healed
	return healed


func spend_use(move_id: String) -> bool:
	var index := moves.find(move_id)
	if index < 0 or index >= move_uses.size() or move_uses[index] <= 0:
		return false
	move_uses[index] -= 1
	return true


# --- levelling -------------------------------------------------------------
# One curve for every species. Per-species growth rates can be added later
# without changing anything that has already stored an experience total.

static func experience_for_level(target_level: int) -> int:
	var effective := clampi(target_level, 1, SpeciesData.MAX_LEVEL)
	var steps := effective - 1
	return steps * steps * steps


static func level_for_experience(total: int) -> int:
	var found := 1
	while found < SpeciesData.MAX_LEVEL and total >= experience_for_level(found + 1):
		found += 1
	return found


## Adds experience and returns how many levels were gained. HP gained from
## levelling is granted immediately, so levelling never heals damage already
## taken but also never leaves a creature above its new maximum.
func gain_experience(amount: int) -> int:
	if amount <= 0 or level >= SpeciesData.MAX_LEVEL:
		return 0
	var before := level
	var hp_before := max_hp()
	experience += amount
	level = level_for_experience(experience)
	current_hp = mini(current_hp + (max_hp() - hp_before), max_hp())
	return level - before


# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"species": species_id,
		"nickname": nickname,
		"level": level,
		"experience": experience,
		"current_hp": current_hp,
		"moves": Array(moves),
		"move_uses": Array(move_uses),
	}


static func from_dict(data: Dictionary) -> Creature:
	var creature := Creature.new()
	creature.species_id = str(data.get("species", ""))
	creature.nickname = str(data.get("nickname", ""))
	creature.level = clampi(int(data.get("level", 1)), 1, SpeciesData.MAX_LEVEL)
	creature.experience = int(data.get("experience", 0))

	for move_id in data.get("moves", []):
		creature.moves.append(str(move_id))
	for remaining in data.get("move_uses", []):
		creature.move_uses.append(int(remaining))
	# A save written before a move was added to a species would desync these.
	while creature.move_uses.size() < creature.moves.size():
		creature.move_uses.append(0)

	creature.current_hp = clampi(int(data.get("current_hp", 0)), 0, creature.max_hp())
	return creature
