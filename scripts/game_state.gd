extends Node
## Run equipment and session time speed. RectWorld2D owns movement/collisions.

signal time_speed_changed(speed: float)

const TIME_SPEEDS: Array[float] = [0.1, 0.2, 0.5, 1.0]

var time_speed_index: int = TIME_SPEEDS.size() - 1
var has_extinguisher: bool = false

func _ready() -> void:
	Engine.time_scale = get_time_speed()

func get_time_speed() -> float:
	return TIME_SPEEDS[time_speed_index]

func change_time_speed(direction: int) -> void:
	var next_index := clampi(time_speed_index + signi(direction), 0, TIME_SPEEDS.size() - 1)
	if next_index == time_speed_index:
		return
	time_speed_index = next_index
	Engine.time_scale = get_time_speed()
	time_speed_changed.emit(get_time_speed())

func reset_run() -> void:
	has_extinguisher = false
