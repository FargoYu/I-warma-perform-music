extends SceneTree
## Run: godot --headless --path . --script res://tests/precision_platforming_test.gd
## Exercises actual body motion at ledges and at the screenshot's 16px gap.

const STEP := 1.0 / 120.0
var failures: Array[String] = []
var level: Node2D
var player: CharacterBody2D

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _release() -> void:
	for action in ["jump", "move_left", "move_right"]:
		Input.action_release(action)

func _tick(count := 1, delta := STEP) -> void:
	for _i in range(count):
		await physics_frame
		player._physics_process(delta)

func _box(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)
	level.add_child(body)
	return body

func _fixture(at: Vector2) -> void:
	_release()
	level = Node2D.new()
	root.add_child(level)
	player = load("res://objects/warma.tscn").instantiate()
	player.position = at
	player.fall_limit = 1000.0
	level.add_child(player)
	player.set_physics_process(false)

func _cleanup() -> void:
	_release()
	level.queue_free()
	await physics_frame

func _ledge_contacts() -> void:
	# The centre lies outside the platform in every case, with only a small
	# part of either foot edge on it. Test falling, resting and actual takeoff.
	for x in [89.1, 90.5, 109.5, 109.9]:
		_fixture(Vector2(x, 80))
		_box(Vector2(100, 120), Vector2(16, 15.98))
		await _tick(90)
		_check(absf(player.position.y - 104.01) < 0.03,
			"Ledge x=%.2f: body must land on the platform" % x)
		_check(player._has_ground_support(), "Ledge x=%.2f: full foot must count as support" % x)
		var launch_y := player.position.y
		Input.action_press("jump")
		await _tick(5)
		_check(player.position.y < launch_y - 3.0 and player.velocity.y < 0.0,
			"Ledge x=%.2f: must be able to jump with only the foot edge supported" % x)
		await _cleanup()

	# A wall beside the foot and even a small real air gap must not grant a jump.
	for at in [Vector2(88.9, 104), Vector2(110.1, 104), Vector2(100, 103.9), Vector2(89, 113)]:
		_fixture(at)
		_box(Vector2(100, 120), Vector2(16, 15.98))
		await physics_frame
		_check(not player._has_ground_support(), "Unsupported %s: must not report a floor" % at)
		Input.action_press("jump")
		await _tick(2)
		_check(player.velocity.y >= 0.0, "Unsupported %s: must not jump" % at)
		await _cleanup()

func _head_contacts() -> void:
	for offset in [-5.8, 6.8, -6.1, 7.1]:
		_fixture(Vector2(100, 120))
		var giraffe: CharacterBody2D = load("res://objects/giraffe.tscn").instantiate()
		giraffe.position = Vector2(100 + offset, 104)
		level.add_child(giraffe)
		giraffe.set_physics_process(false)
		await physics_frame
		var should_lift: bool = offset > -6.0 and offset < 7.0
		var lifted: bool = player._lift_giraffes_above(-150.0, STEP)
		_check(lifted == should_lift, "Head offset %.2f: only the real head width may lift" % offset)
		_check((giraffe.velocity.y < -100.0) == should_lift, "Head offset %.2f: impulse must match contact" % offset)
		_check(is_zero_approx(giraffe.velocity.x), "Head lift must stay vertical")
		await _cleanup()

	_fixture(Vector2(100, 120))
	var distant_giraffe: CharacterBody2D = load("res://objects/giraffe.tscn").instantiate()
	distant_giraffe.position = Vector2(100, 102.2)
	level.add_child(distant_giraffe)
	distant_giraffe.set_physics_process(false)
	await physics_frame
	_check(not player._lift_giraffes_above(-150.0, STEP), "Head must not lift before this frame can reach the giraffe")
	await _cleanup()

func _giraffe_foot_edges() -> void:
	for x in [93.1, 105.9]:
		_fixture(Vector2(x, 104))
		_box(Vector2(128, 136), Vector2(256, 16))
		var giraffe: CharacterBody2D = load("res://objects/giraffe.tscn").instantiate()
		giraffe.position = Vector2(100, 120)
		level.add_child(giraffe)
		giraffe.set_physics_process(false)
		await _tick(12)
		_check(player._has_ground_support(), "Giraffe edge x=%.2f: foot must stay supported" % x)
		_check(absf(player.position.y - 104.0) < 0.03, "Giraffe edge: must stay on the top")
		Input.action_press("jump")
		await _tick(5)
		_check(player.position.y < 100.0, "Giraffe edge: must be able to jump away")
		_check(giraffe.velocity == Vector2.ZERO, "Jumping off a giraffe edge must not lift or push it")
		await _cleanup()

