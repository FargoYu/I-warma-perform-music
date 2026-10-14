extends SceneTree
## Game entry, equipment and pickup behavior use the existing rectangle authority.

const MainScene = preload("res://main.tscn")
const WarmaScene = preload("res://objects/warma.tscn")
const GiraffeScene = preload("res://objects/giraffe.tscn")
const PickupScene = preload("res://objects/extinguisher_pickup.tscn")
const WorldScript = preload("res://scripts/rect_world.gd")
const EPS: float = 0.000001
const DT: float = 1.0 / 120.0

class InterpolationWarma:
	extends "res://objects/warma.gd"
	var interpolation_resets: int = 0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESET_PHYSICS_INTERPOLATION:
			interpolation_resets += 1

class TickingWorld:
	extends "res://scripts/rect_world.gd"
	var tick_deltas: Array[float] = []

	func _physics_process(delta: float) -> void:
		super(delta)
		tick_deltas.append(delta)

var failures: Array[String] = []
var checks: int = 0
var cases: int = 0
var current_case: String = ""
var equipment_changes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("GameState").reset_run()
	var suite: Array[Callable] = [
		_test_window_configuration, _test_main_scene, _test_starter_pickup_reachable,
		_test_level_boundaries,
		_test_character_render_geometry, _test_continuous_visual_motion,
		_test_rebuild_interpolation_reset,
		_test_unequipped_shooting,
		_test_pickup_and_keyboard_shooting, _test_bullet_directions,
		_test_unrestricted_fire, _test_held_fire, _test_time_speed, _test_scaled_simulation,
		_test_giraffe_cannot_collect, _test_duplicate_pickups,
		_test_rebuild_consumed_pickup, _test_nested_pickup_coordinates,
		_test_pickup_edges, _test_run_equipment_persistence,
		_test_fall_restart, _test_fall_restart_current_room, _test_key_restart_current_room, _test_standalone_restart, _test_unequipped_restart, _test_fall_limit_boundary,
		_test_door_keyboard, _test_signboard_switch, _test_room_transition, _test_standalone_door,
		_test_start_screen,
		_test_end_transition,
	]
	for test in suite:
		current_case = str(test.get_method()).trim_prefix("_test_")
		var selected := OS.get_cmdline_user_args()
		if not selected.is_empty() and not selected.has(current_case):
			continue
		root.get_node("GameState").reset_run()
		var before: int = failures.size()
		await test.call()
		cases += 1
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", current_case])
	Input.action_release("shoot")
	root.get_node("GameState").reset_run()
	print("GAMEPLAY: %d cases, %d checks, %d failures" % [cases, checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current_case, message])


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= EPS, "%s; expected %.8f, got %.8f" % [message, expected, actual])


func _safe(world) -> void:
	_check(world.setup_errors.is_empty(), "fixture has no setup errors")
	_check(world.solver.diagnostics.is_empty(), "solver has no diagnostics")
	for i in range(world.solver.bodies.size()):
		for j in range(i + 1, world.solver.bodies.size()):
			var a = world.solver.bodies[i]
			var b = world.solver.bodies[j]
			var ox: float = minf(a.x + a.w, b.x + b.w) - maxf(a.x, b.x)
			var oy: float = minf(a.y + a.h, b.y + b.h) - maxf(a.y, b.y)
			_check(not (ox > EPS and oy > EPS), "solid body interiors never overlap")


func _fixture(player_position: Vector2, pickup_positions: Array = [], giraffe_position = null):
	var world = WorldScript.new()
	var player = WarmaScene.instantiate()
	player.position = player_position
	world.add_child(player)
	if giraffe_position != null:
		var giraffe = GiraffeScene.instantiate()
		giraffe.position = giraffe_position
		world.add_child(giraffe)
	for position in pickup_positions:
		var pickup = PickupScene.instantiate()
		pickup.position = position
		world.add_child(pickup)
	root.add_child(world)
	world.set_physics_process(false)
	return world


func _free_fixture(node: Node) -> void:
	Input.action_release("shoot")
	Input.action_release("move_right")
	node.queue_free()
	await process_frame


func _equipment_changed(_equipped: bool) -> void:
	equipment_changes += 1

