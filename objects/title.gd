extends Node2D
## Temporary title menu: one fresh keyboard press starts the original room.

@export_file("*.tscn") var next_scene: String = "res://rooms/main.tscn"
var _starting := false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		start_game()

func start_game() -> void:
	if _starting or next_scene.is_empty():
		return
	_starting = true
	_open_game.call_deferred()

func _open_game() -> void:
	# Do not carry the menu's starting key into gameplay (notably J or R).
	for action in InputMap.get_actions():
		Input.action_release(action)
	GameState.has_extinguisher = false
	GameState.reset_speed(true)
	var error := get_tree().change_scene_to_file(next_scene)
	if error != OK:
		_starting = false
		push_error("Could not start game: %s" % error_string(error))
