extends SceneTree
## Runtime regression checks for message arbitration and sign positioning.

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

func _visible_messages() -> int:
	var count := 0
	for display in get_nodes_in_group("foreground_messages"):
		if display.get_node("Message").visible:
			count += 1
	return count

func _sign_transitions(reverse_order: bool) -> void:
	var level := Node2D.new()
	root.add_child(level)
	var player: CharacterBody2D = load("res://objects/warma.tscn").instantiate()
	player.position = Vector2(20, 120)
	level.add_child(player)
	player.set_physics_process(false)
	var entry = load("res://objects/screen_text.tscn").instantiate()
	entry.display_duration = 0.05
	level.add_child(entry)
	var hud := load("res://objects/hud.tscn").instantiate() as CanvasLayer
	level.add_child(hud)
	var first = load("res://objects/signboard.tscn").instantiate()
	var second = load("res://objects/signboard.tscn").instantiate()
	first.position = Vector2(116, 120)
	second.position = Vector2(136, 120)
	first.message = "第一块"
	second.message = "第二块"
	for sign in [second, first] if reverse_order else [first, second]:
		level.add_child(sign)
	var first_label := first.get_node("MessageLayer/Message") as Label
	var second_label := second.get_node("MessageLayer/Message") as Label
	_check(_visible_messages() == 1, "Only the room introduction may show initially")
	player.position = first.position
	await _tick()
	_check(first_label.visible and not entry.get_node("Message").visible,
		"Entering a sign must replace the introduction on the same update")
	player.position.x = 128.0
	await _tick()
	_check(second_label.visible and not first_label.visible and _visible_messages() == 1,
		"Newly entered sign must replace the previous sign even when areas overlap")
	await _tick(12)
	_check(second_label.visible and not first_label.visible and _visible_messages() == 1,
		"Overlapping signs and an expired intro timer must not fight over the message")
	_check(hud.get_node("Speed").visible, "Message replacement must preserve the speed UI")
	player.position.x = 20.0
	await _tick()
	_check(_visible_messages() == 0, "Leaving both signs must hide the message without reviving the intro")
	# Teleport directly between signs: the old sign may process its exit after
	# the new one shows, and must only hide its own label.
	player.position = first.position
	await _tick()
	player.position = Vector2(148, 120)
	await _tick()
	_check(second_label.visible and not first_label.visible and _visible_messages() == 1,
		"A direct sign-to-sign transition must preserve the new message in either tree order")
	level.queue_free()
	await _tick(2)

func _positioning() -> void:
	var level := Node2D.new()
	root.add_child(level)
	var sign = load("res://objects/signboard.tscn").instantiate()
	sign.position = Vector2(128, 120)
	sign.message = "居中"
	level.add_child(sign)
	var label := sign.get_node("MessageLayer/Message") as Label
	for size in [8, 16, 24]:
		sign.font_size = size
		sign._apply_message()
		await _tick(2)
		_check(is_equal_approx(label.get_rect().get_center().x, 128.0),
			"Sign message must center over the sign at font size %d" % size)
		_check(is_equal_approx(label.get_rect().end.y, 112.0 - sign.text_distance),
			"Sign message must keep the configured gap above the sprite at font size %d" % size)
	var canvas_transform := Transform2D(0.0, Vector2(-4, -20))
	root.canvas_transform = canvas_transform
	await _tick(2)
	_check(is_equal_approx(label.get_rect().get_center().x, 124.0), "Sign anchor must follow the camera horizontally")
	_check(is_equal_approx(label.get_rect().end.y, 92.0 - sign.text_distance), "Sign anchor must follow the camera vertically")
	root.canvas_transform = Transform2D.IDENTITY
	sign.text_above_sign = false
	sign.centered = false
	sign.text_position = Vector2(15, 25)
	sign._apply_message()
	await _tick(2)
	_check(label.position == Vector2(15, 25) and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT,
		"Disabling sign centering and anchoring must allow an explicit top-left position")
	level.queue_free()
	await _tick(2)

func _run() -> void:
	await _sign_transitions(false)
	await _sign_transitions(true)
	await _positioning()
	print("Foreground message checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