func _make_gap(kind: String, ceiling_offset := 0.0) -> void:
	if kind == "tile":
		var tiles: TileMapLayer = load("res://objects/blocks.tscn").instantiate()
		tiles.set_cell(Vector2i(8, 5), 0, Vector2i.ZERO)
		tiles.set_cell(Vector2i(8, 7), 0, Vector2i.ZERO)
		level.add_child(tiles)
		tiles.update_internals()
	else:
		for at in [Vector2(136, 88 + ceiling_offset), Vector2(136, 120)]:
			var block: StaticBody2D = load("res://objects/block.tscn").instantiate()
			block.position = at
			level.add_child(block)

func _gap_entry(kind: String, direction: int, launch_offset: float, delta: float) -> void:
	var label := "%s direction=%d launch=%.2f dt=%.5f" % [kind, direction, launch_offset, delta]
	_fixture(Vector2(120 if direction > 0 else 154, 120 + launch_offset))
	_box(Vector2(128, 136 + launch_offset), Vector2(256, 16))
	_make_gap(kind)
	await _tick(12, delta)
	Input.action_press("move_right" if direction > 0 else "move_left")
	await _tick(25, delta)
	var wall_x := 125.0 if direction > 0 else 146.0
	_check(absf(player.position.x - wall_x) < 0.03, label + ": solid block side must stop movement")
	Input.action_press("jump")
	var entered := false
	var maximum_alignment := 0.0
	for frame in range(90):
		if frame == 35:
			Input.action_release("jump")
		var previous_y := player.position.y
		await _tick(1, delta)
		if player.position.x > 125.03 and player.position.x < 145.97:
			if not entered:
				maximum_alignment = absf(previous_y - 104.0)
			entered = true
			_check(absf(player.position.y - 104.0) < 0.03, label + ": body must fit between both blocks")
			_check(player._has_ground_support(), label + ": lower block must support the complete foot")
	_check(entered, label + ": jump must enter the one-tile gap")
	_check(maximum_alignment <= 0.8, label + ": correction must stay below one logical pixel (%.3f)" % maximum_alignment)
	_check(player.position.x > 149.0 if direction > 0 else player.position.x < 122.0,
		label + ": must continue through the gap")
	await _cleanup()

func _undersized_gap() -> void:
	for direction in [1, -1]:
		_fixture(Vector2(120 if direction > 0 else 154, 120))
		_box(Vector2(128, 136), Vector2(256, 16))
		_make_gap("block", 0.2)
		await _tick(12)
		Input.action_press("move_right" if direction > 0 else "move_left")
		await _tick(25)
		Input.action_press("jump")
		await _tick(120)
		_check(absf(player.position.x - (125.0 if direction > 0 else 146.0)) < 0.03,
			"Gap under 16px must still block direction %d" % direction)
		await _cleanup()

func _occupied_gap() -> void:
	for direction in [1, -1]:
		_fixture(Vector2(120 if direction > 0 else 154, 120))
		_box(Vector2(128, 136), Vector2(256, 16))
		_make_gap("tile")
		var giraffe: CharacterBody2D = load("res://objects/giraffe.tscn").instantiate()
		giraffe.position = Vector2(136, 104)
		level.add_child(giraffe)
		giraffe.set_physics_process(false)
		await _tick(12)
		Input.action_press("move_right" if direction > 0 else "move_left")
		await _tick(25)
		Input.action_press("jump")
		await _tick(100)
		_check(absf(player.position.x - (129.0 if direction > 0 else 142.0)) < 0.03,
			"Occupied gap: alignment must not pass through the giraffe")
		_check(giraffe.position == Vector2(136, 104) and giraffe.velocity == Vector2.ZERO,
			"Occupied gap: side contact must not move or lift the giraffe")
		await _cleanup()

func _screenshot_room() -> void:
	_release()
	level = load("res://rooms/Standard/room2.tscn").instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector2(120, 120)
	await _tick(12)
	Input.action_press("move_right")
	await _tick(25)
	Input.action_press("jump")
	await _tick(45)
	Input.action_release("jump")
	await _tick(45)
	_check(player.position.x > 146.0, "Screenshot room: must jump through the real gap (%s)" % player.position)
	await _cleanup()

func _run() -> void:
	root.get_node("GameState").reset_speed()
	await _ledge_contacts()
	await _head_contacts()
	await _giraffe_foot_edges()
	for kind in ["block", "tile"]:
		for direction in [1, -1]:
			for offset in [0.0, 0.2, 0.4, 0.6, 0.8]:
				await _gap_entry(kind, direction, offset, STEP)
			await _gap_entry(kind, direction, 0.0, 1.0 / 60.0)
	await _undersized_gap()
	await _occupied_gap()
	await _screenshot_room()
	print("Precision platforming checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
