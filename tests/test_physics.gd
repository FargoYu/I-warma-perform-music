extends SceneTree
## Independent acceptance tests for the documented rectangle movement rules.
## Run: Godot --headless --path . --script res://tests/test_physics.gd

const State = preload("res://physics/rect_state.gd")
const Solver = preload("res://physics/rect_solver.gd")
const EPS: float = 0.000001

var failures: Array[String] = []
var checks: int = 0
var cases: int = 0
var current_case: String = ""
var next_id: int = 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite: Array[Callable] = [
		_test_exact_entrance, _test_short_entrance, _test_tall_entrance,
		_test_offset_support, _test_dynamic_entrances, _test_no_horizontal_push,
		_test_head_on, _test_same_direction, _test_no_carry,
		_test_stack_lift, _test_roof_cap, _test_roof_collision_consumes_jump,
		_test_no_downward_push, _test_lower_separates, _test_upper_jumps_away,
		_test_multiple_supports, _test_simultaneous_handoff,
		_test_corner_without_support, _test_support_exit, _test_high_speed,
		_test_large_coordinates, _test_order_independence, _test_long_simulation,
		_test_initial_overlap, _test_remove_body, _test_event_budget,
	]
	for test in suite:
		current_case = str(test.get_method()).trim_prefix("_test_")
		var before: int = failures.size()
		test.call()
		cases += 1
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", current_case])
	print("PHYSICS: %d cases, %d checks, %d failures" % [cases, checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current_case, message])


func _near(actual: float, expected: float, message: String, tolerance: float = EPS) -> void:
	_check(absf(actual - expected) <= tolerance, "%s; expected %.10f, got %.10f" % [message, expected, actual])


func _body(x: float, y: float, w: float = 5.0, h: float = 16.0, fixed: bool = false, intent: float = 0.0, vy: float = 0.0):
	var body = State.new()
	body.id = next_id
	next_id += 1
	body.x = x
	body.y = y
	body.w = w
	body.h = h
	body.fixed = fixed
	body.intent_x = intent
	body.vy = vy
	body.kind = "block" if fixed else "warma"
	return body


func _world(items: Array):
	var solver = Solver.new()
	for body in items:
		_check(solver.add_body(body), "legal fixture rejected: body %d" % body.id)
	return solver


func _overlap(a, b, tolerance: float = EPS) -> bool:
	var ox: float = minf(a.x + a.w, b.x + b.w) - maxf(a.x, b.x)
	var oy: float = minf(a.y + a.h, b.y + b.h) - maxf(a.y, b.y)
	return ox > tolerance and oy > tolerance


func _safe(solver, message: String = "no interior overlap") -> void:
	for i in range(solver.bodies.size()):
		for j in range(i + 1, solver.bodies.size()):
			_check(not _overlap(solver.bodies[i], solver.bodies[j]), "%s: %d / %d" % [message, solver.bodies[i].id, solver.bodies[j].id])


func _clean(solver) -> void:
	_check(solver.diagnostics.is_empty(), "unexpected diagnostic: %s" % str(solver.diagnostics))
	_safe(solver)


func _entrance(gap: float, floor_x: float = 16.0, offset: float = 0.0, roof_fixed: bool = true, floor_fixed: bool = true) -> Array:
	var actor = _body(offset + 11.0, offset + 12.0, 5.0, 16.0, false, 90.0, 180.0)
	var roof = _body(offset + 16.0, offset, 16.0, 16.0, roof_fixed)
	var floor_body = _body(offset + floor_x, offset + 16.0 + gap, 16.0, 16.0, floor_fixed)
	return [_world([actor, roof, floor_body]), actor, roof, floor_body]


func _test_exact_entrance() -> void:
	var fixture: Array = _entrance(16.0)
	fixture[0].step(1.0 / 15.0)
	_near(fixture[1].x, 15.0, "horizontal input resumes within the same step")
	_near(fixture[1].y, 16.0, "full 16 px actor enters exact-height opening")
	_near(fixture[1].vy, 0.0, "new floor catches vertical motion")
	_check(fixture[1].grounded, "new floor is reported as support")
	_clean(fixture[0])


func _test_short_entrance() -> void:
	var fixture: Array = _entrance(15.0)
	fixture[0].step(1.0 / 15.0)
	_near(fixture[1].x, 11.0, "15 px opening rejects 16 px actor")
	_check(fixture[1].y > 16.0, "actor continues falling beside the short opening")
	_clean(fixture[0])


func _test_tall_entrance() -> void:
	var fixture: Array = _entrance(17.0)
	fixture[0].step(1.0 / 15.0)
	_near(fixture[1].x, 15.0, "17 px opening permits entry")
	_near(fixture[1].y, 17.0, "actor falls the extra pixel before landing")
	_clean(fixture[0])


