extends SceneTree
## Run: godot --headless --path . --script res://tests/giraffe_physics_test.gd

var player: CharacterBody2D
var giraffe: CharacterBody2D
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _tick() -> void:
	await physics_frame

func _release_input() -> void:
	Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_right")

func _reset_bodies(player_at: Vector2, giraffe_at: Vector2, settle_frames: int = 12) -> void:
	_release_input()
	player.global_position = player_at
	player.velocity = Vector2.ZERO
	player.set("_lifting_giraffe", false)
	player.collision_mask = 1
	giraffe.global_position = giraffe_at
	giraffe.velocity = Vector2.ZERO
	giraffe.collision_mask = 1
	for _i in range(settle_frames):
		await _tick()

func _side_jump_does_not_lift(player_at: Vector2, direction_action: String, side_name: String) -> void:
	await _reset_bodies(player_at, Vector2(47, 120))
	var giraffe_start_y := giraffe.position.y
	Input.action_press(direction_action)
	Input.action_press("jump")
	var minimum_giraffe_y := giraffe.position.y
	var minimum_player_y := player.position.y
	var furthest_player_x := player.position.x
	for frame in range(150):
		if frame == 12:
			# Keep the simultaneous side+jump input long enough to exercise the
			# bug, then stop pressing into the giraffe so the landing is local.
			Input.action_release(direction_action)
			Input.action_release("jump")
		await _tick()
		minimum_giraffe_y = minf(minimum_giraffe_y, giraffe.position.y)
		minimum_player_y = minf(minimum_player_y, player.position.y)
		if direction_action == "move_right":
			furthest_player_x = maxf(furthest_player_x, player.position.x)
		else:
			furthest_player_x = minf(furthest_player_x, player.position.x)
	_release_input()
	for _i in range(12):
		await _tick()
	_check(minimum_giraffe_y >= giraffe_start_y - 0.1,
		"%s side jump incorrectly lifted the giraffe" % side_name)
	_check(minimum_player_y < player_at.y - 4.0,
		"%s side contact must not prevent Warma from jumping" % side_name)
	_check(absf(furthest_player_x - player_at.x) < 0.1,
		"%s side jump entered the giraffe while still side-contacting" % side_name)
	_check(player._has_ground_support(),
		"%s side jump left Warma without foot support" % side_name)
	_check(player.get_node("GroundProbe").is_colliding(),
		"%s side jump left a gap under Warma" % side_name)
	_check(absf(player.position.y - 120.0) < 0.1,
		"%s side jump stopped above the floor" % side_name)

