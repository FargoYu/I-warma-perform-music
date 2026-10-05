extends RefCounted
## Read-only geometry adapters for existing Warma/Giraffe/Block scene identities.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")

static func translation_only(node: Node2D) -> bool:
	return node.global_transform.x == Vector2.RIGHT and node.global_transform.y == Vector2.DOWN and node.global_position.is_finite()

static func rectangle_polygon(points: PackedVector2Array, expected: Rect2) -> bool:
	if points.size() != 4:
		return false
	var corners := [expected.position, Vector2(expected.end.x, expected.position.y), expected.end, Vector2(expected.position.x, expected.end.y)]
	for i in range(4):
		if not points[i] in corners:
			return false
		corners.erase(points[i])
		var edge := points[(i + 1) % 4] - points[i]
		if (edge.x == 0.0) == (edge.y == 0.0):
			return false
	return corners.is_empty()

static func body(node: Node2D, owner: Node) -> Dictionary:
	if node is Area2D or node is AnimatableBody2D:
		return Contract.failure("unsupported_solid_type", {"node": str(node.name)})
	if not translation_only(node):
		return Contract.failure("unsupported_transform", {"node": str(node.name)})
	var role: String
	var local: Rect2
	var layer: int
	match node.scene_file_path:
		"res://objects/warma.tscn":
			role = "warma"
			local = Rect2(-2, -8, 5, 16)
			layer = 2
		"res://objects/giraffe.tscn":
			role = "giraffe"
			local = Rect2(-4, -8, 8, 16)
			layer = 4
		"res://objects/block.tscn":
			role = "terrain"
			local = Rect2(-8, -8, 16, 16)
			layer = 1
		_:
			return Contract.failure("unsupported_scene", {"scene": node.scene_file_path})
	if not node is PhysicsBody2D or node.collision_layer != layer:
		return Contract.failure("unexpected_collision_identity")
	var shapes: Array = []
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			shapes.append(child)
	if shapes.size() != 1:
		return Contract.failure("unsupported_shape_count")
	var shape: Node2D = shapes[0]
	if not translation_only(shape) or shape.position != Vector2.ZERO or shape.disabled or shape.one_way_collision:
		return Contract.failure("unsupported_shape_configuration")
	if role == "warma":
		if not shape is CollisionPolygon2D or shape.build_mode != CollisionPolygon2D.BUILD_SOLIDS or not rectangle_polygon(shape.polygon, local):
			return Contract.failure("unexpected_actor_geometry")
	else:
		if not shape is CollisionShape2D or not shape.shape is RectangleShape2D or shape.shape.size != local.size:
			return Contract.failure("terrain_requires_exact_instance" if role == "terrain" else "unexpected_actor_geometry")
	var id := str(owner.get_path_to(node))
	var rect = Bounds.new(float(node.global_position.x) + local.position.x, float(node.global_position.y) + local.position.y, local.size.x, local.size.y)
	return {"ok": true, "record": {"id": id, "node": node, "role": role, "rect": rect,
		"local_origin": local.position, "layer": node.collision_layer, "mask": node.collision_mask}}

static func sensors(warma: Node) -> Array:
	# Classification only. Probes remain in the real scene and are not solids.
	# The list is resolved from the nodes that exist: Warma's HeadProbe was
	# removed together with the head-bump impulse rule it existed for.
	var listed := [
		["GroundProbe", "gameplay_support_query"],
		["HeadProbe", "gameplay_lift_eligibility_query"],
		["EquipmentPivot/HeldExtinguisher/Nozzle", "projectile_spawn_marker"],
	]
	var result: Array = []
	for entry in listed:
		var node := warma.get_node_or_null(entry[0])
		if node != null:
			result.append({"node": node, "purpose": entry[1], "solid": false})
	return result
