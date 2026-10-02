extends CharacterBody2D
## Warma: A/D movement and a variable-height J jump.

const TERRAIN_LAYER := 1
const GIRAFFE_LAYER := 4

@export var move_speed: float = 60.0
@export var jump_velocity: float = -150.0
@export var jump_cut_speed: float = 60.0
@export var gravity: float = 300.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var ground_probe: RayCast2D = $GroundProbe
@onready var head_probe: ShapeCast2D = $HeadProbe

var _lifting_giraffe := false

func _ready() -> void:
	add_to_group("player")

func _physics_process(delta: float) -> void:
	if not _has_ground_support():
		velocity.y += gravity * delta

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * move_speed
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)

	if Input.is_action_just_pressed("jump") and _has_ground_support():
		velocity.y = jump_velocity
		_lifting_giraffe = _lift_giraffes_above(jump_velocity, delta)

	if not Input.is_action_pressed("jump") and velocity.y < 0.0:
		velocity.y = maxf(velocity.y, -jump_cut_speed)

	# A resting Warma uses GroundProbe for support. Axis-separated test-only
	# queries prevent contact recovery from moving either CharacterBody sideways.
	if _lifting_giraffe and velocity.y >= 0.0:
		_lifting_giraffe = false

	var horizontal_motion := velocity.x * delta
	var horizontal_mask := TERRAIN_LAYER
	if not is_zero_approx(horizontal_motion) and not _has_giraffe_above():
		# A giraffe resting on Warma is a vertical support, not a horizontal
		# wall. Keep side contact blocking everywhere else.
		horizontal_mask |= GIRAFFE_LAYER
	if not is_zero_approx(horizontal_motion):
		var horizontal_collision := _move_test_only(horizontal_motion * Vector2.RIGHT, horizontal_mask)
		if horizontal_collision != null and not is_zero_approx(horizontal_collision.get_normal().x):
			velocity.x = 0.0

	var vertical_motion := velocity.y * delta
	var vertical_mask := TERRAIN_LAYER
	if not (_lifting_giraffe and vertical_motion < 0.0):
		vertical_mask |= GIRAFFE_LAYER
	if not is_zero_approx(vertical_motion):
		var vertical_collision := _move_test_only(vertical_motion * Vector2.DOWN, vertical_mask)
		if vertical_collision != null and not is_zero_approx(vertical_collision.get_normal().y):
			velocity.y = 0.0
	collision_mask = TERRAIN_LAYER

	if global_position.y > 180.0:
		global_position = Vector2(85.0, 120.0)
		velocity = Vector2.ZERO

func _move_test_only(motion: Vector2, mask: int) -> KinematicCollision2D:
	collision_mask = mask
	var collision := move_and_collide(motion, true, safe_margin, false)
	if collision == null:
		global_position += motion
	else:
		# Commit only the requested axis. A recovery from an overlapping body can
		# carry a perpendicular travel component, which must not move this axis.
		var travel := collision.get_travel()
		if not is_zero_approx(motion.x):
			global_position.x += travel.x
		else:
			global_position.y += travel.y
	return collision

func _has_giraffe_above() -> bool:
	# The full body shapes are 6x16 for Warma and 8x16 for the giraffe. A
	# contact within this small tolerance means the giraffe is supported by
	# Warma's top; it must not act as a horizontal wall in that state.
	for node in get_tree().get_nodes_in_group("giraffe"):
		var giraffe := node as CharacterBody2D
		if giraffe == null:
			continue
		var top_gap := (global_position.y - 8.0) - (giraffe.global_position.y + 8.0)
		if absf(top_gap) > 0.75:
			continue
		if absf(global_position.x - giraffe.global_position.x) > 7.25:
			continue
		return true
	return false

func _has_ground_support() -> bool:
	# Ground support comes from the floor or the top of the giraffe's full body.
	# The probe reports support while a body is resting in place.
	ground_probe.force_raycast_update()
	return ground_probe.is_colliding()

func _lift_giraffes_above(target_velocity_y: float, physics_delta: float) -> bool:
	# The full-body collision handles contact. This probe adds the explicit
	# upward game rule when Warma jumps into a giraffe from below.
	var found_giraffe := false
	head_probe.force_shapecast_update()
	for index in head_probe.get_collision_count():
		var giraffe := head_probe.get_collider(index) as CharacterBody2D
		if giraffe == null or not giraffe.is_in_group("giraffe"):
			continue

		# A wide head probe can also touch the giraffe's top while Warma is
		# flush against its side. Only an upward-facing contact with the
		# giraffe clearly above Warma is a genuine below-to-above impact.
		var collision_normal := head_probe.get_collision_normal(index)
		if collision_normal.y <= 0.5:
			continue
		if giraffe.global_position.y >= global_position.y - 0.5:
			continue

		found_giraffe = true
		if not giraffe.has_method("apply_external_impulse"):
			continue
		# Giraffe integrates gravity before its own motion, while Warma has
		# already selected the jump velocity this frame. Preload the opposite
		# gravity step so both bodies receive the same first-frame displacement.
		var target_velocity_before_gravity := target_velocity_y - float(giraffe.get("gravity")) * physics_delta
		var delta_velocity := target_velocity_before_gravity - giraffe.velocity.y
		if not is_zero_approx(delta_velocity):
			var mass := maxf(float(giraffe.get("mass")), 0.001)
			giraffe.call("apply_external_impulse", Vector2(0.0, delta_velocity * mass))
	return found_giraffe
