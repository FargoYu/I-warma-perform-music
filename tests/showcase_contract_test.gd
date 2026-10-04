extends SceneTree
## Contract / integration checks for the generated Showcase rooms.
## Run: godot --headless --path . --script res://tests/showcase_contract_test.gd
##
## Covers, in order:
##   1. every rooms/showcase/*.tscn loads and honors the scene contract
##   2. every showcase room is reachable from showcase_hub via next_room doors
##   3. a real W-door transition loop hub -> foundation_index -> fnd_movement -> back
##   4. reset_scene() restores the authored spawn in every room
##   5. instanced lifts own independent CollisionShape2D shape resources
##   6. pickup collection / reset_scene GameState hygiene in cmb_pickup_a
##   7. a natural pit fall in fnd_death_reset dies and reloads to the spawn
##   8. freeze_for_death must stop elevators during the death animation
##
## If no showcase room can be instantiated at all, TESTS 3-7 are reported as
## explicitly BLOCKED (one failure each) instead of cascading dozens of
## identical scene-change failures, and TEST 8 falls back to probing the same
## freeze contract in a runtime-assembled room built from the real
## rooms/room.gd + objects/elevator_up.tscn + objects/warma.tscn.
##
## Timing facts (120 physics ticks per second; one _tick() = one physics step):
##   - lift growth: height_speed px/s (fnd_button Lift1: 12 px/s => 0.1px/tick)

const SHOWCASE_DIR := "res://rooms/showcase"
const HUB_ROOM := "res://rooms/showcase/showcase_hub.tscn"
const ROOM_SCRIPT_PATH := "res://rooms/room.gd"
const DOOR_SCRIPT_PATH := "res://objects/door.gd"
const MIN_ROOM_COUNT := 35
const PIT_TELEPORT := Vector2(180, 120) # above the fnd_death_reset pit (x 160..208)
const SCENE_WAIT_TIMEOUT := 10.0

var failures: Array[String] = []
var scene_changes := 0
var game_state: Node
var state_instance_id := 0
var saved_has_extinguisher := false

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

