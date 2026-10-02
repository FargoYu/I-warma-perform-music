extends SceneTree
## Run: godot --headless --path . --script res://tests/room_transition_test.gd

const MAIN_ROOM := "res://rooms/main.tscn"
const TEMPLATE_ROOM := "res://rooms/roomX.tscn"
const OBJECT_SCENES := [
	"res://objects/warma.tscn",
	"res://objects/block.tscn",
	"res://objects/blocks.tscn",
	"res://objects/music_bullet.tscn",
	"res://objects/giraffe.tscn",
	"res://objects/extinguisher_pickup.tscn",
	"res://objects/door.tscn",
	"res://objects/background.tscn",
	"res://objects/hud.tscn",
	"res://objects/held_extinguisher.tscn",
	"res://objects/game_state.tscn",
]

var failures: Array[String] = []
var game_state: Node
var state_instance_id: int
var scene_changes := 0

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

func _instance(path: String) -> Node:
	var scene := load(path) as PackedScene
	_check(scene != null, "Could not load %s" % path)
	return scene.instantiate() if scene != null else null

func _clear_node(node: Node) -> void:
	node.queue_free()
	await process_frame
	await process_frame

func _on_scene_changed() -> void:
	scene_changes += 1

func _on_timeout() -> void:
	_check(false, "Timed out waiting for scene_changed during room transition checks")
	print("Room transition checks: FAIL (timeout)")
	quit(1)

