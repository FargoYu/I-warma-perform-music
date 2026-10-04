extends SceneTree
## Physical smoke tests for the seven COMBINATIONS showcase rooms.
## Run: godot --headless --path . --script res://tests/showcase_test_combinations.gd
##
## Every room is loaded through change_scene_to_file so reset_scene() and the W
## door transitions exercise the real current_scene path. Notes are fired
## manually (music_bullet.tscn + setup()) exactly the way the extinguisher does.
## A note hit makes the giraffe run at music_run_speed (24px/s) for
## music_run_duration (0.8s => ~19.2px) plus a short friction slide (~3px), so
## each note fired at a resting giraffe advances it ~22px.
##
## Timing facts used below (project runs 120 physics ticks per second, and one
## _tick() waits exactly one physics step, i.e. 1/120s of simulation time):
##   - lift growth: height_speed px/s from min_height to max_height
##   - button pressure zone: center (x, y-6), 14x4; a giraffe body is 8x16, so
##     its center x activates the button while inside [button_x - 11, button_x + 11]

const ROOM_DIR := "res://rooms/showcase/"
const BULLET_SCENE := "res://objects/music_bullet.tscn"

var failures: Array[String] = []
var game_state: Node
var saved_equipment := false

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

func _on_timeout() -> void:
	_check(false, "Timed out during combinations showcase checks")
	print("Combinations showcase checks: FAIL (timeout)")
	quit(1)

func _release_input() -> void:
	for action in ["move_left", "move_right", "jump", "fire_music", "interact", "reset"]:
		Input.action_release(action)