func _send_w(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.keycode = KEY_W
	event.pressed = pressed
	Input.parse_input_event(event)

func _on_scene_changed() -> void:
	scene_changes += 1

## Waits for the next scene change; returns false once `timeout` seconds pass.
## Polling instead of a bare `await scene_changed` keeps a missing transition a
## reported failure instead of a hung run.
func _wait_scene_changed(timeout: float = SCENE_WAIT_TIMEOUT) -> bool:
	var before := scene_changes
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if scene_changes > before:
			return true
	return false

func _showcase_paths() -> Array[String]:
	var paths: Array[String] = []
	var file_names := DirAccess.get_files_at(SHOWCASE_DIR)
	if file_names == null:
		_check(false, "DirAccess could not list %s (error %d)" % [SHOWCASE_DIR, DirAccess.get_open_error()])
		return paths
	for file_name in file_names:
		if file_name.ends_with(".tscn"):
			paths.append(SHOWCASE_DIR + "/" + file_name)
	paths.sort()
	return paths

## Doors are matched by script, not by node name: navigation rooms instance up
## to seven door.tscn copies that all carry the authored name "Door".
func _doors_of(room: Node) -> Array[Area2D]:
	var result: Array[Area2D] = []
	for node in room.find_children("*", "Area2D", true, false):
		var script := (node as Node).get_script() as Script
		if script != null and script.resource_path == DOOR_SCRIPT_PATH:
			result.append(node as Area2D)
	return result

func _door_to(room: Node, target_name: String) -> Area2D:
	var wanted := target_name if target_name.begins_with("res://") else "%s/%s.tscn" % [SHOWCASE_DIR, target_name]
	for door in _doors_of(room):
		if String(door.get("next_room")) == wanted:
			return door
	return null

func _load_room(path: String) -> bool:
	var error := change_scene_to_file(path)
	_check(error == OK, "change_scene_to_file failed for %s: %s" % [path, error_string(error)])
	if error != OK:
		return false
	var changed := await _wait_scene_changed()
	if not changed:
		_check(false, "Timed out waiting for the scene change to %s" % path)
		return false
	await _tick(2)
	var active: String = current_scene.scene_file_path if current_scene != null else "<null>"
	var ok := current_scene != null and current_scene.scene_file_path == path
	_check(ok, "Expected the active room to be %s, got %s" % [path, active])
	return ok

func _begin(label: String) -> int:
	print("--- %s" % label)
	return failures.size()

func _end(label: String, mark: int) -> void:
	var added := failures.size() - mark
	print("    %s: %s" % [label, "PASS" if added == 0 else "FAIL (%d)" % added])

## Counts how many showcase rooms survive PackedScene.instantiate(). A room
## whose scene file is malformed fails here without ever entering the tree.
func _count_instantiable(paths: Array[String]) -> int:
	var ok_count := 0
	for path in paths:
		var packed := load(path) as PackedScene
		if packed != null and packed.instantiate() != null:
			ok_count += 1
	return ok_count

# --------------------------------------------------------------------- TEST 1

func _test_all_rooms_load(paths: Array[String]) -> void:
	var mark := _begin("TEST 1: every showcase room loads and honors the scene contract")
	_check(paths.size() >= MIN_ROOM_COUNT,
		"Showcase must ship at least %d rooms, found %d" % [MIN_ROOM_COUNT, paths.size()])
	var before := scene_changes
	for path in paths:
		var packed := load(path) as PackedScene
		_check(packed != null, "Could not load %s" % path)
		if packed == null:
			continue
		var room := packed.instantiate()
		_check(room != null, "Could not instantiate %s" % path)
		if room == null:
			continue
		root.add_child(room)
		await _tick(2)
		var script := room.get_script() as Script
		var script_path: String = script.resource_path if script != null else "<none>"
		_check(script != null and script_path == ROOM_SCRIPT_PATH,
			"%s root must run rooms/room.gd, got %s" % [path, script_path])
		var player := room.get_node_or_null("Player") as CharacterBody2D
		_check(player != null, "%s must contain a Player" % path)
		if player != null:
			_check(player.is_in_group("player"), "%s Player must join the 'player' group" % path)
			var pos := player.global_position
			_check(pos.x >= 0.0 and pos.x <= 256.0 and pos.y >= 0.0 and pos.y <= 144.0,
				"%s Player spawn %s must sit inside the 256x144 view" % [path, pos])
		for node_name in ["Background", "HUD", "EntryText"]:
			_check(room.get_node_or_null(node_name) != null, "%s must contain a %s node" % [path, node_name])
		var doors := _doors_of(room)
		_check(not doors.is_empty(), "%s must contain at least one Door" % path)
		var door_names := {}
		for door in doors:
			door_names[door.name] = true
		_check(door_names.size() == doors.size(),
			"%s doors must have unique node names: with a repeated name the PackedScene loader leaves every door but the last unregistered in the physics space, so those doors never detect the player and cannot be entered" % path)
		for door in doors:
			var next_room := String(door.get("next_room"))
			_check(not next_room.is_empty(), "%s has a Door without a next_room target" % path)
			if not next_room.is_empty():
				_check(FileAccess.file_exists(next_room),
					"%s Door target '%s' must exist on disk" % [path, next_room])
		_check(not room.find_children("*", "StaticBody2D", true, false).is_empty(),
			"%s must contain at least one terrain Block" % path)
		_check(scene_changes == before, "%s must not switch scenes while being loaded" % path)
		room.queue_free()
		await _tick(1)
	_end("TEST 1", mark)

# --------------------------------------------------------------------- TEST 2

func _test_hub_reachability(paths: Array[String]) -> void:
	var mark := _begin("TEST 2: every showcase room is reachable from showcase_hub")
	_check(FileAccess.file_exists(HUB_ROOM), "Hub room must exist at %s" % HUB_ROOM)
	_check(paths.has(HUB_ROOM), "Hub must be part of the showcase room set")
	var regex := RegEx.create_from_string("next_room\\s*=\\s*\"([^\"]+)\"")
	var targets_by_room := {}
	for path in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		_check(file != null, "Could not read %s" % path)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		var targets: Array[String] = []
		for found in regex.search_all(text):
			var target := found.get_string(1)
			_check(FileAccess.file_exists(target),
				"%s declares door target '%s' which does not exist on disk" % [path, target])
			targets.append(target)
		_check(not targets.is_empty(), "%s must declare at least one door target" % path)
		targets_by_room[path] = targets
	var visited := {HUB_ROOM: true}
	var queue: Array[String] = [HUB_ROOM]
	while not queue.is_empty():
		var current: String = queue.pop_back()
		for target_variant in targets_by_room.get(current, []):
			var target := String(target_variant)
			if not visited.has(target) and paths.has(target):
				visited[target] = true
				queue.append(target)
	for path in paths:
		_check(visited.has(path), "Showcase room %s is unreachable from showcase_hub" % path)
	_end("TEST 2", mark)

# --------------------------------------------------------------------- TEST 3

func _test_w_transition_loop() -> void:
	var mark := _begin("TEST 3: W-door loop hub -> foundation_index -> fnd_movement -> back")
	var stops: Array[String] = ["foundation_index", "fnd_movement", "foundation_index", "showcase_hub"]
	if not await _load_room(HUB_ROOM):
		_end("TEST 3", mark)
		return
	for stop in stops:
		if current_scene == null:
			_check(false, "TEST 3 aborted: no active room")
			break
		var door := _door_to(current_scene, stop)
		_check(door != null, "%s must contain a door to %s" % [current_scene.scene_file_path, stop])
		if door == null:
			break
		var player := current_scene.get_node_or_null("Player") as CharacterBody2D
		_check(player != null, "%s must contain a Player" % current_scene.scene_file_path)
		if player == null:
			break
		player.set_physics_process(false)
		player.global_position = door.global_position
		player.velocity = Vector2.ZERO
		await _tick(3)
		_check(bool(door.get("player_inside")), "Player must stand inside the door to %s" % stop)
		var before := scene_changes
		_send_w(true)
		var changed := await _wait_scene_changed()
		_send_w(false)
		if not changed:
			_check(false, "Timed out waiting for the W transition into %s" % stop)
			break
		await _tick(2)
		_check(scene_changes == before + 1, "The W entry into %s must change rooms exactly once" % stop)
		var expected := stop if stop.begins_with("res://") else "%s/%s.tscn" % [SHOWCASE_DIR, stop]
		var active: String = current_scene.scene_file_path if current_scene != null else "<null>"
		_check(active == expected, "After the W entry the active room must be %s, got %s" % [expected, active])
		_check(game_state != null and game_state.get_instance_id() == state_instance_id,
			"The GameState autoload must survive the transition into %s" % stop)
		_check(game_state != null and not bool(game_state.get("has_extinguisher")),
			"The transition into %s must not grant an extinguisher" % stop)
	_end("TEST 3", mark)

# --------------------------------------------------------------------- TEST 4

func _test_reset_restores_spawn(paths: Array[String]) -> void:
	var mark := _begin("TEST 4: reset_scene restores the authored spawn in every room")
	for path in paths:
		if not await _load_room(path):
			continue
		var room := current_scene
		var player := room.get_node_or_null("Player") as CharacterBody2D
		if player == null:
			_check(false, "%s must contain a Player to exercise reset_scene" % path)
			continue
		var spawn := player.global_position
		player.global_position = Vector2(200, 100)
		player.velocity = Vector2.ZERO
		await _tick(3)
		if current_scene != room:
			_check(false, "%s must survive a teleport to (200,100) before the reset" % path)
			continue
		room.call("reset_scene")
		var changed := await _wait_scene_changed()
		if not changed:
			_check(false, "%s reset_scene must reload the room" % path)
			continue
		await _tick(2)
		var active: String = current_scene.scene_file_path if current_scene != null else "<null>"
		_check(active == path, "Reset of %s must reload the same room, got %s" % [path, active])
		var fresh: CharacterBody2D = null
		if current_scene != null:
			fresh = current_scene.get_node_or_null("Player") as CharacterBody2D
		if fresh == null:
			_check(false, "Reloaded %s must contain a Player" % path)
			continue
		var drift := fresh.global_position.distance_to(spawn)
		_check(drift < 0.1,
			"Reset of %s must restore the spawn %s, got %s (drift %.3fpx)" % [path, spawn, fresh.global_position, drift])
	_end("TEST 4", mark)

# --------------------------------------------------------------------- TEST 5

func _test_lift_shape_isolation() -> void:
	var mark := _begin("TEST 5: instanced lifts must not share one shape resource")
	var probes := [
		["res://rooms/showcase/trt_elevator.tscn", "LiftA", "LiftB"],
		["res://rooms/showcase/elv_up.tscn", "Lift1", "Lift2"],
	]
	for probe in probes:
		var path: String = probe[0]
		if not await _load_room(path):
			continue
		var first := current_scene.get_node_or_null(String(probe[1])) as AnimatableBody2D
		var second := current_scene.get_node_or_null(String(probe[2])) as AnimatableBody2D
		_check(first != null and second != null, "%s must contain lifts %s and %s" % [path, probe[1], probe[2]])
		if first == null or second == null:
			continue
		var first_collision := first.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var second_collision := second.get_node_or_null("CollisionShape2D") as CollisionShape2D
		_check(first_collision != null and second_collision != null,
			"%s: %s and %s must own a CollisionShape2D" % [path, probe[1], probe[2]])
		if first_collision == null or second_collision == null:
			continue
		var first_shape := first_collision.shape
		var second_shape := second_collision.shape
		_check(first_shape != null and second_shape != null,
			"%s: %s and %s must own a shape resource" % [path, probe[1], probe[2]])
		if first_shape == null or second_shape == null:
			continue
		_check(first_shape.get_instance_id() != second_shape.get_instance_id(),
			"%s: %s and %s share one RectangleShape2D resource; elevator.gd _ready must duplicate it per instance" % [path, probe[1], probe[2]])
	_end("TEST 5", mark)

# --------------------------------------------------------------------- TEST 6

func _test_game_state_hygiene() -> void:
	var mark := _begin("TEST 6: pickup collection and reset_scene GameState hygiene")
	if not await _load_room("res://rooms/showcase/cmb_pickup_a.tscn"):
		_end("TEST 6", mark)
		return
	var room := current_scene
	var pickup := room.get_node_or_null("ExtinguisherPickup") as Area2D
	_check(pickup != null, "cmb_pickup_a must ship an ExtinguisherPickup")
	var player := room.get_node_or_null("Player") as CharacterBody2D
	_check(player != null, "cmb_pickup_a must contain a Player")
	if pickup == null or player == null:
		_end("TEST 6", mark)
		return
	player.global_position = pickup.global_position
	player.velocity = Vector2.ZERO
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")),
		"Overlapping the pickup must set GameState.has_extinguisher")
	_check(not is_instance_valid(pickup), "The collected pickup must be freed")
	_check(not room.has_node("ExtinguisherPickup"), "The collected pickup must leave the room tree")
	room.call("reset_scene")
	var changed := await _wait_scene_changed()
	if not changed:
		_check(false, "cmb_pickup_a reset_scene must reload the room")
		_end("TEST 6", mark)
		return
	await _tick(2)
	var active: String = current_scene.scene_file_path if current_scene != null else "<null>"
	_check(active == "res://rooms/showcase/cmb_pickup_a.tscn",
		"Reset must reload cmb_pickup_a, got %s" % active)
	_check(not bool(game_state.get("has_extinguisher")),
		"Reset must restore the entry-time GameState.has_extinguisher (false)")
	if current_scene != null:
		_check(current_scene.has_node("ExtinguisherPickup"), "Reset must respawn the ExtinguisherPickup")
	_end("TEST 6", mark)

