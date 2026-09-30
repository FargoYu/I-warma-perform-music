extends Area2D
## Press W while the player is inside the door area.

var player_inside := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if player_inside and Input.is_action_just_pressed("interact"):
		get_tree().call_group("game", "show_completion")

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D:
		player_inside = true

func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		player_inside = false
