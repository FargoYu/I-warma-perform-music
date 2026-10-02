@tool
extends Node2D
## Shared room presentation; gameplay belongs to the instanced objects.

var _initial_has_extinguisher := false
var _resetting := false

func _ready() -> void:
	# Keep the background out of the editor's tile-painting canvas.
	$Background.visible = not Engine.is_editor_hint()
	if not Engine.is_editor_hint():
		# GameState survives room transitions, so remember the state at the
		# moment this room was entered and restore it when the room is reset.
		_initial_has_extinguisher = GameState.has_extinguisher

func reset_scene() -> void:
	if _resetting or not is_inside_tree():
		return
	_resetting = true
	GameState.has_extinguisher = _initial_has_extinguisher
	var error := get_tree().reload_current_scene()
	if error != OK:
		_resetting = false
		push_error("Could not reset room: %s" % error_string(error))

func freeze_for_death() -> void:
	# Stop room input and motion during the animation. SceneTree timers still
	# run, so Warma's animation can finish before the room is replaced.
	process_mode = Node.PROCESS_MODE_DISABLED