# --------------------------------------------------------------------- TEST 7

func _test_pit_death_reset() -> void:
	var mark := _begin("TEST 7: a natural pit fall in fnd_death_reset reloads to the spawn")
	if not await _load_room("res://rooms/showcase/fnd_death_reset.tscn"):
		_end("TEST 7", mark)
		return
	var room := current_scene
	var player := room.get_node_or_null("Player") as CharacterBody2D
	_check(player != null, "fnd_death_reset must contain a Player")
	if player == null:
		_end("TEST 7", mark)
		return
	var spawn := player.global_position
	player.set("death_flash_duration", 0.04)
	player.global_position = PIT_TELEPORT
	player.velocity = Vector2.ZERO
	var before := scene_changes
	var changed := await _wait_scene_changed(15.0)
	if not changed:
		_check(bool(player.get("_dying")) if is_instance_valid(player) else false,
			"Falling into the pit must reach the death sequence")
		_check(scene_changes > before,
			"The pit fall must reload fnd_death_reset (no scene change within 15s)")
		_end("TEST 7", mark)
		return
	await _tick(2)
	_check(scene_changes == before + 1, "The pit fall must reload the room exactly once")
	var active: String = current_scene.scene_file_path if current_scene != null else "<null>"
	_check(active == "res://rooms/showcase/fnd_death_reset.tscn",
		"The death reset must reload fnd_death_reset, got %s" % active)
	var fresh: CharacterBody2D = null
	if current_scene != null:
		fresh = current_scene.get_node_or_null("Player") as CharacterBody2D
	if fresh == null:
		_check(false, "Reloaded fnd_death_reset must contain a Player")
	else:
		_check(fresh.global_position.distance_to(spawn) < 0.1,
			"The death reset must return Warma to spawn %s, got %s" % [spawn, fresh.global_position])
	_end("TEST 7", mark)

