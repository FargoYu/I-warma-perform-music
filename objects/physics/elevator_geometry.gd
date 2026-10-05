extends RefCounted
## Real anchored rod. One occupied rectangle; no invented separate platform cap.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
const Geometry = preload("res://objects/physics/scene_geometry.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")
const SCENES := ["res://objects/elevator_up.tscn", "res://objects/elevator_down.tscn",
	"res://objects/elevator_left.tscn", "res://objects/elevator_right.tscn"]

static func rectangle(anchor: Vector2, axis: Vector2, height: float):
	if axis == Vector2.UP:
		return Bounds.new(float(anchor.x)-4.0, float(anchor.y)-height, 8.0, height)
	if axis == Vector2.DOWN:
		return Bounds.new(float(anchor.x)-4.0, float(anchor.y), 8.0, height)
	if axis == Vector2.LEFT:
		return Bounds.new(float(anchor.x)-height, float(anchor.y)-4.0, height, 8.0)
	return Bounds.new(float(anchor.x), float(anchor.y)-4.0, height, 8.0)

static func registration(node: Node2D, owner: Node) -> Dictionary:
	if node.scene_file_path not in SCENES or not node is AnimatableBody2D:
		return Contract.failure("unsupported_elevator_scene")
	if not Geometry.translation_only(node) or not is_finite(node.current_height) or node.current_height < node.min_height or node.current_height > node.max_height:
		return Contract.failure("invalid_elevator_geometry")
	if not is_finite(node.min_height) or not is_finite(node.max_height) or node.min_height < 3.0 or node.max_height < node.min_height or not is_finite(node.height_speed) or node.height_speed <= 0.0:
		return Contract.failure("invalid_elevator_parameters")
	var shape_count := 0
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			shape_count += 1
	if shape_count != 1:
		return Contract.failure("unsupported_elevator_shape_count")
	if node.collision_layer != 1 or node.collision_mask != 0 or not node.collision_shape.shape is RectangleShape2D:
		return Contract.failure("unexpected_elevator_identity")
	if node.collision_shape.disabled or node.collision_shape.one_way_collision or not Geometry.translation_only(node.collision_shape):
		return Contract.failure("unsupported_elevator_shape")
	var axis: Vector2 = node._axis()
	if axis not in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		return Contract.failure("unsupported_elevator_axis")
	var value := {"id": str(owner.get_path_to(node)), "node": node, "role": "elevator",
		"axis": axis, "anchor": node.global_position, "height": float(node.current_height),
		"rect": rectangle(node.global_position, axis, node.current_height), "layer": 1, "mask": 0}
	return {"ok": true, "record": value}

static func check_committed(record: Dictionary, rect) -> Dictionary:
	var node: Node2D = record.node
	if node.global_position != record.anchor or node._axis() != record.axis or node.current_height != record.height:
		return Contract.failure("external_elevator_geometry_write", {"id": record.id})
	if node.is_physics_processing() and node.can_process():
		return Contract.failure("legacy_elevator_still_active")
	if node.collision_layer != 1 or node.collision_mask != 0 or node.sync_to_physics:
		return Contract.failure("external_elevator_identity_write")
	var shape: CollisionShape2D = node.collision_shape
	if not shape.shape is RectangleShape2D or shape.disabled or shape.one_way_collision or not Geometry.translation_only(shape):
		return Contract.failure("external_elevator_shape_write")
	if shape.shape.size != Vector2(rect.width, rect.height) or shape.position != record.axis * (record.height * 0.5):
		return Contract.failure("external_elevator_shape_write")
	return {"ok": true}
