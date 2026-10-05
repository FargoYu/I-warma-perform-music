extends Node
## Development helpers bound to debug keys.
##
## N: instantly grant the extinguisher ability.
## M: instantly walk through the first door of the current room.
##
## Autoloaded so it works in every gameplay room without any per-room wiring.
## The title menu deliberately eats the first key press to start the game, so
## these keys only apply once a room is running. Remove this autoload (and the
## two matching input actions) to ship a release build.

## Input actions mapped in project.godot. Both are plain physical keys: N and M.
const GRANT_ACTION := &"debug_grant_extinguisher"
const ENTER_DOOR_ACTION := &"debug_enter_door"

## Group names used to find objects without relying on node paths.
const DOOR_GROUP := "doors"
const PLAYER_GROUP := "player"


func _ready() -> void:
	# Keep responding while the game is paused or running at a low time scale.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A release build may drop the debug actions while keeping this autoload.
	# Warn once and turn the keys off instead of erroring on every key press.
	for action in [GRANT_ACTION, ENTER_DOOR_ACTION]:
		if not InputMap.has_action(action):
			push_warning("DebugTools: input action '%s' is missing; debug keys disabled." % action)
			set_process_unhandled_input(false)
			return


func _unhandled_input(event: InputEvent) -> void:
	# is_action_pressed() accepts every event type and ignores key echo, so a
	# held key fires exactly once and unrelated events fall straight through.
	if event.is_action_pressed(GRANT_ACTION):
		grant_extinguisher()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ENTER_DOOR_ACTION):
		enter_first_door()
		get_viewport().set_input_as_handled()


## N — give the player the extinguisher right away.
func grant_extinguisher() -> void:
	# Set the persistent flag first so it still applies when no player is in the
	# tree yet (for example while poking at a room scene directly).
	GameState.has_extinguisher = true
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node.has_method("pick_up_extinguisher"):
			node.pick_up_extinguisher()


## M — open the first door of the current room. Doors are visited in scene-tree
## order, and doors that cannot be used (no target room, or already
## transitioning) are skipped so the key still works in a room that places a
## decorative door first. Returns the door that was used, or null when the room
## offers no usable exit.
func enter_first_door() -> Node:
	for door in get_tree().get_nodes_in_group(DOOR_GROUP):
		if not door.has_method("enter_room"):
			continue
		if door.has_method("can_enter") and not door.can_enter():
			continue
		door.enter_room()
		return door
	return null
