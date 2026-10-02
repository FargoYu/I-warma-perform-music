extends SceneTree
## Run: godot --headless --path . --script res://tests/death_reset_test.gd

const MAIN_ROOM := "res://rooms/main.tscn"
const OTHER_ROOM := "res://rooms/roomX.tscn"
var failures: Array[String] = []
var scene_changes := 0
var game_state: Node

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

func _send_r(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.keycode = KEY_R
	event.pressed = pressed
	Input.parse_input_event(event)

func _on_timeout() -> void:
	push_error("Death/reset checks timed out")
	quit(1)

func _watch_death(player: CharacterBody2D, room: Node) -> void:
	var before := scene_changes
	var visibility_changes: Array[bool] = []
	var death_position := Vector2.ZERO
	var saw_death := false
	var giraffe := room.get_node_or_null("Giraffe") as CharacterBody2D
	var giraffe_position := giraffe.position if giraffe != null else Vector2.ZERO
	while is_instance_valid(room) and current_scene == room:
		if bool(player.get("_dying")):
			if not saw_death:
				death_position = player.position
				if giraffe != null:
					giraffe_position = giraffe.position
				saw_death = true
				_check(not player.is_physics_processing(), "Death must stop player physics")
				_check(room.process_mode == Node.PROCESS_MODE_DISABLED, "Death must freeze room input and movement")
				_send_r(false)
				# Repeated requests must not restart or duplicate the animation.
				player.call("die")
				player.call("die")
			if visibility_changes.is_empty() or visibility_changes.back() != player.visible:
				visibility_changes.append(player.visible)
			_check(player.position == death_position, "Player must stay still during death animation")
			if giraffe != null:
				_check(giraffe.position == giraffe_position, "Giraffe must freeze during death animation")
		await process_frame
	if current_scene == null:
		await scene_changed
	await _tick(2)
	_check(saw_death, "Death sequence must run before reset")
	_check(visibility_changes == [false, true, false, true], "Death animation must blink exactly twice")
	_check(scene_changes == before + 1, "Repeated death requests must reload exactly once")
	_check(not is_instance_valid(room), "Reset must release the old room")
	_check(current_scene != null and current_scene.process_mode != Node.PROCESS_MODE_DISABLED, "New room must resume processing")
	_check(current_scene.get_node("Player").visible, "New player must be visible")

func _run() -> void:
	create_timer(15.0).timeout.connect(_on_timeout)
	scene_changed.connect(func(): scene_changes += 1)
	game_state = root.get_node("GameState")
	game_state.set("has_extinguisher", false)
	_check(InputMap.has_action("reset"), "Reset action must exist")
	_send_r(false)
	change_scene_to_file(MAIN_ROOM)
	await scene_changed
	await _tick(2)

	var room := current_scene
	var player := room.get_node("Player") as CharacterBody2D
	player.set("death_flash_duration", 0.04)
	player.position = Vector2(200, 120)
	player.call("pick_up_extinguisher")
	room.get_node("ExtinguisherPickup").queue_free()
	var giraffe := room.get_node("Giraffe") as CharacterBody2D
	giraffe.position = Vector2(160, 120)
	giraffe.velocity = Vector2(24, 0)
	var note := load("res://objects/music_bullet.tscn").instantiate() as Node2D
	room.add_child(note)
	note.position = Vector2(200, 70)
	await process_frame
	_send_r(true)
	await _watch_death(player, room)
	_check(current_scene.scene_file_path == MAIN_ROOM, "R must reload the current room")
	_check(current_scene.get_node("Player").position.distance_to(Vector2(29, 120)) < 0.1, "Reset must restore player spawn")
	_check(current_scene.get_node("Giraffe").position.distance_to(Vector2(118, 120)) < 0.1, "Reset must restore giraffe spawn")
	_check(get_nodes_in_group("music_bullet").is_empty(), "Reset must clear old music bullets")
	_check(not bool(game_state.get("has_extinguisher")), "Reset must restore equipment state from room entry")
	_check(current_scene.has_node("ExtinguisherPickup"), "Reset must restore an item collected during this room")
	_check(not current_scene.get_node("Player/EquipmentPivot").visible, "Reset equipment display must match restored state")

	# Remove the floor and let the player naturally reach the bottom boundary.
	room = current_scene
	player = room.get_node("Player") as CharacterBody2D
	player.set("death_flash_duration", 0.04)
	room.get_node("Blocks").free()
	room.get_node("Giraffe").free()
	player.position = Vector2(29, 135)
	player.velocity = Vector2(0, 60)
	await _watch_death(player, room)
	_check(current_scene.scene_file_path == MAIN_ROOM, "Falling must reload the same room")
	_check(current_scene.has_node("Blocks"), "Falling reset must restore the whole scene")

	# Equipment obtained in a previous room remains part of this room's initial state.
	game_state.set("has_extinguisher", true)
	change_scene_to_file(OTHER_ROOM)
	await scene_changed
	await _tick(2)
	room = current_scene
	player = room.get_node("Player") as CharacterBody2D
	player.set("death_flash_duration", 0.04)
	player.position = Vector2(160, 120)
	_send_r(true)
	await _watch_death(player, room)
	_check(current_scene.scene_file_path == OTHER_ROOM, "R in another room must stay in that room")
	_check(bool(game_state.get("has_extinguisher")), "Reset must retain equipment present on room entry")
	_check(current_scene.get_node("Player/EquipmentPivot").visible, "Restored player must show entry equipment")
	_send_r(false)
	print("Death/reset checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
