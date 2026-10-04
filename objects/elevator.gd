extends AnimatableBody2D
## Shared behaviour for a narrow, continuously resizing lift anchored at one end.
##
## The extension direction is not a runtime property. Each direction has its own
## script (elevator_up.gd, elevator_down.gd, elevator_left.gd, elevator_right.gd)
## that overrides _axis(), and its scene is authored with the collision shape and
## visual already rotated for that direction.

const TERRAIN_LAYER := 1
const SUPPORT_TOLERANCE := 0.75
const GROWTH_CLEARANCE := 0.05
const EDGE_INSET := 0.02
const MIN_COLLISION_LENGTH := 0.1
const RISE_EPSILON := 0.01

@export_range(3.0, 256.0, 0.01) var max_height: float = 32.0
@export_range(3.0, 256.0, 0.01) var min_height: float = 3.0
@export_range(0.1, 256.0, 0.1) var height_speed: float = 24.0
@export var starts_extended := false
@export var button_path: NodePath
@export var elevator_color: Color = Color(0.78, 0.31, 0.16, 1.0)

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual: Polygon2D = $Visual

var current_height: float = 3.0
var button_active := false
var _button_source: Node

func _ready() -> void:
	add_to_group("elevators")
	# Keep the default PROCESS_MODE_INHERIT: a frozen room (death animation)
	# must freeze its lifts too, and PROCESS_MODE_ALWAYS bypassed that freeze.
	collision_layer = TERRAIN_LAYER
	collision_mask = 0
	sync_to_physics = true
	min_height = maxf(min_height, 3.0)
	max_height = maxf(max_height, min_height)
	current_height = max_height if starts_extended else min_height
	visual.color = elevator_color
	# Each instance owns its collision shape. Instances of the same PackedScene
	# otherwise share one RectangleShape2D resource, so one lift's resize would
	# corrupt every other lift (and every direction) in the same room.
	if collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	_apply_height(current_height)
	if not button_path.is_empty():
		var source := get_node_or_null(button_path)
		if source != null:
			set_button_source(source)

func _physics_process(delta: float) -> void:
	var pressed_target := min_height if starts_extended else max_height
	var released_target := max_height if starts_extended else min_height
	var target := pressed_target if button_active else released_target
	var next_height := move_toward(current_height, target, maxf(height_speed, 0.01) * delta)
	if is_equal_approx(next_height, current_height):
		return
	var change := next_height - current_height
	var grows := next_height > current_height
	# A lift is a telescoping rod, not a wall: its extension passes through
	# static scenery. It still stops for an actor that would be swallowed, or
	# that would be pushed into solid terrain while riding the rod.
	if grows and _growth_blocked(next_height):
		return
	# The upward lift has a moving support plane, so carry its complete stack in
	# either extension direction. Downward and horizontal tops stay anchored.
	var supported := _supported_stack()
	if not supported.is_empty() and not _can_push_supported_bodies(change, supported):
		return
	if not supported.is_empty():
		_push_supported_bodies(change, supported)
	_apply_height(next_height)

func set_button_source(source: Node) -> void:
	if _button_source == source:
		return
	if is_instance_valid(_button_source) and _button_source.has_signal("activation_changed"):
		var old_callable := Callable(self, "_on_button_activation_changed")
		if _button_source.is_connected("activation_changed", old_callable):
			_button_source.disconnect("activation_changed", old_callable)
	_button_source = source
	if is_instance_valid(_button_source):
		if _button_source.has_signal("activation_changed"):
			_button_source.activation_changed.connect(_on_button_activation_changed)
		button_active = bool(_button_source.get("activated"))

func _on_button_activation_changed(active: bool) -> void:
	set_button_active(active)

func set_button_active(active: bool) -> void:
	button_active = bool(active)

func is_button_active() -> bool:
	return button_active

func set_height(value: float) -> void:
	_apply_height(clampf(value, min_height, max_height))

func get_height() -> float:
	return current_height

func get_current_height() -> float:
	return current_height

## Unit vector the lift grows along. Each concrete direction script overrides
## this; the base lift grows upward.
func _axis() -> Vector2:
	return Vector2.UP

## True only for the lift whose support plane moves with it and therefore
## carries its rider stack while resizing.
func _carries_stack() -> bool:
	return _axis() == Vector2.UP

func _perpendicular() -> Vector2:
	var axis := _axis()
	return Vector2(-axis.y, axis.x)

func _apply_height(value: float) -> void:
	current_height = clampf(value, min_height, max_height)
	var axis := _axis()
	var perpendicular := _perpendicular()
	var collision_length := maxf(current_height - EDGE_INSET, MIN_COLLISION_LENGTH)
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		collision_shape.shape = rectangle
	# Block uses a 15.98px high shape for a 16px tile. Insetting both ends by
	# 0.01px keeps a lift flush with that surface at a seam.
	rectangle.size = Vector2(
		absf(perpendicular.x) * 8.0 + absf(perpendicular.y) * collision_length,
		absf(perpendicular.x) * collision_length + absf(perpendicular.y) * 8.0)
	collision_shape.position = axis * (current_height * 0.5)
	visual.polygon = PackedVector2Array([
		perpendicular * -4.0,
		axis * current_height + perpendicular * -4.0,
		axis * current_height + perpendicular * 4.0,
		perpendicular * 4.0,
	])

