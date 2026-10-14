extends SceneTree
## Uses actual InputEventKey dispatch instead of action_press. All events stay in
## this headless Godot process; no operating-system keyboard injection is used.
## The testbed is a minimal world built in code (one floor block plus Warma), so
## the suite does not depend on any playable level's layout.

const WorldScript = preload("res://scripts/rect_world.gd")
const RectBodyScript = preload("res://objects/rect_body.gd")
const WarmaScene = preload("res://objects/warma.tscn")
const DT: float = 1.0 / 120.0
var world
var checks: int = 0
var cases: int = 0
var failures: Array[String] = []
var current_case: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Default InputEventKey device: %d" % InputEventKey.new().device)
	for device_mode in ["default", "zero"]:
		for action in ["move_left", "move_right", "jump", "shoot"]:
			current_case = "%s_%s" % [device_mode, action]
			var before: int = failures.size()
			await _test_action(action, device_mode)
			cases += 1
			print("%s %s" % ["PASS" if failures.size() == before else "FAIL", current_case])
	for device_mode in ["default", "zero"]:
		current_case = "%s_held_jump" % device_mode
		var before: int = failures.size()
		await _test_held_jump(device_mode)
		cases += 1
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", current_case])
	for code in [KEY_N, KEY_W, KEY_M]:
		current_case = "interaction_%s" % OS.get_keycode_string(code)
		var before: int = failures.size()
		await _test_interaction_key(code)
		cases += 1
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", current_case])
	current_case = "time_speed_arrows"
	var before_speed: int = failures.size()
	await _test_time_speed_arrows()
	cases += 1
	print("%s %s" % ["PASS" if failures.size() == before_speed else "FAIL", current_case])
	current_case = "single_shot_all_speeds"
	var before_shots: int = failures.size()
	await _test_single_shot_all_speeds()
	cases += 1
	print("%s %s" % ["PASS" if failures.size() == before_shots else "FAIL", current_case])
	print("REAL INPUT: %d cases, %d checks, %d failures" % [cases, checks, failures.size()])
	for failure in failures:
		printerr(failure)
	_free_world()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(current_case + ": " + message)

func _test_interaction_key(code: Key) -> void:
	await _make_fixture(false)
	var door = load("res://objects/door.tscn").instantiate()
	door.position = Vector2(8, 16) if code == KEY_W else Vector2(100, 100)
	door.target_room = "res://levels/level_02.tscn"
	world.add_child(door)
	world.rebuild()
	var requests: Array[String] = []
	world.room_requested.connect(func(path: String): requests.append(path))
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	if code == KEY_N:
		_check(world.player.has_extinguisher, "real N event grants equipment")
	else:
		_check(requests == [door.target_room], "real W/M event requests configured room")
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_free_world()
	await process_frame
	root.get_node("GameState").reset_run()