# --------------------------------------------------------------------- TEST 8

func _test_death_freeze_stops_elevators() -> void:
	var mark := _begin("TEST 8: freeze_for_death must stop elevators during the death animation")
	var packed := load("res://rooms/showcase/fnd_button.tscn") as PackedScene
	var room_loadable := packed != null and packed.instantiate() != null
	if room_loadable:
		await _death_freeze_in_fnd_button()
	else:
		print("    fnd_button.tscn cannot instantiate (see TEST 1); probing the same contract in a runtime-assembled room")
		await _death_freeze_fallback()
	_end("TEST 8", mark)

func _death_freeze_in_fnd_button() -> void:
	if not await _load_room("res://rooms/showcase/fnd_button.tscn"):
		return
	var room := current_scene
	var player := room.get_node_or_null("Player") as CharacterBody2D
	var lift := room.get_node_or_null("Lift1") as AnimatableBody2D
	_check(player != null and lift != null, "fnd_button must contain a Player and the Lift1 elevator")
	if player == null or lift == null:
		return
	await _tick(5)
	# Drive the lift through its own contract API so it is provably in motion
	# before the death sequence starts.
	lift.call("set_button_active", true)
	var start_height := float(lift.get("current_height"))
	await _tick(20)
	var moving_height := float(lift.get("current_height"))
	_check(moving_height > start_height + 0.5,
		"Precondition: set_button_active(true) must extend Lift1 (height %.2f -> %.2f)" % [start_height, moving_height])
	player.set("death_flash_duration", 0.04)
	player.call("die")
	var frozen := is_instance_valid(room) and room.process_mode == Node.PROCESS_MODE_DISABLED
	_check(frozen, "die() must trigger freeze_for_death (room PROCESS_MODE_DISABLED)")
	var death_height := float(lift.get("current_height")) if is_instance_valid(lift) else moving_height
	var before := scene_changes
	var max_drift := 0.0
	var deadline := Time.get_ticks_msec() + 8000
	# Keep ticking through the whole death animation and read the lift every tick.
	while is_instance_valid(lift) and is_instance_valid(room) and current_scene == room \
			and Time.get_ticks_msec() < deadline:
		await physics_frame
		await process_frame
		if not is_instance_valid(lift):
			break
		max_drift = maxf(max_drift, absf(float(lift.get("current_height")) - death_height))
	if scene_changes == before:
		# The loop can exit one frame before the deferred reload emits the signal.
		await _wait_scene_changed(2.0)
	_check(scene_changes > before, "The death animation must end in a room reload")
	_check(max_drift <= 0.001,
		"Death freeze must stop elevators: Lift1 current_height drifted %.3fpx during the death animation (room.freeze_for_death sets PROCESS_MODE_DISABLED, but elevator.gd _ready sets PROCESS_MODE_ALWAYS, which bypasses the freeze)" % max_drift)

