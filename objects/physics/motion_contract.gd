extends RefCounted
## Data boundaries only: no input, velocity integration, sensors or controller code.
const MOTION_SKIN := 0.0
const QUERY_MARGIN := 0.0
const SOLID_MASK := 1 | 2 | 4
const ROLES := ["terrain", "warma", "giraffe", "elevator"]

static func intent(dx: float = 0.0, dy: float = 0.0, detach: bool = false) -> Dictionary:
	return {"dx": dx, "dy": dy, "detach": detach}

static func valid_intent(value: Dictionary) -> bool:
	if not value.has_all(["dx", "dy", "detach"]):
		return false
	return typeof(value.dx) in [TYPE_FLOAT, TYPE_INT] and typeof(value.dy) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value.dx)) and is_finite(float(value.dy)) and value.detach is bool

static func illegal_overlap(a: String, b: String) -> bool:
	# Overlapping static terrain is a union, not an invalid actor spawn.
	# Production rod extension is terrain-permeable, never actor-permeable.
	if (a == "elevator" and b == "terrain") or (b == "elevator" and a == "terrain"):
		return false
	return a != "terrain" or b != "terrain"

static func can_lift(source: String, target: String, axis: int, amount: float) -> bool:
	# Contract for later intent integration. No generic platform/Elevator role.
	return source == "warma" and target == "giraffe" and axis == 1 and amount < 0.0

static func failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "details": details}

static func result(id: String, request: Dictionary, dx: float, dy: float, contacts: Array, support: Dictionary) -> Dictionary:
	return {"ok": true, "id": id, "requested": request.duplicate(), "dx": dx, "dy": dy,
		"blocked_x": dx != float(request.dx), "blocked_y": dy != float(request.dy),
		"contacts": contacts, "support": support, "detached": request.detach}
