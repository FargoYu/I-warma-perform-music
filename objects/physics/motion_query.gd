extends RefCounted
## Queries keep native collider identity. No replacement layer-1 actor proxies.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")
const MAX_RESULTS := 256
var space: PhysicsDirectSpaceState2D
var native_hits: Dictionary = {}
var query_count := 0

func _init(value: PhysicsDirectSpaceState2D) -> void:
	space = value

func parameters(rect: Rect2) -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	query.shape = shape
	query.transform = Transform2D(0.0, rect.get_center())
	query.margin = Contract.QUERY_MARGIN
	query.collision_mask = Contract.SOLID_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return query

func candidates(id: String, state: Dictionary, records: Dictionary, amount: float, axis: int) -> Dictionary:
	var rect = state[id]
	var edges: Array = rect.coordinates()
	if axis == 0:
		edges[0] += minf(amount, 0.0)
		edges[2] += maxf(amount, 0.0)
	else:
		edges[1] += minf(amount, 0.0)
		edges[3] += maxf(amount, 0.0)
	var envelope := Rect2(Vector2(edges[0], edges[1]), Vector2(edges[2] - edges[0], edges[3] - edges[1]))
	if not envelope.position.is_finite() or not envelope.size.is_finite():
		return Contract.failure("query_conversion_out_of_range")
	var query := parameters(envelope)
	query.exclude = [records[id].node.get_rid()]
	query_count += 1
	var hits := space.intersect_shape(query, MAX_RESULTS)
	if hits.size() >= MAX_RESULTS:
		return Contract.failure("candidate_overflow", {"limit": MAX_RESULTS})
	var found: Dictionary = {}
	for hit in hits:
		var known := false
		for other in records:
			if records[other].node == hit.collider:
				known = true
				var native_id: String = other.get_slice("/cell(", 0) if records[other].has("cell") else other
				native_hits[native_id] = {"class": hit.collider.get_class(), "layer": records[other].layer, "mask": records[other].mask}
				# A TileMap hit maps to registered cells on this layer, filtered below.
				if other != id and Bounds.touches_envelope(state[other], edges):
					found[other] = state[other]
		if not known:
			return Contract.failure("unregistered_solid", {"collider": str(hit.collider)})
	# Exact logical broad phase supplements native discovery at tangent faces and
	# after same-frame commits. No padding/epsilon: closed scalar swept AABBs.
	# This exhaustive registry scan is deliberate at this checkpoint (small rooms).
	# Native queries still diagnose unknown solids/overflow and retain hit identity.
	for other in state:
		if other != id and Bounds.touches_envelope(state[other], edges):
			found[other] = state[other]
	query = parameters(rect.query_rect())
	query.exclude = [records[id].node.get_rid()]
	query.motion = Vector2(amount, 0.0) if axis == 0 else Vector2(0.0, amount)
	query_count += 1
	var fractions := space.cast_motion(query)
	return {"ok": true, "candidates": found, "cast_safe": fractions[0], "cast_unsafe": fractions[1]}
