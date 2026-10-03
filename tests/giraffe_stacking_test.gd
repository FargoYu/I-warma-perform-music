extends SceneTree
## Stacked giraffes must land, slide independently, and retain side blocking.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _tick(count := 1) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func _new_level() -> Node2D:
	var level := Node2D.new()
	root.add_child(level)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(128, 136)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(256, 16)
	shape.shape = rectangle
	floor_body.add_child(shape)
	level.add_child(floor_body)
	return level

func _giraffe(at: Vector2) -> CharacterBody2D:
	var body := load("res://objects/giraffe.tscn").instantiate() as CharacterBody2D
	body.position = at
	return body

func _stack(reverse_order: bool) -> void:
	var level := _new_level()
	var lower := _giraffe(Vector2(128, 120))
	var middle := _giraffe(Vector2(128, 72))
	var upper := _giraffe(Vector2(128, 40))
	for body in [upper, middle, lower] if reverse_order else [lower, middle, upper]:
		level.add_child(body)
	await _tick(160)
	_check(absf(lower.position.y - 120.0) < 0.02, "Bottom giraffe must remain on the floor")
	_check(absf(middle.position.y - 104.0) < 0.02, "Falling giraffe must land flush on another giraffe")
	_check(absf(upper.position.y - 88.0) < 0.02, "Three giraffes must form a stable stack in either tree order")
	for body in [lower, middle, upper]:
		_check(absf(body.position.x - 128.0) < 0.02 and is_zero_approx(body.velocity.y),
			"A stationary giraffe stack must not drift or retain downward velocity")
	level.queue_free()
	await _tick(2)

func _slide(direction: int, move_support: bool, reverse_order: bool) -> void:
	var level := _new_level()
	var lower := _giraffe(Vector2(128, 120))
	var upper := _giraffe(Vector2(128, 104))
	for body in [upper, lower] if reverse_order else [lower, upper]:
		level.add_child(body)
	await _tick(4)
	var mover := lower if move_support else upper
	var stationary := upper if move_support else lower
	mover.run_in_direction(direction)
	await _tick(16)
	_check((mover.position.x - 128.0) * direction > 2.0,
		"Either member of a giraffe stack must be able to slide horizontally")
	_check(absf(stationary.position.x - 128.0) < 0.02 and is_zero_approx(stationary.velocity.x),
		"A sliding giraffe must not drag or push its support/rider horizontally")
	_check(absf(upper.position.y - (lower.position.y - 16.0)) < 0.02,
		"Partially overlapping giraffes must retain vertical support while sliding")
	await _tick(50)
	_check(upper.position.y > 104.5, "A giraffe must fall naturally after sliding off its support")
	level.queue_free()
	await _tick(2)

func _side_blocking() -> void:
	var level := _new_level()
	var lower := _giraffe(Vector2(128, 120))
	var upper := _giraffe(Vector2(128, 104))
	var side := _giraffe(Vector2(136, 120))
	for body in [lower, upper, side]:
		level.add_child(body)
	await _tick(4)
	lower.run_in_direction(1)
	await _tick(16)
	_check(absf(lower.position.x - 128.0) < 0.02,
		"A giraffe with a rider must still be blocked by another giraffe's side")
	_check(absf(side.position.x - 136.0) < 0.02, "Side contact must not push the other giraffe")
	level.queue_free()
	await _tick(2)

func _run() -> void:
	for reverse_order in [false, true]:
		await _stack(reverse_order)
		for direction in [-1, 1]:
			for move_support in [false, true]:
				await _slide(direction, move_support, reverse_order)
	await _side_blocking()
	print("Giraffe stacking checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