func _key(code: Key, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	return event

func _test_start_screen() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://start.tscn", "game boots into opening scene")
	var start = load("res://start.tscn").instantiate()
	_check(start.target_scene == "res://main.tscn", "opening defaults to game entry")
	start.target_scene = "res://levels/level_02.tscn"
	root.add_child(start)
	current_scene = start
	start._unhandled_input(_key(KEY_T, true))
	_check(not start.transitioning, "key echo cannot start game")
	var event := _key(KEY_T)
	event.pressed = false
	start._unhandled_input(event)
	_check(not start.transitioning, "key release cannot start game")
	Input.parse_input_event(_key(KEY_T))
	Input.flush_buffered_events()
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == "res://levels/level_02.tscn", "arbitrary key opens Inspector-configured scene")
	if current_scene != null:
		current_scene.set_physics_process(false)
		await _free_fixture(current_scene)
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _test_end_transition() -> void:
	var game = MainScene.instantiate()
	root.add_child(game)
	current_scene = game
	for room in range(1, 17):
		if not is_instance_valid(game):
			_check(false, "main game stays active until room 16")
			break
		game.world.set_physics_process(false)
		_check(game.world.scene_file_path == "res://levels/level_%02d.tscn" % room, "main route visits room %02d in order" % room)
		game.world.enter_first_door()
		await process_frame
		await process_frame
	_check(current_scene != null and current_scene.scene_file_path == "res://end.tscn", "last room door opens ending scene")
	if current_scene != null:
		if current_scene.get_script() == preload("res://scripts/scene_screen.gd"):
			_check(current_scene.quit_on_key, "ending is configured to quit")
		await _free_fixture(current_scene)

func _test_door_keyboard() -> void:
	var world = _fixture(Vector2(10, 10))
	var group := Node2D.new()
	group.position = Vector2(8, 4)
	world.add_child(group)
	var first = load("res://objects/door.tscn").instantiate()
	first.position = Vector2(2, 6)
	first.target_room = "res://levels/level_02.tscn"
	group.add_child(first)
	var second = load("res://objects/door.tscn").instantiate()
	second.target_room = "res://levels/level_01.tscn"
	world.add_child(second)
	world.rebuild()
	var requests: Array[String] = []
	world.room_requested.connect(func(path: String): requests.append(path))
	world._unhandled_input(_key(KEY_N, true))
	_check(not world.player.has_extinguisher, "echo N does not grant equipment")
	world._unhandled_input(_key(KEY_N))
	_check(world.player.has_extinguisher and root.get_node("GameState").has_extinguisher, "N grants equipment and run state")
	world.player.position = Vector2(100, 100)
	world._unhandled_input(_key(KEY_W))
	_check(requests == ["res://levels/level_02.tscn"], "W uses authoritative coordinates and nested door range")
	world._unhandled_input(_key(KEY_M))
	_check(requests.size() == 1, "transition prevents duplicate requests")
	world.transitioning = false
	world.player.state.x = 100
	world._unhandled_input(_key(KEY_W))
	_check(requests.size() == 1, "W outside all doors does nothing")
	world._unhandled_input(_key(KEY_M))
	_check(requests.size() == 2 and requests[1] == first.target_room, "M chooses first door without proximity")
	world.transitioning = false
	first.target_room = ""
	world.enter_first_door()
	_check(requests.size() == 2 and not world.transitioning, "unconfigured first door does not fall through to second")
	first.target_room = "res://objects/door.tscn"
	world.enter_first_door()
	_check(not world.transitioning, "invalid room root leaves current world usable")
	await _free_fixture(world)
	root.get_node("GameState").reset_run()

func _test_signboard_switch() -> void:
	var world = _fixture(Vector2(10, 10))
	var first = load("res://objects/signboard.tscn").instantiate()
	first.position = Vector2(10, 10)
	first.text = "第一块告示牌\n多行文字"
	world.add_child(first)
	var second = load("res://objects/signboard.tscn").instantiate()
	second.position = Vector2(20, 10)
	second.text = "第二块告示牌"
	world.add_child(second)
	world.rebuild()
	world._step_signboards()
	await process_frame
	_check(first._panel.visible and not second._panel.visible, "only touching first sign displays text")
	_check(first._label.text == first.text and first._panel.get_global_transform_with_canvas().origin.y >= 0, "multiline message near the top stays on screen")
	world.player.state.x = 18
	world._step_signboards()
	_check(not first._panel.visible and second._panel.visible, "new overlapping sign immediately replaces previous text")
	world.player.state.x = 26
	world._step_signboards()
	_check(world.active_signboard == second, "remaining within sign keeps message")
	world.player.state.x = 36
	world._step_signboards()
	_check(not first._panel.visible and not second._panel.visible, "leaving hides all text, edge contact is outside")
	world.player.state.x = 10
	world._step_signboards()
	world.rebuild()
	_check(not first._panel.visible and world.active_signboard == null, "rebuild clears message selection")
	await _free_fixture(world)

