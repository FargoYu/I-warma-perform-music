extends Area2D
## A level item that is collected as soon as Warma enters its area.

func _ready() -> void:
	if GameState.has_extinguisher:
		queue_free()
		return
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("pick_up_extinguisher"):
		body.pick_up_extinguisher()
		queue_free()
