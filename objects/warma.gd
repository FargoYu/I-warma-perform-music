extends CharacterBody2D
## Warma: A/D movement and a variable-height J jump.
##
## Giraffes resting on her head are riders. She never tunnels through them and
## her jump is never shortened by them: the whole chain above her is lifted by
## the vertical travel she actually commits, so the jump height is the same with
## no, one or twenty giraffes on her head.

const TERRAIN_LAYER := 1
const GIRAFFE_LAYER := 4
const BODY_HALF_HEIGHT := 8.0
const BODY_LEFT := -2.0
const BODY_RIGHT := 3.0
const CONTACT_TOLERANCE := 0.02
const TIGHT_GAP_ALIGNMENT := 0.75
const JUMP_BUFFER_DURATION := 0.15
const SUPPORT_GRACE_DURATION := 0.10
## Support contract shared with the lifts: an edge within this gap is a contact.
const RIDER_TOLERANCE := 0.75
## A rider already moving up is leaving the surface, not resting on it.
const RISE_EPSILON := 0.01
const MUSIC_BULLET_SCENE := preload("res://objects/music_bullet.tscn")

@export var move_speed: float = 60.0
@export var jump_velocity: float = -150.0
@export var jump_cut_speed: float = 60.0
@export var gravity: float = 300.0
@export var music_bullet_speed: float = 24.0
@export var music_bullet_growth_duration: float = 0.24
## Zero permits every fresh fire press, even while the previous note is growing.
@export_range(0.0, 1.0, 0.001) var music_bullet_interval: float = 0.0
@export var fall_limit: float = 144.0
@export var death_flash_duration: float = 0.08

@onready var sprite: Sprite2D = $Sprite2D
@onready var ground_probe: ShapeCast2D = $GroundProbe
@onready var equipment_pivot: Node2D = $EquipmentPivot
@onready var nozzle: Marker2D = $EquipmentPivot/HeldExtinguisher/Nozzle

var facing_direction := 1
var _music_bullet_cooldown := 0.0
var _dying := false
var _jump_was_held := false
var _jump_buffer_time := 0.0
var _support_grace_time := 0.0

func _ready() -> void:
	add_to_group("player")
	_sync_equipment_from_state()
	_apply_facing()

func _physics_process(delta: float) -> void:
	if _dying:
		return
	if Input.is_action_just_pressed("reset"):
		die()
		return

	_music_bullet_cooldown = maxf(_music_bullet_cooldown - delta, 0.0)
	if Input.is_action_just_pressed("fire_music"):
		_fire_music_bullet()

	var has_ground_support := _has_ground_support()
	if has_ground_support:
		_support_grace_time = SUPPORT_GRACE_DURATION
	else:
		_support_grace_time = maxf(_support_grace_time - delta, 0.0)
	if not has_ground_support:
		velocity.y += gravity * delta

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = direction * move_speed
		facing_direction = -1 if direction < 0.0 else 1
		_apply_facing()
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)

	# A held jump is deliberately sampled at the support surface. This keeps the
	# normal variable-height jump, while allowing the next landing on terrain or
	# the giraffe to immediately launch again without a timing-perfect re-press.
	var jump_held := Input.is_action_pressed("jump")
	if jump_held:
		_jump_buffer_time = JUMP_BUFFER_DURATION
	else:
		# Releasing J cancels a pending request. A held key continuously renews
		# the buffer, which is the behavior needed for a moving support surface.
		_jump_buffer_time = 0.0
	# Side contact only constrains horizontal movement. Actual overhead
	# obstacles are handled by the vertical sweep, not by the jump eligibility.
	# The request buffer and short support grace absorb the one-frame ordering
	# gap between a moving platform and the character's next floor query.
	var can_chain_jump := velocity.y >= 0.0 and (has_ground_support or _support_grace_time > 0.0)
	if can_chain_jump and _jump_buffer_time > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_time = 0.0
		_support_grace_time = 0.0
	_jump_was_held = jump_held

	if not Input.is_action_pressed("jump") and velocity.y < 0.0:
		velocity.y = maxf(velocity.y, -jump_cut_speed)

	# Everything Warma is carrying on her head this frame.
	var riders := _rider_chain(true)
	# Giraffes whose whole body clears her head. She may slide in under those, so
	# they are never horizontal walls; a giraffe sharing her height still blocks
	# her, which is what stops her walking straight through one.
	var overhead := _overhead_giraffes()

	# A resting Warma uses GroundProbe for support. Axis-separated test-only
	# queries prevent contact recovery from moving either CharacterBody sideways.
	var horizontal_motion := velocity.x * delta
	if not is_zero_approx(horizontal_motion):
		_set_body_exceptions(overhead, true)
		var horizontal_collision := _move_test_only(horizontal_motion * Vector2.RIGHT, TERRAIN_LAYER | GIRAFFE_LAYER)
		if horizontal_collision != null and not is_zero_approx(horizontal_collision.get_normal().x):
			if not _try_enter_tight_gap(horizontal_collision.get_remainder().x, TERRAIN_LAYER | GIRAFFE_LAYER, riders):
				velocity.x = 0.0
		_set_body_exceptions(overhead, false)

	# Only the riders leave the sweep; every other giraffe is still a real
	# ceiling. The chain then follows the vertical travel Warma actually
	# committed, which is what keeps her own trajectory independent of it.
	var vertical_motion := velocity.y * delta
	if not is_zero_approx(vertical_motion):
		var before_y := global_position.y
		_set_body_exceptions(riders, true)
		var vertical_collision := _move_test_only(vertical_motion * Vector2.DOWN, TERRAIN_LAYER | GIRAFFE_LAYER)
		_carry_riders(riders, global_position.y - before_y)
		_set_body_exceptions(riders, false)
		if vertical_collision != null and not is_zero_approx(vertical_collision.get_normal().y):
			velocity.y = 0.0
	collision_mask = TERRAIN_LAYER

	# The bottom of the 16px body touching the screen edge counts as death.
	if global_position.y + BODY_HALF_HEIGHT >= fall_limit:
		die()