func _run() -> void:
	var level: Node2D = load("res://rooms/main.tscn").instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	giraffe = level.get_node("Giraffe")
	await physics_frame

	_check(giraffe is CharacterBody2D, "Giraffe must use CharacterBody2D collision movement")
	_check(giraffe.has_method("apply_external_impulse"),
		"Giraffe must expose an external impulse entry point")
	var giraffe_shape := giraffe.get_node("CollisionShape2D").shape as RectangleShape2D
	_check(giraffe_shape != null and giraffe_shape.size == Vector2(8, 16),
		"Giraffe must use one complete 8x16 body shape")

	# Warma cannot pass through the giraffe from the left, and ordinary contact
	# does not move the giraffe horizontally.
	await _reset_bodies(Vector2(31, 120), Vector2(47, 120))
	var left_giraffe_x := giraffe.position.x
	Input.action_press("move_right")
	for _i in range(60):
		await _tick()
	_release_input()
	_check(player.position.x > 36.0, "Warma did not move toward the giraffe from the left")
	_check(player.position.x < left_giraffe_x - 6.5, "Warma passed through the giraffe from the left")
	_check(is_zero_approx(player.velocity.x), "Warma kept horizontal velocity after left contact")
	_check(absf(giraffe.position.x - left_giraffe_x) < 0.1,
		"Left-side Warma contact pushed the giraffe horizontally")
	_check(is_zero_approx(giraffe.velocity.x), "Giraffe gained horizontal velocity from Warma contact")

	# The same rule must hold from the right side.
	await _reset_bodies(Vector2(63, 120), Vector2(47, 120))
	var right_giraffe_x := giraffe.position.x
	Input.action_press("move_left")
	for _i in range(60):
		await _tick()
	_release_input()
	_check(player.position.x < 58.0, "Warma did not move toward the giraffe from the right")
	_check(player.position.x >= right_giraffe_x + 6.0 - 0.01, "Warma passed through the giraffe from the right")
	_check(is_zero_approx(player.velocity.x), "Warma kept horizontal velocity after right contact")
	_check(absf(giraffe.position.x - right_giraffe_x) < 0.1,
		"Right-side Warma contact pushed the giraffe horizontally")
	_check(is_zero_approx(giraffe.velocity.x), "Giraffe gained horizontal velocity from right contact")

	# A falling giraffe must land on Warma's complete body instead of passing
	# through the player.
	await _reset_bodies(Vector2(47, 120), Vector2(47, 80), 2)
	for _i in range(70):
		await _tick()
	_check(absf(player.position.y - 120.0) < 0.5, "Falling giraffe moved Warma through the floor")
	_check(giraffe.position.y <= player.position.y - 15.5,
		"Giraffe penetrated Warma from above")
	_check(absf(giraffe.position.y - (player.position.y - 16.0)) < 0.75,
		"Giraffe did not settle on Warma's top")

	# Warma can stand on the giraffe and jump away without lifting it.
	await _reset_bodies(Vector2(47, 104), Vector2(47, 120))

	_check(player._has_ground_support(), "Warma could not stand on the giraffe")
	_check(absf(player.position.y - (giraffe.position.y - 16.0)) < 0.1,
		"Warma had a gap above the giraffe")
	var giraffe_floor_y := giraffe.position.y
	Input.action_press("jump")
	for _i in range(20):
		await _tick()
	_release_input()
	_check(player.position.y < 100.0, "Warma could not jump off the giraffe")
	_check(giraffe.position.y >= giraffe_floor_y - 0.25,
		"Jumping off the giraffe lifted it unexpectedly")

	# Warma can move sideways from below without dragging the giraffe.
	await _reset_bodies(Vector2(47, 120), Vector2(47, 104))
	_check(player._has_giraffe_above(),
		"Top contact was not recognized as a horizontal pass-through support")
	var under_giraffe_x := giraffe.position.x
	var under_player_x := player.position.x
	Input.action_press("move_right")
	for _i in range(30):
		await _tick()
	_release_input()
	_check(player.position.x > under_player_x + 10.0,
		"Warma could not move out from below the giraffe")
	_check(absf(giraffe.position.x - under_giraffe_x) < 0.1,
		"Horizontal movement below the giraffe moved it sideways")

	# Jumping into the giraffe from below transfers an explicit vertical impulse
	# while the full body collision keeps both bodies in contact.
	await _reset_bodies(Vector2(47, 120), Vector2(47, 104))
	var player_start_y := player.position.y
	var giraffe_start_y := giraffe.position.y
	Input.action_press("jump")
	for _i in range(20):
		await _tick()
	_release_input()
	_check(player.position.y < player_start_y - 4.0, "Warma could not jump from below")
	_check(giraffe.position.y < giraffe_start_y - 4.0,
		"Jumping from below did not lift the giraffe")
	_check(absf((giraffe.position.y - player.position.y) + 16.0) < 1.0,
		"Warma and giraffe separated during the upward collision")

	# A full-height jump must keep the lifted giraffe synchronized through the
	# apex. If the first gravity step is integrated twice, collision recovery
	# pushes the giraffe upward by roughly one pixel at this point.
	await _reset_bodies(Vector2(47, 120), Vector2(47, 104))
	Input.action_press("jump")
	var maximum_lift_separation_error := 0.0
	var lift_frames := 0
	for _i in range(80):
		await _tick()
		if player.get("_lifting_giraffe"):
			lift_frames += 1
			maximum_lift_separation_error = maxf(
				maximum_lift_separation_error,
				absf((giraffe.position.y - player.position.y) + 16.0))
	_release_input()
	_check(lift_frames > 40, "Full jump did not keep the giraffe lifted through the apex")
	_check(maximum_lift_separation_error < 0.1,
		"Giraffe moved upward at the full-jump apex")

	# A Warma landing beside the giraffe must reach the floor, even when its
	# falling body is exactly flush with the giraffe's side.
	await _reset_bodies(Vector2(53, 80), Vector2(47, 120), 2)
	for _i in range(100):
		await _tick()
	_release_input()
	_check(absf(player.position.x - 53.0) < 0.1,
		"Warma drifted horizontally while landing beside the giraffe")
	_check(absf(player.position.y - 120.0) < 0.1,
		"Warma landed above the floor beside the giraffe")
	_check(player._has_ground_support(), "Warma lost floor support beside the giraffe")

	# A directional jump that meets the giraffe must settle on its top without
	# leaving a gap at the contact surface.
	await _reset_bodies(Vector2(31, 120), Vector2(47, 120))
	Input.action_press("move_right")
	Input.action_press("jump")
	for frame in range(150):
		if frame == 30:
			_release_input()
		await _tick()
	_release_input()
	for _i in range(12):
		await _tick()
	_check(absf(player.position.y - (giraffe.position.y - 16.0)) < 0.1,
		"Directional jump landed above the giraffe without surface contact")
	_check(player._has_ground_support(), "Directional jump lost support on the giraffe")
	_check(absf(giraffe.position.y - 120.0) < 0.1,
		"Directional jump moved the giraffe off the floor")

	# Pressing into either side while jumping must not be mistaken for a
	# below-to-above impact or leave a support gap after the jump.
	await _side_jump_does_not_lift(Vector2(40, 120), "move_right", "Left")
	await _side_jump_does_not_lift(Vector2(53, 120), "move_left", "Right")

	# The future projectile contract must move the giraffe in either direction.
	await _reset_bodies(Vector2(200, 120), Vector2(120, 120))
	var impulse_start_x := giraffe.position.x
	giraffe.call("apply_external_impulse", Vector2(24.0, 0.0))
	for _i in range(8):
		await _tick()
	_check(giraffe.position.x > impulse_start_x + 0.5,
		"Positive horizontal external impulse did not move the giraffe")

	await _reset_bodies(Vector2(200, 120), Vector2(120, 120))
	impulse_start_x = giraffe.position.x
	giraffe.call("apply_external_impulse", Vector2(-24.0, 0.0))
	for _i in range(8):
		await _tick()
	_check(giraffe.position.x < impulse_start_x - 0.5,
		"Negative horizontal external impulse did not move the giraffe")

	print("Giraffe physics checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