func _growth_blocked(next_height: float) -> bool:
	var axis := _axis()
	var delta_length := next_height - current_height
	if is_zero_approx(delta_length):
		return false
	# A telescoping rod extends through Blocks and tiles instead of colliding
	# with them, so only actors and other lifts obstruct the newly added strip
	# here. A carried rider is still protected by _can_push_supported_bodies().
	var old_end := global_position + axis * current_height
	var new_end := global_position + axis * next_height
	for candidate in _occupants():
		var bounds := _body_bounds(candidate)
		if not _body_intersects_added_strip(bounds, old_end, new_end):
			continue
		# Only the upward lift has a moving support plane that will carry a
		# body at the old endpoint. A body that is already rising is jumping
		# away and is not carried either.
		if _carries_stack() and _body_is_supported_by_endpoint(bounds, old_end) and _vertical_speed(candidate) >= -RISE_EPSILON:
			continue
		return true
	# Lifts are solid to one another in every direction: another rod entering
	# the added strip jams this one exactly like an actor. The jam is not a
	# cancel — each rod keeps its button target, so once the other retracts
	# and the strip reopens, motion resumes on a later frame.
	for other in get_tree().get_nodes_in_group("elevators"):
		var lift := other as Node2D
		if lift == null or lift == self:
			continue
		if _body_intersects_added_strip(_body_bounds(lift), old_end, new_end):
			return true
	return false

func _body_intersects_added_strip(bounds: Rect2, old_end: Vector2, new_end: Vector2) -> bool:
	var axis := _axis()
	var perpendicular := _perpendicular()
	var old_axis := (old_end - global_position).dot(axis)
	var new_axis := (new_end - global_position).dot(axis)
	var projected_axis := _project_rect(bounds, axis)
	var projected_cross := _project_rect(bounds, perpendicular)
	var cross_half := 4.0
	# The far-edge test only asks whether the body occupies the corridor beyond
	# the previous tip. The near-edge test must freeze the tip at a clearance
	# BEFORE the body: a lift that cannot carry its obstruction (downward and
	# horizontal lifts, or a body the upward lift has no support claim on) keeps
	# that overlap forever, and physics depenetration then grinds the grounded
	# body into whatever it stands on. SUPPORT_TOLERANCE is a support contract,
	# not permission to penetrate.
	return projected_axis.y > old_axis + SUPPORT_TOLERANCE and projected_axis.x < new_axis + GROWTH_CLEARANCE \
		and projected_cross.y > -cross_half and projected_cross.x < cross_half

func _body_is_supported_by_endpoint(bounds: Rect2, endpoint: Vector2) -> bool:
	var axis := _axis()
	var projected := _project_rect(bounds, axis)
	var endpoint_distance := (endpoint - global_position).dot(axis)
	# The edge facing the stretch direction is the minimum projection for all
	# four unit axes (bottom for UP, top for DOWN, right for LEFT, left for RIGHT).
	return absf(projected.x - endpoint_distance) <= SUPPORT_TOLERANCE

func _project_rect(bounds: Rect2, vector: Vector2) -> Vector2:
	var points := [bounds.position, Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.position.x, bounds.end.y), bounds.end]
	var minimum := INF
	var maximum := -INF
	for point in points:
		var value: float = (point - global_position).dot(vector)
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return Vector2(minimum, maximum)

func _vertical_speed(body: Node2D) -> float:
	# Read a body's vertical velocity without assuming it is a CharacterBody2D.
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity.y
	return 0.0

func _supported_stack() -> Array[Node2D]:
	var result: Array[Node2D] = []
	# Only an upward extending lift has a moving support plane. Downward and
	# horizontal variants keep their anchored top surface fixed while growing.
	if not _carries_stack():
		return result
	var axis := _axis()
	var endpoint := global_position + axis * current_height
	for candidate in _occupants():
		var bounds := _body_bounds(candidate)
		if _body_is_supported_by_endpoint(bounds, endpoint) and _cross_overlaps(bounds, endpoint):
			# A body that is already rising is jumping away from the support
			# plane, not resting on it. Carrying it would lift it and clear its
			# upward velocity, cancelling a jump on the next physics frame.
			if _vertical_speed(candidate) < -RISE_EPSILON:
				continue
			_add_supported_chain(candidate, result)
	return result

func _add_supported_chain(support: Node2D, result: Array[Node2D]) -> void:
	if result.has(support):
		return
	result.append(support)
	var support_bounds := _body_bounds(support)
	var axis := _axis()
	# Vertical lifts carry a complete stack. Downward and horizontal lifts keep
	# their anchored top surface fixed; side contacts remain ordinary collisions.
	if axis.x != 0.0:
		return
	for candidate in _occupants():
		if candidate == support or result.has(candidate):
			continue
		var bounds := _body_bounds(candidate)
		var supported_edge := bounds.end.y if axis == Vector2.UP else bounds.position.y
		var support_edge := support_bounds.position.y if axis == Vector2.UP else support_bounds.end.y
		if absf(supported_edge - support_edge) <= SUPPORT_TOLERANCE and _cross_overlaps(bounds, support.global_position):
			_add_supported_chain(candidate, result)

