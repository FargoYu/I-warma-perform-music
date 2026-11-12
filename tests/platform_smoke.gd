extends SceneTree
## Run: Godot --headless --path . --script res://tests/platform_smoke.gd
## Integration checks use real scenes, viewport input dispatch, and touch events.

var failures: Array[String] = []
var checks := 0
var shot_count := 0
var controls: Node
var state: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)

func _frames(count: int = 3) -> void:
	for frame in count:
		await process_frame

func _physics_frames(count: int = 3) -> void:
	for frame in count:
		await physics_frame

func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	root.push_input(event, true)

func _button(action: StringName) -> Vector2:
	for button in controls._buttons:
		if button.action == action:
			return button.rect.get_center()
	_check(false, "Touch button exists: " + str(action))
	return Vector2(-100, -100)

func _tap(action: StringName, index: int = 20) -> void:
	var position := _button(action)
	_touch(index, position, true)
	_touch(index, position, false)

func _key(code: Key, pressed: bool, echo: bool = false, device_id: int = InputEvent.DEVICE_ID_KEYBOARD) -> void:
	var event := InputEventKey.new()
	event.device = device_id
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _count_shot(cue: StringName) -> void:
	if str(cue).begins_with("shoot_"):
		shot_count += 1

func _run() -> void:
	Input.use_accumulated_input = false
	controls = root.get_node("PlatformControls")
	state = root.get_node("GameState")
	root.get_node("AudioManager").sfx_played.connect(_count_shot)
	state.has_extinguisher = true
	state.change_time_speed(-1)
	_check(change_scene_to_file("res://start.tscn") == OK, "Title loads")
	await _frames()
	_check(not state.has_extinguisher and is_equal_approx(Engine.time_scale, 1.0), "Title resets equipment and speed")
	if not controls.is_touch_mode():
		await _desktop_input_checks()
	_touch(0, Vector2(128, 80), true)
	_touch(0, Vector2(128, 80), false)
	await _frames()
	_check(current_scene.scene_file_path == "res://start.tscn", "Transition guard rejects stale touch")
	await create_timer(0.28, true, false, true).timeout
	_touch(0, Vector2(128, 80), true)
	_touch(0, Vector2(128, 80), false)
	await _frames()
	_check(current_scene.scene_file_path == "res://main.tscn", "Touch starts game")
	if current_scene.scene_file_path != "res://main.tscn":
		_finish()
		return
	var game: Node2D = current_scene
	_check(controls.is_touch_mode(), "Touch enables control deck")
	_check(controls._buttons.size() == 9, "All nine touch controls available")
	_check(game.world.setup_errors.is_empty(), "First room has valid geometry")
	_check(game.world.signboards[0]._input_hint() == "按左 / 右按钮移动", "Touch signs describe touch controls")
	await _physics_frames()
	var initial_x: float = game.world.player.state.x
	_touch(1, _button(&"move_right"), true)
	_touch(2, _button(&"jump"), true)
	_check(Input.is_action_pressed("move_right") and Input.is_action_pressed("jump"), "Move and jump hold simultaneously")
	await _physics_frames(5)
	_check(game.world.player.state.x > initial_x, "Touch moves the player")
	_check(game.world.player.state.vy < 0, "Touch jump lifts the player")
	_touch(3, _button(&"move_right"), true)
	_touch(1, _button(&"move_right"), false)
	_check(Input.is_action_pressed("move_right"), "Second finger keeps the same action held")
	_touch(3, _button(&"move_right"), false)
	_check(not Input.is_action_pressed("move_right") and Input.is_action_pressed("jump"), "Releasing movement preserves independent jump")
	_touch(2, _button(&"jump"), false, true)
	_check(not Input.is_action_pressed("jump"), "Canceled touch releases jump")
	_touch(4, _button(&"move_left"), true)
	_drag(4, _button(&"move_right"))
	_check(not Input.is_action_pressed("move_left") and Input.is_action_pressed("move_right"), "Sliding between movement buttons changes direction")
	_drag(4, _button(&"shoot"))
	_check(not Input.is_action_pressed("move_right") and shot_count == 0, "Sliding out releases movement without firing")
	_touch(4, _button(&"shoot"), false)
	game.world.grant_extinguisher()
	_touch(5, _button(&"shoot"), true)
	await _physics_frames(5)
	_check(shot_count == 1, "Holding shoot fires once")
	_touch(6, _button(&"shoot"), true)
	_touch(5, _button(&"shoot"), false)
	_check(shot_count == 1 and Input.is_action_pressed("shoot"), "Multiple fingers do not duplicate a held shot")
	_touch(6, _button(&"shoot"), false)
	_tap(&"shoot")
	_check(shot_count == 2, "New shoot tap fires again")
	_key(KEY_K, true)
	_key(KEY_K, true, true)
	_key(KEY_K, false)
	_check(shot_count == 3, "Keyboard shoot works and ignores repeat")
	_touch(7, _button(&"move_right"), true)
	_tap(&"pause")
	_check(game.is_paused() and not Input.is_action_pressed("move_right"), "Pausing releases held controls")
	_tap(&"shoot")
	_check(shot_count == 3, "Paused gameplay ignores shoot")
	_tap(&"time_slower")
	_check(is_equal_approx(state.get_time_speed(), 0.5), "Touch slowdown works while paused")
	_tap(&"time_faster")
	_check(is_equal_approx(state.get_time_speed(), 1.0), "Touch speedup restores normal speed")
	_tap(&"pause")
	_check(not game.is_paused(), "Touch resumes game")
	_touch(8, _button(&"jump"), true)
	controls.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(game.is_paused() and not Input.is_action_pressed("jump"), "Backgrounding pauses and releases held touch")
	controls.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not game.is_paused(), "Android back toggles pause")
	controls.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not game.is_paused(), "Duplicate Android back delivery does not toggle twice")
	await create_timer(0.27, true, false, true).timeout
	controls.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(game.is_paused(), "A later Android back press still toggles pause")
	_tap(&"pause")
	_check(not game.is_paused(), "Touch resumes after Android back pause")
	_touch(9, _button(&"move_right"), true)
	root.size = Vector2i(600, 900)
	await _frames()
	_check(not Input.is_action_pressed("move_right"), "Portrait resize releases held controls")
	_check_layout(game, "portrait")
	root.size = Vector2i(1600, 720)
	await _frames()
	_check_layout(game, "wide landscape")
	root.size = Vector2i(1024, 576)
	await _frames()
	var previous_room_id: int = game.world.get_instance_id()
	_tap(&"restart")
	await create_timer(0.6, true, false, true).timeout
	_check(game.world.get_instance_id() != previous_room_id, "Touch restart reloads the room")
	_check(game.world.player.has_extinguisher, "Restart preserves equipment")
	# Exercise the actual door connections, including the final completion screen.
	for index in range(1, 25):
		var expected := "res://levels/level_%02d.tscn" % index
		_check(game.world.scene_file_path == expected, "Room sequence: " + expected)
		_check(game.world.player != null and game.world.setup_errors.is_empty(), "Valid room: %02d" % index)
		_check(not game.world.doors.is_empty(), "Room has an exit: %02d" % index)
		game.world.enter_first_door()
		await _frames()
	_check(current_scene.scene_file_path == "res://end.tscn", "Final door opens completion screen")
	_check(root.content_scale_size == Vector2i(256, 144), "Completion screen restores original viewport")
	state.change_time_speed(-1)
	await create_timer(0.28, true, false, true).timeout
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(128, 80)
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await _frames()
	_check(current_scene.scene_file_path == "res://start.tscn", "Mouse returns completion screen to title")
	_check(not state.has_extinguisher and is_equal_approx(Engine.time_scale, 1.0), "Repeat run resets equipment and time")
	await create_timer(0.28, true, false, true).timeout
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _frames()
	_check(current_scene.scene_file_path == "res://main.tscn", "Keyboard starts a repeat run")
	_check(not current_scene.world.player.has_extinguisher, "New run starts without prior equipment")
	controls.release_all()
	_finish()

