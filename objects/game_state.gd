extends Node
## Persistent run state shared by every level instance.

var has_extinguisher: bool = false

## Runtime simulation speed. The values are intentionally discrete so that
## puzzle timing stays predictable while testing a room.
const SPEED_MULTIPLIERS: Array[float] = [0.1, 0.2, 0.5, 1.0]
var speed_index: int = SPEED_MULTIPLIERS.size() - 1
var speed_multiplier: float = 1.0
signal speed_changed(multiplier: float)

func _ready() -> void:
	# Speed input must remain responsive even while Engine.time_scale is low.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_speed()

func _process(_delta: float) -> void:
	# Input actions cover both physical arrow keys and deterministic presses in
	# automated tests, while PROCESS_MODE_ALWAYS keeps this responsive at x0.1.
	if Input.is_action_just_pressed("speed_decrease"):
		decrease_speed()
	elif Input.is_action_just_pressed("speed_increase"):
		increase_speed()

func increase_speed() -> void:
	set_speed_index(speed_index + 1)

func decrease_speed() -> void:
	set_speed_index(speed_index - 1)

func set_speed_index(index: int) -> void:
	var next_index := clampi(index, 0, SPEED_MULTIPLIERS.size() - 1)
	if next_index == speed_index and is_equal_approx(speed_multiplier, SPEED_MULTIPLIERS[next_index]):
		return
	speed_index = next_index
	_apply_speed()

func reset_speed() -> void:
	speed_index = SPEED_MULTIPLIERS.size() - 1
	_apply_speed()

func _apply_speed() -> void:
	speed_multiplier = SPEED_MULTIPLIERS[speed_index]
	Engine.time_scale = speed_multiplier
	speed_changed.emit(speed_multiplier)
