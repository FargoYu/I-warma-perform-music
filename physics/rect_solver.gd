class_name RectSolver
extends RefCounted
const StateScript = preload("res://physics/rect_state.gd")
## Synchronous, axis-aligned rectangle physics. No native body solver is used.
## Gravity and jump requests are applied by the world once, before step().
## Contacts may reduce horizontal intent; only vertical contacts can push.

const GEOMETRY_EPS: float = 0.00000001
const SPEED_EPS: float = 0.000000001

var bodies: Array[StateScript] = []
var diagnostics: Array[String] = []
var event_count: int = 0
var max_events: int = 256
var _next_id: int = 1


func add_body(body: StateScript) -> bool:
	if body == null or body.w <= 0.0 or body.h <= 0.0:
		diagnostics.append("Rejected a rectangle with nonpositive dimensions.")
		return false
	if not is_finite(body.x) or not is_finite(body.y) or not is_finite(body.w) or not is_finite(body.h):
		diagnostics.append("Rejected a rectangle with nonfinite geometry.")
		return false
	if bodies.has(body):
		return true
	for other in bodies:
		if _penetrates(body, other):
			var source: String = str(body.node.get_path()) if is_instance_valid(body.node) else body.kind
			var other_source: String = str(other.node.get_path()) if is_instance_valid(other.node) else other.kind
			diagnostics.append("Rejected initial overlap: %s at (%.2f, %.2f) / %s at (%.2f, %.2f)." % [source, body.x, body.y, other_source, other.x, other.y])
			return false
		if body.id > 0 and body.id == other.id:
			diagnostics.append("Rejected duplicate rectangle id %d." % body.id)
			return false
	if body.id <= 0:
		body.id = _next_id
	_next_id = maxi(_next_id, body.id + 1)
	if body.fixed:
		body.vx = 0.0
		body.vy = 0.0
	bodies.append(body)
	return true


func remove_body(body: StateScript) -> void:
	bodies.erase(body)


func step(delta: float) -> void:
	diagnostics.clear()
	event_count = 0
	if not is_finite(delta) or delta < 0.0:
		diagnostics.append("Rejected invalid physics delta.")
		_stop_motion()
		return
	for body in bodies:
		if not is_finite(body.x) or not is_finite(body.y) or not is_finite(body.intent_x) or not is_finite(body.vy):
			diagnostics.append("Nonfinite state on rectangle %d; motion stopped." % body.id)
			_stop_motion()
			return
	if not _validate_nonpenetration("step start"):
		_stop_motion()
		return
	_solve_contacts()
	var remaining: float = delta
	while remaining > 0.0:
		var event_time: float = _next_event_time(remaining)
		if event_time < 0.0:
			var free_advance_start: PackedFloat64Array = _save_positions()
			_advance(remaining)
			if not _validate_nonpenetration("free advance"):
				_restore_positions(free_advance_start)
				_stop_motion()
			remaining = 0.0
			break
		if event_count >= max_events:
			diagnostics.append("Event budget %d exhausted with %.12f seconds unprocessed; motion stopped." % [max_events, remaining])
			_stop_motion()
			break
		var last_valid: PackedFloat64Array = _save_positions()
		_advance(event_time)
		remaining = maxf(remaining - event_time, 0.0)
		event_count += 1
		# All simultaneous contacts are rebuilt from this shared boundary state.
		# Never retain one actor's old support while processing a different actor.
		if not _anchor_contacts():
			_restore_positions(last_valid)
			_stop_motion()
			break
		_solve_contacts()
		if not _validate_nonpenetration("event %d" % event_count):
			_restore_positions(last_valid)
			_stop_motion()
			break
	if not _validate_nonpenetration("step end"):
		_stop_motion()
	refresh_contacts()


func refresh_contacts() -> void:
	# This is a query refresh, not another velocity or gravity integration.
	for body in bodies:
		body.grounded = false
	for i in range(bodies.size()):
		var a: StateScript = bodies[i]
		for j in range(i + 1, bodies.size()):
			var b: StateScript = bodies[j]
			if not _outgoing_x_overlap(a, b):
				continue
			if absf(a.bottom() - b.y) <= GEOMETRY_EPS and absf(a.vy - b.vy) <= SPEED_EPS:
				a.grounded = not a.fixed
			if absf(b.bottom() - a.y) <= GEOMETRY_EPS and absf(a.vy - b.vy) <= SPEED_EPS:
				b.grounded = not b.fixed


