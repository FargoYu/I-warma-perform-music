extends CharacterBody2D
## Giraffe movement is collision-driven, with explicit external impulse support.

const TERRAIN_LAYER := 1
const WARMA_LAYER := 2
const GIRAFFE_LAYER := 4

const BODY_HALF_WIDTH := 4.0
const BODY_HALF_HEIGHT := 8.0
## A note-driven run forgives only a sub-pixel ledge mismatch: two surfaces at
## the same logical height (a giraffe's head and a one-cell block top) must be
## crossable, but any ledge that genuinely rises above the feet — even by a
## fraction of a pixel more — stays a wall and stops the run.
const STEP_UP_REACH := 0.1
const STEP_UP_TOLERANCE := 0.1

@export var gravity: float = 300.0
@export var mass: float = 1.0
@export var music_run_speed: float = 24.0
@export var music_run_duration: float = 0.8

var _music_run_time := 0.0
## Set by the carrier that just moved this body, consumed by its own next step.
var _carried_this_frame := false
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
	# A carrier (Warma's head) already committed this body's whole vertical
	# travel for the frame, so its own gravity step must not run on top of it.
	# Besides doubling the motion, the carrier moves after the physics server's
	# last snapshot of this body: an extra query would read that stale pair and
	# "recover" the rider straight back down into the carrier. A carried body is
	# supported, exactly like one resting on a lift.
	var carried := _carried_this_frame
	_carried_this_frame = false
	if not elevator_support and not carried:
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
		# Vertical stack contacts supply only support. Ignore every body that is
		# resting on this body, or that this body is resting on, while performing a
		# horizontal sweep. Without this, a stacked body can be read back as a
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
			if _music_run_time > 0.0 and _try_step_up(horizontal_mask, stack_contacts):
				# The ledge became floor: finish this frame's run on top of it.
				_move_test_only(horizontal_motion * Vector2.RIGHT, horizontal_mask)
			else:
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
	#
	# Warma belongs to the same rule. She is a 16px body centred on her origin
	# exactly like a giraffe, so when her top edge is level with this body's feet
	# her whole box lies below it and she can only support it — for example
	# standing in a one-tile hole flush against the wall this body is about to
	# walk off. Reading her back as a side wall there cancels the music impulse
	# until she happens to move away, which is the reported bug.
	var contacts: Array[PhysicsBody2D] = []
	var top_y := global_position.y - 8.0
	var bottom_y := global_position.y + 8.0
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("giraffe"))
	candidates.append_array(get_tree().get_nodes_in_group("player"))
	for node in candidates:
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

## Climbs onto the ledge whose face just stopped a music run. The ledge top is
## sampled by a ray half a pixel past the leading edge, so a corner graze is
## read the same as a full face contact. The climb needs a clear lift and a
## clear first step onto the surface; a ceiling, a rider overhead or a taller
## face keeps it a wall and the run stops as before.
func _try_step_up(mask: int, stack_contacts: Array[PhysicsBody2D]) -> bool:
	var feet_y := global_position.y + BODY_HALF_HEIGHT
	var sample_x := global_position.x + signf(velocity.x) * (BODY_HALF_WIDTH + 0.5)
	var exclude: Array[RID] = [get_rid()]
	for body in stack_contacts:
		exclude.append(body.get_rid())
	var query := PhysicsRayQueryParameters2D.create(Vector2(sample_x, feet_y - STEP_UP_REACH - 2.0), Vector2(sample_x, feet_y), mask, exclude)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var rise := feet_y - (hit["position"] as Vector2).y
	if rise < -STEP_UP_TOLERANCE or rise > STEP_UP_REACH + STEP_UP_TOLERANCE:
		return false
	# Land a hair above the surface so the follow-up horizontal sweep cannot
	# graze the ledge corner; gravity settles the body onto it right after.
	var lift := rise + 0.02
	var raised := global_transform
	raised.origin.y -= lift
	collision_mask = TERRAIN_LAYER | GIRAFFE_LAYER | WARMA_LAYER
	var blocked := test_move(global_transform, Vector2(0.0, -lift), null, safe_margin, true) \
			or test_move(raised, Vector2(signf(velocity.x) * 1.5, 0.0), null, safe_margin, true)
	collision_mask = TERRAIN_LAYER
	if blocked:
		return false
	global_position.y -= lift
	return true

func _move_test_only(motion: Vector2, mask: int) -> KinematicCollision2D:
	collision_mask = mask
	var collision := move_and_collide(motion, true, safe_margin, false)
	if collision == null:
		global_position += motion
	else:
		# Commit only the requested axis, and never more of it than was asked for.
		# Two contact shapes have to be rejected here:
		# - a floor or ceiling contact carries no constraint for the horizontal
		#   axis, but while this body rests a fraction of a pixel inside its
		#   support the solver returns that contact with its vertical recovery as
		#   the whole travel. Taking travel.x from it would freeze the body
		#   against the ground it is standing on, so the requested motion wins.
		#   A real wall is reported with a horizontal normal and still blocks.
		# - the same recovery can point against the motion (a stack pressing this
		#   body downwards), and the requested motion is the ceiling for the axis,
		#   so a slow tick cannot push the body deeper than it asked to move.
		var travel := collision.get_travel()
		if not is_zero_approx(motion.x):
			var requested := motion.x if is_zero_approx(collision.get_normal().x) else travel.x
			global_position.x += clampf(requested, minf(motion.x, 0.0), maxf(motion.x, 0.0))
		else:
			global_position.y += clampf(travel.y, minf(motion.y, 0.0), maxf(motion.y, 0.0))
	return collision

## Vertical travel this giraffe can still make while the body it rests on
## carries it. The carrier stack is already excluded by the carrier, so only
## terrain and unrelated bodies limit the move; nothing is committed here.
func carried_travel_limit(delta_y: float) -> float:
	if is_zero_approx(delta_y):
		return 0.0
	collision_mask = TERRAIN_LAYER | GIRAFFE_LAYER
	var probe := KinematicCollision2D.new()
	var blocked := test_move(global_transform, Vector2(0.0, delta_y), probe, safe_margin, true)
	collision_mask = TERRAIN_LAYER
	return probe.get_travel().y if blocked else delta_y


## Commits a vertical travel chosen by the carrier. The rider keeps the
## carrier's surface instead of the speed its own gravity step would add.
func apply_carried_travel(delta_y: float) -> void:
	global_position.y += delta_y
	_carried_this_frame = true
	if not is_zero_approx(velocity.y) and signf(velocity.y) == signf(delta_y):
		velocity.y = 0.0


func apply_external_impulse(impulse: Vector2) -> void:
	# Projectiles and other explicit game events use this entry point. Normal
	# CharacterBody2D contact does not transfer Warma's movement to this body.
	velocity += impulse / maxf(mass, 0.001)

func run_in_direction(direction: int) -> void:
	_music_run_direction = -1 if direction < 0 else 1
	_music_run_time = maxf(music_run_duration, 0.0)
	velocity.x = float(_music_run_direction) * music_run_speed
