extends Node
## Room-scoped scheduler. Actors own gameplay/input/velocity; MotionWorld owns
## solid resolution and all migrated transforms. No automatic room rollout.
const World = preload("res://objects/physics/motion_world.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")
var world
var last_result: Dictionary = {}
var running := false
var tick_count := 0

func configure(room: Node2D, actors: Array, terrain: Array, elevators: Array = []) -> Dictionary:
	if world != null:
		return Contract.failure("driver_already_configured")
	# Only explicitly supplied production Elevators join geometry coordination.
	# Unlisted legacy Elevators could still directly move actors and are refused.
	for lift in get_tree().get_nodes_in_group("elevators"):
		if (room == lift or room.is_ancestor_of(lift)) and lift not in elevators:
			return Contract.failure("elevator_requires_stage_d")
	var candidate = World.new(room)
	for lift in elevators:
		if not room.is_ancestor_of(lift) or is_instance_valid(lift.get("_motion_coordinator")):
			return Contract.failure("elevator_outside_room_or_bound")
		var registration: Dictionary = candidate.register_elevator(lift)
		if not registration.ok:
			return registration
	for node in terrain:
		var registration: Dictionary = candidate.register_tiles(node) if node is TileMapLayer else candidate.register_body(node)
		if not registration.ok:
			return registration
	for actor in actors:
		if not room.is_ancestor_of(actor):
			return Contract.failure("actor_outside_room")
		if not actor.has_method("collect_motion_intent") or not actor.has_method("apply_motion_result"):
			return Contract.failure("missing_controller_interface")
		if is_instance_valid(actor.get("_motion_coordinator")):
			return Contract.failure("actor_already_bound")
		var registration: Dictionary = candidate.register_body(actor)
		if not registration.ok:
			return registration
	var valid: Dictionary = candidate.validate()
	if not valid.ok:
		return valid
	world = candidate
	for lift in elevators:
		lift.bind_motion_coordinator(self)
		lift.commit_coordinated_geometry(lift.current_height)
	for actor in actors:
		actor.bind_motion_coordinator(self)
	world.synchronize_geometry_queries()
	running = true
	return {"ok": true}

func _physics_process(delta: float) -> void:
	if running:
		advance(delta)

func advance(delta: float) -> Dictionary:
	if world == null or not running or not can_process():
		return Contract.failure("driver_inactive")
	if is_queued_for_deletion() or not is_instance_valid(world.owner) or not world.owner.is_inside_tree() or world.owner.is_queued_for_deletion():
		return Contract.failure("room_tearing_down")
	for lift in get_tree().get_nodes_in_group("elevators"):
		if world.owner.is_ancestor_of(lift) and not world.records.values().any(func(r): return r.node==lift and r.role=="elevator"):
			return _fail(Contract.failure("elevator_requires_stage_d"))
	# Removing actors is an explicit registry event. Normal scene exit also
	# releases the whole room-local world; no process-global state survives.
	for id in world.records.keys():
		if not is_instance_valid(world.records[id].node):
			world.unregister(id)
	var valid: Dictionary = world._ownership_check()
	if not valid.ok:
		return _fail(valid)
	valid = world.validate()
	if not valid.ok:
		return _fail(valid)
	var intents: Dictionary = {}
	var geometry: Dictionary = {}
	var ids: Array = world.records.keys()
	ids.sort()
	for id in ids:
		if world.roles[id] == "elevator":
			geometry[id] = world.records[id].node.collect_geometry_intent(delta)
		elif world.roles[id] != "terrain":
			intents[id] = world.records[id].node.collect_motion_intent(delta, world.contact_facts(id))
	# A gameplay reset/death may freeze the room during collection.
	if not can_process():
		return Contract.failure("room_frozen")
	last_result = world.step_frame(intents, geometry)
	if not last_result.ok:
		return _fail(last_result)
	for id in intents:
		world.records[id].node.apply_motion_result(last_result.results[id])
	tick_count += 1
	return last_result

func _fail(result: Dictionary) -> Dictionary:
	last_result = result
	running = false
	return result # Inspectable fail-closed diagnostic, no fallback native motion.
