extends CharacterBody2D
## 最小的平台跳跃玩家：A/D 移动，J 单段跳。

@export var move_speed: float = 60.0
@export var jump_velocity: float = -112.0
@export var gravity: float = 300.0

@onready var sprite: Sprite2D = $Sprite2D

func _physics_process(delta: float) -> void:
	# 不在地面时，持续受到重力影响。
	if not is_on_floor():
		velocity.y += gravity * delta

	# A/D 是项目 Input Map 中的 move_left / move_right。
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * move_speed
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)

	# is_on_floor() 保证只能进行一段跳。
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	move_and_slide()

	# 先做一个简单的掉落保护，方便测试关卡。
	if global_position.y > 220.0:
		global_position = Vector2(40.0, 120.0)
		velocity = Vector2.ZERO