func _send_w(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.keycode = KEY_W
	event.pressed = pressed
	Input.parse_input_event(event)

func _check_object_scripts(node: Node) -> void:
	var script := node.get_script() as Script
	if script != null:
		_check(script.resource_path.begins_with("res://objects/"), "Reusable object script must live in objects: %s" % script.resource_path)
	for child in node.get_children():
		_check_object_scripts(child)

func _check_door_export(door: Node) -> void:
	var found := false
	for property in door.get_property_list():
		if property["name"] == "next_room":
			found = true
			_check(int(property["type"]) == TYPE_STRING, "Door next_room must be a String")
			_check(int(property["hint"]) == PROPERTY_HINT_FILE, "Door next_room must use an Inspector file picker")
			_check(String(property["hint_string"]) == "*.tscn", "Door next_room file picker must filter *.tscn")
			_check((int(property["usage"]) & PROPERTY_USAGE_EDITOR) != 0, "Door next_room must be exported in Inspector")
	_check(found, "Door must export next_room")
	_check(door.has_method("enter_room"), "Door must expose enter_room()")

func _check_object_contract(node: Node, path: String) -> void:
	match path:
		"res://objects/warma.tscn":
			_check(node is CharacterBody2D, "Warma root must be CharacterBody2D")
			if node is CharacterBody2D:
				_check((node as CharacterBody2D).collision_layer == 2, "Warma collision layer must remain 2")
				_check(is_equal_approx((node as CharacterBody2D).safe_margin, 0.001), "Warma safe margin must remain 0.001")
			_check(node.has_node("EquipmentPivot/HeldExtinguisher/Nozzle"), "Standalone Warma must include its nozzle")
		"res://objects/block.tscn":
			_check(node is StaticBody2D, "Block root must be StaticBody2D")
			var collision := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
			_check(collision != null, "Independent Block must have a collision shape")
			if collision != null:
				var shape := collision.shape as RectangleShape2D
				_check(shape != null and shape.size.is_equal_approx(Vector2(16, 15.98)), "Block collision must be 16x15.98")
				_check(collision.position.is_equal_approx(Vector2.ZERO), "Block collision must be centered at the origin")
			if node is StaticBody2D:
				_check((node as StaticBody2D).collision_layer == 1, "Block collision layer must be terrain 1")
		"res://objects/blocks.tscn":
			var blocks := node as TileMapLayer
			_check(blocks != null, "Blocks root must be TileMapLayer")
			if blocks != null:
				_check(blocks.get_used_cells().is_empty(), "Reusable Blocks must start empty")
				_check(blocks.tile_set != null, "Blocks must include a TileSet")
				if blocks.tile_set != null:
					_check(blocks.tile_set.resource_path == "res://objects/tileset.tres", "Reusable TileSet must live in objects")
					_check(blocks.tile_set.tile_size == Vector2i(16, 16), "Blocks grid must be 16x16")
		"res://objects/music_bullet.tscn":
			_check(node is Area2D, "MusicBullet root must be Area2D")
		"res://objects/giraffe.tscn":
			_check(node is CharacterBody2D, "Giraffe root must remain CharacterBody2D")
			_check(node.has_method("run_in_direction"), "Giraffe must retain run_in_direction()")
		"res://objects/door.tscn":
			_check(node is Area2D, "Door root must be Area2D")
			_check_door_export(node)
			_check(String(node.get("next_room")).is_empty(), "Standalone Door must default to no destination")

func _test_standalone_objects() -> void:
	var paths: Array[String] = []
	for path in OBJECT_SCENES:
		paths.append(path)
	for file_name in DirAccess.get_files_at("res://objects"):
		var path := "res://objects/" + file_name
		if file_name.ends_with(".tscn") and not paths.has(path):
			paths.append(path)
	for path in paths:
		var object := _instance(path)
		if object == null:
			continue
		_check_object_scripts(object)
		_check_object_contract(object, path)
		var holder := Node2D.new()
		holder.name = "IsolatedObjectTest"
		root.add_child(holder)
		holder.add_child(object)
		if object is CharacterBody2D:
			object.set_physics_process(false)
		await _tick(2)
		_check(current_scene == null, "Standalone objects must not load main room")
		_check(is_instance_valid(object), "Standalone object unexpectedly freed itself: %s" % path)
		if path == "res://objects/door.tscn" and is_instance_valid(object):
			var before := scene_changes
			object.call("enter_room")
			object.call("enter_room")
			await _tick(3)
			_check(scene_changes == before and current_scene == null, "Unconfigured standalone Door must not change scenes")
			_check(not bool(object.get("_transitioning")), "Empty destination must not latch transition guard")
		await _clear_node(holder)

func _check_room_contract(room: Node, path: String) -> void:
	if path != MAIN_ROOM and path != TEMPLATE_ROOM:
		return
	var expected_nodes := ["Background", "Blocks", "Player", "Door", "HUD"]
	if path == MAIN_ROOM:
		expected_nodes.append_array(["Giraffe", "ExtinguisherPickup"])
	for node_name in expected_nodes:
		var child := room.get_node_or_null(NodePath(node_name))
		_check(child != null, "%s must retain node %s" % [path, node_name])
		if child != null:
			_check(child.scene_file_path.begins_with("res://objects/"), "Room node must instance a reusable object: %s/%s" % [path, node_name])
	var player := room.get_node_or_null("Player") as CharacterBody2D
	_check(player != null, "Room Player must be CharacterBody2D")
	if player != null:
		_check(player.position.is_equal_approx(Vector2(29, 120)), "Room must retain Player spawn position")
	var door := room.get_node_or_null("Door") as Area2D
	if door != null:
		_check_door_export(door)
		_check(String(door.get("next_room")) == (TEMPLATE_ROOM if path == MAIN_ROOM else MAIN_ROOM), "Room Door must point to the opposite room")
		_check(door.position.is_equal_approx(Vector2(232, 120)), "Room must retain Door position")
	var blocks := room.get_node_or_null("Blocks") as TileMapLayer
	_check(blocks != null, "Room Blocks must be TileMapLayer")
	if blocks != null:
		var expected_cells: Array[Vector2i] = []
		for x in range(16):
			expected_cells.append(Vector2i(x, 8))
		if path == MAIN_ROOM:
			for x in range(7, 13):
				expected_cells.append(Vector2i(x, 6))
			for x in range(12, 16):
				expected_cells.append(Vector2i(x, 4))
		_check(blocks.get_used_cells().size() == expected_cells.size(), "Room must retain its tile layout: %s" % path)
		for cell in expected_cells:
			_check(blocks.get_cell_source_id(cell) == 0 and blocks.get_cell_atlas_coords(cell) == Vector2i.ZERO, "Missing room floor/platform tile %s in %s" % [cell, path])
	if path == MAIN_ROOM:
		var giraffe := room.get_node_or_null("Giraffe") as Node2D
		var pickup := room.get_node_or_null("ExtinguisherPickup") as Node2D
		_check(giraffe != null and giraffe.position.is_equal_approx(Vector2(118, 120)), "Main must retain Giraffe position")
		_check(pickup != null and pickup.position.is_equal_approx(Vector2(88, 108)), "Main must retain pickup position")

func _test_room_resources() -> void:
	var paths: Array[String] = [MAIN_ROOM, TEMPLATE_ROOM]
	for file_name in DirAccess.get_files_at("res://rooms"):
		var path := "res://rooms/" + file_name
		if file_name.ends_with(".tscn") and not paths.has(path):
			paths.append(path)
	for path in paths:
		var room := _instance(path)
		if room == null:
			continue
		_check_room_contract(room, path)
		root.add_child(room)
		await _tick(2)
		_check(is_instance_valid(room) and room.is_inside_tree(), "Room must instantiate independently: %s" % path)
		await _clear_node(room)

func _check_scene_path(expected: String) -> bool:
	_check(current_scene != null, "A room scene must be active")
	if current_scene == null:
		return false
	var matches := current_scene.scene_file_path == expected
	_check(matches, "Expected active room %s, got %s" % [expected, current_scene.scene_file_path])
	return matches

func _load_room(path: String) -> bool:
	var error := change_scene_to_file(path)
	_check(error == OK, "change_scene_to_file failed for %s: %s" % [path, error_string(error)])
	if error != OK:
		return false
	await scene_changed
	await _tick(2)
	return _check_scene_path(path)

func _move_player(at: Vector2) -> void:
	var player := current_scene.get_node_or_null("Player") as CharacterBody2D
	_check(player != null, "Active room must contain Player")
	if player == null:
		return
	player.set_physics_process(false)
	player.global_position = at
	player.velocity = Vector2.ZERO
	await _tick(3)

func _check_persistent_equipment() -> void:
	var state := root.get_node_or_null("GameState")
	_check(state != null and state.get_instance_id() == state_instance_id, "Room changes must preserve the same GameState autoload")
	_check(state != null and bool(state.get("has_extinguisher")), "Room changes must retain the extinguisher")
	if current_scene != null:
		var pivot := current_scene.get_node_or_null("Player/EquipmentPivot") as Node2D
		_check(pivot != null and pivot.visible, "New room Player must restore held extinguisher from GameState")
		if current_scene.scene_file_path == MAIN_ROOM:
			_check(not current_scene.has_node("ExtinguisherPickup"), "Collected extinguisher must not respawn when returning to main")

func _collect_extinguisher() -> void:
	var pickup := current_scene.get_node_or_null("ExtinguisherPickup") as Node2D
	_check(pickup != null, "Fresh main room must contain extinguisher pickup")
	if pickup == null:
		return
	await _move_player(pickup.global_position)
	await process_frame
	_check(not is_instance_valid(pickup), "Actual player overlap must collect pickup")
	_check_persistent_equipment()

func _test_w_transition(target: String) -> void:
	if current_scene == null:
		_check(false, "Cannot test W without active room")
		return
	var old_room := current_scene
	var door := old_room.get_node_or_null("Door") as Area2D
	_check(door != null, "Active room must contain Door")
	if door == null:
		return
	var before := scene_changes
	await _move_player(door.global_position)
	_check(bool(door.get("player_inside")), "Door must detect actual player entry")
	await _move_player(door.global_position + Vector2(-40, 0))
	_check(not bool(door.get("player_inside")), "Player outside door must not be eligible")
	_send_w(true)
	await _tick(3)
	_send_w(false)
	await _tick(2)
	_check(current_scene == old_room and scene_changes == before, "W outside door must not change rooms")
	if not is_instance_valid(door):
		return
	await _move_player(door.global_position)
	_check(bool(door.get("player_inside")), "Actual player overlap must enable W door entry")
	if not bool(door.get("player_inside")):
		return
	_send_w(true)
	await scene_changed
	_send_w(false)
	await _tick(3)
	_check_scene_path(target)
	_check(scene_changes == before + 1, "W door entry must change rooms exactly once")
	_check(not is_instance_valid(old_room) and not is_instance_valid(door), "Room change must release old room and door")
	_check_persistent_equipment()

func _test_repeated_entry(target: String) -> void:
	if current_scene == null:
		_check(false, "Cannot test repeated entry without active room")
		return
	var old_room := current_scene
	var door := old_room.get_node_or_null("Door")
	if door == null or not door.has_method("enter_room"):
		_check(false, "Door must implement enter_room()")
		return
	var before := scene_changes
	door.call("enter_room")
	door.call("enter_room")
	door.call("enter_room")
	_check(current_scene == old_room, "enter_room must defer scene replacement")
	_check(bool(door.get("_transitioning")), "Door must guard repeated entry while transition is pending")
	await scene_changed
	await _tick(3)
	_check_scene_path(target)
	_check(scene_changes == before + 1, "Repeated enter_room must cause exactly one scene change")
	_check(not is_instance_valid(door), "Transition must free the old Door")
	_check_persistent_equipment()

func _test_empty_destination() -> void:
	if current_scene == null:
		return
	var room := current_scene
	var door := room.get_node_or_null("Door") as Area2D
	if door == null:
		_check(false, "Cannot test empty destination without Door")
		return
	var destination := String(door.get("next_room"))
	door.set("next_room", "")
	await _move_player(door.global_position)
	var before := scene_changes
	_send_w(true)
	await _tick(3)
	_send_w(false)
	door.call("enter_room")
	door.call("enter_room")
	await _tick(3)
	_check(current_scene == room and scene_changes == before, "Empty next_room must ignore W and public enter_room()")
	_check(not bool(door.get("_transitioning")), "Empty next_room must leave the transition guard clear")
	door.set("next_room", destination)
	_check_persistent_equipment()

func _run() -> void:
	# Bound signal waits so a missing transition reports failure rather than hanging.
	create_timer(20.0).timeout.connect(_on_timeout)
	scene_changed.connect(_on_scene_changed)
	for action in ["move_left", "move_right", "jump", "fire_music", "interact"]:
		Input.action_release(action)
	_send_w(false)
	game_state = root.get_node_or_null("GameState")
	_check(game_state != null, "GameState autoload must exist")
	if game_state == null:
		quit(1)
		return
	state_instance_id = game_state.get_instance_id()
	_check(String(ProjectSettings.get_setting("autoload/GameState", "")) == "*res://objects/game_state.tscn", "GameState autoload must use objects/game_state.tscn")
	_check(game_state.scene_file_path == "res://objects/game_state.tscn", "GameState must be instantiated from its reusable scene")
	var saved_equipment := bool(game_state.get("has_extinguisher"))
	game_state.set("has_extinguisher", false)
	await _test_standalone_objects()
	await _test_room_resources()
	if await _load_room(MAIN_ROOM):
		var initial_pivot := current_scene.get_node_or_null("Player/EquipmentPivot") as Node2D
		_check(initial_pivot != null and not initial_pivot.visible, "Fresh Player must start without a held extinguisher")
		await _collect_extinguisher()
		await _test_w_transition(TEMPLATE_ROOM)
		await _test_w_transition(MAIN_ROOM)
		await _test_repeated_entry(TEMPLATE_ROOM)
		await _test_repeated_entry(MAIN_ROOM)
		await _test_empty_destination()
	_send_w(false)
	game_state.set("has_extinguisher", saved_equipment)
	print("Room transition checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