func _test_offset_support() -> void:
	var fixture: Array = _entrance(16.0, 20.0)
	fixture[0].step(0.1)
	_near(fixture[1].x, 15.0, "offset lower block blocks the side when reached")
	_near(fixture[1].y, 30.0, "absent support does not lock Y in air")
	_check(not fixture[1].grounded, "side contact is not a floor")
	_clean(fixture[0])


func _test_dynamic_entrances() -> void:
	for fixed_pair in [[true, false], [false, true], [false, false]]:
		var fixture: Array = _entrance(16.0, 16.0, 0.0, fixed_pair[0], fixed_pair[1])
		fixture[0].step(1.0 / 15.0)
		_near(fixture[1].x, 15.0, "same entrance rule for dynamic/static boundaries")
		_near(fixture[1].y, 16.0, "same full-size geometry for every body kind")
		_clean(fixture[0])


func _test_no_horizontal_push() -> void:
	var left = _body(0.0, 0.0, 5.0, 16.0, false, 100.0)
	var right = _body(5.0, 0.0, 8.0)
	var solver = _world([left, right])
	solver.step(0.5)
	_near(left.x, 0.0, "driving body stops at stationary neighbor")
	_near(right.x, 5.0, "stationary neighbor is not pushed")
	_near(right.vx, 0.0, "contact does not create horizontal velocity")
	_clean(solver)


func _test_head_on() -> void:
	var left = _body(0.0, 0.0, 5.0, 16.0, false, 100.0)
	var right = _body(25.0, 0.0, 8.0, 16.0, false, -100.0)
	var solver = _world([left, right])
	solver.step(0.2)
	_near(left.x, 10.0, "left actor reaches relative-motion collision")
	_near(right.x, 15.0, "right actor reaches relative-motion collision")
	_near(left.vx, 0.0, "opposing input stops")
	_near(right.vx, 0.0, "opposing input stops symmetrically")
	_clean(solver)


func _test_same_direction() -> void:
	var rear = _body(0.0, 0.0, 5.0, 16.0, false, 90.0)
	var front = _body(11.0, 0.0, 8.0, 16.0, false, 30.0)
	var solver = _world([rear, front])
	solver.step(0.2)
	_near(rear.x, 12.0, "faster rear actor slows after catching the front")
	_near(front.x, 17.0, "front actor keeps its own input")
	_near(rear.vx, 30.0, "rear speed is limited to front speed")
	_clean(solver)


func _test_no_carry() -> void:
	var upper = _body(0.0, 0.0)
	var lower = _body(0.0, 16.0, 8.0, 16.0, false, 30.0)
	var solver = _world([upper, lower])
	solver.step(0.1)
	_near(upper.x, 0.0, "rider receives no platform horizontal movement")
	_near(lower.x, 3.0, "lower actor moves independently")
	_near(upper.vx, 0.0, "rider does not inherit vx")
	_clean(solver)


func _test_stack_lift() -> void:
	var top = _body(0.0, 0.0, 8.0)
	var middle = _body(0.0, 16.0, 8.0)
	var bottom = _body(0.0, 32.0, 8.0, 16.0, false, 0.0, -120.0)
	var solver = _world([top, middle, bottom])
	solver.step(0.05)
	for body in [top, middle, bottom]:
		_near(body.vy, -120.0, "upward lift propagates through all layers")
	_near(top.y, -6.0, "top layer is lifted")
	_near(bottom.y, 26.0, "bottom layer completes jump movement")
	_clean(solver)


func _test_roof_cap() -> void:
	var roof = _body(-4.0, -16.0, 32.0, 16.0, true)
	var top = _body(0.0, 0.0, 8.0)
	var middle = _body(0.0, 16.0, 8.0)
	var bottom = _body(0.0, 32.0, 8.0, 16.0, false, 0.0, -120.0)
	var solver = _world([top, bottom, roof, middle])
	solver.step(0.1)
	for body in [top, middle, bottom]:
		_near(body.vy, 0.0, "static roof caps entire connected stack")
	_near(bottom.y, 32.0, "blocked stack remains in place")
	_clean(solver)


func _test_roof_collision_consumes_jump() -> void:
	var actor = _body(0.0, 20.0, 5.0, 16.0, false, 0.0, -120.0)
	var roof = _body(0.0, 0.0, 16.0, 16.0, true)
	var solver = _world([actor, roof])
	solver.step(0.1)
	_near(actor.y, 16.0, "upward CCD stops at ceiling")
	_near(actor.vy, 0.0, "ceiling consumes upward velocity")
	actor.intent_x = 120.0
	solver.step(0.2)
	_near(actor.y, 16.0, "old jump velocity is not restored after leaving roof")
	_near(actor.x, 24.0, "actor can move out from under roof")
	_clean(solver)