## Starts the reusable death sequence, then restores the current room.
func die() -> void:
	if _dying:
		return
	_dying = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	var room := get_parent()
	if room != null and room.has_method("freeze_for_death"):
		room.freeze_for_death()
	await play_death_animation()

	if room != null and room.has_method("reset_scene"):
		room.reset_scene()
	else:
		get_tree().reload_current_scene()

## Visual death animation kept separate so its timing/effects can be changed later.
func play_death_animation() -> void:
	var was_visible := visible
	var flash_time := maxf(death_flash_duration, 0.01)
	for _flash in range(2):
		visible = false
		await get_tree().create_timer(flash_time).timeout
		visible = was_visible
		await get_tree().create_timer(flash_time).timeout
	visible = was_visible

func pick_up_extinguisher() -> void:
	GameState.has_extinguisher = true
	equipment_pivot.visible = true

func _sync_equipment_from_state() -> void:
	equipment_pivot.visible = GameState.has_extinguisher

func _apply_facing() -> void:
	var is_facing_left := facing_direction < 0
	sprite.flip_h = is_facing_left
	# The held item and its nozzle marker are children of this pivot. Mirroring
	# the pivot preserves their local relationship without per-frame world edits.
	equipment_pivot.scale.x = float(facing_direction)

func _fire_music_bullet() -> void:
	if not GameState.has_extinguisher or not equipment_pivot.visible:
		return
	if _music_bullet_cooldown > 0.0:
		return

	var bullet := MUSIC_BULLET_SCENE.instantiate()
	bullet.setup(facing_direction, music_bullet_speed, music_bullet_growth_duration)
	var bullet_parent: Node = get_tree().current_scene
	if bullet_parent == null:
		bullet_parent = get_tree().root
	bullet_parent.add_child(bullet)
	bullet.global_position = nozzle.global_position
	_music_bullet_cooldown = music_bullet_interval

func _move_test_only(motion: Vector2, mask: int) -> KinematicCollision2D:
	collision_mask = mask
	var collision := move_and_collide(motion, true, safe_margin, false)
	if collision == null:
		global_position += motion
	else:
		# Commit only the requested axis, and never more of it than was asked for.
		# A recovery can carry a perpendicular travel component, which must not
		# move this axis; a floor or ceiling contact in particular is returned
		# with its vertical recovery as the whole travel while the body rests a
		# fraction of a pixel inside its support, and reading travel.x from it
		# would cancel a horizontal move that nothing is blocking. A real wall is
		# reported with a horizontal normal and still blocks. The requested motion
		# is the ceiling for the axis, so a slow tick cannot press the body deeper
		# into its support than its own gravity asked for.
		var travel := collision.get_travel()
		if not is_zero_approx(motion.x):
			var requested := motion.x if is_zero_approx(collision.get_normal().x) else travel.x
			global_position.x += clampf(requested, minf(motion.x, 0.0), maxf(motion.x, 0.0))
		else:
			global_position.y += clampf(travel.y, minf(motion.y, 0.0), maxf(motion.y, 0.0))
	return collision

