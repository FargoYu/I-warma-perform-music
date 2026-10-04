extends CharacterBody2D
## Giraffe movement is collision-driven, with explicit external impulse support.

const TERRAIN_LAYER := 1
const WARMA_LAYER := 2
const GIRAFFE_LAYER := 4

@export var gravity: float = 300.0
@export var mass: float = 1.0
@export var music_run_speed: float = 24.0
@export var music_run_duration: float = 0.8

var _music_run_time := 0.0
var _music_run_direction := 0

func _ready() -> void:
	add_to_group("giraffe")

func _physics_process(delta: float) -> void:
	if _music_run_time > 0.0:
		_music_run_time = maxf(_music_run_time - delta, 0.0)
		velocity.x = float(_music_run_direction) * music_run_speed
	else:
		# Let an ordinary external impulse wind down instead of keeping a note
		# reaction active forever.
		velocity.x = move_toward(velocity.x, 0.0, music_run_speed * 4.0 * delta)

	# Keep gravity explicit so this body remains controllable without a
	# per-frame horizontal lock that would defeat projectile impulses. A moving
	# Elevator can advance between physics queries, so let it snap a near-contact
	# foot to its support plane before applying the next gravity step.
	var elevator_support := false
	for elevator in get_tree().get_nodes_in_group("elevators"):
		if elevator != null and elevator.has_method("snap_body_to_support") and elevator.call("snap_body_to_support", self, 0.75):
			elevator_support = true
			break
	if not elevator_support:
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	# Warma's body is the authoritative blocker for ordinary side contact.
	# The giraffe scans Warma only while it has its own motion to resolve:
	# vertical motion handles falling and upward impacts, while horizontal
	# motion is enabled for explicit external impulses.
	var horizontal_motion := velocity.x * delta
	var horizontal_mask := TERRAIN_LAYER | GIRAFFE_LAYER
	if not is_zero_approx(velocity.x):
		horizontal_mask |= WARMA_LAYER
	if not is_zero_approx(horizontal_motion):
		# Vertical stack contacts supply only support. Ignore every giraffe that is
		# resting on this body, or that this body is resting on, while performing a
		# horizontal sweep. Without this, a stacked giraffe can be read back as a
		# side wall and cancel the music impulse even though the contact is vertical.
		# Same-level neighbours are still included and continue to block real side
		# contact.
		var stack_contacts := _vertical_stack_contacts()
		for body in stack_contacts:
			add_collision_exception_with(body)
		var horizontal_collision := _move_test_only(horizontal_motion * Vector2.RIGHT, horizontal_mask)
		for body in stack_contacts:
			remove_collision_exception_with(body)
		if horizontal_collision != null and not is_zero_approx(horizontal_collision.get_normal().x):
			velocity.x = 0.0

	var vertical_motion := velocity.y * delta
	var vertical_mask := TERRAIN_LAYER | GIRAFFE_LAYER
	if velocity.y >= 0.0:
		vertical_mask |= WARMA_LAYER
	if not is_zero_approx(vertical_motion):
		var vertical_collision := _move_test_only(vertical_motion * Vector2.DOWN, vertical_mask)
		if vertical_collision != null and not is_zero_approx(vertical_collision.get_normal().y):
			velocity.y = 0.0

	collision_mask = TERRAIN_LAYER

func _vertical_stack_contacts() -> Array[PhysicsBody2D]:
	# Bodies in the same vertical stack must be ignored as horizontal obstacles.
	# This covers both directions: the support can slide out from under a rider,
	# and a rider can slide across its support. The discriminator is the vertical
	# relationship alone — a body whose top or bottom edge meets this body's
	# opposite edge (within the settle tolerance) is stack, never wall. Width is
	# deliberately unbounded: two touching columns also sit 8px apart centre to
	# centre, so a horizontal window cannot tell the touching neighbour that
	# forms the walkable seam from a same-level wall — the vertical gap can
	# (a wall sits a full body height away and stays blocking).
	var contacts: Array[PhysicsBody2D] = []
	var top_y := global_position.y - 8.0
	var bottom_y := global_position.y + 8.0
	for node in get_tree().get_nodes_in_group("giraffe"):
		var other := node as CharacterBody2D
		if other == null or other == self:
			continue

		var other_top_y := other.global_position.y - 8.0
		var other_bottom_y := other.global_position.y + 8.0
		var rider_gap := top_y - other_bottom_y
		var support_gap := other_top_y - bottom_y
		if absf(rider_gap) <= 0.75 or absf(support_gap) <= 0.75:
			contacts.append(other)
	return contacts

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

func run_in_direction(direction: int) -> void:
	_music_run_direction = -1 if direction < 0 else 1
	_music_run_time = maxf(music_run_duration, 0.0)
	velocity.x = float(_music_run_direction) * music_run_speed
