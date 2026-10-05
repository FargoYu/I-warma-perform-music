extends RefCounted
## Pure geometry. Resolves before commit; never centers, snaps or depenetrates.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")

static func validate(state: Dictionary, roles: Dictionary) -> Dictionary:
	var ids := state.keys()
	ids.sort()
	for i in range(ids.size()):
		var id: String = ids[i]
		if not state[id].valid() or not roles.has(id) or not roles[id] in Contract.ROLES:
			return Contract.failure("invalid_geometry_or_role", {"id": id})
		for j in range(i + 1, ids.size()):
			var other: String = ids[j]
			if roles.has(other) and Contract.illegal_overlap(roles[id], roles[other]) and Bounds.overlaps(state[id], state[other]):
				return Contract.failure("invalid_initial_overlap", {"a": id, "b": other})
	return {"ok": true}

static func axis(rect, candidates: Dictionary, amount: float, dimension: int) -> Dictionary:
	if dimension not in [0, 1] or not is_finite(amount):
		return Contract.failure("invalid_motion")
	var proposal = rect.copy()
	var start: float = rect.left() if dimension == 0 else rect.top()
	var length: float = rect.width if dimension == 0 else rect.height
	var target := start + amount
	var contacts: Array = []
	var ids := candidates.keys()
	ids.sort()
	for id in ids:
		var solid = candidates[id]
		if Bounds.overlaps(rect, solid):
			return Contract.failure("invalid_initial_overlap", {"other": id})
		if not Bounds.cross_overlap(rect, solid, dimension) or amount == 0.0:
			continue
		var near: float = solid.left() if dimension == 0 else solid.top()
		var far: float = solid.right() if dimension == 0 else solid.bottom()
		var end: float = rect.right() if dimension == 0 else rect.bottom()
		var plane: float
		var cap: float
		if amount > 0.0 and near >= end:
			plane = near
			cap = near - length
			if cap > target:
				continue
		elif amount < 0.0 and far <= start:
			plane = far
			cap = far
			if cap < target:
				continue
		else:
			continue
		if cap != target:
			contacts.clear()
		target = cap
		contacts.append({"other": id, "axis": dimension, "plane": plane, "normal": -signf(amount)})
	if dimension == 0:
		proposal.x = target
	else:
		proposal.y_anchor = target
		proposal.y_offset = 0.0
	for id in ids:
		if Bounds.overlaps(proposal, candidates[id]):
			return Contract.failure("invalid_proposal", {"other": id})
	return {"ok": true, "rect": proposal, "travel": target - start, "contacts": contacts}

static func required_vertical_group(state: Dictionary, roles: Dictionary, source: String, offsets: Dictionary, amount: float) -> Dictionary:
	# Explicit preassembled chain contract, not a production head-bump controller.
	var valid := validate(state, roles)
	if not valid.ok:
		return valid
	if not state.has(source) or not offsets.has(source) or offsets[source] != 0.0 or not is_finite(amount):
		return Contract.failure("invalid_group")
	var start: float = state[source].top()
	var target := start + amount
	var blockers: Array = []
	var members := offsets.keys()
	members.sort()
	for id in members:
		if not state.has(id) or roles[id] == "terrain" or state[id].top() != start + float(offsets[id]):
			return Contract.failure("invalid_group", {"id": id})
		var others: Dictionary = {}
		for other in state:
			if not offsets.has(other):
				others[other] = state[other]
		var resolved := axis(state[id], others, amount, 1)
		if not resolved.ok:
			return resolved
		# An unobstructed member imposes no cap. Subtracting a large chain
		# offset from its independently summed target can round differently from
		# the source anchor; that arithmetic difference is not a contact plane.
		if resolved.contacts.is_empty():
			continue
		var cap: float = resolved.rect.top() - float(offsets[id])
		if (amount > 0.0 and cap < target) or (amount < 0.0 and cap > target):
			target = cap
			blockers = resolved.contacts
	var proposed := state.duplicate()
	for id in members:
		proposed[id] = state[id].copy()
		proposed[id].y_anchor = target
		proposed[id].y_offset = float(offsets[id])
	valid = validate(proposed, roles)
	if not valid.ok:
		return valid
	return {"ok": true, "state": proposed, "travel": target - start, "contacts": blockers, "members": members}