## Same freeze contract without any showcase .tscn: a room node carrying the
## real rooms/room.gd script, one real elevator_up.tscn instance and one real
## warma.tscn instance, assembled here at runtime. reset_scene() cannot reload
## (there is no current_scene), so the drift is sampled over a fixed window.
func _death_freeze_fallback() -> void:
	var room_script := load("res://rooms/room.gd") as Script
	var lift_scene := load("res://objects/elevator_up.tscn") as PackedScene
	var player_scene := load("res://objects/warma.tscn") as PackedScene
	_check(room_script != null and lift_scene != null and player_scene != null,
		"TEST 8 fallback needs rooms/room.gd, objects/elevator_up.tscn and objects/warma.tscn")
	if room_script == null or lift_scene == null or player_scene == null:
		return
	var room := Node2D.new()
	room.name = "FreezeFallbackRoom"
	room.set_script(room_script)
	var background := Node2D.new()
	background.name = "Background" # rooms/room.gd _ready touches $Background
	room.add_child(background)
	root.add_child(room)
	var lift := lift_scene.instantiate() as AnimatableBody2D
	lift.name = "Lift1"
	lift.position = Vector2(40, 128)
	room.add_child(lift)
	var player := player_scene.instantiate() as CharacterBody2D
	player.name = "Player"
	player.position = Vector2(100, 60)
	room.add_child(player)
	await _tick(5)
	lift.call("set_button_active", true)
	var start_height := float(lift.get("current_height"))
	await _tick(20)
	var moving_height := float(lift.get("current_height"))
	_check(moving_height > start_height + 0.5,
		"Precondition: set_button_active(true) must extend the lift (height %.2f -> %.2f)" % [start_height, moving_height])
	player.set("death_flash_duration", 0.04)
	player.call("die")
	var frozen := is_instance_valid(room) and room.process_mode == Node.PROCESS_MODE_DISABLED
	_check(frozen, "die() must trigger freeze_for_death (room PROCESS_MODE_DISABLED)")
	var death_height := float(lift.get("current_height")) if is_instance_valid(lift) else moving_height
	var max_drift := 0.0
	for _i in range(60):
		await physics_frame
		await process_frame
		if not is_instance_valid(lift):
			break
		max_drift = maxf(max_drift, absf(float(lift.get("current_height")) - death_height))
	_check(max_drift <= 0.001,
		"Death freeze must stop elevators: Lift1 current_height drifted %.3fpx during the death animation (room.freeze_for_death sets PROCESS_MODE_DISABLED, but elevator.gd _ready sets PROCESS_MODE_ALWAYS, which bypasses the freeze)" % max_drift)
	if is_instance_valid(room):
		room.queue_free()
	await _tick(1)