func _send_w(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.keycode = KEY_W
	event.pressed = pressed
	Input.parse_input_event(event)

func _room_node(node_name: String) -> Node:
	if current_scene == null:
		return null
	if current_scene.has_node(node_name):
		return current_scene.get_node_or_null(node_name)
	# Generated rooms number their doors (Door1, Door2, ...); find the first one.
	var index := 1
	while current_scene.has_node("Door%d" % index):
		var door := current_scene.get_node_or_null("Door%d" % index)
		if door != null and door is Area2D and String(door.get("next_room")) != "":
			return door
		index += 1
	return null

func _load_room(room_name: String) -> bool:
	var path := ROOM_DIR + room_name + ".tscn"
	var error := change_scene_to_file(path)
	_check(error == OK, "%s: change_scene_to_file failed: %s" % [room_name, error_string(error)])
	if error != OK:
		# Known generator defect: tools/generate_showcase_rooms.gd emits the
		# Terrain container without a parent attribute, which
		# SceneState::instantiate() rejects ("node Terrain does not specify its
		# parent node"), so every rooms/showcase/*.tscn fails to load.
		var text := FileAccess.get_file_as_string(path)
		if text.contains("[node name=\"Terrain\" type=\"Node2D\"]"):
			_check(false, "%s: room carries the known parentless-Terrain defect; regenerate after fixing tools/generate_showcase_rooms.gd line 260 to emit parent=\".\"" % room_name)
		return false
	await scene_changed
	await _tick(3)
	var loaded := current_scene != null and current_scene.scene_file_path == path
	_check(loaded, "%s: expected the room to become current_scene" % room_name)
	return loaded

func _teleport(at: Vector2) -> CharacterBody2D:
	var where := String(current_scene.scene_file_path) if current_scene != null else "<no scene>"
	var player := _room_node("Player") as CharacterBody2D
	_check(player != null, "%s: active room must contain Player" % where)
	if player == null:
		return null
	player.set_physics_process(false)
	player.global_position = at
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	await _tick(4)
	return player

func _is_grounded(player: CharacterBody2D) -> bool:
	return bool(player.call("_has_ground_support"))

func _equipment_visible(player: CharacterBody2D) -> bool:
	var pivot := player.get_node_or_null("EquipmentPivot") as Node2D
	return pivot != null and pivot.visible

func _fire_note(from: Vector2, direction: int) -> void:
	var bullet := (load(BULLET_SCENE) as PackedScene).instantiate() as Area2D
	_check(bullet != null, "music_bullet.tscn must instantiate")
	if bullet == null:
		return
	bullet.call("setup", direction, 480.0, 0.03)
	current_scene.add_child(bullet)
	bullet.global_position = from

func _wait_giraffe_rest(giraffe: CharacterBody2D) -> void:
	for _i in range(240):
		if float(giraffe.get("_music_run_time")) <= 0.0 and absf(giraffe.velocity.x) < 0.01:
			await _tick(2)
			return
		await _tick()

## Fires one note from `from_x` at y=113, waits for the hit and asserts the
## music run started, then waits for the giraffe to come back to rest.
func _herd_once(giraffe: CharacterBody2D, label: String, shot: int, from_x: float) -> void:
	await _wait_giraffe_rest(giraffe)
	_fire_note(Vector2(from_x, 113.0), 1)
	await _tick(16)
	_check(float(giraffe.get("_music_run_time")) > 0.0,
		"%s: note %d must trigger the giraffe's music run" % [label, shot])

func _wait_giraffe_below(giraffe: CharacterBody2D, limit_y: float, max_ticks: int) -> bool:
	for _i in range(max_ticks):
		if giraffe.global_position.y > limit_y:
			await _tick(2)
			return true
		await _tick()
	return false

## Teleports Warma into the room's Door and presses W; verifies the arrival.
func _enter_door(target_room: String) -> bool:
	var door := _room_node("Door") as Area2D
	_check(door != null, "Room must contain a Door to reach %s" % target_room)
	if door == null:
		return false
	var path := ROOM_DIR + target_room + ".tscn"
	_check(String(door.get("next_room")) == path,
		"Door must point at %s (got %s)" % [path, String(door.get("next_room"))])
	await _teleport(door.global_position)
	if not is_instance_valid(door):
		return false
	_check(bool(door.get("player_inside")), "Door must detect Warma standing inside it")
	if not bool(door.get("player_inside")):
		return false
	_send_w(true)
	await scene_changed
	_send_w(false)
	await _tick(3)
	var arrived := current_scene != null and current_scene.scene_file_path == path
	_check(arrived, "W at the door must lead to %s (got %s)" % [
		path, String(current_scene.scene_file_path) if current_scene != null else "<none>"])
	return arrived


# --------------------------------------------------------------------- 1
func _test_giraffe_elevator() -> void:
	var label := "cmb_giraffe_elevator"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	if not await _load_room(label):
		return
	var giraffe := _room_node("Giraffe1") as CharacterBody2D
	var button := _room_node("Btn1")
	var lift := _room_node("Lift1")
	_check(giraffe != null and button != null and lift != null, "%s: must expose Giraffe1/Btn1/Lift1" % label)
	if giraffe == null or button == null or lift == null:
		return
	# The giraffe is born on the button; the lift needs (32-3)/16 = 1.8125s of
	# growth, so wait 240 ticks (2.0s) for the clamped maximum.
	await _tick(240)
	_check(bool(button.get("activated")), "%s: the giraffe standing on Btn1 must keep it activated" % label)
	_check(is_equal_approx(float(lift.get("current_height")), 32.0),
		"%s: pressed lift must stay fully extended at 32 (got %s)" % [label, float(lift.get("current_height"))])
	_check(absf(giraffe.global_position.y - 120.0) < 0.5,
		"%s: giraffe must rest on the button cell at y~120 (got %s)" % [label, giraffe.global_position.y])
	# Lift top: 128 - 32 = 96, so Warma's centre rides at y=88.
	var player := await _teleport(Vector2(136, 88))
	if player != null:
		await _tick(6)
		_check(_is_grounded(player), "%s: Warma must stand on the extended lift top at (136,88)" % label)
	# High platform: blocks x in [192,224], top y=96.
	player = await _teleport(Vector2(200, 88))
	if player != null:
		await _tick(6)
		_check(_is_grounded(player), "%s: Warma must stand on the high platform at (200,88)" % label)
		_check(absf(player.global_position.y - 88.0) < 1.0,
			"%s: platform top must hold Warma at y~88 (got %s)" % [label, player.global_position.y])
	_check(is_equal_approx(float(lift.get("current_height")), 32.0),
		"%s: lift must still be extended while the giraffe keeps pressing" % label)

# --------------------------------------------------------------------- 2
func _test_bullet_plate() -> void:
	var label := "cmb_bullet_plate"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	if not await _load_room(label):
		return
	var giraffe := _room_node("Giraffe1") as CharacterBody2D
	var button := _room_node("Btn1")
	var lift := _room_node("Lift1")
	_check(giraffe != null and button != null and lift != null, "%s: must expose Giraffe1/Btn1/Lift1" % label)
	if giraffe == null or button == null or lift == null:
		return
	# Collect the pickup at (40,124) by standing on it.
	var player := await _teleport(Vector2(40, 120))
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "%s: overlapping the pickup must grant the extinguisher" % label)
	_check(player == null or not current_scene.has_node("ExtinguisherPickup"),
		"%s: collected pickup must self-destruct" % label)
	_check(player != null and _equipment_visible(player), "%s: EquipmentPivot must show after collection" % label)
	# Herd the giraffe from x=88 into Btn1's pressure window [157,179]:
	# four notes fired at a resting giraffe advance it ~22px each (88 -> ~176).
	for shot in range(4):
		var from_x := giraffe.global_position.x - 28.0
		await _herd_once(giraffe, label, shot + 1, from_x)
	await _wait_giraffe_rest(giraffe)
	var final_x := giraffe.global_position.x
	_check(final_x >= 157.0 and final_x <= 179.0,
		"%s: four notes must herd the giraffe into Btn1's window 157..179 (got %.1f)" % [label, final_x])
	_check(absf(giraffe.global_position.y - 120.0) < 0.5,
		"%s: herded giraffe must stay on the floor (got %s)" % [label, giraffe.global_position.y])
	_check(bool(button.get("activated")), "%s: the herded giraffe must press Btn1" % label)
	# (32-3)/24 = 1.208s of growth => 220 ticks is plenty; the button stays held.
	await _tick(220)
	_check(is_equal_approx(float(lift.get("current_height")), 32.0),
		"%s: pressed lift must reach full 32 extension (got %s)" % [label, float(lift.get("current_height"))])
	_check(bool(button.get("activated")), "%s: Btn1 must stay activated while the lift extends" % label)
	# Reset must restore actors, lift height and the un-collected pickup.
	current_scene.call("reset_scene")
	await scene_changed
	await _tick(5)
	var reset_giraffe := _room_node("Giraffe1") as CharacterBody2D
	var reset_lift := _room_node("Lift1")
	_check(reset_giraffe != null and reset_giraffe.global_position.distance_to(Vector2(88, 120)) < 0.5,
		"%s: reset must return the giraffe to (88,120) (got %s)" % [label, reset_giraffe.global_position if reset_giraffe != null else Vector2.INF])
	_check(reset_lift != null and is_equal_approx(float(reset_lift.get("current_height")), 3.0),
		"%s: reset must restore the lift to min height 3 (got %s)" % [label, float(reset_lift.get("current_height")) if reset_lift != null else -1.0])
	_check(current_scene.has_node("ExtinguisherPickup"), "%s: reset must bring the pickup back" % label)
	_check(not bool(game_state.get("has_extinguisher")), "%s: reset must restore the pre-entry equipment state" % label)
	game_state.set("has_extinguisher", false)

