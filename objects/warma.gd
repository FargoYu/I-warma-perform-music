extends CharacterBody2D
## Warma: A/D movement and a variable-height J jump.

const TERRAIN_LAYER := 1
const GIRAFFE_LAYER := 4
const BODY_HALF_HEIGHT := 8.0
const BODY_LEFT := -2.0
const BODY_RIGHT := 3.0
const CONTACT_TOLERANCE := 0.02
const TIGHT_GAP_ALIGNMENT := 0.75
const JUMP_BUFFER_DURATION := 0.15
const SUPPORT_GRACE_DURATION := 0.10
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
@onready var head_probe: ShapeCast2D = $HeadProbe
@onready var equipment_pivot: Node2D = $EquipmentPivot
@onready var nozzle: Marker2D = $EquipmentPivot/HeldExtinguisher/Nozzle

var _lifting_giraffe := false
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
		_lifting_giraffe = _lift_giraffes_above(jump_velocity, delta)
	_jump_was_held = jump_held

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
			if not _try_enter_tight_gap(horizontal_collision.get_remainder().x, horizontal_mask):
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
		# Commit only the requested axis. A recovery from an overlapping body can
		# carry a perpendicular travel component, which must not move this axis.
		var travel := collision.get_travel()
		if not is_zero_approx(motion.x):
			global_position.x += travel.x
		else:
			global_position.y += travel.y
	return collision

func _try_enter_tight_gap(horizontal_motion: float, mask: int) -> bool:
	# A 16px body fits a one-tile gap, but the discrete vertical steps can
	# skip its 0.02px clearance. Align by at most a fraction of one logical
	# pixel, only when both surfaces bound a real gap and the complete body
	# can safely move to and through it. Ordinary walls and giraffes still block.
	if is_zero_approx(horizontal_motion) or is_zero_approx(velocity.y) or _lifting_giraffe:
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

func _has_giraffe_above() -> bool:
	# Warma's complete body spans x=-2..3 and the giraffe is 8x16. A
	# contact within this small tolerance means the giraffe is supported by
	# Warma's top; it must not act as a horizontal wall in that state.
	for node in get_tree().get_nodes_in_group("giraffe"):
		var giraffe := node as CharacterBody2D
		if giraffe == null:
			continue
		var top_gap := (global_position.y - 8.0) - (giraffe.global_position.y + 8.0)
		if absf(top_gap) > 0.75:
			continue
		if global_position.x + BODY_RIGHT <= giraffe.global_position.x - 4.0 or global_position.x + BODY_LEFT >= giraffe.global_position.x + 4.0:
			continue
		return true
	return false

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

func _lift_giraffes_above(target_velocity_y: float, physics_delta: float) -> bool:
	# The full-body collision handles contact. This probe adds the explicit
	# upward game rule when Warma jumps into a giraffe from below.
	var found_giraffe := false
	# Sweep only as far as this jump frame actually travels, plus the inset
	# of the thin head strip. This prevents lifting a body before reaching it.
	head_probe.target_position.y = minf(target_velocity_y * physics_delta, 0.0) - 0.05 - CONTACT_TOLERANCE
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
