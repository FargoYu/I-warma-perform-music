extends SceneTree
## Validate saved layouts and exercise both F6 and hosted room physics.

const DT: float = 1.0 / 120.0
const MainScene = preload("res://main.tscn")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_saved_layouts()
	await _test_standalone_level4()
	await _test_level3_door()
	print("LEVEL LOADING: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _test_saved_layouts() -> void:
	var paths := DirAccess.get_files_at("res://levels")
	paths.sort()
	for filename in paths:
		if not filename.ends_with(".tscn"):
			continue
		var path := "res://levels/" + filename
		var world = load(path).instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		_check(world.setup_errors.is_empty(), "%s: %s" % [path, world.setup_errors])
		_check(not world.frozen, path + ": layout must not freeze the world")
		_check(world.player != null and world.player.state != null, path + ": player must register")
		if world.setup_errors.is_empty() and world.player != null:
			for frame in range(120):
				world._physics_process(DT)
				_check(world.solver.diagnostics.is_empty(), "%s frame %d: %s" % [path, frame, world.solver.diagnostics])
			_check(world.player.state.grounded, path + ": player must settle on the floor")
			_check(not world.restarting, path + ": spawn must survive settling")
		world.free()

func _test_standalone_level4() -> void:
	_check(change_scene_to_file("res://levels/level_04.tscn") == OK, "standalone level4 must load")
	await process_frame
	await process_frame
	var world = current_scene
	_check(world != null and world.scene_file_path == "res://levels/level_04.tscn", "F6 must run the requested room")
	if world != null:
		await _check_live_movement(world, "standalone level4")
		world.queue_free()
		await process_frame

func _test_level3_door() -> void:
	var game = MainScene.instantiate()
	game.level = load("res://levels/level_03.tscn")
	root.add_child(game)
	current_scene = game
	game.world.set_physics_process(false)
	game.world.enter_first_door()
	await process_frame
	await process_frame
	_check(game.world.scene_file_path == "res://levels/level_04.tscn", "level3 door must enter level4")
	if game.world.scene_file_path == "res://levels/level_04.tscn":
		await _check_live_movement(game.world, "hosted level4")
	game.queue_free()
	await process_frame

func _check_live_movement(world, context: String) -> void:
	_check(not world.frozen and not world.transitioning and world.setup_errors.is_empty(), context + ": room must be active")
	if world.player == null or world.player.state == null:
		_check(false, context + ": player is missing")
		return
	var player = world.player
	var floor_y: float = player.state.y
	# The authored level4 spawn already touches the floor. Lift it to verify gravity.
	player.state.y -= 16.0
	player.state.vy = 0.0
	world.solver.refresh_contacts()
	world.sync_visuals()
	var start_x: float = player.state.x
	var start_y: float = player.state.y
	Input.action_press("move_right")
	world.set_physics_process(true)
	for frame in range(30):
		await physics_frame
	Input.action_release("move_right")
	_check(player.state.x > start_x + 5.0, context + ": D must move the player during live physics ticks")
	_check(player.state.y > start_y + 1.0, context + ": gravity must make the player fall")
	for frame in range(60):
		await physics_frame
	world.set_physics_process(false)
	_check(player.state.grounded and absf(player.state.y - floor_y) < 0.000001, context + ": player must land on the floor")
	_check(world.solver.diagnostics.is_empty(), context + ": physics must remain valid")
