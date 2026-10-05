extends RefCounted
## Proposed shape + carried-actor transaction. Only terrain/rod overlap is legal.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
const Geometry = preload("res://objects/physics/elevator_geometry.gd")
const Resolver = preload("res://objects/physics/contact_resolver.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")

static func solve(frame, id: String, request: Dictionary) -> Dictionary:
	var record: Dictionary = frame.records[id]
	var old_height: float = record.height
	var desired: float = request.height
	var anchor: Vector2 = record.anchor
	var axis: Vector2 = record.axis
	var old = frame.state[id]
	# Discover unknown native occupants over the full old/new rod envelope too.
	# Candidate geometry remains logical; no extra discovery padding is used.
	var native_check: Dictionary = frame.query.candidates(id, frame.state, frame.records,
		(desired-old_height)*(axis.y if axis.y!=0.0 else axis.x),1 if axis.y!=0.0 else 0)
	if not native_check.ok:
		return native_check
	var offsets: Dictionary = frame.graph.required_offsets(id, frame.state) if axis == Vector2.UP else {id: 0.0}
	var allowed := desired
	var blockers: Array = []
	# Growth into an uncarried actor or another rod rejects this height step.
	# Terrain never caps rod growth. Carried actors still collide with terrain below.
	if desired > old_height:
		var ids: Array = frame.state.keys()
		ids.sort()
		for other in ids:
			if offsets.has(other) or frame.roles[other] == "terrain":
				continue
			var solid = frame.state[other]
			if not Bounds.cross_overlap(old, solid, 1 if axis.y != 0.0 else 0):
				continue
			# Scalar planes, no Vector2 rounding in contact legality.
			var near: float
			if axis == Vector2.UP:
				near = float(anchor.y)-solid.bottom()
			elif axis == Vector2.DOWN:
				near = solid.top()-float(anchor.y)
			elif axis == Vector2.LEFT:
				near = float(anchor.x)-solid.right()
			else:
				near = solid.left()-float(anchor.x)
			if near >= old_height and near <= allowed:
				if near < allowed:
					blockers.clear()
				allowed = near
				blockers.append(other)
		if not blockers.is_empty():
			# Preserve the production wait/retry policy. Publishing a new contact
			# plane at an unrelated actor would grant support and lift it next tick.
			allowed = old_height
	var proposed_rod = Geometry.rectangle(anchor, axis, allowed)
	var top: float = proposed_rod.top()
	if axis == Vector2.UP:
		var dy: float = top-old.top()
		for member in offsets:
			if member == id:
				continue
			var candidates: Dictionary = frame.query.candidates(member, frame.state, frame.records, dy, 1)
			if not candidates.ok:
				return candidates
			for other in offsets:
				candidates.candidates.erase(other)
			var resolved := Resolver.axis(frame.state[member], candidates.candidates, dy, 1)
			if not resolved.ok:
				return resolved
			if resolved.contacts.is_empty():
				continue
			var cap: float = resolved.rect.top()-float(offsets[member])
			if (dy < 0 and cap >= top) or (dy > 0 and cap <= top):
				top = cap
				for hit in resolved.contacts:
					blockers.append(hit.other)
		allowed = float(anchor.y)-top
		proposed_rod = Geometry.rectangle(anchor,axis,allowed)
		# Derive the group from exactly the same top expression as the rod.
		top = proposed_rod.top()
	var proposed: Dictionary = frame.state.duplicate()
	proposed[id] = proposed_rod
	for member in offsets:
		if member == id:
			continue
		proposed[member] = frame.state[member].copy()
		proposed[member].y_anchor = top
		proposed[member].y_offset = offsets[member]
	var valid := Resolver.validate(proposed, frame.roles)
	if not valid.ok:
		return valid
	var carried: Array = offsets.keys()
	carried.erase(id)
	return {"ok": true, "state": proposed, "height": allowed, "members": carried,
		"dy": proposed_rod.top()-old.top(), "jammed": allowed != desired,
		"blockers": blockers, "requested_height": desired, "old_height": old_height}
