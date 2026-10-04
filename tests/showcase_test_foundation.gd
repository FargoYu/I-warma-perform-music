extends SceneTree
## Physical smoke tests for the six FOUNDATION showcase rooms.
## Run: godot --headless --path . --script res://tests/showcase_test_foundation.gd
##
## Physics runs at 120 Hz (project.godot), so 60 px/s walking moves 0.5 px per
## tick, a 12 px/s lift moves 0.1 px per tick and 300 px/s^2 gravity adds
## 0.0208 px/tick of fall speed. Assertions therefore target settled or clamped
## states (rest height, face contact, fully extended lift) instead of exact
## mid-motion instants. Block bodies are 16x15.98, so a row-y block's top face
## sits at y*16+0.01 and a resting Warma (feet = centre + 8) stands 0.01 below
## the nominal tile height.

const FND_MOVEMENT := "res://rooms/showcase/fnd_movement.tscn"
const FND_PRECISION := "res://rooms/showcase/fnd_precision.tscn"
const FND_WALL_JUMP := "res://rooms/showcase/fnd_wall_jump.tscn"
const FND_BUTTON := "res://rooms/showcase/fnd_button.tscn"
const FND_MUSIC_BULLET := "res://rooms/showcase/fnd_music_bullet.tscn"
const FND_DEATH_RESET := "res://rooms/showcase/fnd_death_reset.tscn"
const BULLET_SCENE := "res://objects/music_bullet.tscn"

const STAND_Y_GROUND := 120.01   # row 8 floor top face at 128.01
const STAND_Y_STEP1 := 104.01    # one-high step (row 7) top face at 112.01
const STAND_Y_STEP2 := 88.01     # two-high step (row 6) top face at 96.01
const Y_TOL := 0.3
const X_TOL := 0.05
const GUARD_MS := 15000          # hang guard for scene-change waits

var failures: Array[String] = []
var game_state: Node

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

func _release_input() -> void:
	for action in ["jump", "move_left", "move_right", "fire_music", "interact"]:
		Input.action_release(action)

func _load_room(path: String) -> Node2D:
	_release_input()
	var room := (load(path) as PackedScene).instantiate() as Node2D
	_check(room != null, "Could not instantiate %s" % path)
	if room != null:
		root.add_child(room)
	return room

func _unload_room(room: Node2D) -> void:
	_release_input()
	if is_instance_valid(room):
		room.queue_free()
	await _tick(2)

func _teleport(player: CharacterBody2D, at: Vector2) -> void:
	player.velocity = Vector2.ZERO
	player.position = at

func _grounded(player: CharacterBody2D) -> bool:
	return bool(player.call("_has_ground_support"))

## Climb one 16 px tier while drift-holding right: a 16-tick jump hold rises
## ~17.3 px before the variable-height jump cut caps further rise at 60 px/s
## (apex ~23.3 px, airtime ~66 ticks, ~26 px of drift). Waits for the landing
## so the follow-up asserts read a settled support state.
func _hop_until_landed(player: CharacterBody2D, max_ticks: int) -> bool:
	Input.action_press("jump")
	await _tick(16)
	Input.action_release("jump")
	var landed := false
	for _i in range(max_ticks):
		await _tick(1)
		if _grounded(player):
			landed = true
			break
	Input.action_release("jump")
	Input.action_release("move_right")
	Input.action_release("move_left")
	return landed

func _wait_for_current_scene() -> Node:
	# change_scene_to_file applies at the end of the frame; never wait forever.
	var deadline := Time.get_ticks_msec() + GUARD_MS
	while Time.get_ticks_msec() < deadline and current_scene == null:
		await process_frame
	return current_scene

