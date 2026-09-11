extends Node2D
## Hosts the active map, the player, and the overworld UI.
##
## This is the seam that map-to-map travel will go through in a later step: the
## map is a child scene that can be swapped, and nothing inside a map holds a
## reference to the player or the UI.

@onready var _map: GameMap = $Map
@onready var _player: Player = $Player
@onready var _dialogue: DialogueBox = $DialogueBox
@onready var _camera: Camera2D = $Player/Camera


func _ready() -> void:
	# Children are ready before we are, so the map has already parsed its data.
	_map.dialogue_requested.connect(_dialogue.show_pages)
	_dialogue.opened.connect(_on_dialogue_opened)
	_dialogue.closed.connect(_on_dialogue_closed)

	_player.global_position = _map.player_spawn_position()
	_apply_camera_limits()


func _apply_camera_limits() -> void:
	var bounds := _map.world_bounds()
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	# Without this the camera lerps in from the origin on the first frame.
	_camera.reset_smoothing()


func _on_dialogue_opened() -> void:
	_player.input_enabled = false


func _on_dialogue_closed() -> void:
	_player.input_enabled = true