func _test_room_transition() -> void:
	root.get_node("GameState").reset_run()
	var game = MainScene.instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	var previous = game.world
	previous._unhandled_input(_key(KEY_N))
	previous._unhandled_input(_key(KEY_M))
	await process_frame
	game.world.set_physics_process(false)
	_check(game.world != previous and game.world.scene_file_path == "res://levels/level_02.tscn", "M replaces active room with configured scene")
	_check(game.world.player.has_extinguisher, "equipment survives room replacement")
	_check(not game.world.transitioning and game.world.setup_errors.is_empty(), "new room runs with valid physical layout")
	game.world.doors[0].target_room = "res://levels/level_01.tscn"
	game.world.enter_first_door()
	await process_frame
	game.world.set_physics_process(false)
	_check(game.world.scene_file_path == "res://levels/level_01.tscn", "rooms can point back without circular resource load")
	_check(game.world.player.has_extinguisher, "equipment survives return trip")
	await _free_fixture(game)
	root.get_node("GameState").reset_run()

func _test_standalone_door() -> void:
	root.get_node("GameState").reset_run()
	var scene = load("res://levels/level_01.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_physics_process(false)
	scene._unhandled_input(_key(KEY_N))
	scene._unhandled_input(_key(KEY_M))
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == "res://levels/level_02.tscn", "F6 door changes current scene")
	if current_scene != null:
		current_scene.set_physics_process(false)
		_check(current_scene.player.has_extinguisher, "F6 room transition restores equipment")
		await _free_fixture(current_scene)
	root.get_node("GameState").reset_run()

func _wait_for_restart(previous: Node) -> void:
	var deadline: int = Time.get_ticks_msec() + 2000
	while (current_scene == null or is_instance_valid(previous)) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(current_scene != null and not is_instance_valid(previous), "restart completes within two seconds")


