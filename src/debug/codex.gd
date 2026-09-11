extends Control
## Developer view of the creature data model. Not part of the game.
##
## Open scenes/debug/codex.tscn and press F6 (Run Current Scene) to check that
## data/ parses, that stats grow the way docs/DESIGN.md says, and that the type
## chart and the damage formula agree with each other.

const PREVIEW_LEVELS := [5, 25, 50]
## Damage is previewed at the level cap, where the numbers are largest and any
## scaling mistake is most obvious.
const BATTLE_LEVEL := SpeciesData.MAX_LEVEL

const COLOR_DIM := "5d6878"
const COLOR_HEAD := "8fa1b8"
const COLOR_GOOD := "8fd19e"
const COLOR_BAD := "e0806a"
const COLOR_SELECTED := "e8c37a"

var _ids := PackedStringArray()
var _index := 0
var _foe_index := 0

@onready var _roster: RichTextLabel = $Roster
@onready var _left: RichTextLabel = $LeftPane
@onready var _right: RichTextLabel = $RightPane
@onready var _footer: RichTextLabel = $Footer


func _ready() -> void:
	_footer.text = "[color=#%s]W/S creature    A/D opponent[/color]" % COLOR_DIM
	if not Content.loaded:
		_left.text = "[color=#%s]Content failed to load.\nCheck the Output panel.[/color]" % COLOR_BAD
		return
	_ids = Content.species_ids()
	if _ids.is_empty():
		_left.text = "[color=#%s]No creatures in data/creatures.json.[/color]" % COLOR_BAD
		return
	_foe_index = 1 % _ids.size()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _ids.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("move_down"):
		_index = wrapi(_index + 1, 0, _ids.size())
	elif event.is_action("move_up"):
		_index = wrapi(_index - 1, 0, _ids.size())
	elif event.is_action("move_right"):
		_foe_index = wrapi(_foe_index + 1, 0, _ids.size())
	elif event.is_action("move_left"):
		_foe_index = wrapi(_foe_index - 1, 0, _ids.size())
	else:
		return
	get_viewport().set_input_as_handled()
	_refresh()


func _refresh() -> void:
	_render_roster()
	var species := Content.get_species(_ids[_index])
	var foe := Content.get_species(_ids[_foe_index])
	if species == null or foe == null:
		return
	_render_species(species)
	_render_matchup(species, foe)


func _render_roster() -> void:
	var names := PackedStringArray()
	for i in _ids.size():
		var species := Content.get_species(_ids[i])
		var label := species.display_name if species != null else _ids[i]
		if i == _index:
			names.append("[color=#%s][b]%s[/b][/color]" % [COLOR_SELECTED, label])
		elif i == _foe_index:
			names.append("[color=#%s]%s[/color]" % [COLOR_HEAD, label])
		else:
			names.append("[color=#%s]%s[/color]" % [COLOR_DIM, label])
	_roster.text = " ".join(names)


func _render_species(species: SpeciesData) -> void:
	var header := PackedStringArray(["", "base"])
	for level in PREVIEW_LEVELS:
		header.append("L%d" % level)

	var body: Array = []
	for stat_name in SpeciesData.STATS:
		var row := PackedStringArray([stat_name])
		row.append(str(int(species.base_stats.get(stat_name, 0))))
		for level in PREVIEW_LEVELS:
			row.append(str(species.stat_at(stat_name, level)))
		body.append(row)

	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % species.display_name)
	lines.append("[color=#%s]%s · %s · attune x%.2f[/color]" % [
		COLOR_HEAD, " / ".join(species.types), species.temperament, species.attunement_rate,
	])
	lines.append(_table(header, body))
	_left.text = "\n".join(lines)


func _render_matchup(species: SpeciesData, foe: SpeciesData) -> void:
	var lines := PackedStringArray()

	for type_id in species.types:
		var parts := PackedStringArray()
		var matchups := Content.type_chart.matchups_for(type_id)
		for defender in Content.type_chart.ring:
			if not matchups.has(defender):
				continue
			var value := float(matchups[defender])
			var colour := COLOR_GOOD if value > TypeChart.NEUTRAL else COLOR_BAD
			parts.append("[color=#%s]%s x%s[/color]" % [colour, defender, _format(value)])
		lines.append("[color=#%s]%s attacks[/color]  %s" % [
			COLOR_DIM, type_id, " · ".join(parts),
		])

	lines.append("")
	lines.append("[color=#%s]at L%d against[/color] [b]%s[/b] [color=#%s](%s)[/color]" % [
		COLOR_DIM, BATTLE_LEVEL, foe.display_name, COLOR_HEAD, " / ".join(foe.types),
	])

	# Running the real Creature and Damage code rather than re-deriving the
	# numbers here, so this pane fails when the game would fail.
	var attacker := Creature.create(species.id, BATTLE_LEVEL)
	var defender := Creature.create(foe.id, BATTLE_LEVEL)
	var body: Array = []
	var best := 0

	for move_id in attacker.moves:
		var move := Content.get_move(move_id)
		if move == null:
			continue
		var result := Damage.compute(attacker, defender, move, Damage.VARIANCE_MAX)
		var amount := int(result["amount"])
		var note := ""
		var amount_text := "[color=#%s]--[/color]" % COLOR_DIM
		if bool(result["is_damaging"]):
			best = maxi(best, amount)
			amount_text = str(amount)
			var multiplier := float(result["type_multiplier"])
			if not is_equal_approx(multiplier, TypeChart.NEUTRAL):
				var colour := COLOR_GOOD if multiplier > TypeChart.NEUTRAL else COLOR_BAD
				note = "[color=#%s]x%s[/color]" % [colour, _format(multiplier)]
			if float(result["stab"]) > 1.0:
				note += " [color=#%s]STAB[/color]" % COLOR_HEAD
		body.append(PackedStringArray([move.display_name, amount_text, note]))

	lines.append(_table(PackedStringArray(["move", "dmg", ""]), body))

	var foe_hp := defender.max_hp()
	if best > 0:
		lines.append("[color=#%s]%d HP — best move KOs in %.1f hits[/color]" % [
			COLOR_DIM, foe_hp, float(foe_hp) / float(best),
		])
	else:
		lines.append("[color=#%s]%d HP — no damaging move[/color]" % [COLOR_DIM, foe_hp])

	_right.text = "\n".join(lines)


func _table(header: PackedStringArray, body: Array) -> String:
	var out := "[table=%d]" % header.size()
	for cell in header:
		out += "[cell][color=#%s]%s[/color][/cell]" % [COLOR_DIM, cell]
	for row in body:
		for cell in row:
			out += "[cell]%s[/cell]" % cell
	return out + "[/table]"


## Trims "2.00" to "2" and "0.50" to "0.5" so multipliers read cleanly.
func _format(value: float) -> String:
	return ("%.2f" % value).rstrip("0").rstrip(".")