func _solve_contacts() -> void:
	var count: int = bodies.size()
	var right_edges: Array = []
	var left_edges: Array = []
	var down_edges: Array = []
	var order_x: Array[int] = []
	var order_y: Array[int] = []
	var roof_reachable: Array[bool] = []
	for i in range(count):
		right_edges.append([])
		left_edges.append([])
		down_edges.append([])
		order_x.append(i)
		order_y.append(i)
		roof_reachable.append(bodies[i].fixed)
		bodies[i].vx = 0.0 if bodies[i].fixed else bodies[i].intent_x
		if bodies[i].fixed:
			bodies[i].vy = 0.0
	order_x.sort_custom(func(i: int, j: int) -> bool:
		return bodies[i].x < bodies[j].x if bodies[i].x != bodies[j].x else bodies[i].id < bodies[j].id)
	order_y.sort_custom(func(i: int, j: int) -> bool:
		return bodies[i].y < bodies[j].y if bodies[i].y != bodies[j].y else bodies[i].id < bodies[j].id)
	for i in range(count):
		var a: StateScript = bodies[i]
		for j in range(i + 1, count):
			var b: StateScript = bodies[j]
			if a.fixed and b.fixed:
				continue
			if minf(a.bottom(), b.bottom()) - maxf(a.y, b.y) <= GEOMETRY_EPS:
				continue
			if absf(a.right() - b.x) <= GEOMETRY_EPS:
				right_edges[i].append(j)
				left_edges[j].append(i)
			elif absf(b.right() - a.x) <= GEOMETRY_EPS:
				right_edges[j].append(i)
				left_edges[i].append(j)
	# Rightward requests are limited by their right neighbours, never pushed.
	for k in range(count - 1, -1, -1):
		var i: int = order_x[k]
		if bodies[i].vx > 0.0:
			for j: int in right_edges[i]:
				bodies[i].vx = minf(bodies[i].vx, maxf(bodies[j].vx, 0.0))
	for i: int in order_x:
		if bodies[i].vx < 0.0:
			for j: int in left_edges[i]:
				bodies[i].vx = maxf(bodies[i].vx, minf(bodies[j].vx, 0.0))
	# Freeze vx first. At a double-zero corner, only horizontal closing creates
	# a vertical contact. This is the single global horizontal-priority rule.
	for i in range(count):
		var a: StateScript = bodies[i]
		for j in range(i + 1, count):
			var b: StateScript = bodies[j]
			if a.fixed and b.fixed:
				continue
			if not _outgoing_x_overlap(a, b):
				continue
			if absf(a.bottom() - b.y) <= GEOMETRY_EPS:
				down_edges[i].append(j)
			elif absf(b.bottom() - a.y) <= GEOMETRY_EPS:
				down_edges[j].append(i)
	# A static ceiling's lower contact chain cannot move upward.
	for i: int in order_y:
		if roof_reachable[i]:
			for j: int in down_edges[i]:
				roof_reachable[j] = true
	for k in range(count - 1, -1, -1):
		var i: int = order_y[k]
		var body: StateScript = bodies[i]
		if body.fixed:
			body.vy = 0.0
			continue
		if roof_reachable[i]:
			body.vy = maxf(body.vy, 0.0)
		for j: int in down_edges[i]:
			body.vy = minf(body.vy, bodies[j].vy)


func _outgoing_x_overlap(a: StateScript, b: StateScript) -> bool:
	var overlap: float = minf(a.right(), b.right()) - maxf(a.x, b.x)
	if overlap > GEOMETRY_EPS:
		return true
	if overlap < -GEOMETRY_EPS:
		return false
	if absf(a.right() - b.x) <= GEOMETRY_EPS and a.vx > b.vx + SPEED_EPS:
		return true
	if absf(b.right() - a.x) <= GEOMETRY_EPS and b.vx > a.vx + SPEED_EPS:
		return true
	return false


func _next_event_time(limit: float) -> float:
	var earliest: float = -1.0
	for i in range(bodies.size()):
		var a: StateScript = bodies[i]
		for j in range(i + 1, bodies.size()):
			var b: StateScript = bodies[j]
			if a.fixed and b.fixed:
				continue
			var rvx: float = a.vx - b.vx
			var rvy: float = a.vy - b.vy
			if absf(rvx) > SPEED_EPS:
				# Both leading and trailing edge equalities matter: trailing edges
				# release a support, even when there is no new collision.
				for gap: float in [b.x - a.right(), b.right() - a.x]:
					if absf(gap) <= GEOMETRY_EPS:
						continue
					var t: float = gap / rvx
					if t <= 0.0 or t > limit or (earliest >= 0.0 and t >= earliest):
						continue
					var ay: float = a.y + a.vy * t
					var by: float = b.y + b.vy * t
					if minf(ay + a.h, by + b.h) - maxf(ay, by) >= -GEOMETRY_EPS:
						earliest = t
			if absf(rvy) > SPEED_EPS:
				for gap: float in [b.y - a.bottom(), b.bottom() - a.y]:
					if absf(gap) <= GEOMETRY_EPS:
						continue
					var t: float = gap / rvy
					if t <= 0.0 or t > limit or (earliest >= 0.0 and t >= earliest):
						continue
					var ax: float = a.x + a.vx * t
					var bx: float = b.x + b.vx * t
					if minf(ax + a.w, bx + b.w) - maxf(ax, bx) >= -GEOMETRY_EPS:
						earliest = t
	return earliest