func _test_window_configuration() -> void:
	_check(ProjectSettings.get_setting("display/window/size/viewport_width") == 256, "logical viewport is 256 pixels wide and matches sixteen blocks")
	_check(ProjectSettings.get_setting("display/window/size/viewport_height") == 144, "logical viewport is 144 pixels high")
	_check(ProjectSettings.get_setting("display/window/size/window_width_override") == 1024, "default window is 1024 pixels wide")
	_check(ProjectSettings.get_setting("display/window/size/window_height_override") == 576, "default window is 576 pixels high")
	_check(ProjectSettings.get_setting("display/window/size/resizable", true) == true, "window can be freely resized")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "canvas renders at window resolution without quantizing movement to logical pixels")
	_check(ProjectSettings.get_setting("physics/common/physics_interpolation", false) == true, "render frames interpolate the unchanged physics positions")
	_check(not ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false), "display transforms keep subpixel positions")
	_check(not ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel", false), "display vertices keep subpixel positions")


func _test_level_boundaries() -> void:
	var viewport_width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	for path in ["res://levels/level_01.tscn", "res://levels/level_02.tscn"]:
		var level = load(path).instantiate()
		var background: Sprite2D = level.get_node("Background")
		_check(background.region_rect.size == Vector2(256, 144), "level background matches the logical viewport: " + path)
		_check(background.scale == Vector2.ONE, "background needs no corrective horizontal stretch: " + path)
		_near(background.position.x + background.region_rect.size.x * background.scale.x, viewport_width, "background right edge matches the viewport")
		level.free()
	_near(16.0 * 16.0, viewport_width, "sixteen full-size blocks end exactly on the viewport right edge")


func _test_character_render_geometry() -> void:
	var world = _fixture(Vector2(64, 24), [], Vector2(90, 24))
	var player = world.player
	for direction in [-1, 1]:
		player.direction = direction
		var sprite: Transform2D = player.get_sprite_transform()
		_check(sprite.x == Vector2(direction, 0.0), "Warma's right-facing source follows movement direction")
		var equipment: Transform2D = player.get_equipment_transform()
		var nozzle_center: Vector2 = equipment * Vector2(1.5, 0.5)
		_check(nozzle_center.is_equal_approx(Vector2(5.5 if direction > 0 else -0.5, 2.5)), "black extinguisher nozzle stays next to Warma's face")
		var tank_center: Vector2 = equipment * Vector2(0.5, 2.5)
		_check(tank_center.is_equal_approx(Vector2(4.5 if direction > 0 else 0.5, 4.5)), "extinguisher tank overlaps the matching hand")
		var nozzle: Vector2 = player.get_nozzle_position()
		_check(nozzle.is_equal_approx(Vector2(6.0 if direction > 0 else -1.0, 2.0)), "shot origin is at the outer nozzle edge")
		_near(player.state.x, 64.0, "mirroring never moves the collision rectangle")
		_near(player.state.w, 5.0, "mirroring never changes the collision width")
		var giraffe = world.actors[1]
		giraffe.direction = direction
		_check(giraffe.get_sprite_transform().x == Vector2(-direction, 0.0), "Giraffe retains its left-facing source convention")
	_safe(world)
	await _free_fixture(world)


func _test_continuous_visual_motion() -> void:
	var world = _fixture(Vector2(16, 16))
	_check(world.player.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "pixel art remains nearest-filtered")
	_check(world.player.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_INHERIT, "Warma inherits display interpolation without changing solver authority")
	Input.action_press("move_right")
	for frame in range(11):
		var before: float = world.player.state.x
		world._physics_process(DT)
		_near(world.player.state.x - before, world.player.move_speed * DT, "solver retains every fractional horizontal step")
		_near(world.player.position.x, world.player.state.x, "visual sync preserves the fractional solver coordinate")
	_check(not is_equal_approx(world.player.position.x, roundf(world.player.position.x)), "movement is not rounded back to whole logical pixels")
	_safe(world)
	await _free_fixture(world)


func _test_rebuild_interpolation_reset() -> void:
	var world = WorldScript.new()
	var player = InterpolationWarma.new()
	player.kind = "warma"
	player.fixed = false
	player.body_width = 5.0
	player.body_height = 16.0
	player.position = Vector2(64, 24)
	world.add_child(player)
	root.add_child(world)
	world.set_physics_process(false)
	_check(player.interpolation_resets > 0, "initial registration resets display interpolation")
	var resets: int = player.interpolation_resets
	player.position = Vector2(100, 40)
	world.rebuild()
	_check(player.interpolation_resets > resets, "rebuilding a teleported actor resets its interpolation history")
	_near(player.state.x, 100.0, "rebuild starts physics at the authored horizontal position")
	_near(player.state.y, 40.0, "rebuild starts physics at the authored vertical position")
	_safe(world)
	await _free_fixture(world)


func _test_main_scene() -> void:
	var game = MainScene.instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	var world = game.world
	_check(world.player != null, "game entry has a real player")
	_check(not world.player.has_extinguisher, "new run starts without an extinguisher")
	_near(world.player.state.w, 5.0, "Warma collision width is exactly 5")
	_near(world.player.state.h, 16.0, "Warma collision height is exactly 16")
	_check(world.player.WARMA_TEXTURE.get_size() == Vector2(6, 17), "Warma uses the supplied 6 by 17 texture")
	_safe(world)
	# The opening room teaches walking and jumping; giraffes start in room 2.
	game._switch_room("res://levels/level_02.tscn")
	game.world.set_physics_process(false)
	world = game.world
	var giraffe_count: int = 0
	for actor in world.actors:
		if actor.kind == "giraffe":
			giraffe_count += 1
			_near(actor.state.w, 8.0, "Giraffe collision width is exactly 8")
			_near(actor.state.h, 16.0, "Giraffe collision height is exactly 16")
			_check(actor.GIRAFFE_TEXTURE.get_size() == Vector2(9, 16), "Giraffe uses the supplied 9 by 16 texture")
	_check(giraffe_count > 0, "second level includes a Giraffe")
	_safe(world)
	await _free_fixture(game)


func _test_unequipped_shooting() -> void:
	var world = _fixture(Vector2(16, 16))
	world.fire()
	_check(world.bullets.is_empty(), "direct fire is blocked before pickup")
	Input.action_press("shoot")
	world._physics_process(DT)
	_check(world.bullets.is_empty(), "K is blocked before pickup through the live controller")
	_check(not world.player.has_extinguisher, "shooting cannot grant equipment")
	_safe(world)
	await _free_fixture(world)


func _test_starter_pickup_reachable() -> void:
	var game = MainScene.instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	# The pickup is injected so the walking path stays independent of the level's
	# authored decorations; only the real controller and collect flow are tested.
	var pickup = PickupScene.instantiate()
	pickup.position = Vector2(40, 120)
	game.world.add_child(pickup)
	game.world.rebuild()
	Input.action_press("move_right")
	for frame in range(100):
		game.world._physics_process(DT)
	_check(game.world.player.has_extinguisher, "starter pickup is reachable through ordinary player movement")
	_check(game.world.pickups.is_empty(), "walking through the pickup consumes it")
	_check(not game.world.frozen, "pickup path leaves the game playable")
	_safe(game.world)
	await _free_fixture(game)
	root.get_node("GameState").reset_run()


func _test_pickup_and_keyboard_shooting() -> void:
	var world = _fixture(Vector2(22, 16), [Vector2(24, 24)])
	var state = world.player.state
	state.vy = 37.0
	var body_count: int = world.solver.bodies.size()
	equipment_changes = 0
	world.player.extinguisher_changed.connect(_equipment_changed)
	world._step_pickups()
	_check(world.player.has_extinguisher, "overlapping pickup equips Warma")
	_check(equipment_changes == 1, "first acquisition emits one equipment change")
	_check(world.pickups.is_empty(), "acquired pickup leaves the world pickup list")
	_check(world.solver.bodies.size() == body_count, "pickup never enters the solid solver")
	_near(state.vy, 37.0, "acquisition does not change vertical velocity")
	_near(state.x, 22.0, "acquisition does not change horizontal position")
	_near(state.y, 16.0, "acquisition does not change vertical position")
	Input.action_press("shoot")
	world._unhandled_input(_key(KEY_K))
	world._physics_process(DT)
	_check(world.bullets.size() == 1, "K fires through the live controller after pickup")
	_safe(world)
	await _free_fixture(world)


func _test_bullet_directions() -> void:
	for direction in [-1, 1]:
		var world = _fixture(Vector2(64, 24), [], Vector2(40 if direction < 0 else 90, 24))
		var giraffe = world.actors[1]
		giraffe.state.vy = 37.0
		world.player.pick_up_extinguisher()
		world.player.direction = direction
		world.fire()
		_check(world.bullets.size() == 1, "equipped player creates one bullet")
		if not world.bullets.is_empty():
			var bullet = world.bullets[0]
			_check(bullet.direction == direction, "bullet follows player facing")
			var expected_x: float = 70.0 if direction > 0 else 60.0
			_near(bullet.position.x, expected_x, "bullet starts outside the matching extinguisher nozzle")
			_near(bullet.position.y, 26.0, "bullet starts at the actual nozzle height")
		# Allow the slower default projectile to reach either target.
		world._step_bullets(1.0, {})
		_check(giraffe.move_direction == direction, "Giraffe follows the received bullet direction")
		_near(giraffe.state.vy, 37.0, "bullet does not modify Giraffe vertical velocity")
		_check(world.hits == 1 and world.bullets.is_empty(), "one impact counts once and consumes its bullet")
		_safe(world)
		await _free_fixture(world)

func _test_unrestricted_fire() -> void:
	var world = _fixture(Vector2(16, 16))
	world.player.pick_up_extinguisher()
	for shot in range(5):
		Input.action_press("shoot")
		world._unhandled_input(_key(KEY_K))
		world._physics_process(DT)
		_check(world.bullets.size() == shot + 1, "each fresh press fires without waiting for a cooldown")
		Input.action_release("shoot")
		await process_frame
		world._physics_process(DT)
		_check(world.bullets.size() == shot + 1, "released K does not create more shots")
	_safe(world)
	await _free_fixture(world)


func _test_held_fire() -> void:
	var world = _fixture(Vector2(16, 16))
	world.player.pick_up_extinguisher()
	Input.action_press("shoot")
	world._unhandled_input(_key(KEY_K))
	for shot in range(10):
		world._unhandled_input(_key(KEY_K, true))
		world._physics_process(DT)
		_check(world.bullets.size() == 1, "held K and key echo never repeat the initial shot")
		await process_frame
	Input.action_release("shoot")
	world._physics_process(DT)
	_check(world.bullets.size() == 1, "releasing K does not fire")
	_safe(world)
	await _free_fixture(world)

func _test_time_speed() -> void:
	var world = _fixture(Vector2(16, 16))
	var run_state := root.get_node("GameState")
	_near(Engine.time_scale, 1.0, "session starts at normal speed")
	_check(world._time_speed_label.text == "x1", "HUD displays the default speed")
	world._unhandled_input(_key(KEY_RIGHT))
	_near(Engine.time_scale, 1.0, "right at maximum speed does nothing")
	world._unhandled_input(_key(KEY_LEFT, true))
	_near(Engine.time_scale, 1.0, "key echo does not change speed")
	var release := _key(KEY_LEFT)
	release.pressed = false
	world._unhandled_input(release)
	_near(Engine.time_scale, 1.0, "key release does not change speed")
	for speed in [0.5, 0.2, 0.1]:
		world._unhandled_input(_key(KEY_LEFT))
		_near(Engine.time_scale, speed, "left reduces speed by exactly one step")
		_check(world._time_speed_label.text == "x%s" % str(speed), "HUD immediately displays the new speed")
	world._unhandled_input(_key(KEY_LEFT))
	_near(Engine.time_scale, 0.1, "left at minimum speed does nothing")
	for speed in [0.2, 0.5, 1.0]:
		world._unhandled_input(_key(KEY_RIGHT))
		_near(Engine.time_scale, speed, "right increases speed by exactly one step")
	world.frozen = true
	world._unhandled_input(_key(KEY_LEFT))
	_near(Engine.time_scale, 0.5, "speed can be selected while paused")
	run_state.reset_run()
	_near(Engine.time_scale, 0.5, "restart preserves selected session speed")
	await _free_fixture(world)
	var game = MainScene.instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	_check(game.world._time_speed_label.text == "x0.5", "new room restores selected speed in its HUD")
	game._switch_room("res://levels/level_02.tscn")
	game.world.set_physics_process(false)
	_check(game.world._time_speed_label.text == "x0.5", "room replacement retains the speed display")
	_near(Engine.time_scale, 0.5, "room replacement retains the time scale")
	game.world._unhandled_input(_key(KEY_RIGHT))
	await _free_fixture(game)


func _test_scaled_simulation() -> void:
	var world = TickingWorld.new()
	var player = WarmaScene.instantiate()
	player.position = Vector2(16, 16)
	world.add_child(player)
	root.add_child(world)
	world.set_physics_process(false)
	player.pick_up_extinguisher()
	world.fire()
	var bullet = world.bullets[0]
	var run_state := root.get_node("GameState")
	Input.action_press("move_right")
	for speed in [1.0, 0.5, 0.2, 0.1]:
		if speed < 1.0:
			run_state.change_time_speed(-1)
		world.tick_deltas.clear()
		var player_x: float = player.state.x
		var player_vy: float = player.state.vy
		var bullet_x: float = bullet.position.x
		var lifetime: float = bullet.lifetime
		world.set_physics_process(true)
		for frame in range(4):
			await physics_frame
		await process_frame
		world.set_physics_process(false)
		_check(not world.tick_deltas.is_empty(), "real simulation receives physics updates")
		var elapsed := 0.0
		for delta in world.tick_deltas:
			_near(delta, DT * speed, "engine scales each real physics tick to the selected speed")
			elapsed += delta
		_near(player.state.x - player_x, player.move_speed * elapsed, "player movement follows scaled game time")
		_near(player.state.vy - player_vy, world.GRAVITY * elapsed, "gravity follows scaled game time")
		# Node2D positions are float32 vectors; allow their rounding error.
		_check(absf(bullet.position.x - bullet_x - bullet.speed * elapsed) < 0.0001, "bullet movement follows scaled game time")
		_near(lifetime - bullet.lifetime, elapsed, "bullet expiry follows scaled game time")
	for step in range(3):
		run_state.change_time_speed(1)
	_safe(world)
	await _free_fixture(world)


func _test_giraffe_cannot_collect() -> void:
	var world = _fixture(Vector2(0, 16), [Vector2(36, 24)], Vector2(32, 16))
	var pickup = world.pickups[0]
	_check(not pickup.collect(world.actors[1]), "Giraffe cannot directly collect an extinguisher")
	world._step_pickups()
	_check(world.pickups.size() == 1, "overlapping Giraffe leaves the pickup available")
	_check(not world.player.has_extinguisher, "distant Warma is not equipped by Giraffe contact")
	_safe(world)
	await _free_fixture(world)


func _test_duplicate_pickups() -> void:
	var world = _fixture(Vector2(22, 16), [Vector2(24, 24), Vector2(24, 24)])
	equipment_changes = 0
	world.player.extinguisher_changed.connect(_equipment_changed)
	world._step_pickups()
	_check(world.player.has_extinguisher, "duplicate pickups retain equipped state")
	_check(world.pickups.is_empty(), "all duplicate pickups are removed")
	_check(equipment_changes == 1, "duplicate acquisition does not repeat state-change signals")
	world._step_pickups()
	_check(equipment_changes == 1, "rechecking consumed pickups has no extra state change")
	_safe(world)
	await _free_fixture(world)


func _test_rebuild_consumed_pickup() -> void:
	var world = _fixture(Vector2(22, 16), [Vector2(24, 24)])
	world._step_pickups()
	world.rebuild()
	_check(world.pickups.is_empty(), "rebuild does not re-register a queued consumed pickup")
	_check(world.player.has_extinguisher, "rebuild preserves player equipment")
	await process_frame
	world.rebuild()
	_check(world.pickups.is_empty(), "rebuild does not recreate a freed pickup")
	_safe(world)
	await _free_fixture(world)


func _test_nested_pickup_coordinates() -> void:
	var world = WorldScript.new()
	world.position = Vector2(123, 87)
	world.scale = Vector2(4, 4)
	var group := Node2D.new()
	group.position = Vector2(40, 12)
	var nested := Node2D.new()
	nested.position = Vector2(8, 4)
	var pickup = PickupScene.instantiate()
	pickup.position = Vector2(16, 8)
	var player = WarmaScene.instantiate()
	player.position = Vector2(62, 16)
	nested.add_child(pickup)
	group.add_child(nested)
	world.add_child(group)
	world.add_child(player)
	root.add_child(world)
	world.set_physics_process(false)
	var rect: Rect2 = pickup.get_world_rect(world)
	_check(rect.position == Vector2(60, 20), "pickup includes nested offsets in authority coordinates")
	_check(rect.size == Vector2(8, 8), "display scale does not enlarge pickup authority rectangle")
	world._step_pickups()
	_check(player.has_extinguisher, "nested pickup meets the world-local player rectangle")
	_safe(world)
	await _free_fixture(world)


func _test_pickup_edges() -> void:
	var world = _fixture(Vector2(15, 16), [Vector2(24, 24)])
	world._step_pickups()
	_check(not world.player.has_extinguisher and world.pickups.size() == 1, "zero-width edge touching is not an acquisition")
	world.player.state.x += 0.01
	world._step_pickups()
	_check(world.player.has_extinguisher and world.pickups.is_empty(), "positive rectangle overlap acquires the pickup")
	_safe(world)
	await _free_fixture(world)


func _test_run_equipment_persistence() -> void:
	var game = MainScene.instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	game.world.player.pick_up_extinguisher()
	_check(root.get_node("GameState").has_extinguisher, "game entry persists acquired equipment for the run")
	await _free_fixture(game)
	game = MainScene.instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	_check(game.world.player.has_extinguisher, "a following level entry inherits the run equipment")
	current_scene = game
	var restart := InputEventKey.new()
	restart.physical_keycode = KEY_R
	restart.pressed = true
	var previous = game.world
	game._unhandled_input(restart)
	_check(game.world.restarting and game.world.frozen, "R freezes the world for the death flash")
	_check(not game.world.player.visible, "R starts with the player hidden for a blink")
	_check(current_scene == game, "R waits for the flash before reloading")
	game._unhandled_input(restart)
	await _wait_for_restart(previous)
	_check(current_scene == game, "R keeps the game host")
	_check(current_scene != null, "R reloads a playable game scene")
	if current_scene != null:
		current_scene.world.set_physics_process(false)
		_check(root.get_node("GameState").has_extinguisher, "R preserves the run equipment")
		_check(current_scene.world.player.has_extinguisher, "restarted player retains the extinguisher")
		_check(current_scene.world.bullets.is_empty(), "R reloads without stale bullets")
		current_scene.world.fire()
		_check(current_scene.world.bullets.size() == 1, "player can fire immediately after R")
		await _free_fixture(current_scene)


func _test_fall_restart() -> void:
	var game = MainScene.instantiate()
	root.add_child(game)
	current_scene = game
	var world = game.world
	world.set_physics_process(false)
	var actor_count: int = world.actors.size()
	var authored_x: float = world.player.state.x
	world.player.pick_up_extinguisher()
	world.player.state.x = 300.0
	world.player.state.y = world.fall_limit - world.player.state.h
	world.fire()
	world._physics_process(DT)
	_check(world.restarting and world.frozen, "falling below the limit starts the guarded restart")
	_check(not world.player.visible, "fall death blinks the player before reload")
	var old_position := Vector2(world.player.state.x, world.player.state.y)
	var old_bullets: int = world.bullets.size()
	Input.action_press("move_right")
	Input.action_press("shoot")
	world._physics_process(DT)
	world.fire()
	_check(Vector2(world.player.state.x, world.player.state.y) == old_position, "death freezes movement")
	_check(world.bullets.size() == old_bullets, "death blocks shooting")
	Input.action_release("move_right")
	Input.action_release("shoot")
	world.request_restart()
	await _wait_for_restart(world)
	if current_scene != null:
		current_scene.world.set_physics_process(false)
		_near(current_scene.world.player.state.x, authored_x, "fall restores the authored spawn")
		_check(current_scene.world.player.has_extinguisher, "fall preserves equipment like R")
		_check(root.get_node("GameState").has_extinguisher, "fall preserves run state like R")
		_check(current_scene.world.bullets.is_empty(), "fall removes old bullets")
		_check(current_scene.world.actors.size() == actor_count, "fall restores the level actors")
		_check(not current_scene.world.restarting and not current_scene.world.frozen, "restarted game is playable")
		await _free_fixture(current_scene)


func _test_fall_restart_current_room() -> void:
	await _test_restart_current_room("fall")


func _test_key_restart_current_room() -> void:
	await _test_restart_current_room("R")


func _test_restart_current_room(trigger: String) -> void:
	var game = MainScene.instantiate()
	game.child_entered_tree.connect(func(room: Node): room.set_physics_process(false))
	root.add_child(game)
	current_scene = game
	for path in ["res://levels/level_02.tscn", "res://levels/level_04.tscn", "res://levels/level_16.tscn"]:
		game.world.request_room(path)
		await process_frame
		_check(game.world.scene_file_path == path, "enter room before testing " + trigger + ": " + path)
		var spawn := Vector2(game.world.player.state.x, game.world.player.state.y)
		for attempt in range(2):
			var previous = game.world
			previous.grant_extinguisher()
			previous.fire()
			previous.player.state.x = 300.0
			previous.player.state.y = previous.fall_limit
			if trigger == "fall":
				previous._physics_process(DT)
			else:
				game._unhandled_input(_key(KEY_R))
				_check(previous.restarting and previous.frozen, "R freezes the current room")
				game._unhandled_input(_key(KEY_R))
			await _wait_for_restart(previous)
			_check(current_scene == game, trigger + " keeps the game host")
			_check(game.world.scene_file_path == path, trigger + " keeps the current room: " + path)
			_near(game.world.player.state.x, spawn.x, trigger + " restores current room spawn X")
			_near(game.world.player.state.y, spawn.y, trigger + " restores current room spawn Y")
			_check(not game.world.restarting and not game.world.frozen, "room is playable after repeated " + trigger)
			_check(game.world.player.has_extinguisher, "current room restart preserves equipment")
			_check(root.get_node("GameState").has_extinguisher, "current room restart preserves run equipment")
			_check(game.world.bullets.is_empty(), "current room restart removes stale bullets")
	await _free_fixture(game)


func _test_standalone_restart() -> void:
	for trigger in ["fall", "R"]:
		var level = load("res://levels/level_01.tscn").instantiate()
		root.add_child(level)
		current_scene = level
		level.set_physics_process(false)
		level.player.pick_up_extinguisher()
		if trigger == "fall":
			level.player.state.x = 300.0
			level.player.state.y = level.fall_limit
			level._physics_process(DT)
		else:
			var restart := InputEventKey.new()
			restart.physical_keycode = KEY_R
			restart.pressed = true
			level._unhandled_input(restart)
		_check(level.restarting, "standalone F6 level handles " + trigger)
		await _wait_for_restart(level)
		if current_scene != null:
			current_scene.set_physics_process(false)
			_check(current_scene.player != null and not current_scene.frozen, "F6 level restarts playable")
			_check(current_scene.player.has_extinguisher, "F6 reload retains acquired equipment")
			_check(root.get_node("GameState").has_extinguisher, "F6 restart persists acquired equipment")
			current_scene.fire()
			_check(current_scene.bullets.size() == 1, "F6 player can fire after restart")
			await _free_fixture(current_scene)


func _test_unequipped_restart() -> void:
	for path in ["res://main.tscn", "res://levels/level_01.tscn"]:
		root.get_node("GameState").reset_run()
		var scene = load(path).instantiate()
		root.add_child(scene)
		current_scene = scene
		var world = scene.world if path == "res://main.tscn" else scene
		world.set_physics_process(false)
		_check(not world.player.has_extinguisher, "fresh player starts unequipped")
		scene._unhandled_input(_key(KEY_R))
		await _wait_for_restart(world)
		var restored = current_scene.world if path == "res://main.tscn" else current_scene
		restored.set_physics_process(false)
		_check(not restored.player.has_extinguisher, "R does not grant an uncollected extinguisher")
		_check(not root.get_node("GameState").has_extinguisher, "unequipped R keeps session unequipped")
		await _free_fixture(current_scene)


func _test_fall_limit_boundary() -> void:
	var world = _fixture(Vector2(300, 20))
	world.fall_limit = 60.0
	world.player.state.y = 60.0 - world.player.state.h - 0.1
	world._physics_process(DT)
	_check(not world.restarting, "feet above a custom death line remain alive")
	world.player.state.y = 60.0 - world.player.state.h
	world._physics_process(DT)
	_check(world.restarting, "feet reaching a custom death line trigger death")
	await _free_fixture(world)