func _test_fnd_movement() -> void:
	var room := _load_room(FND_MOVEMENT)
	if room == null:
		return
	await _tick(12)
	var player := room.get_node("Player") as CharacterBody2D
	_check(player != null, "fnd_movement: room must instantiate a Player")
	if player == null:
		await _unload_room(room)
		return
	_check(_grounded(player), "fnd_movement: spawn must be grounded on the floor")
	_check(absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_movement: spawn must rest on row 8 (y=%.3f, want %.2f)" % [player.position.y, STAND_Y_GROUND])

	# Walk from mid-floor into the one-high tier: Warma must stop precisely at
	# the block face instead of slipping under or through it.
	_teleport(player, Vector2(140, 120))
	await _tick(2)
	_check(_grounded(player) and absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_movement: teleported state must be grounded on the floor (y=%.3f)" % player.position.y)
	Input.action_press("move_right")
	await _tick(40)
	_check(absf(player.position.x - 157.0) <= X_TOL,
		"fnd_movement: walking into the one-high tier must stop at its face (x=%.3f, want 157.0)" % player.position.x)
	_check(_grounded(player), "fnd_movement: must stay grounded while pressed against the tier")

	# Hop the one-high tier, then hop again while still drifting right. The
	# second hop must launch from the first tier's top: walking on into col 12
	# would drop into the gap, and from the ground the two-high face is 32 px.
	var landed := await _hop_until_landed(player, 90)
	_check(landed, "fnd_movement: first hop must land on the one-high tier (at %s)" % player.position)
	_check(absf(player.position.y - STAND_Y_STEP1) <= Y_TOL,
		"fnd_movement: must stand on the one-high tier (y=%.3f, want %.2f)" % [player.position.y, STAND_Y_STEP1])
	_check(player.position.x > 175.0 and player.position.x < 193.0,
		"fnd_movement: first hop must land on the one-high tier span (x=%.3f, want 176..192)" % player.position.x)

	Input.action_press("move_right")
	landed = await _hop_until_landed(player, 90)
	_check(landed, "fnd_movement: second hop must land on the two-high tier (at %s)" % player.position)
	_check(absf(player.position.y - STAND_Y_STEP2) <= Y_TOL,
		"fnd_movement: must stand on the two-high tier (y=%.3f, want %.2f)" % [player.position.y, STAND_Y_STEP2])
	_check(player.position.x > 208.0 and player.position.x < 232.0,
		"fnd_movement: second hop must land on the two-high tier span (x=%.3f, want 208..240)" % player.position.x)
	_check(_grounded(player), "fnd_movement: two-high tier must support Warma")
	await _tick(5)
	_check(_grounded(player) and absf(player.position.y - STAND_Y_STEP2) <= Y_TOL,
		"fnd_movement: Warma must stay settled on the two-high tier (y=%.3f)" % player.position.y)
	await _unload_room(room)

func _test_fnd_precision() -> void:
	var room := _load_room(FND_PRECISION)
	if room == null:
		return
	await _tick(12)
	var player := room.get_node("Player") as CharacterBody2D
	_check(player != null, "fnd_precision: room must instantiate a Player")
	if player == null:
		await _unload_room(room)
		return

	# The single-cell platform (14,4) top face is at 64.01: Warma teleported
	# onto it must be supported at once and must be able to take off there.
	_teleport(player, Vector2(232, 56))
	await _tick(20)
	_check(_grounded(player), "fnd_precision: single-cell platform must support Warma")
	_check(absf(player.position.y - 56.01) <= Y_TOL,
		"fnd_precision: must rest on the single cell (y=%.3f, want 56.01)" % player.position.y)
	var launch_y := player.position.y
	Input.action_press("jump")
	await _tick(5)
	_check(player.position.y < launch_y - 3.0 and player.velocity.y < 0.0,
		"fnd_precision: must jump off the single cell (y=%.3f from %.3f)" % [player.position.y, launch_y])
	_release_input()

	# The room's lesson: a foot edge on a platform counts as support. x=177
	# puts only 4 px of the 5 px-wide foot on the (11,5) block (176..192).
	_teleport(player, Vector2(177, 72))
	await _tick(12)
	_check(_grounded(player), "fnd_precision: a 4 px foot edge on the mid platform must count as support (x=%.3f)" % player.position.x)
	_check(absf(player.position.y - 72.01) <= Y_TOL,
		"fnd_precision: edge support must hold the resting height (y=%.3f, want 72.01)" % player.position.y)
	launch_y = player.position.y
	Input.action_press("jump")
	await _tick(5)
	_check(player.position.y < launch_y - 3.0 and player.velocity.y < 0.0,
		"fnd_precision: must jump from the foot-edge support (y=%.3f from %.3f)" % [player.position.y, launch_y])
	_release_input()

	# Dropped into the empty air between the platforms, Warma must fall all
	# the way down to the floor; nothing may leave it hovering.
	_teleport(player, Vector2(160, 110))
	await _tick(35)
	_check(_grounded(player), "fnd_precision: falling between platforms must reach the floor")
	_check(absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_precision: must land on the floor (y=%.3f, want %.2f)" % [player.position.y, STAND_Y_GROUND])
	await _unload_room(room)

func _test_fnd_wall_jump() -> void:
	var room := _load_room(FND_WALL_JUMP)
	if room == null:
		return
	await _tick(12)
	var player := room.get_node("Player") as CharacterBody2D
	_check(player != null, "fnd_wall_jump: room must instantiate a Player")
	if player == null:
		await _unload_room(room)
		return

	# The col 8 wall (x 128..144) must stop the walk at exact side contact.
	_teleport(player, Vector2(116, 120))
	await _tick(2)
	_check(_grounded(player), "fnd_wall_jump: teleported state must be grounded")
	Input.action_press("move_right")
	await _tick(65)
	_check(absf(player.position.x - 125.0) <= X_TOL,
		"fnd_wall_jump: walking into the wall must reach exact side contact (x=%.3f, want 125.0)" % player.position.x)
	_check(_grounded(player), "fnd_wall_jump: must stay grounded while pressed into the wall")

	# Jumping while still pressing into the wall must launch upward without
	# penetrating the wall face.
	var launch_y := player.position.y
	Input.action_press("jump")
	await _tick(8)
	_check(player.position.y < launch_y - 4.0,
		"fnd_wall_jump: must jump while pressed into the wall (y=%.3f from %.3f)" % [player.position.y, launch_y])
	_check(player.position.x <= 125.0 + X_TOL,
		"fnd_wall_jump: the jump must not enter the wall (x=%.3f)" % player.position.x)
	_release_input()
	await _tick(90)
	_check(_grounded(player), "fnd_wall_jump: must land back on the floor after the wall jump")
	_check(absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_wall_jump: must rest on the floor (y=%.3f, want %.2f)" % [player.position.y, STAND_Y_GROUND])
	_check(absf(player.position.x - 125.0) <= X_TOL,
		"fnd_wall_jump: must stay on the near side of the wall (x=%.3f, want 125.0)" % player.position.x)
	await _unload_room(room)

func _test_fnd_button() -> void:
	var room := _load_room(FND_BUTTON)
	if room == null:
		return
	await _tick(2)
	var player := room.get_node("Player") as CharacterBody2D
	var button := room.get_node("Btn1")
	var lift := room.get_node("Lift1")
	_check(player != null and button != null and lift != null,
		"fnd_button: room must instantiate Player, Btn1 and Lift1")
	if player == null or button == null or lift == null:
		await _unload_room(room)
		return
	_check(not bool(button.get("activated")), "fnd_button: Btn1 must start released")
	_check(is_equal_approx(float(lift.get("current_height")), 3.0),
		"fnd_button: Lift1 must start at its 3 px minimum (h=%.3f)" % float(lift.get("current_height")))

	# Standing on the embedded plate (pressure zone spans y 128..132 above the
	# block at (7,8)) must activate it, and the 12 px/s lift then needs
	# (24-3)/12 = 1.75 s = 210 ticks to reach its maximum.
	_teleport(player, Vector2(120, 120))
	await _tick(2)
	_check(bool(button.get("activated")), "fnd_button: standing on Btn1 must activate it")
	await _tick(250)
	var height := float(lift.get("current_height"))
	_check(is_equal_approx(height, 24.0),
		"fnd_button: held plate must extend Lift1 to its 24 px clamp (h=%.3f after 250 ticks)" % height)
	_check(height <= 24.001, "fnd_button: Lift1 must clamp at its 24 px maximum (h=%.3f)" % height)

	# Leaving the plate must release it and let the lift retract fully.
	_teleport(player, Vector2(40, 120))
	await _tick(2)
	_check(not bool(button.get("activated")), "fnd_button: leaving Btn1 must release it")
	await _tick(250)
	height = float(lift.get("current_height"))
	_check(is_equal_approx(height, 3.0),
		"fnd_button: released plate must retract Lift1 to its 3 px floor (h=%.3f after 250 ticks)" % height)
	_check(height >= 2.99, "fnd_button: Lift1 must never retract below its 3 px minimum (h=%.3f)" % height)
	await _unload_room(room)

func _test_fnd_music_bullet() -> void:
	var saved := bool(game_state.get("has_extinguisher"))
	game_state.set("has_extinguisher", false)
	var room := _load_room(FND_MUSIC_BULLET)
	if room == null:
		game_state.set("has_extinguisher", saved)
		return
	await _tick(2)
	var player := room.get_node("Player") as CharacterBody2D
	var pickup := room.get_node_or_null("ExtinguisherPickup")
	var giraffe := room.get_node("Giraffe1") as CharacterBody2D
	_check(player != null and giraffe != null, "fnd_music_bullet: room must instantiate Player and Giraffe1")
	_check(pickup != null, "fnd_music_bullet: pickup must exist while has_extinguisher is false")
	if player == null or giraffe == null or pickup == null:
		await _unload_room(room)
		game_state.set("has_extinguisher", saved)
		return
	_check(absf(giraffe.position.x - 152.0) <= 0.1,
		"fnd_music_bullet: giraffe must start at its authored cell (x=%.3f)" % giraffe.position.x)

	# Walking into the pickup must grant the extinguisher and free the pickup.
	_teleport(player, Vector2(56, 120))
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "fnd_music_bullet: the pickup must grant has_extinguisher")
	_check(not is_instance_valid(pickup), "fnd_music_bullet: the pickup must be freed after collection")
	_check(player.get_node_or_null("EquipmentPivot") != null and player.get_node("EquipmentPivot").visible,
		"fnd_music_bullet: the held extinguisher must become visible")

	# A note spawned mid-room (manual spawn: player._fire_music_bullet would
	# parent to current_scene) must hit the giraffe and send it running right.
	var bullet := (load(BULLET_SCENE) as PackedScene).instantiate()
	bullet.call("setup", 1, 480.0, 0.03)
	room.add_child(bullet)
	bullet.global_position = Vector2(140, 113)
	await _tick(30)
	_check(giraffe.position.x > 153.0,
		"fnd_music_bullet: the note must hit the giraffe and move it right (x=%.3f)" % giraffe.position.x)
	_check(giraffe.velocity.x > 0.0,
		"fnd_music_bullet: the giraffe must still be running right (vx=%.3f)" % giraffe.velocity.x)

	# The run lasts 0.8 s = 96 ticks (24 px) plus the wind-down, so after the
	# total wait the giraffe must stand still, short of the col 12 wall.
	await _tick(110)
	_check(absf(giraffe.velocity.x) <= 0.5,
		"fnd_music_bullet: the giraffe must stop after the music run (vx=%.3f)" % giraffe.velocity.x)
	_check(giraffe.position.x < 197.0,
		"fnd_music_bullet: the giraffe must stop in front of the wall (x=%.3f)" % giraffe.position.x)
	_check(absf(giraffe.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_music_bullet: the giraffe must stay on the floor (y=%.3f)" % giraffe.position.y)
	await _unload_room(room)
	game_state.set("has_extinguisher", saved)

func _test_fnd_death_reset() -> void:
	var error := change_scene_to_file(FND_DEATH_RESET)
	_check(error == OK, "fnd_death_reset: change_scene_to_file must load the room")
	if error != OK:
		return
	var room := await _wait_for_current_scene() as Node2D
	_check(room != null and room.scene_file_path == FND_DEATH_RESET,
		"fnd_death_reset: current scene must be the death-reset room")
	if room == null:
		return
	await _tick(2)
	var player := room.get_node("Player") as CharacterBody2D
	_check(player != null, "fnd_death_reset: room must instantiate a Player")
	if player == null:
		return
	var spawn := player.position
	_check(absf(spawn.x - 40.0) <= 0.5 and absf(spawn.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_death_reset: the authored spawn must rest on the floor (spawn=%s)" % spawn)

	# Drop into the pit (cols 10-12): the bottom boundary must kill Warma and
	# the room must reload on its own. The deadline only guards against hangs.
	player.set("death_flash_duration", 0.04)
	_teleport(player, Vector2(180, 120))
	var deadline := Time.get_ticks_msec() + GUARD_MS
	while Time.get_ticks_msec() < deadline and is_instance_valid(room) and current_scene == room:
		await process_frame
	_check(current_scene != room,
		"fnd_death_reset: falling into the pit must trigger the death reset within the timeout")
	if current_scene == null:
		await _wait_for_current_scene()
	await _tick(2)
	var reset_room := current_scene as Node2D
	_check(reset_room != null and reset_room.scene_file_path == FND_DEATH_RESET,
		"fnd_death_reset: the reset must reload the same room")
	if reset_room == null:
		return
	var reset_player := reset_room.get_node_or_null("Player") as CharacterBody2D
	_check(reset_player != null, "fnd_death_reset: the reloaded room must instantiate a Player")
	if reset_player != null:
		_check(reset_player.position.distance_to(spawn) < 0.5,
			"fnd_death_reset: the reset must return Warma to the spawn (at %s, want %s)" % [reset_player.position, spawn])
		_check(_grounded(reset_player), "fnd_death_reset: the restored Warma must be grounded at the spawn")

	# The R key must drive the same room-level reset through the real input
	# action, not only the fall-limit path exercised above.
	var r_room := current_scene as Node2D
	var r_player := r_room.get_node_or_null("Player") as CharacterBody2D
	if r_player != null:
		r_player.set("death_flash_duration", 0.04)
		var r_event := InputEventKey.new()
		r_event.physical_keycode = KEY_R
		r_event.keycode = KEY_R
		r_event.pressed = true
		Input.parse_input_event(r_event)
		var r_deadline := Time.get_ticks_msec() + GUARD_MS
		while Time.get_ticks_msec() < r_deadline and is_instance_valid(r_room) and current_scene == r_room:
			await process_frame
		_check(current_scene != r_room,
			"fnd_death_reset: pressing R must trigger the death reset within the timeout")
		if current_scene == null:
			await _wait_for_current_scene()
		await _tick(2)
		var r_reset_room := current_scene as Node2D
		_check(r_reset_room != null and r_reset_room.scene_file_path == FND_DEATH_RESET,
			"fnd_death_reset: the R reset must reload the same room")
		if r_reset_room != null:
			var r_reset_player := r_reset_room.get_node_or_null("Player") as CharacterBody2D
			_check(r_reset_player != null and r_reset_player.position.distance_to(spawn) < 0.5,
				"fnd_death_reset: the R reset must return Warma to the spawn")
		var release := InputEventKey.new()
		release.physical_keycode = KEY_R
		release.keycode = KEY_R
		release.pressed = false
		Input.parse_input_event(release)

func _run() -> void:
	game_state = root.get_node("GameState")
	game_state.reset_speed()
	_release_input()
	await _test_fnd_movement()
	await _test_fnd_precision()
	await _test_fnd_wall_jump()
	await _test_fnd_button()
	await _test_fnd_music_bullet()
	await _test_fnd_death_reset()
	print("Foundation showcase checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