func _test_time_speed_arrows() -> void:
	await _make_fixture(true)
	for code in [KEY_LEFT, KEY_LEFT, KEY_LEFT, KEY_LEFT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT, KEY_RIGHT]:
		var previous_speed: float = Engine.time_scale
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
		var expected: float = previous_speed
		if code == KEY_LEFT:
			expected = {1.0: 0.5, 0.5: 0.2, 0.2: 0.1, 0.1: 0.1}[previous_speed]
		else:
			expected = {0.1: 0.2, 0.2: 0.5, 0.5: 1.0, 1.0: 1.0}[previous_speed]
		_check(is_equal_approx(Engine.time_scale, expected), "real arrow event changes exactly one step and respects limits")
		_check(world._time_speed_label.text == "x%s" % str(expected).trim_suffix(".0"), "real arrow event updates the HUD")
		event.echo = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
		_check(is_equal_approx(Engine.time_scale, expected), "holding an arrow does not repeatedly change speed")
		event.echo = false
		event.pressed = false
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
		_check(is_equal_approx(Engine.time_scale, expected), "arrow release does not change speed")
		_check(not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right"), "speed arrows do not activate movement")
	_free_world()
	await process_frame


func _test_single_shot_all_speeds() -> void:
	await _make_fixture(true)
	var run_state := root.get_node("GameState")
	var shots := 0
	for speed in [1.0, 0.5, 0.2, 0.1]:
		if speed < 1.0:
			run_state.change_time_speed(-1)
		# Send all taps before any physics update, including at x0.1.
		for tap in range(10):
			Input.parse_input_event(_event("shoot", true, "default"))
			Input.flush_buffered_events()
			shots += 1
			_check(world.bullets.size() == shots, "each rapid tap immediately emits one note at every speed")
			var echo := _event("shoot", true, "default")
			echo.echo = true
			Input.parse_input_event(echo)
			Input.flush_buffered_events()
			_check(world.bullets.size() == shots, "key echo does not emit another note")
			Input.parse_input_event(_event("shoot", false, "default"))
			Input.flush_buffered_events()
			_check(world.bullets.size() == shots, "key release does not emit a note")
		Input.parse_input_event(_event("shoot", true, "default"))
		Input.flush_buffered_events()
		shots += 1
		await process_frame
		for frame in range(12):
			world._physics_process(DT * speed)
			_check(world.bullets.size() == shots, "holding K across physics updates does not fire again")
		Input.parse_input_event(_event("shoot", false, "default"))
		Input.flush_buffered_events()
	world.frozen = true
	Input.parse_input_event(_event("shoot", true, "default"))
	Input.flush_buffered_events()
	_check(world.bullets.size() == shots, "paused game ignores firing presses")
	Input.parse_input_event(_event("shoot", false, "default"))
	Input.flush_buffered_events()
	for step in range(3):
		run_state.change_time_speed(1)
	_free_world()
	await process_frame


func _test_held_jump(device_mode: String) -> void:
	await _make_fixture(false)
	var state = world.player.state
	Input.parse_input_event(_event("jump", true, device_mode))
	Input.flush_buffered_events()
	_tick()
	_check(state.vy < 0.0 and not state.grounded, "holding J starts the first jump")
	await process_frame
	_check(not Input.is_action_just_pressed("jump"), "held jump continues without a new press edge")
	for bounce in range(3):
		var landed := false
		var previous_vy: float = state.vy
		for frame in range(240):
			_tick()
			if state.grounded:
				landed = true
				break
			_check(state.vy >= previous_vy, "holding J does not restart the jump in midair")
			previous_vy = state.vy
		_check(landed, "jump returns to its support")
		_tick()
		_check(state.vy < -100.0 and not state.grounded, "held J jumps on the first eligible physics tick after landing")
	Input.parse_input_event(_event("jump", false, device_mode))
	Input.flush_buffered_events()
	_tick()
	_check(state.vy >= -68.0 and state.vy < 0.0, "releasing a repeated jump still cuts its height")
	await process_frame
	_tick(240)
	_check(state.grounded and is_zero_approx(state.vy), "releasing J stops automatic jumping")
	_free_world()
	await process_frame


func _make_fixture(equipped: bool) -> void:
	_free_world()
	world = WorldScript.new()
	var floor_block = RectBodyScript.new()
	floor_block.kind = "block"
	floor_block.position = Vector2(0, 32)
	world.add_child(floor_block)
	var warma = WarmaScene.instantiate()
	warma.position = Vector2(8, 16)
	warma.has_extinguisher = equipped
	world.add_child(warma)
	root.add_child(world)
	world.set_physics_process(false)
	await process_frame


func _free_world() -> void:
	if is_instance_valid(world):
		world.queue_free()
	world = null


func _event(action: String, pressed: bool, device_mode: String) -> InputEventKey:
	var keys: Dictionary = {"move_left": KEY_A, "move_right": KEY_D, "jump": KEY_J, "shoot": KEY_K}
	var event := InputEventKey.new()
	event.physical_keycode = keys[action]
	event.pressed = pressed
	if device_mode == "zero":
		event.device = 0
	return event


func _tick(count: int = 1) -> void:
	for frame in range(count):
		world._physics_process(DT)


func _test_action(action: String, device_mode: String) -> void:
	await _make_fixture(action == "shoot")
	_tick()
	var state = world.player.state
	var start_x: float = state.x
	var press := _event(action, true, device_mode)
	_check(InputMap.event_is_action(press, action), "physical press matches saved input binding")
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	_check(Input.is_action_pressed(action), "physical press activates action")
	_check(Input.is_action_just_pressed(action), "physical press creates action edge")
	_tick()
	match action:
		"move_left":
			_check(state.x < start_x and state.vx < 0.0, "A moves Warma left through real controller")
		"move_right":
			_check(state.x > start_x and state.vx > 0.0, "D moves Warma right through real controller")
		"jump":
			_check(state.vy < -100.0 and state.y < 80.0, "J starts a jump through real controller")
		"shoot":
			_check(world.bullets.size() == 1, "K fires a bullet through real controller")
	await process_frame
	var release := _event(action, false, device_mode)
	_check(InputMap.event_is_action(release, action), "physical release matches saved input binding")
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	_check(not Input.is_action_pressed(action), "physical release clears action")
	_check(Input.is_action_just_released(action), "physical release creates release edge")
	var release_x: float = state.x
	_tick()
	match action:
		"move_left", "move_right":
			_check(absf(state.x - release_x) < 0.000001 and state.vx == 0.0, "physical key release immediately stops horizontal movement")
		"jump":
			_check(state.vy >= -68.0 and state.vy < 0.0, "physical J release cuts the jump")
		"shoot":
			_tick(40)
			_check(world.bullets.size() == 1, "physical K release prevents repeated fire")
	await process_frame
	_free_world()
	await process_frame