func _test_no_downward_push() -> void:
	var upper = _body(0.0, 0.0, 5.0, 16.0, false, 0.0, 200.0)
	var lower = _body(0.0, 16.0, 8.0)
	var solver = _world([upper, lower])
	solver.step(0.1)
	_near(upper.vy, 0.0, "falling upper actor is stopped")
	_near(lower.y, 16.0, "upper actor does not press lower actor downward")
	_clean(solver)


func _test_lower_separates() -> void:
	var upper = _body(0.0, 0.0, 5.0, 16.0, false, 0.0, 20.0)
	var lower = _body(0.0, 16.0, 8.0, 16.0, false, 0.0, 100.0)
	var solver = _world([upper, lower])
	solver.step(0.1)
	_near(upper.y, 2.0, "descending support does not drag upper body")
	_near(lower.y, 26.0, "lower body freely separates")
	_check(not upper.grounded, "opened contact is not retained as grounded")
	_clean(solver)


func _test_upper_jumps_away() -> void:
	var upper = _body(0.0, 0.0, 5.0, 16.0, false, 0.0, -100.0)
	var lower = _body(0.0, 16.0, 8.0)
	var solver = _world([upper, lower])
	solver.step(0.1)
	_near(upper.y, -10.0, "upper body jumps off its support")
	_near(lower.y, 16.0, "jumping actor does not pull lower body")
	_check(not upper.grounded, "jumping actor is no longer grounded")
	_clean(solver)


func _test_multiple_supports() -> void:
	var upper = _body(0.0, 0.0, 18.0)
	var left = _body(0.0, 16.0, 8.0)
	var right = _body(8.0, 16.0, 8.0, 16.0, false, 0.0, -60.0)
	var solver = _world([upper, left, right])
	solver.step(0.1)
	_near(upper.y, -6.0, "strongest upward support wins")
	_near(left.y, 16.0, "other support is not pulled upward")
	_near(right.y, 10.0, "moving support lifts upper body")
	_clean(solver)


func _test_simultaneous_handoff() -> void:
	var fixture: Array = _entrance(16.0)
	var old_support = _body(8.0, 28.0, 8.0, 16.0, false, -225.0, 180.0)
	_check(fixture[0].add_body(old_support), "old support fixture accepted")
	fixture[0].step(1.0 / 15.0)
	_near(fixture[1].x, 15.0, "old support exit and wall exit preserve right input")
	_near(fixture[1].y, 16.0, "new floor takes over at the same instant")
	_near(old_support.x, -7.0, "old support continues independently")
	old_support.vy = -100.0
	fixture[0].step(0.01)
	_near(fixture[1].y, 16.0, "departed support cannot transmit a later jump")
	_clean(fixture[0])


func _test_corner_without_support() -> void:
	var actor = _body(11.0, 16.0, 5.0, 16.0, false, 0.0, 60.0)
	var floor_body = _body(16.0, 32.0, 16.0, 16.0, true)
	var solver = _world([actor, floor_body])
	solver.step(0.1)
	_near(actor.y, 22.0, "corner with no inward horizontal motion is not support")
	_check(not actor.grounded, "zero-width contact does not grant jump permission")
	_clean(solver)


func _test_support_exit() -> void:
	var actor = _body(0.0, 0.0)
	var support = _body(0.0, 16.0, 8.0, 16.0, false, 120.0)
	var solver = _world([actor, support])
	solver.step(0.1)
	_check(not actor.grounded, "support edge is removed when X projection ends")
	actor.vy += 10.0
	solver.step(0.1)
	_near(actor.y, 1.0, "unsupported actor responds to next gravity update")
	_clean(solver)


func _test_high_speed() -> void:
	var actor = _body(0.0, 0.0, 5.0, 16.0, false, 1000000.0)
	var wall = _body(100.0, -100.0, 16.0, 216.0, true)
	var solver = _world([actor, wall])
	solver.step(1.0 / 60.0)
	_near(actor.x, 95.0, "very high speed cannot tunnel through side wall")
	_clean(solver)
	var falling = _body(0.0, -1000.0, 5.0, 16.0, false, 0.0, 1000000.0)
	var floor_body = _body(-100.0, 16.0, 216.0, 16.0, true)
	solver = _world([falling, floor_body])
	solver.step(1.0 / 60.0)
	_near(falling.y, 0.0, "very high speed cannot tunnel through floor")
	_clean(solver)