# ---------------------------------------------------------------------- SUITE

func _run() -> void:
	game_state = root.get_node_or_null("GameState")
	if game_state == null:
		push_error("GameState autoload missing; showcase contract checks aborted")
		print("Showcase contract checks: FAIL (GameState autoload missing)")
		quit(1)
		return
	state_instance_id = game_state.get_instance_id()
	game_state.call("reset_speed")
	saved_has_extinguisher = bool(game_state.get("has_extinguisher"))
	game_state.set("has_extinguisher", false)
	scene_changed.connect(_on_scene_changed)
	for action in ["move_left", "move_right", "jump", "fire_music", "interact", "reset"]:
		Input.action_release(action)
	_send_w(false)

	var paths := _showcase_paths()
	await _test_all_rooms_load(paths)
	await _test_hub_reachability(paths)
	var instantiable := _count_instantiable(paths)
	if instantiable == 0:
		# Fatal generated-scene defect: every room fails PackedScene.instantiate,
		# so scene-dependent checks cannot run at all. Report each blocked test
		# once instead of cascading dozens of identical failures.
		print("!!! FATAL: 0 of %d showcase rooms can be instantiated — scene-dependent checks are blocked" % paths.size())
		for blocked in ["TEST 3", "TEST 4", "TEST 5", "TEST 6", "TEST 7"]:
			_check(false,
				"%s BLOCKED: no showcase room can be instantiated (every generated room fails PackedScene.instantiate — see TEST 1), so these scene-dependent assertions cannot run" % blocked)
			print("    %s: BLOCKED (rooms cannot instantiate)" % blocked)
		await _test_death_freeze_stops_elevators()
	else:
		await _test_w_transition_loop()
		await _test_lift_shape_isolation()
		await _test_game_state_hygiene()
		await _test_reset_restores_spawn(paths)
		await _test_pit_death_reset()
		await _test_death_freeze_stops_elevators()

	if is_instance_valid(game_state):
		game_state.set("has_extinguisher", saved_has_extinguisher)
		game_state.call("reset_speed")
	_send_w(false)
	print("Showcase contract checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	for failure in failures:
		print("  FAILURE: ", failure)
	quit(0 if failures.is_empty() else 1)