# --------------------------------------------------------------------- 3
func _test_elevator_door() -> void:
	var label := "cmb_elevator_door"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	if not await _load_room(label):
		return
	var giraffe := _room_node("Giraffe1") as CharacterBody2D
	var button := _room_node("Btn1")
	var lift := _room_node("Lift1")
	_check(giraffe != null and button != null and lift != null, "%s: must expose Giraffe1/Btn1/Lift1" % label)
	if giraffe == null or button == null or lift == null:
		return
	var player := await _teleport(Vector2(40, 120))
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "%s: overlapping the pickup must grant the extinguisher" % label)
	# Park Warma on the idle lift top (min 3 => support y=125.005, centre 117).
	player = await _teleport(Vector2(168, 112))
	if player == null:
		return
	await _tick(24)
	_check(_is_grounded(player), "%s: Warma must stand on the idle lift top at (168,117)" % label)
	_check(absf(player.global_position.y - 117.0) < 1.0,
		"%s: idle lift top must hold Warma at y~117 (got %s)" % [label, player.global_position.y])
	# Herd the giraffe from x=72 into Btn1's pressure window [125,147]:
	# three notes at ~22px each land it at ~138.
	for shot in range(3):
		var from_x := giraffe.global_position.x - 28.0
		await _herd_once(giraffe, label, shot + 1, from_x)
	await _wait_giraffe_rest(giraffe)
	var final_x := giraffe.global_position.x
	_check(final_x >= 125.0 and final_x <= 147.0,
		"%s: three notes must herd the giraffe into Btn1's window 125..147 (got %.1f)" % [label, final_x])
	_check(bool(button.get("activated")), "%s: the herded giraffe must press Btn1" % label)
	# (48-3)/16 = 2.8125s of growth => 420 ticks; the lift must carry Warma up.
	await _tick(420)
	_check(is_equal_approx(float(lift.get("current_height")), 48.0),
		"%s: pressed lift must clamp at its 48 px maximum (got %s)" % [label, float(lift.get("current_height"))])
	_check(player.global_position.y < 90.0,
		"%s: the rising lift must carry Warma upward (got y=%s)" % [label, player.global_position.y])
	_check(_is_grounded(player), "%s: Warma must stay grounded while carried by the lift" % label)
	# High platform: blocks x in [192,240] at row 4, top y=64.
	player = await _teleport(Vector2(200, 56))
	await _tick(6)
	_check(_is_grounded(player), "%s: Warma must stand on the high platform at (200,56)" % label)
	_check(absf(player.global_position.y - 56.0) < 1.0,
		"%s: platform top must hold Warma at y~56 (got %s)" % [label, player.global_position.y])
	game_state.set("has_extinguisher", false)

