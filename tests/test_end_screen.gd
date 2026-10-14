extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var screen = load("res://end.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	echo.physical_keycode = KEY_T
	Input.parse_input_event(echo)
	Input.flush_buffered_events()
	await process_frame
	if screen.transitioning:
		printerr("Ending unexpectedly accepts echo")
		quit(1)
		return
	root.tree_exiting.connect(func():
		if screen.transitioning:
			print("END SCREEN: arbitrary key exits game, 0 failures")
	)
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_T
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await create_timer(0.2).timeout
	printerr("Ending did not quit")
	quit(1)
