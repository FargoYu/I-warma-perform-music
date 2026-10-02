extends CharacterBody2D
## Giraffe movement is collision-driven, with explicit external impulse support.

const TERRAIN_LAYER := 1
const WARMA_LAYER := 2

@export var gravity: float = 300.0
@export var mass: float = 1.0

func _ready() -> void:
	add_to_group("giraffe")

func _physics_process(delta: float) -> void:
	# Keep gravity explicit so this body remains controllable without a
	# per-frame horizontal lock that would defeat projectile impulses.
	velocity.y += gravity * delta

	# Warma's body is the authoritative blocker for ordinary side contact.
	# The giraffe scans Warma only while it has its own motion to resolve:
	# vertical motion handles falling and upward impacts, while horizontal
	# motion is enabled for explicit external impulses.
	var horizontal_motion := velocity.x * delta
	var horizontal_mask := TERRAIN_LAYER
	if not is_zero_approx(velocity.x):
		horizontal_mask |= WARMA_LAYER
	if not is_zero_approx(horizontal_motion):
		var horizontal_collision := _move_test_only(horizontal_motion * Vector2.RIGHT, horizontal_mask)
		if horizontal_collision != null and not is_zero_approx(horizontal_collision.get_normal().x):
			velocity.x = 0.0

	var vertical_motion := velocity.y * delta
	var vertical_mask := TERRAIN_LAYER
	if velocity.y >= 0.0:
		vertical_mask |= WARMA_LAYER
	if not is_zero_approx(vertical_motion):
		var vertical_collision := _move_test_only(vertical_motion * Vector2.DOWN, vertical_mask)
		if vertical_collision != null and not is_zero_approx(vertical_collision.get_normal().y):
			velocity.y = 0.0

	collision_mask = TERRAIN_LAYER

func _move_test_only(motion: Vector2, mask: int) -> KinematicCollision2D:
	collision_mask = mask
	var collision := move_and_collide(motion, true, safe_margin, false)
	if collision == null:
		global_position += motion
	else:
		# Commit only the requested axis. Vertical contact recovery must not move
		# the giraffe sideways during a landing.
		var travel := collision.get_travel()
		if not is_zero_approx(motion.x):
			global_position.x += travel.x
		else:
			global_position.y += travel.y
	return collision

func apply_external_impulse(impulse: Vector2) -> void:
	# Projectiles and other explicit game events use this entry point. Normal
	# CharacterBody2D contact does not transfer Warma's movement to this body.
	velocity += impulse / maxf(mass, 0.001)