func _advance(delta: float) -> void:
	for body in bodies:
		if not body.fixed:
			body.x += body.vx * delta
			body.y += body.vy * delta


func _anchor_contacts() -> bool:
	# Event division and independent multiply/add operations can disagree by a
	# few ulps. Close a simultaneous set as one system of boundary equalities.
	# Each connected component uses a static coordinate when available, and
	# otherwise the smallest stable body id. No dimensions are ever changed.
	for axis in range(2):
		var edges: Array = []
		var visited: Array[bool] = []
		var order: Array[int] = []
		for i in range(bodies.size()):
			edges.append([])
			visited.append(false)
			order.append(i)
		for i in range(bodies.size()):
			var a: StateScript = bodies[i]
			for j in range(i + 1, bodies.size()):
				var b: StateScript = bodies[j]
				var offset: float = INF
				if axis == 0:
					if minf(a.bottom(), b.bottom()) - maxf(a.y, b.y) < -GEOMETRY_EPS:
						continue
					if absf(a.right() - b.x) <= GEOMETRY_EPS:
						offset = a.w
					elif absf(b.right() - a.x) <= GEOMETRY_EPS:
						offset = -b.w
				else:
					if minf(a.right(), b.right()) - maxf(a.x, b.x) < -GEOMETRY_EPS:
						continue
					if absf(a.bottom() - b.y) <= GEOMETRY_EPS:
						offset = a.h
					elif absf(b.bottom() - a.y) <= GEOMETRY_EPS:
						offset = -b.h
				if is_finite(offset):
					edges[i].append([j, offset])
					edges[j].append([i, -offset])
		order.sort_custom(func(i: int, j: int) -> bool:
			if bodies[i].fixed != bodies[j].fixed:
				return bodies[i].fixed
			return bodies[i].id < bodies[j].id)
		for root: int in order:
			if visited[root]:
				continue
			var queue: Array[int] = [root]
			visited[root] = true
			var cursor: int = 0
			while cursor < queue.size():
				var i: int = queue[cursor]
				cursor += 1
				var base: float = bodies[i].x if axis == 0 else bodies[i].y
				for edge: Array in edges[i]:
					var j: int = edge[0]
					var desired: float = base + float(edge[1])
					var current: float = bodies[j].x if axis == 0 else bodies[j].y
					if absf(current - desired) > GEOMETRY_EPS * 4.0:
						diagnostics.append("Inconsistent simultaneous boundary, axis %d: #%d / #%d; motion stopped." % [axis, bodies[i].id, bodies[j].id])
						return false
					if not visited[j]:
						if not bodies[j].fixed:
							if axis == 0:
								bodies[j].x = desired
							else:
								bodies[j].y = desired
						visited[j] = true
						queue.append(j)
	return true


func _save_positions() -> PackedFloat64Array:
	var saved := PackedFloat64Array()
	saved.resize(bodies.size() * 2)
	for i in range(bodies.size()):
		saved[2 * i] = bodies[i].x
		saved[2 * i + 1] = bodies[i].y
	return saved


func _restore_positions(saved: PackedFloat64Array) -> void:
	for i in range(bodies.size()):
		bodies[i].x = saved[2 * i]
		bodies[i].y = saved[2 * i + 1]


func _penetrates(a: StateScript, b: StateScript) -> bool:
	return (minf(a.right(), b.right()) - maxf(a.x, b.x) > GEOMETRY_EPS
		and minf(a.bottom(), b.bottom()) - maxf(a.y, b.y) > GEOMETRY_EPS)


func _validate_nonpenetration(context: String) -> bool:
	for i in range(bodies.size()):
		for j in range(i + 1, bodies.size()):
			if _penetrates(bodies[i], bodies[j]):
				diagnostics.append("Penetration at %s: #%d (%.12f, %.12f), #%d (%.12f, %.12f)." % [context, bodies[i].id, bodies[i].x, bodies[i].y, bodies[j].id, bodies[j].x, bodies[j].y])
				return false
	return true


func _stop_motion() -> void:
	for body in bodies:
		body.vx = 0.0
		body.vy = 0.0