func _try_enter_tight_gap(horizontal_motion: float, mask: int, riders: Array[CharacterBody2D]) -> bool:
	# A 16px body fits a one-tile gap, but the discrete vertical steps can
	# skip its 0.02px clearance. Align by at most a fraction of one logical
	# pixel, only when both surfaces bound a real gap and the complete body
	# can safely move to and through it. Ordinary walls and giraffes still block,
	# and a carried stack does not fit such a gap in the first place.
	if is_zero_approx(horizontal_motion) or is_zero_approx(velocity.y) or not riders.is_empty():
		return false
	var leading_edge := BODY_RIGHT if horizontal_motion > 0.0 else BODY_LEFT
	var sample := global_position + Vector2(leading_edge + horizontal_motion, 0.0)
	var space := get_world_2d().direct_space_state
	var reach := BODY_HALF_HEIGHT + TIGHT_GAP_ALIGNMENT + CONTACT_TOLERANCE
	var above_query := PhysicsRayQueryParameters2D.create(sample, sample + Vector2.UP * reach, TERRAIN_LAYER, [get_rid()])
	var below_query := PhysicsRayQueryParameters2D.create(sample, sample + Vector2.DOWN * reach, TERRAIN_LAYER, [get_rid()])
	var above := space.intersect_ray(above_query)
	var below := space.intersect_ray(below_query)
	if above.is_empty() or below.is_empty():
		return false
	if Vector2(above["normal"]).y < 0.5 or Vector2(below["normal"]).y > -0.5:
		return false
	var ceiling_y := Vector2(above["position"]).y
	var floor_y := Vector2(below["position"]).y
	var gap_height := floor_y - ceiling_y
	if gap_height < BODY_HALF_HEIGHT * 2.0 + safe_margin * 2.0 or gap_height > BODY_HALF_HEIGHT * 2.0 + CONTACT_TOLERANCE * 2.0:
		return false
	var aligned_y := (floor_y + ceiling_y) * 0.5
	var correction := aligned_y - global_position.y
	if absf(correction) > TIGHT_GAP_ALIGNMENT:
		return false
	# Validate both legs without committing either. Include the giraffe layer
	# even if the ordinary horizontal rule currently allows walking under one.
	collision_mask = mask | GIRAFFE_LAYER
	var vertical_check := KinematicCollision2D.new()
	if test_move(global_transform, Vector2(0.0, correction), vertical_check, safe_margin, true):
		if absf(vertical_check.get_travel().y - correction) > safe_margin:
			return false
	var aligned_transform := global_transform
	aligned_transform.origin.y = aligned_y
	if test_move(aligned_transform, Vector2(horizontal_motion, 0.0), null, safe_margin, true):
		return false
	global_position.y = aligned_y
	_move_test_only(Vector2(horizontal_motion, 0.0), mask)
	velocity.y = 0.0
	return true

## The chain Warma's head is carrying, bottom-up: every giraffe whose bottom
## edge rests on her top, then every giraffe resting on those. Contact is the
## same support contract the lifts use, measured between real collision edges,
## so a rider is never decided by its sprite or its centre point.
##
## `skip_rising` leaves out a giraffe that is already moving up under its own
## power (a music-bullet launch). It is leaving the surface rather than resting
## on it, and carrying it would cancel that motion.
func _rider_chain(skip_rising: bool) -> Array[CharacterBody2D]:
	var riders: Array[CharacterBody2D] = []
	var carriers: Array[Node2D] = [self]
	var index := 0
	while index < carriers.size():
		var carrier_bounds := _body_bounds(carriers[index])
		index += 1
		for node in get_tree().get_nodes_in_group("giraffe"):
			var giraffe := node as CharacterBody2D
			if giraffe == null or riders.has(giraffe):
				continue
			if skip_rising and giraffe.velocity.y < -RISE_EPSILON:
				continue
			var bounds := _body_bounds(giraffe)
			if absf(bounds.end.y - carrier_bounds.position.y) > RIDER_TOLERANCE:
				continue
			if bounds.end.x <= carrier_bounds.position.x or bounds.position.x >= carrier_bounds.end.x:
				continue
			riders.append(giraffe)
			carriers.append(giraffe)
	return riders


