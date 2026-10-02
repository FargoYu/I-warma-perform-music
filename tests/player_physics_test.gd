extends SceneTree
## Run: godot --headless --path . --script res://tests/player_physics_test.gd

const STEP := 1.0 / 120.0
var player: CharacterBody2D
var level: Node2D
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _tick() -> void:
	await physics_frame
	player._physics_process(STEP)

func _settle(at: Vector2) -> void:
	Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_right")
	player.global_position = at
	player.velocity = Vector2.ZERO
	for _i in range(12):
		await _tick()
	_check(player._has_ground_support(), "Player must have ground support")

func _jump_height(hold_frames: int, repress := false) -> float:
	await _settle(Vector2(40, 120))
	var start_y := player.position.y
	var top_y := start_y
	Input.action_press("jump")
	for frame in range(240):
		if frame == hold_frames:
			Input.action_release("jump")
		if repress and frame == 24:
			Input.action_press("jump")
		if repress and frame == 40:
			Input.action_release("jump")
		await _tick()
		top_y = minf(top_y, player.position.y)
		if frame > 2 and player._has_ground_support() and player.velocity.y >= 0.0:
			break
	Input.action_release("jump")
	return start_y - top_y

func _run() -> void:
	level = load("res://rooms/main.tscn").instantiate()
	# This suite isolates terrain and jumps; giraffe contacts have their own suite.
	level.get_node("Giraffe").free()
	root.add_child(level)
	player = level.get_node("Player")
	player.set_physics_process(false)
	await physics_frame

	var points: PackedVector2Array = player.get_node("CollisionPolygon2D").polygon
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	_check(bounds.size == Vector2(6, 16), "Player collision must be 6x16")
	_check(level.get_node("Blocks").tile_set.tile_size == Vector2i(16, 16), "Grid must be 16x16")
	_check(is_equal_approx(player.safe_margin, 0.001), "Player safe_margin must remain 0.001")

	# Cross the one-tile-high corridor.
	await _settle(Vector2(107, 120))
	Input.action_press("move_right")
	for _i in range(250):
		await _tick()
		_check(player._has_ground_support(), "Lost floor support while crossing tile seams")
	Input.action_release("move_right")
	_check(player.position.x > 210, "Could not cross the 16px corridor")

	# Cross the corridor in the other direction.
	await _settle(Vector2(225, 120))
	Input.action_press("move_left")
	for _i in range(260):
		await _tick()
	Input.action_release("move_left")
	_check(player.position.x < 120, "Could not cross corridor from the right")

	var short_height := await _jump_height(2)
	var medium_height := await _jump_height(16)
	var full_height := await _jump_height(240)
	var repress_height := await _jump_height(2, true)
	_check(short_height > 0.0 and medium_height > short_height and full_height > medium_height,
		"Holding jump longer must produce a higher jump")
	_check(absf(repress_height - short_height) < 0.2, "Airborne re-press caused a second jump")

	print("Jump heights (px): short=%.3f medium=%.3f full=%.3f" % [short_height, medium_height, full_height])
	print("Player physics checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