# --------------------------------------------------------------------- 4
func _test_pickup_cross_room() -> void:
	var label := "cmb_pickup"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	if not await _load_room("cmb_pickup_a"):
		return
	# Collect the pickup at (56,124).
	var player := await _teleport(Vector2(56, 120))
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "%s_a: overlapping the pickup must grant the extinguisher" % label)
	_check(player != null and _equipment_visible(player), "%s_a: EquipmentPivot must show after collection" % label)
	if not await _enter_door("cmb_pickup_b"):
		return
	player = _room_node("Player") as CharacterBody2D
	_check(player != null and _equipment_visible(player),
		"%s_b: held equipment must persist across the door transition" % label)
	var giraffe := _room_node("Giraffe1") as CharacterBody2D
	_check(giraffe != null, "%s_b: must expose Giraffe1" % label)
	if giraffe != null:
		# Equipment must still fire across rooms: the note shoves the giraffe right.
		await _herd_once(giraffe, "%s_b" % label, 1, 110.0)
		await _wait_giraffe_rest(giraffe)
		_check(giraffe.global_position.x > 136.0,
			"%s_b: fired note must move the giraffe right of its spawn 136 (got %.1f)" % [label, giraffe.global_position.x])
	if not await _enter_door("cmb_pickup_a"):
		return
	_check(not current_scene.has_node("ExtinguisherPickup"),
		"%s_a: pickup must stay collected while the equipment is held" % label)
	# The re-entered room captured has_extinguisher=true, so a reset keeps it.
	current_scene.call("reset_scene")
	await scene_changed
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "%s_a: reset must keep the equipment held on re-entry" % label)
	player = _room_node("Player") as CharacterBody2D
	_check(player != null and _equipment_visible(player), "%s_a: EquipmentPivot must stay visible after reset" % label)
	_check(not current_scene.has_node("ExtinguisherPickup"),
		"%s_a: reset while holding the equipment must not respawn the pickup" % label)
	game_state.set("has_extinguisher", false)

