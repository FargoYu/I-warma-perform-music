extends CharacterBody2D
## Player: A/D move, J performs a single jump.

@export var move_speed: float = 60.0
@export var jump_velocity: float = -112.0
@export var gravity: float = 300.0

@onready var sprite: Sprite2D = $Sprite2D

func _physics_process(delta: float) -> void:
	# Apply gravity only while airborne.
	if not is_on_floor():
		velocity.y += gravity * delta

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * move_speed
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)

	# Checking the floor prevents a second jump in mid-air.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	move_and_slide()

	# Reset after falling out of the 256x144 play area.
	if global_position.y > 180.0:
		global_position = Vector2(85.0, 120.0)
		velocity = Vector2.ZERO