func _desktop_input_checks() -> void:
	# Native, browser, and injected keyboard events need not share a device ID.
	for device_id in [0, InputEvent.DEVICE_ID_KEYBOARD, 73]:
		for binding in [["interact", KEY_W], ["restart", KEY_R], ["pause", KEY_P], ["pause", KEY_ESCAPE], ["time_slower", KEY_LEFT], ["time_faster", KEY_RIGHT]]:
			var event := InputEventKey.new()
			event.device = device_id
			event.physical_keycode = binding[1]
			event.pressed = true
			_check(event.is_action_pressed(binding[0]), "Keyboard action accepts device %d: %s" % [device_id, binding[0]])
	await create_timer(0.28, true, false, true).timeout
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _frames()
	_check(current_scene.scene_file_path == "res://main.tscn", "Desktop keyboard starts game")
	var game: Node2D = current_scene
	_check(controls._buttons.is_empty() and root.content_scale_size == Vector2i(256, 144), "Desktop preserves full original gameplay area")
	await _physics_frames()
	var initial_x: float = game.world.player.state.x
	_key(KEY_D, true)
	_key(KEY_J, true)
	await _physics_frames(5)
	_check(game.world.player.state.x > initial_x and game.world.player.state.vy < 0, "Desktop movement and jump work together")
	_key(KEY_D, false)
	_key(KEY_J, false)
	_key(KEY_P, true, false, 0)
	_key(KEY_P, true, true, 0)
	_key(KEY_P, false, false, 0)
	_check(game.is_paused(), "Desktop pause ignores keyboard repeat")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	_check(not game.is_paused(), "Escape resumes desktop gameplay")
	_check(change_scene_to_file("res://start.tscn") == OK, "Return to title for touch checks")
	await _frames()

func _check_layout(game: Node2D, label: String) -> void:
	var viewport := root.get_visible_rect()
	var level := Rect2(game.position, Vector2(256, 144))
	var deck_top: float = viewport.size.y - controls.DECK_HEIGHT
	_check(viewport.encloses(level) and level.end.y <= deck_top + 0.01, "Whole level fits above controls: " + label)
	for button in controls._buttons:
		_check(viewport.encloses(button.rect) and button.rect.position.y >= deck_top, "Button remains inside deck: %s / %s" % [label, button.action])
	for signboard in game.world.signboards:
		signboard.show_message(true)
		signboard._fit_message()
		var message: Rect2 = signboard.get_global_transform_with_canvas() * Rect2(signboard._panel.position, signboard._panel.size)
		_check(level.grow(0.01).encloses(message), "Sign text stays inside playfield: %s / %s" % [label, signboard.name])
		signboard.show_message(false)

func _finish() -> void:
	# Let the audio mix thread finish releasing active voices before shutdown.
	for player in root.get_node("AudioManager").get_children():
		if player is AudioStreamPlayer:
			player.stop()
	await create_timer(0.15, true, false, true).timeout
	print("PLATFORM_SMOKE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