# --------------------------------------------------------------------- 5
func _test_reset_giraffe() -> void:
	var label := "cmb_reset_giraffe"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	if not await _load_room(label):
		return
	var giraffe := _room_node("Giraffe1") as CharacterBody2D
	_check(giraffe != null, "%s: must expose Giraffe1" % label)
	if giraffe == null:
		return
	_check(absf(giraffe.global_position.x - 136.0) < 0.5, "%s: giraffe must spawn at x=136" % label)
	# Collect the pickup at (40,124).
	var player := await _teleport(Vector2(40, 120))
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "%s: overlapping the pickup must grant the extinguisher" % label)
	# Two notes: the first lands the giraffe at ~158 (still floor), the second
	# carries it past the pit edge (floor ends at x=160, body left passes 164).
	await _herd_once(giraffe, label, 1, 100.0)
	await _wait_giraffe_rest(giraffe)
	var after_first := giraffe.global_position.x
	_check(after_first > 145.0 and after_first < 175.0,
		"%s: first note must advance the giraffe toward the pit (got %.1f)" % [label, after_first])
	await _herd_once(giraffe, label, 2, giraffe.global_position.x - 28.0)
	var fell := await _wait_giraffe_below(giraffe, 200.0, 420)
	_check(fell and giraffe.global_position.y > 200.0,
		"%s: two notes must drive the giraffe over the pit edge into a fall (got %s)" % [label, giraffe.global_position])
	# Reset must recover the fallen giraffe and the pickup.
	current_scene.call("reset_scene")
	await scene_changed
	await _tick(5)
	var reset_giraffe := _room_node("Giraffe1") as CharacterBody2D
	_check(reset_giraffe != null and reset_giraffe.global_position.distance_to(Vector2(136, 120)) < 0.5,
		"%s: reset must return the giraffe to (136,120) (got %s)" % [label, reset_giraffe.global_position if reset_giraffe != null else Vector2.INF])
	_check(current_scene.has_node("ExtinguisherPickup"), "%s: reset must bring the pickup back" % label)
	_check(not bool(game_state.get("has_extinguisher")), "%s: reset must restore the pre-entry equipment state" % label)
	game_state.set("has_extinguisher", false)

# --------------------------------------------------------------------- 6
func _test_reset_elevator() -> void:
	var label := "cmb_reset_elevator"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	if not await _load_room(label):
		return
	var lift := _room_node("Lift1")
	_check(lift != null, "%s: must expose Lift1" % label)
	if lift == null:
		return
	_check(is_equal_approx(float(lift.get("current_height")), 3.0),
		"%s: lift must start at min height 3 (got %s)" % [label, float(lift.get("current_height"))])
	lift.call("set_button_active", true)
	# speed 8px/s => 45 ticks (0.375s) grow it to 6.0.
	await _tick(45)
	_check(float(lift.get("current_height")) > 5.0,
		"%s: forced button must extend the lift past 5 (got %s)" % [label, float(lift.get("current_height"))])
	current_scene.call("reset_scene")
	await scene_changed
	await _tick(5)
	var reset_lift := _room_node("Lift1")
	var player := _room_node("Player") as CharacterBody2D
	_check(reset_lift != null and is_equal_approx(float(reset_lift.get("current_height")), 3.0),
		"%s: reset must restore the authored min height 3 (got %s)" % [label, float(reset_lift.get("current_height")) if reset_lift != null else -1.0])
	_check(player != null and player.global_position.distance_to(Vector2(40, 120)) < 0.5,
		"%s: reset must return Warma to its spawn (got %s)" % [label, player.global_position if player != null else Vector2.INF])

func _run() -> void:
	# Bound the whole run so a missing transition reports failure, not a hang.
	create_timer(240.0).timeout.connect(_on_timeout)
	_release_input()
	root.get_node_or_null("GameState").reset_speed()
	game_state = root.get_node_or_null("GameState")
	_check(game_state != null, "GameState autoload must exist")
	if game_state == null:
		print("Combinations showcase checks: FAIL (1)")
		quit(1)
		return
	saved_equipment = bool(game_state.get("has_extinguisher"))
	game_state.set("has_extinguisher", false)
	await _test_giraffe_elevator()
	await _test_bullet_plate()
	await _test_elevator_door()
	await _test_pickup_cross_room()
	await _test_reset_giraffe()
	await _test_reset_elevator()
	_release_input()
	game_state.set("has_extinguisher", saved_equipment)
	print("Combinations showcase checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
