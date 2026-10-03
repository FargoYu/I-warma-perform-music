extends SceneTree
## Lightweight regression checks for the sign, pressure plate, lift and speed UI.

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _tick(count: int = 1) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func _run() -> void:
	var game_state := root.get_node("GameState")
	game_state.reset_speed()
	var level := Node2D.new()
	root.add_child(level)
	var player := load("res://objects/warma.tscn").instantiate() as CharacterBody2D
	var sign := load("res://objects/signboard.tscn").instantiate() as Area2D
	var button := load("res://objects/button.tscn").instantiate() as Area2D
	var elevator := load("res://objects/elevator_up.tscn").instantiate() as Node2D
	_check(player != null and sign != null and button != null and elevator != null, "New reusable scenes must instantiate")
	if player == null or sign == null or button == null or elevator == null:
		quit(1)
		return
	player.name = "Player"
	player.position = Vector2(64, 89)
	player.set_physics_process(false)
	sign.position = Vector2(64, 100)
	button.position = Vector2(120, 100)
	elevator.position = Vector2(120, 100)
	level.add_child(sign)
	level.add_child(button)
	level.add_child(elevator)
	level.add_child(player)
	await _tick(3)
	_check(bool(sign.get("player_inside")), "Sign must show while Warma is inside its area")
	player.position = Vector2(20, 20)
	await _tick(2)
	_check(not bool(sign.get("player_inside")), "Sign must hide after Warma leaves its area")
	player.position = Vector2(120, 89)
	await _tick(2)
	_check(bool(button.get("activated")), "Button must activate while Warma overlaps it")
	var start_height := float(elevator.get("current_height"))
	elevator.call("set_button_source", button)
	await _tick(30)
	_check(float(elevator.get("current_height")) > start_height, "Held button must extend the lift")
	player.position = Vector2(20, 20)
	button.call("set_activated", false)
	var held_height := float(elevator.get("current_height"))
	await _tick(30)
	_check(float(elevator.get("current_height")) < held_height, "Released button must reverse the lift")
	var giraffe := load("res://objects/giraffe.tscn").instantiate() as CharacterBody2D
	giraffe.position = Vector2(120, 86)
	giraffe.set("gravity", 0.0)
	level.add_child(giraffe)
	await _tick(2)
	_check(bool(button.get("activated")), "Button must also activate under the giraffe")
	giraffe.queue_free()
	await _tick(2)
	_check(not bool(button.get("activated")), "Button must deactivate after the giraffe leaves")
	var chain_room := load("res://rooms/main.tscn").instantiate() as Node2D
	root.add_child(chain_room)
	var chain_player := chain_room.get_node("Player") as CharacterBody2D
	var chain_giraffe := chain_room.get_node("Giraffe") as CharacterBody2D
	chain_player.position = Vector2(47, 104)
	chain_player.velocity = Vector2.ZERO
	chain_giraffe.position = Vector2(47, 120)
	chain_giraffe.velocity = Vector2.ZERO
	await _tick(12)
	Input.action_press("jump")
	var chain_launches := 0
	var previous_vertical_speed := 0.0
	for _frame in range(320):
		await _tick(1)
		if previous_vertical_speed >= 0.0 and chain_player.velocity.y < -100.0:
			chain_launches += 1
		previous_vertical_speed = chain_player.velocity.y
	Input.action_release("jump")
	_check(chain_launches >= 2, "Holding jump must chain a second jump after landing on the giraffe")
	chain_room.queue_free()
	await _tick(2)
	game_state.set_speed_index(0)
	_check(is_equal_approx(Engine.time_scale, 0.1), "Speed index 0 must set x0.1")
	game_state.increase_speed()
	_check(is_equal_approx(Engine.time_scale, 0.2), "Right speed step must set x0.2")
	game_state.reset_speed()
	Input.action_press("speed_decrease")
	await _tick(1)
	Input.action_release("speed_decrease")
	_check(is_equal_approx(Engine.time_scale, 0.5), "Left arrow action must step from x1 to x0.5")
	game_state.reset_speed()
	_check(is_equal_approx(Engine.time_scale, 1.0), "Speed reset must return to x1")
	print("New feature checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
