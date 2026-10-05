extends RefCounted
## Logical commit owner. No input or gravity integration. Stage B's single-driver
## step() remains available; Stage C's scheduler uses atomic step_frame().
const Geometry = preload("res://objects/physics/scene_geometry.gd")
const Terrain = preload("res://objects/physics/terrain_adapter.gd")
const Query = preload("res://objects/physics/motion_query.gd")
const Resolver = preload("res://objects/physics/contact_resolver.gd")
const Graph = preload("res://objects/physics/support_graph.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")
const FrameResolver = preload("res://objects/physics/frame_resolver.gd")
const ElevatorGeometry = preload("res://objects/physics/elevator_geometry.gd")

var owner: Node2D
var records: Dictionary = {}
var state: Dictionary = {}
var roles: Dictionary = {}
var support = Graph.new()
var queries
var commits := 0
var last_detached: Array = []

func contact_facts(id: String) -> Dictionary:
	support.rebuild(state, roles, last_detached)
	var facts: Dictionary = support.links[id].duplicate(true)
	facts["anchored"] = support.anchored(id, roles)
	return facts

func step_frame(intents: Dictionary, geometry: Dictionary = {}) -> Dictionary:
	var valid := _ownership_check()
	if not valid.ok:
		return valid
	valid = validate()
	if not valid.ok:
		return valid
	for id in state:
		if roles[id] == "elevator":
			if not geometry.has(id) or not geometry[id].has("height") or not is_finite(float(geometry[id].height)) or geometry[id].height < records[id].node.min_height or geometry[id].height > records[id].node.max_height:
				return Contract.failure("invalid_geometry_intent", {"id":id})
			continue
		if roles[id] == "terrain":
			continue
		if not intents.has(id) or not Contract.valid_intent(intents[id]) or not intents[id].has("velocity_y"):
			return Contract.failure("missing_actor_intent", {"id": id})
		if typeof(intents[id].velocity_y) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(intents[id].velocity_y)):
			return Contract.failure("missing_actor_intent", {"id": id})
	for id in intents:
		if not state.has(id) or roles[id] not in ["warma","giraffe"]:
			return Contract.failure("invalid_intent_or_driver")
	for id in geometry:
		if not roles.has(id) or roles[id] != "elevator":
			return Contract.failure("invalid_geometry_driver")
	var frame = FrameResolver.new(self, intents, geometry)
	var outcome: Dictionary = frame.solve()
	if not outcome.ok:
		return outcome # No logical/node writes until the complete frame is valid.
	for id in intents:
		outcome.results[id]["requested"] = intents[id].duplicate()
		outcome.results[id]["dx"] = outcome.state[id].left() - state[id].left()
		outcome.results[id]["dy"] = outcome.state[id].top() - state[id].top()
	state = outcome.state
	last_detached = outcome.detached
	# All logical proposals have passed validation. No callbacks/queries are
	# dispatched in this publish phase; geometry and actors become one new frame.
	for id in geometry:
		records[id].height = outcome.geometry_results[id].height
		records[id].node.commit_coordinated_geometry(records[id].height)
	for id in intents:
		var record: Dictionary = records[id]
		record.node.global_position = Vector2(state[id].left() - record.local_origin.x, state[id].top() - record.local_origin.y)
	synchronize_geometry_queries()
	commits += 1
	support.rebuild(state, roles, last_detached, intents)
	return outcome

func synchronize_geometry_queries() -> void:
	# GodotPhysicsServer2D queues shape-bound updates. body_test_motion drains
	# that queue, whereas direct-space queries alone can still see stale bounds.
	# Zero-motion, margin-zero read-only test: discard collision/travel results.
	# This is a publication barrier AFTER the atomic logical/node commit, never
	# a native movement solver, snap, mask change, or penetration repair.
	for id in records:
		if roles[id] == "elevator":
			var parameters := PhysicsTestMotionParameters2D.new()
			parameters.from = records[id].node.global_transform
			parameters.motion = Vector2.ZERO
			parameters.margin = 0.0
			parameters.recovery_as_collision = false
			PhysicsServer2D.body_test_motion(records[id].node.get_rid(), parameters)
			break

func _init(room: Node2D) -> void:
	owner = room
	queries = Query.new(room.get_world_2d().direct_space_state)

func register_body(node: Node2D) -> Dictionary:
	var value := Geometry.body(node, owner)
	if not value.ok:
		return value
	return _register([value.record])

