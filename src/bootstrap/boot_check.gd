extends Node2D
## Boot check scene.
##
## Proves the project's display and input contract holds before any gameplay is
## built on top of it: 16px grid alignment, nearest-neighbour filtering,
## integer window scaling, and a live input map. Replaced by the overworld in
## step 2 — nothing else should depend on this script.

const TILE_SIZE := 16
const BASE_SIZE := Vector2i(320, 180)

const COLOR_BG := Color("14181f")
const COLOR_CHECKER := Color("1b2029")
const COLOR_MARK := Color("e8c37a")
const COLOR_TEXT := Color("cfd6e0")
const COLOR_DIM := Color("5d6878")
const COLOR_LIVE := Color("8fd19e")

## Every action defined in project.godot, so a missing binding shows up here
## rather than as a silent no-op in the overworld controller.
const ACTIONS: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "cancel", "run",
]

var _scale_label: Label
var _input_label: RichTextLabel


func _ready() -> void:
	_build_ui()
	get_window().size_changed.connect(_refresh_scale_readout)
	_refresh_scale_readout()


func _process(_delta: float) -> void:
	_refresh_input_readout()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(BASE_SIZE)), COLOR_BG)

	# 16px checkerboard. If the tiles look uneven or blurred at the window
	# edges, the stretch mode or texture filter has drifted from the contract.
	var cols := int(ceil(float(BASE_SIZE.x) / TILE_SIZE))
	var rows := int(ceil(float(BASE_SIZE.y) / TILE_SIZE))
	for y in rows:
		for x in cols:
			if (x + y) % 2 == 0:
				continue
			var pos := Vector2(x * TILE_SIZE, y * TILE_SIZE)
			draw_rect(Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE)), COLOR_CHECKER)

	# One tile outlined at a known grid position. Its edges must be exactly one
	# screen-pixel thick times the window scale, with no softening.
	var marked := Vector2(4 * TILE_SIZE, 2 * TILE_SIZE)
	draw_rect(Rect2(marked, Vector2(TILE_SIZE, TILE_SIZE)), COLOR_MARK, false, 1.0)


func _build_ui() -> void:
	_add_label("HOLLOWMERE", 60, 16, COLOR_TEXT)
	_add_label("boot check — step 1 of 6", 82, 8, COLOR_DIM)
	_scale_label = _add_label("", 96, 8, COLOR_DIM)

	_add_label("hold a key to verify the input map:", 140, 8, COLOR_DIM)

	_input_label = RichTextLabel.new()
	_input_label.bbcode_enabled = true
	_input_label.fit_content = true
	_input_label.scroll_active = false
	_input_label.position = Vector2(0, 154)
	_input_label.size = Vector2(BASE_SIZE.x, 20)
	_input_label.add_theme_font_size_override("normal_font_size", 8)
	add_child(_input_label)


func _add_label(text: String, y: int, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(0, y)
	label.size = Vector2(BASE_SIZE.x, font_size + 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _refresh_scale_readout() -> void:
	var window_size := get_window().size
	var factor := float(window_size.x) / float(BASE_SIZE.x)
	var integer_scale: bool = is_equal_approx(factor, roundf(factor))
	var suffix := "integer scale" if integer_scale else "NON-INTEGER — expect shimmer"
	_scale_label.text = "%dx%d → %dx%d  (%.2fx, %s)" % [
		BASE_SIZE.x, BASE_SIZE.y, window_size.x, window_size.y, factor, suffix,
	]
	_scale_label.add_theme_color_override(
		"font_color", COLOR_DIM if integer_scale else COLOR_MARK
	)


func _refresh_input_readout() -> void:
	var parts := PackedStringArray()
	for action in ACTIONS:
		if not InputMap.has_action(action):
			parts.append("[color=#e86a6a]%s?[/color]" % action)
		elif Input.is_action_pressed(action):
			parts.append("[color=#%s]%s[/color]" % [COLOR_LIVE.to_html(false), action])
		else:
			parts.append("[color=#%s]%s[/color]" % [COLOR_DIM.to_html(false), action])
	_input_label.text = "[center]%s[/center]" % " ".join(parts)