func _test_large_coordinates() -> void:
	var offset: float = 1000000000.0
	var fixture: Array = _entrance(16.0, 16.0, offset)
	fixture[0].step(1.0 / 15.0)
	_near(fixture[1].x - offset, 15.0, "scalar position retains precision far from origin", 0.00001)
	_near(fixture[1].y - offset, 16.0, "large-coordinate entrance preserves exact height", 0.00001)
	_clean(fixture[0])


func _ordered_trial(order: Array) -> Array:
	var actor = _body(11.0, 12.0, 5.0, 16.0, false, 90.0, 180.0)
	var roof = _body(16.0, 0.0, 16.0, 16.0, true)
	var floor_body = _body(16.0, 32.0, 16.0, 16.0, true)
	var old_support = _body(8.0, 28.0, 8.0, 16.0, false, -225.0, 180.0)
	var bodies: Array = [actor, roof, floor_body, old_support]
	var solver = Solver.new()
	for index in order:
		_check(solver.add_body(bodies[index]), "reordered valid fixture accepted")
	for frame in range(8):
		solver.step(1.0 / 120.0)
	_clean(solver)
	var result: Array = []
	for body in bodies:
		result.append_array([body.x, body.y, body.vx, body.vy])
	return result


func _test_order_independence() -> void:
	var reference: Array = _ordered_trial([0, 1, 2, 3])
	for a in range(4):
		for b in range(4):
			for c in range(4):
				for d in range(4):
					if a == b or a == c or a == d or b == c or b == d or c == d:
						continue
					var result: Array = _ordered_trial([a, b, c, d])
					for i in range(result.size()):
						_near(result[i], reference[i], "all 24 insertion orders yield same state")


func _test_long_simulation() -> void:
	var floor_body = _body(-32.0, 128.0, 320.0, 16.0, true)
	var left_wall = _body(-48.0, -80.0, 16.0, 224.0, true)
	var right_wall = _body(288.0, -80.0, 16.0, 224.0, true)
	var solver = _world([floor_body, left_wall, right_wall])
	var actors: Array = []
	for i in range(10):
		var actor = _body(float(i % 5) * 32.0, float(i / 5) * 16.0, 8.0)
		actors.append(actor)
		_check(solver.add_body(actor), "stress fixture accepted")
	var rng := RandomNumberGenerator.new()
	rng.seed = 926031
	for frame in range(1800):
		for actor in actors:
			actor.vy = minf(actor.vy + 360.0 / 120.0, 800.0)
			if frame % 31 == 0:
				actor.intent_x = float(rng.randi_range(-1, 1)) * 70.0
			if frame % 71 == 0 and actor.grounded and rng.randf() < 0.6:
				actor.vy = -150.0
		solver.step(1.0 / 120.0)
		_safe(solver, "stress frame %d" % frame)
		_check(solver.diagnostics.is_empty(), "stress frame %d has diagnostics: %s" % [frame, str(solver.diagnostics)])
		if not solver.diagnostics.is_empty():
			break
	for actor in actors:
		_check(actor.y + actor.h <= 128.0 + EPS, "actor never passed through the floor")
		_check(actor.x >= -32.0 - EPS and actor.x + actor.w <= 288.0 + EPS, "actor remains inside side walls")


func _test_initial_overlap() -> void:
	var solver = Solver.new()
	var first = _body(0.0, 0.0, 16.0, 16.0, true)
	_check(solver.add_body(first), "first valid body accepted")
	_check(not solver.add_body(_body(8.0, 8.0)), "initial interior overlap rejected")
	_check(solver.bodies.size() == 1, "rejected overlapping body is not registered")
	_check(solver.add_body(_body(16.0, 0.0)), "edge touching is allowed")
	_check(solver.add_body(_body(0.0, 16.0)), "floor touching is allowed")
	_safe(solver)


func _test_remove_body() -> void:
	var actor = _body(0.0, 0.0, 5.0, 16.0, false, 90.0)
	var obstacle = _body(5.0, 0.0, 16.0, 16.0, true)
	var solver = _world([actor, obstacle])
	solver.step(0.1)
	_near(actor.x, 0.0, "registered obstacle blocks")
	solver.remove_body(obstacle)
	solver.step(0.1)
	_near(actor.x, 9.0, "removed obstacle leaves no ghost constraint")
	_clean(solver)


func _test_event_budget() -> void:
	var fixture: Array = _entrance(17.0)
	fixture[0].max_events = 1
	fixture[0].step(0.2)
	_check(not fixture[0].diagnostics.is_empty(), "event budget exhaustion reports diagnostic")
	_check(fixture[1].x < 27.0 - EPS, "unprocessed time is not blindly advanced")
	_safe(fixture[0], "budget exhaustion preserves legal state")