## Every giraffe whose bottom edge is level with or above her head, whether or
## not it overlaps her horizontally yet. Those are the bodies she can move in
## under, so her own sweep must not treat them as walls; everything sharing her
## height keeps blocking her.
func _overhead_giraffes() -> Array[CharacterBody2D]:
	var overhead: Array[CharacterBody2D] = []
	var warma_top := global_position.y - BODY_HALF_HEIGHT
	for node in get_tree().get_nodes_in_group("giraffe"):
		var giraffe := node as CharacterBody2D
		if giraffe == null:
			continue
		if _body_bounds(giraffe).end.y <= warma_top + RIDER_TOLERANCE:
			overhead.append(giraffe)
	return overhead


## World-space bounds from a body's real collision geometry. Warma's polygon is
## x=-2..3, so her box is deliberately not centred on her origin.
func _body_bounds(node: Node2D) -> Rect2:
	var polygon := node.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if polygon != null and not polygon.polygon.is_empty():
		var rect := Rect2(polygon.polygon[0], Vector2.ZERO)
		for point in polygon.polygon:
			rect = rect.expand(point)
		return Rect2(node.global_position + rect.position, rect.size)
	var shape_node := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var size := (shape_node.shape as RectangleShape2D).size
		return Rect2(node.global_position + shape_node.position - size * 0.5, size)
	var half_size := Vector2(3.0, BODY_HALF_HEIGHT)
	return Rect2(node.global_position - half_size, half_size * 2.0)


## A packed stack moves as one body, so the contacts inside it (and with Warma)
## must not be read back as walls while each member tests its travel. The same
## switch hides the giraffes she is sliding under from her own sweep.
func _set_body_exceptions(bodies: Array[CharacterBody2D], enabled: bool) -> void:
	for body in bodies:
		if enabled:
			add_collision_exception_with(body)
			body.add_collision_exception_with(self)
		else:
			remove_collision_exception_with(body)
			body.remove_collision_exception_with(self)
		for other in bodies:
			if other == body:
				continue
			if enabled:
				body.add_collision_exception_with(other)
			else:
				body.remove_collision_exception_with(other)


## Moves the complete rider chain by the vertical travel Warma committed this
## frame. The chain is rigid for this step: every member stops at the first
## common blocking plane, so a rider pinned under a ceiling can never be
## compressed into the riders below it. Warma's own travel is already committed
## and is never shortened by her riders.
func _carry_riders(riders: Array[CharacterBody2D], travel_y: float) -> void:
	if riders.is_empty() or is_zero_approx(travel_y):
		return
	var allowed := absf(travel_y)
	for rider in riders:
		allowed = minf(allowed, absf(rider.carried_travel_limit(travel_y)))
	var carry := signf(travel_y) * allowed
	if is_zero_approx(carry):
		return
	for rider in riders:
		rider.apply_carried_travel(carry)

func _has_ground_support() -> bool:
	# The probe spans the complete bottom edge of the collision polygon.  A
	# centre ray misses a ledge whenever the centre is just beyond its edge,
	# even though part of Warma's foot is supported.  Only an upward-facing
	# contact counts; a side hit at the same height is not a floor.
	ground_probe.force_shapecast_update()
	for index in ground_probe.get_collision_count():
		var foot_gap := ground_probe.get_collision_point(index).y - (global_position.y + BODY_HALF_HEIGHT)
		if ground_probe.get_collision_normal(index).y <= -0.5 and absf(foot_gap) <= CONTACT_TOLERANCE:
			return true
	# Moving platforms can advance after this body's physics step. Let the
	# platform confirm that the feet still overlap its support plane within a
	# sub-pixel tolerance; static terrain keeps the exact ShapeCast rule above.
	for elevator in get_tree().get_nodes_in_group("elevators"):
		if elevator != null and elevator.has_method("snap_body_to_support") and elevator.call("snap_body_to_support", self, 0.75):
			return true
	return false
