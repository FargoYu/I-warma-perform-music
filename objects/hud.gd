extends CanvasLayer
## Small always-visible runtime controls, kept separate from room gameplay.

@onready var speed_label: Label = $Speed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if is_instance_valid(GameState):
		GameState.speed_changed.connect(_on_speed_changed)
		_on_speed_changed(GameState.speed_multiplier)

func _on_speed_changed(multiplier: float) -> void:
	if speed_label == null:
		return
	speed_label.text = "x1" if is_equal_approx(multiplier, 1.0) else "x%.1f" % multiplier
