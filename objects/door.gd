extends Area2D
## Press W while the player is inside the door area.

## Every door joins this group on ready, so debug tools (and any future system)
## can find the exits of the current room without hard-coded node paths.
const DOOR_GROUP := "doors"

## The room scene opened by this door. An empty path disables the exit.
@export_file("*.tscn") var next_room: String = ""

var player_inside := false
var _transitioning := false

func _ready() -> void:
	add_to_group(DOOR_GROUP)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if player_inside and Input.is_action_just_pressed("interact"):
		enter_room()

## True while this door can actually take the player somewhere: it has a target
## room and is not already mid-transition.
func can_enter() -> bool:
	return not _transitioning and not next_room.is_empty()

func enter_room() -> void:
	if not can_enter():
		return
	_transitioning = true
	# Leave the input/physics callback before removing the current room.
	_change_room.call_deferred()

func _change_room() -> void:
	if not is_inside_tree():
		return
	var error := get_tree().change_scene_to_file(next_room)
	if error != OK:
		_transitioning = false
		push_error("Could not open room '%s': %s" % [next_room, error_string(error)])

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_inside = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_inside = false