func register_elevator(node: Node2D) -> Dictionary:
	var value := ElevatorGeometry.registration(node,owner)
	if not value.ok:
		return value
	return _register([value.record])

func register_tiles(layer: TileMapLayer) -> Dictionary:
	var value := Terrain.cells(layer, owner)
	if not value.ok:
		return value
	return _register(value.records)

func _register(values: Array) -> Dictionary:
	for record in values:
		if records.has(record.id):
			return Contract.failure("duplicate_identity", {"id": record.id})
	for record in values:
		records[record.id] = record
		state[record.id] = record.rect.copy()
		roles[record.id] = record.role
	return {"ok": true}

func validate() -> Dictionary:
	return Resolver.validate(state, roles)

func unregister(id: String) -> void:
	records.erase(id)
	state.erase(id)
	roles.erase(id)
	support.rebuild(state, roles)

func _ownership_check() -> Dictionary:
	var checked_tiles: Array = []
	for id in records:
		var record: Dictionary = records[id]
		if not is_instance_valid(record.node):
			return Contract.failure("stale_registration", {"id": id})
		var node: Node2D = record.node
		if not node.is_inside_tree():
			return Contract.failure("stale_registration", {"id": id})
		if not Geometry.translation_only(node):
			return Contract.failure("unsupported_transform", {"id": id})
		if record.role == "elevator":
			var elevator_check := ElevatorGeometry.check_committed(record,state[id])
			if not elevator_check.ok:
				return elevator_check
			continue
		if node is TileMapLayer:
			if node in checked_tiles:
				continue
			checked_tiles.append(node)
			var extraction := Terrain.cells(node, owner)
			if not extraction.ok:
				return extraction
			var registered_count := 0
			for registered in records.values():
				if registered.node == node:
					registered_count += 1
			if registered_count != extraction.records.size():
				return Contract.failure("registered_geometry_changed", {"id": id})
			for cell in extraction.records:
				if not state.has(cell.id) or state[cell.id].coordinates() != cell.rect.coordinates() or records[cell.id].layer != cell.layer or records[cell.id].mask != cell.mask:
					return Contract.failure("registered_geometry_changed", {"id": id})
			continue
		if node is CharacterBody2D:
			if node.is_physics_processing() and node.can_process():
				return Contract.failure("controller_still_active", {"id": id})
		var expected := Vector2(state[id].left() - record.local_origin.x, state[id].top() - record.local_origin.y)
		if node.global_position != expected:
			return Contract.failure("external_transform_write", {"id": id})
		var actual := Geometry.body(node, owner)
		if not actual.ok:
			return actual
		if actual.record.id != id or actual.record.role != record.role or actual.record.layer != record.layer or actual.record.mask != record.mask:
			return Contract.failure("registered_identity_changed", {"id": id})
	return {"ok": true}

func step(id: String, intent: Dictionary) -> Dictionary:
	if not state.has(id) or roles[id] == "terrain" or not Contract.valid_intent(intent):
		return Contract.failure("invalid_intent_or_driver")
	var valid := _ownership_check()
	if not valid.ok:
		return valid
	valid = validate()
	if not valid.ok:
		return valid
	var working := state.duplicate()
	working[id] = state[id].copy()
	var contacts: Array = []
	var query_evidence: Array = []
	for axis in [0, 1]:
		var amount := float(intent.dx if axis == 0 else intent.dy)
		var candidates: Dictionary = queries.candidates(id, working, records, amount, axis)
		if not candidates.ok:
			return candidates
		var resolved := Resolver.axis(working[id], candidates.candidates, amount, axis)
		if not resolved.ok:
			return resolved
		working[id] = resolved.rect
		contacts.append_array(resolved.contacts)
		query_evidence.append({"axis": axis, "cast_safe": candidates.cast_safe, "cast_unsafe": candidates.cast_unsafe})
		valid = Resolver.validate(working, roles)
		if not valid.ok:
			return valid
	var dx: float = working[id].left() - state[id].left()
	var dy: float = working[id].top() - state[id].top()
	state = working
	var record: Dictionary = records[id]
	# Root origin, not rectangle center (Warma's center is +0.5).
	record.node.global_position = Vector2(state[id].left() - record.local_origin.x, state[id].top() - record.local_origin.y)
	commits += 1
	support.rebuild(state, roles, [id] if intent.detach else [])
	var facts: Dictionary = support.links[id].duplicate(true)
	facts["anchored"] = support.anchored(id, roles)
	var output := Contract.result(id, intent, dx, dy, contacts, facts)
	output["queries"] = query_evidence
	return output
