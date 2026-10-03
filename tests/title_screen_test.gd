extends SceneTree

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

func _run() -> void:
	create_timer(12.0).timeout.connect(func():
		push_error("Title/entry text checks timed out")
		quit(1)
	)
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://rooms/title.tscn",
		"Project must start at the title scene")
	var title_scene := load("res://rooms/title.tscn") as PackedScene
	_check(title_scene != null, "Title scene must load")
	if title_scene == null:
		quit(1)
		return
	change_scene_to_packed(title_scene)
	await scene_changed
	var title := current_scene
	await _tick(2)
	var prompt := title.get_node("StartPrompt")
	_check(prompt != null, "Title must include the reusable screen text")
	_check(bool(prompt.get("show_on_enter")), "Title prompt must show on enter")
	_check(prompt.get_node("Message").visible, "Title prompt must be visible")
	_check(prompt.get_node("Message").text == "按任意键开始", "Title prompt must use Chinese text")
	_check(prompt.get_node("Message").get_rect().get_center().is_equal_approx(Vector2(128, 72)),
		"Prompt must be centered on the viewport")
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = false
	Input.parse_input_event(event)
	await _tick(2)
	_check(current_scene == title, "Key release must not start the game")
	event.echo = true
	event.pressed = true
	Input.parse_input_event(event)
	await _tick(2)
	_check(current_scene == title, "Key echo must not start the game")
	event.echo = false
	event.keycode = KEY_J
	event.physical_keycode = KEY_J
	Input.parse_input_event(event)
	await scene_changed
	await _tick(2)
	_check(current_scene != null and current_scene.scene_file_path == "res://rooms/main.tscn",
		"Any key on title must open the original main scene")
	_check(not Input.is_action_pressed("jump"), "Starting key must not become a gameplay jump")
	var entry := current_scene.get_node("EntryText")
	_check(entry.get_node("Message").visible, "Entry text must appear immediately on entering the room")
	for size in [6, 16, 32, 64]:
		entry.set("font_size", size)
		await _tick(2)
		_check(entry.get_node("Message").get_rect().get_center().is_equal_approx(Vector2(128, 72)),
			"Entry text must stay at the viewport center at font size %d" % size)
	entry.set("center_on_screen", false)
	entry.set("text_position", Vector2(80, 45))
	entry.set("font_size", 12)
	_check(entry.get_node("Message").get_rect().get_center().is_equal_approx(Vector2(80, 45)),
		"Entry text center must be configurable")
	_check(entry.get_node("Message").get_theme_font_size("font_size") == 12,
		"Entry text font size must be configurable")
	# Exercise the real elapsed-time expiry without sleeping two seconds.
	entry.set("display_duration", 0.05)
	entry.show_message()
	await _tick(16)
	_check(not entry.get_node("Message").visible, "Entry text must disappear after its duration")
	var sign := current_scene.get_node("Signboard") as Area2D
	_check(sign.z_index > current_scene.get_node("Background").z_index and sign.z_index < 0,
		"Signboard sprite must be above background and below actors/blocks")
	var sign_text := sign.get_node("MessageLayer") as CanvasLayer
	_check(sign_text != null and sign_text.layer > current_scene.get_node("HUD").layer,
		"Sign text must render in front of the world and persistent HUD")
	var player := current_scene.get_node("Player") as CharacterBody2D
	player.set_physics_process(false)
	entry.set("display_duration", 0.0)
	entry.show_message()
	player.position = sign.position
	await _tick(3)
	_check(sign.get_node("MessageLayer/Message").visible, "Sign must still show its message in range")
	_check(not entry.get_node("Message").visible, "Touching a sign must immediately dismiss the entry text")
	player.position.x += 50.0
	await _tick(2)
	_check(not sign.get_node("MessageLayer/Message").visible, "Sign must still hide its message out of range")
	# Reset and speed keys are also valid title keys; their gameplay actions
	# must not leak into the newly loaded room.
	for key in [KEY_R, KEY_LEFT]:
		change_scene_to_packed(title_scene)
		await scene_changed
		await _tick(2)
		event.keycode = key
		event.physical_keycode = key
		event.pressed = true
		Input.parse_input_event(event)
		await scene_changed
		event.pressed = false
		Input.parse_input_event(event)
		await _tick(3)
		_check(current_scene.scene_file_path == "res://rooms/main.tscn", "Title must accept R and arrows")
		_check(not current_scene.get_node("Player").get("_dying"), "Title key must not kill the new player")
		_check(is_equal_approx(Engine.time_scale, 1.0), "Title arrow key must not slow the new game")
	print("Title screen checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
