extends RefCounted
## Deterministic actor/shape transactions. No input, gravity or mass integration.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")
const Resolver = preload("res://objects/physics/contact_resolver.gd")
const Graph = preload("res://objects/physics/support_graph.gd")
const ElevatorTransaction = preload("res://objects/physics/elevator_transaction.gd")
var state: Dictionary
var roles: Dictionary
var records: Dictionary
var intents: Dictionary
var detached: Array = []
var graph = Graph.new()
var query
var results: Dictionary = {}
var transactions: Array = []
var geometry_requests: Dictionary = {}
var geometry_results: Dictionary = {}

func _init(world, requests: Dictionary, geometry: Dictionary = {}) -> void:
	state = {}
	for id in world.state:
		state[id] = world.state[id].copy()
	roles = world.roles
	records = world.records
	query = world.queries
	intents = requests
	geometry_requests = geometry
	for id in intents:
		if intents[id].detach:
			detached.append(id)
		results[id] = {"blocked_x": false, "blocked_y": false, "contacts": [],
			"velocity_y": float(intents[id].velocity_y), "vertical_driver": id, "detached": intents[id].detach}

func rebuild() -> void:
	var support_intents := intents.duplicate()
	for id in geometry_requests:
		support_intents[id] = {"dy": records[id].height-float(geometry_requests[id].height) if records[id].axis==Vector2.UP else 0.0}
	graph.rebuild(state, roles, detached, support_intents)

func depth(id: String) -> int:
	var value := 0
	var seen: Array = []
	while graph.links.has(id) and graph.links[id].attached:
		if id in seen:
			return 0
		seen.append(id)
		id = graph.links[id].support
		value += 1
	return value

func ordered() -> Array:
	var ids := intents.keys()
	ids.sort_custom(func(a, b):
		var ad := depth(a)
		var bd := depth(b)
		if ad != bd:
			return ad < bd
		# Among independent drivers, rising/faster-upward requests run first.
		# A Giraffe's independent upward impulse can therefore leave Warma's
		# head instead of being overwritten by a slower jump/carry transaction.
		var ay := float(intents[a].dy)
		var by := float(intents[b].dy)
		if ay != by:
			return ay < by
		if roles[a] != roles[b]:
			return roles[a] == "warma"
		return a < b)
	return ids

func vertical(source: String, amount: float) -> Dictionary:
	var start: float = state[source].top()
	var target := start + amount
	var offsets: Dictionary = graph.required_offsets(source, state)
	var blocked := false
	var contacts: Array = []
	var events := 0
	while state[source].top() != target:
		events += 1
		if events > state.size() + 1:
			return Contract.failure("nonprogressing_lift_events")
		var legal := target
		var hits: Array = []
		var members := offsets.keys()
		members.sort()
		for id in members:
			var remaining: float = target - state[source].top()
			var candidates: Dictionary = query.candidates(id, state, records, remaining, 1)
			if not candidates.ok:
				return candidates
			for other in offsets:
				candidates.candidates.erase(other)
			var resolved := Resolver.axis(state[id], candidates.candidates, remaining, 1)
			if not resolved.ok:
				return resolved
			if resolved.contacts.is_empty():
				continue
			var cap: float = resolved.rect.top() - float(offsets[id])
			if (amount < 0.0 and cap < legal) or (amount > 0.0 and cap > legal):
				continue
			if cap != legal:
				hits.clear()
			legal = cap
			for contact in resolved.contacts:
				var hit: Dictionary = contact.duplicate()
				hit["member"] = id
				hits.append(hit)
		var proposed := state.duplicate()
		for id in offsets:
			proposed[id] = state[id].copy()
			proposed[id].y_anchor = legal
			proposed[id].y_offset = float(offsets[id])
		var valid := Resolver.validate(proposed, roles)
		if not valid.ok:
			return valid
		state = proposed
		if hits.is_empty():
			break
		var expanded := false
		for hit in hits:
			var other: String = hit.other
			if offsets.has(other):
				continue # One obstacle may touch several members at the same plane.
			if Contract.can_lift(roles[source], roles[other], 1, amount) and not offsets.has(other):
				offsets[other] = float(offsets[hit.member]) - state[other].height
				rebuild()
				var riders: Dictionary = graph.required_offsets(other, state)
				for rider in riders:
					if not offsets.has(rider):
						offsets[rider] = float(offsets[other]) + float(riders[rider])
				expanded = true
			else:
				blocked = true
				contacts.append(hit)
		if blocked or not expanded:
			break
	var final_velocity: float = 0.0 if blocked else float(intents[source].velocity_y)
	for id in offsets:
		results[id].velocity_y = final_velocity
		results[id].vertical_driver = source
		results[id].blocked_y = blocked
		results[id].contacts.append_array(contacts)
	transactions.append({"source": source, "members": offsets.keys(), "requested": amount,
		"committed": state[source].top() - start, "blocked": blocked, "contacts": contacts})
	return {"ok": true, "members": offsets.keys()}

func solve() -> Dictionary:
	rebuild()
	# Canonical X arbitration, then support-depth Y arbitration. Earlier committed
	# horizontal movement is visible to later requests; contact never transfers X.
	var ids := intents.keys()
	ids.sort()
	for id in ids:
		var dx := float(intents[id].dx)
		var candidates: Dictionary = query.candidates(id, state, records, dx, 0)
		if not candidates.ok:
			return candidates
		var result := Resolver.axis(state[id], candidates.candidates, dx, 0)
		if not result.ok:
			return result
		state[id] = result.rect
		results[id].contacts.append_array(result.contacts)
		# Contact planes, not subtraction roundoff, determine velocity cancellation.
		results[id].blocked_x = not result.contacts.is_empty()
	rebuild()
	var consumed: Array = []
	# Canonical geometry transactions operate on working state after actor X.
	# Jump/impulse detach was captured before this phase; no post-commit repair.
	var lifts := geometry_requests.keys()
	lifts.sort()
	for id in lifts:
		var mutation := ElevatorTransaction.solve(self,id,geometry_requests[id])
		if not mutation.ok:
			return mutation
		state = mutation.state
		geometry_results[id] = mutation
		for member in mutation.members:
			consumed.append(member)
			# Kinematic carry is support displacement, not a new actor jump impulse.
			results[member].velocity_y = 0.0
			results[member].vertical_driver = id
			results[member].blocked_y = mutation.jammed
		transactions.append({"source":id,"geometry":true,"height":mutation.height,"dy":mutation.dy,
			"members":mutation.members,"jammed":mutation.jammed,"blockers":mutation.blockers})
		rebuild()
	for id in ordered():
		if id in consumed:
			continue
		var dy := float(intents[id].dy)
		if dy == 0.0:
			continue
		var moved := vertical(id, dy)
		if not moved.ok:
			return moved
		consumed.append_array(moved.members)
		rebuild()
	var valid := Resolver.validate(state, roles)
	if not valid.ok:
		return valid
	rebuild()
	for id in ids:
		results[id]["support"] = graph.links[id].duplicate(true)
		results[id].support["anchored"] = graph.anchored(id, roles)
		results[id]["bottom"] = state[id].bottom()
		results[id]["ok"] = true
	return {"ok": true, "state": state, "results": results, "transactions": transactions, "detached": detached, "geometry_results":geometry_results}