func _cross_overlaps(bounds: Rect2, point: Vector2) -> bool:
	var projected := _project_rect(bounds, _perpendicular())
	var center_cross := (point - global_position).dot(_perpendicular())
	return projected.y > center_cross - 4.0 and projected.x < center_cross + 4.0

func _push_supported_bodies(change: float, supported: Array[Node2D]) -> void:
	var delta := _axis() * change
	for candidate in supported:
		candidate.global_position += delta
		if candidate is CharacterBody2D and _axis().y != 0.0:
			var character := candidate as CharacterBody2D
			if signf(character.velocity.y) == signf(delta.y):
				character.velocity.y = 0.0

func _can_push_supported_bodies(change: float, supported: Array[Node2D]) -> bool:
	var delta := _axis() * change
	# The body is already touching this lift, and stacked riders touch one
	# another. Ignore those known support contacts during the prospective move;
	# terrain and unrelated bodies remain blocking collisions.
	for candidate in supported:
		if candidate is CharacterBody2D:
			var character := candidate as CharacterBody2D
			character.add_collision_exception_with(self)
			for other in supported:
				if other != candidate and other is PhysicsBody2D:
					character.add_collision_exception_with(other)
	var allowed := true
	for candidate in supported:
		if candidate is CharacterBody2D:
			var character := candidate as CharacterBody2D
			if character.test_move(character.global_transform, delta, null, 0.001, true):
				allowed = false
	for candidate in supported:
		if candidate is CharacterBody2D:
			var character := candidate as CharacterBody2D
			character.remove_collision_exception_with(self)
			for other in supported:
				if other != candidate and other is PhysicsBody2D:
					character.remove_collision_exception_with(other)
	return allowed

func _occupants() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for group_name in ["player", "giraffe"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node2D and not result.has(node):
				result.append(node)
	return result

func get_support_surface_y() -> float:
	var axis := _axis()
	if axis.y != 0.0:
		# Vertical lifts support from their top edge: the far end for an
		# upward lift, the anchored end for a downward lift.
		return global_position.y + minf(0.0, axis.y * current_height) + EDGE_INSET * 0.5
	# Horizontal lifts keep the full 8px height; only the length is inset, so
	# the support surface sits exactly on the top edge.
	return global_position.y - 4.0

func snap_body_to_support(body: Node2D, tolerance: float = SUPPORT_TOLERANCE) -> bool:
	if not supports_body(body, tolerance):
		return false
	var bounds := _body_bounds(body)
	var correction := get_support_surface_y() - bounds.end.y
	if absf(correction) > tolerance:
		return false
	body.global_position.y += correction
	return true

func supports_body(body: Node2D, tolerance: float = SUPPORT_TOLERANCE) -> bool:
	# ShapeCast2D samples exact contacts. A moving platform can advance between
	# the character and its next physics query by a fraction of a pixel, so expose
	# the platform's own support plane as a continuous contact contract.
	if body == null or not is_instance_valid(body):
		return false
	# A body moving upward is leaving the platform, not seeking support. The
	# absolute-gap tolerance below must never re-snap an active jump, whose
	# per-frame rise is smaller than SUPPORT_TOLERANCE at slow time scales.
	if _vertical_speed(body) < -RISE_EPSILON:
		return false
	var bounds := _body_bounds(body)
	var pressed_target := min_height if starts_extended else max_height
	var released_target := max_height if starts_extended else min_height
	var target := pressed_target if button_active else released_target
	var effective_tolerance := tolerance if not is_equal_approx(current_height, target) else EDGE_INSET
	var support_y := get_support_surface_y()
	var axis := _axis()
	var range_min := global_position.x - 4.0
	var range_max := global_position.x + 4.0
	if axis.x < 0.0:
		range_min = global_position.x - current_height
		range_max = global_position.x
	elif axis.x > 0.0:
		range_min = global_position.x
		range_max = global_position.x + current_height
	if absf(bounds.end.y - support_y) > effective_tolerance:
		return false
	return bounds.end.x > range_min + 0.001 and bounds.position.x < range_max - 0.001

func _body_bounds(node: Node2D) -> Rect2:
	# Return world-space bounds from the body's real collision geometry. A body
	# can carry a sub-pixel origin offset (Warma's polygon is x=-2..3, centre
	# +0.5), so the extents must never be assumed centred on global_position.
	var shape_node := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var shape := shape_node.shape as RectangleShape2D
		var half_size := shape.size * 0.5
		return Rect2(node.global_position + shape_node.position - half_size, shape.size)
	var polygon := node.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if polygon != null and not polygon.polygon.is_empty():
		var rect := Rect2(polygon.polygon[0], Vector2.ZERO)
		for point in polygon.polygon:
			rect = rect.expand(point)
		return Rect2(node.global_position + rect.position, rect.size)
	var half_size := Vector2(3.0, 8.0)
	return Rect2(node.global_position - half_size, half_size * 2.0)
