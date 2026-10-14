extends SceneTree
## Timed reactions use the real world controller and rectangle solver.

const WorldScript = preload("res://scripts/rect_world.gd")
const BodyScript = preload("res://objects/rect_body.gd")
const GiraffeScene = preload("res://objects/giraffe.tscn")
const EPS: float = 0.000001

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_stops_after_duration()
	await _test_repeat_hit_refreshes_duration()
	await _test_pause_preserves_duration()
	await _test_blocking_consumes_duration()
	await _test_zero_duration()
	print("GIRAFFE MOTION: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= EPS, "%s; expected %.8f, got %.8f" % [message, expected, actual])


func _fixture(wall: bool = false):
	var world = WorldScript.new()
	var giraffe = GiraffeScene.instantiate()
	giraffe.position = Vector2(100.0, 0.0)
	world.add_child(giraffe)
	var floor_body = BodyScript.new()
	floor_body.position = Vector2(0.0, 16.0)
	floor_body.body_width = 500.0
	world.add_child(floor_body)
	if wall:
		var blocker = BodyScript.new()
		blocker.name = "Blocker"
		blocker.position = Vector2(108.0, 0.0)
		world.add_child(blocker)
	root.add_child(world)
	world.set_physics_process(false)
	_check(world.setup_errors.is_empty(), "fixture is a legal layout")
	return world


func _dispose(world) -> void:
	_check(world.solver.diagnostics.is_empty(), "timed movement preserves solver invariants")
	world.queue_free()
	await process_frame


func _test_stops_after_duration() -> void:
	for direction in [-1, 1]:
		var world = _fixture()
		var giraffe = world.actors[0]
		world._physics_process(0.25)
		_near(giraffe.state.x, 100.0, "an unhit giraffe stays idle")
		giraffe.hit_by_bullet(direction)
		world._physics_process(0.13)
		_check(giraffe.move_direction == direction, "reaction stays active before expiry")
		_near(giraffe.state.x, 100.0 + direction * giraffe.move_speed * 0.13, "hit starts movement in the shot direction")
		world._physics_process(0.29)
		world._physics_process(0.41)
		var stopped_x: float = giraffe.state.x
		_near(stopped_x, 100.0 + direction * giraffe.move_speed * giraffe.hit_move_duration, "a partial final tick cannot exceed the configured duration")
		_check(giraffe.move_direction == 0, "reaction becomes idle when duration expires")
		_check(giraffe.direction == direction, "stopping preserves sprite facing")
		world._physics_process(1.0)
		_near(giraffe.state.x, stopped_x, "expired reaction stays stopped")
		_near(giraffe.state.vx, 0.0, "expired reaction has no horizontal velocity")
		await _dispose(world)


func _test_repeat_hit_refreshes_duration() -> void:
	var world = _fixture()
	var giraffe = world.actors[0]
	giraffe.hit_by_bullet(1)
	world._physics_process(0.6)
	var turn_x: float = giraffe.state.x
	giraffe.hit_by_bullet(-1)
	world._physics_process(0.4)
	_check(giraffe.move_direction == -1, "another hit reverses direction and refreshes the countdown")
	world._physics_process(0.4)
	_near(giraffe.state.x, turn_x - giraffe.move_speed * giraffe.hit_move_duration, "repeat hit receives one full new movement duration")
	_check(giraffe.move_direction == 0, "refreshed reaction also stops")
	giraffe.hit_by_bullet(1)
	world._physics_process(0.1)
	_check(giraffe.move_direction == 1, "a stopped giraffe can react to a later hit")
	await _dispose(world)


func _test_pause_preserves_duration() -> void:
	var world = _fixture()
	var giraffe = world.actors[0]
	giraffe.hit_by_bullet(1)
	world._physics_process(0.3)
	var paused_x: float = giraffe.state.x
	world.frozen = true
	giraffe._process(3.0)
	world._physics_process(3.0)
	_near(giraffe.state.x, paused_x, "pausing freezes timed movement")
	_check(giraffe.move_direction == 1, "render frames and paused ticks do not expire the reaction")
	world.frozen = false
	world._physics_process(0.6)
	_near(giraffe.state.x, 100.0 + giraffe.move_speed * giraffe.hit_move_duration, "resuming uses only the remaining gameplay time")
	_check(giraffe.move_direction == 0, "resumed countdown eventually stops")
	await _dispose(world)


func _test_blocking_consumes_duration() -> void:
	var world = _fixture(true)
	var giraffe = world.actors[0]
	giraffe.hit_by_bullet(1)
	world._physics_process(giraffe.hit_move_duration + 0.1)
	_near(giraffe.state.x, 100.0, "a wall still blocks the timed reaction")
	_check(giraffe.move_direction == 0, "a blocked reaction still expires")
	world.solver.remove_body(world.get_node("Blocker").state)
	world._physics_process(0.2)
	_near(giraffe.state.x, 100.0, "removing the wall cannot revive an expired reaction")
	await _dispose(world)


func _test_zero_duration() -> void:
	var world = _fixture()
	var giraffe = world.actors[0]
	giraffe.hit_move_duration = 0.0
	giraffe.hit_by_bullet(1)
	world._physics_process(0.1)
	_near(giraffe.state.x, 100.0, "zero duration disables reaction travel")
	_check(giraffe.move_direction == 0, "zero duration leaves the giraffe idle")
	await _dispose(world)
