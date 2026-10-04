extends SceneTree
## Physical smoke tests for the three MULTI and two CHALLENGE showcase rooms.
## Run: godot --headless --path . --script res://tests/showcase_test_multi_challenge.gd
##
## Physics runs at 120 Hz (project.godot), so 60 px/s walking moves 0.5 px per
## tick, a 24 px/s lift moves 0.2 px per tick, a 16 px/s lift moves 0.1333 px
## per tick and 300 px/s^2 gravity adds 2.5 px/s of fall speed each tick. A
## full held jump rises 38.1 px (apex at tick 60) and stays airborne 120 ticks,
## i.e. 60 px of drift. Assertions therefore target settled or clamped states
## (rest heights, fully extended lifts, landing planes) instead of mid-motion
## instants. Block bodies are 16x15.98, so a row-y block's top face sits at
## y*16+0.01; a resting Warma stands 0.01 below the nominal tile height and a
## resting giraffe settles 0.01 below its authored cell centre.
##
## Every room loads through change_scene_to_file so the death resets of the two
## CHALLENGE pits exercise the real current_scene path. Notes are fired manually
## (music_bullet.tscn + setup()) exactly the way the extinguisher does; a hit
## makes the giraffe run 0.8 s at 24 px/s (~19.2 px) plus a short friction slide
## (~3 px), so each note fired at a resting giraffe advances it ~22 px.
##
## Task-brief deviations kept honest against tools/showcase_room_defs.gd, the
## generated rooms/showcase/*.tscn and the object scripts:
##   - mlt_elevator_relay: walking from (100,72) to the middle platform needs
##     ~90 ticks (the brief's 60 ticks only cover 30 px of the 44 px walk);
##     the test holds move_right for 120 ticks.
##   - mlt_elevator_relay: a seam probe walks from the left tower onto Bridge1.
##     Block tops sit at 80.01; a horizontal lift's top is pos.y - 4 with no
##     edge inset, so the room now anchors Bridge1 at (48,84.01) - support 80.01,
##     0.01 px above the blocks - which makes the seam walkable both ways (an
##     earlier 80.00 anchoring formed a 0.01 px lip that stopped walking Warma
##     dead at the bridge face).
##   - chl_musical_freight: the giraffe centre window for Btn1 is 93..115 (the
##     pressure zone spans x 97..111 and the 8 px giraffe body widens it); in
##     practice the second note drives the giraffe against Lift1's retracted
##     rod face (x=116, body half-width 4) so it rests at x~112.
##   - chl_musical_freight: the brief's jump sequence (jump directly from the
##     lift top at (118,88)) is physically ~11 px short: even the optimal
##     rod-edge takeoff (centre 126) plus the 60 px maximum drift reaches only
##     ~186, while landing on the far bank needs centre > 189. The crossing is
##     therefore scripted through the documented 0.1 s support grace
##     (SUPPORT_GRACE_DURATION): walk off the rod edge, jump 10 ticks later,
##     which lands at x~191. The landing is asserted at x > 189.
##   - chl_vertical_climb was regenerated after the original route proved
##     unreachable: Lift2's top sat 48 px above the far bank ground (beyond the
##     38.1 px maximum jump rise) and Giraffe2 filled Lift2's 8 px support span.
##     The room now climbs via two stepping columns (A 7,6-7 top 96.01 whose
##     span catches the full-held pit jump's y=96.01 descent at x~122, and
##     B 9,5-6 top 80.01) before the tower jump; the test scripts every hop.

const ROOM_DIR := "res://rooms/showcase/"
const MLT_GIRAFFE_LOGISTICS := ROOM_DIR + "mlt_giraffe_logistics.tscn"
const MLT_STACK_FREIGHT := ROOM_DIR + "mlt_stack_freight.tscn"
const MLT_ELEVATOR_RELAY := ROOM_DIR + "mlt_elevator_relay.tscn"
const CHL_MUSICAL_FREIGHT := ROOM_DIR + "chl_musical_freight.tscn"
const CHL_VERTICAL_CLIMB := ROOM_DIR + "chl_vertical_climb.tscn"
const BULLET_SCENE := "res://objects/music_bullet.tscn"

const STAND_Y_GROUND := 120.01   # row 8 floor top face at 128.01
const HEAD_ON_FLOOR_Y := 120.01  # giraffe centre resting on the floor
const LIFT_TOP_32_Y := 88.01     # Warma centre on a 32 px lift top (96.01)
const LIFT_TOP_48_Y := 72.01     # Warma centre on a 48 px lift top (80.01)
const SHELF_TOP_64_Y := 56.01    # Warma centre on a row-4 block top (64.01)
const TOWER_TOP_48_Y := 40.01    # Warma centre on a row-3 block top (48.01)
const GIRAFFE_ON_32_Y := 88.01   # giraffe centre on a 32 px lift top
const GIRAFFE_ON_48_Y := 72.01   # giraffe centre on a 48 px lift top
const Y_TOL := 0.3
const X_TOL := 0.1
const GUARD_MS := 15000          # hang guard for scene-change waits
const SUITE_TIMEOUT_S := 300.0

enum Air { LANDED, FELL, GONE, TIMEOUT }

var failures: Array[String] = []
var game_state: Node
var saved_equipment := false

func _initialize() -> void:
	_run.call_deferred()

func _on_timeout() -> void:
	_check(false, "Timed out during the multi/challenge showcase checks")
	print("Multi/Challenge showcase checks: FAIL (timeout)")
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _tick(count: int = 1) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func _release_input() -> void:
	for action in ["jump", "move_left", "move_right", "fire_music", "interact", "reset"]:
		Input.action_release(action)

func _load_room(path: String) -> Node2D:
	_release_input()
	var error := change_scene_to_file(path)
	_check(error == OK, "%s: change_scene_to_file failed (%s)" % [path, error_string(error)])
	if error != OK:
		return null
	var deadline := Time.get_ticks_msec() + GUARD_MS
	while Time.get_ticks_msec() < deadline and (current_scene == null or current_scene.scene_file_path != path):
		await process_frame
	var room := current_scene as Node2D
	_check(room != null and room.scene_file_path == path,
		"%s: the room must become current_scene" % path)
	if room != null:
		await _tick(3)
	return room

func _room_node(room: Node, node_name: String) -> Node:
	if room == null or not is_instance_valid(room):
		return null
	return room.get_node_or_null(node_name)

func _teleport(player: CharacterBody2D, at: Vector2) -> void:
	player.velocity = Vector2.ZERO
	player.position = at

func _grounded(player: CharacterBody2D) -> bool:
	return bool(player.call("_has_ground_support"))

func _fire_note(from: Vector2) -> void:
	var bullet := (load(BULLET_SCENE) as PackedScene).instantiate() as Area2D
	_check(bullet != null, "music_bullet.tscn must instantiate")
	if bullet == null:
		return
	bullet.call("setup", 1, 480.0, 0.03)
	current_scene.add_child(bullet)
	bullet.global_position = from

func _wait_giraffe_rest(giraffe: CharacterBody2D) -> bool:
	for _i in range(400):
		if not is_instance_valid(giraffe):
			return false
		if float(giraffe.get("_music_run_time")) <= 0.0 and absf(giraffe.velocity.x) < 0.01:
			await _tick(3)
			return true
		await _tick(1)
	return false

## Fires one note from (from_x, 113) at a resting giraffe and asserts the run
## started, so the caller can trust the ~22 px advance afterwards.
func _herd_once(giraffe: CharacterBody2D, label: String, shot: int, from_x: float) -> void:
	await _wait_giraffe_rest(giraffe)
	if not is_instance_valid(giraffe):
		_check(false, "%s: note %d cannot fire, the giraffe vanished (room reset mid-herd)" % [label, shot])
		return
	_fire_note(Vector2(from_x, 113.0))
	await _tick(16)
	if not is_instance_valid(giraffe):
		_check(false, "%s: note %d was fired but the giraffe vanished before the run check" % [label, shot])
		return
	_check(float(giraffe.get("_music_run_time")) > 0.0,
		"%s: note %d must trigger the giraffe's music run" % [label, shot])

## Watches an airborne Warma until it lands, falls to its death, is freed by a
## room reset, or the budget runs out. y > 130 is below every landing plane in
## these rooms, so it means the jump has already failed.
func _watch_airborne(player: CharacterBody2D, max_ticks: int) -> Air:
	for _i in range(max_ticks):
		await _tick(1)
		if not is_instance_valid(player):
			return Air.GONE
		if player.position.y > 130.0:
			return Air.FELL
		if _grounded(player):
			return Air.LANDED
	return Air.TIMEOUT

## If Warma is dying (or still falling towards the death boundary), waits for
## the room's own reset and returns the fresh scene; otherwise returns the
## room unchanged. y > 130 is below every landing plane in these rooms, so it
## means the death sequence is inevitable even before _dying flips.
func _wait_pending_reset(room: Node2D, player: CharacterBody2D) -> Node2D:
	if room == null or not is_instance_valid(room):
		return current_scene as Node2D
	var deadline := Time.get_ticks_msec() + GUARD_MS
	while Time.get_ticks_msec() < deadline and is_instance_valid(room) and current_scene == room:
		if is_instance_valid(player) and not bool(player.get("_dying")) and player.position.y <= 130.0:
			break  # nobody is dying; the room is staying
		await process_frame
	if not is_instance_valid(room) or current_scene != room:
		# A reset is swapping (or has swapped) the scene: wait for the new one.
		while Time.get_ticks_msec() < deadline and current_scene == null:
			await process_frame
		await _tick(3)
		return current_scene as Node2D
	return room

func _describe(outcome: Air, player: CharacterBody2D) -> String:
	var state := "<freed>"
	if is_instance_valid(player):
		state = str(player.position)
	return "outcome=%d at %s" % [outcome, state]


# --------------------------------------------------------------------- 1
## mlt_giraffe_logistics: pickup at (40,124), Giraffe1 at (72,120), Btn1 at
## (136,136) (pressure zone x 129..143 above the plate), Lift1 at (168,128)
## min 3 max 32 speed 24, high platform cols 13-14 rows 6-7 (top 96.01).
func _test_mlt_giraffe_logistics() -> void:
	var label := "mlt_giraffe_logistics"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	var room := await _load_room(MLT_GIRAFFE_LOGISTICS)
	if room == null:
		return
	var player := _room_node(room, "Player") as CharacterBody2D
	var pickup := _room_node(room, "ExtinguisherPickup")
	var giraffe := _room_node(room, "Giraffe1") as CharacterBody2D
	var button := _room_node(room, "Btn1")
	var lift := _room_node(room, "Lift1")
	_check(player != null and giraffe != null and button != null and lift != null,
		"%s: room must instantiate Player, Giraffe1, Btn1 and Lift1" % label)
	_check(pickup != null, "%s: the pickup must exist while has_extinguisher is false" % label)
	if player == null or giraffe == null or button == null or lift == null:
		return
	await _tick(9)
	_check(not bool(game_state.get("has_extinguisher")), "%s: has_extinguisher must start false" % label)
	_check(not bool(button.get("activated")), "%s: Btn1 must start released" % label)
	_check(is_equal_approx(float(lift.get("current_height")), 3.0),
		"%s: Lift1 must start at its 3 px minimum (h=%.3f)" % [label, float(lift.get("current_height"))])
	_check(absf(giraffe.position.x - 72.0) <= X_TOL and absf(giraffe.position.y - HEAD_ON_FLOOR_Y) <= 0.1,
		"%s: the giraffe must settle at its authored cell (at %s)" % [label, giraffe.position])

	# Walking onto the pickup at (40,124) grants the extinguisher.
	_teleport(player, Vector2(40, 120))
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "%s: the pickup must grant has_extinguisher" % label)
	_check(not is_instance_valid(pickup), "%s: the pickup must be freed after collection" % label)

	# Three notes (each from 25 px behind the resting giraffe) advance it
	# ~22 px per hit: 72 -> ~94 -> ~116 -> ~139, inside the 129..143 window.
	for shot in range(3):
		await _herd_once(giraffe, label, shot + 1, giraffe.position.x - 25.0)
	var rested := await _wait_giraffe_rest(giraffe)
	_check(rested, "%s: the giraffe must come back to rest after the third note" % label)
	var final_x := giraffe.position.x
	_check(final_x >= 129.0 and final_x <= 143.0,
		"%s: three notes must herd the giraffe into Btn1's window 129..143 (got %.2f)" % [label, final_x])
	_check(absf(giraffe.position.y - HEAD_ON_FLOOR_Y) <= 0.1,
		"%s: the herded giraffe must stay on the floor (y=%.3f)" % [label, giraffe.position.y])
	_check(bool(button.get("activated")), "%s: the herded giraffe must press Btn1" % label)

	# (32-3)/24 = 1.208 s of growth => 145 ticks; 200 is plenty and the
	# giraffe keeps the plate held the whole time.
	await _tick(200)
	_check(is_equal_approx(float(lift.get("current_height")), 32.0),
		"%s: the pressed lift must reach its full 32 px extension (h=%.3f)" % [label, float(lift.get("current_height"))])
	_check(bool(button.get("activated")), "%s: Btn1 must stay activated while the lift extends" % label)

	# The extended lift top (support plane 96.01) must carry Warma at y ~88.01.
	_teleport(player, Vector2(168, 88))
	await _tick(12)
	_check(_grounded(player), "%s: the extended lift top must support Warma at (168,88)" % label)
	_check(absf(player.position.y - LIFT_TOP_32_Y) <= Y_TOL,
		"%s: Warma must rest on the lift top (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_32_Y])

	# The high platform (cols 13-14, rows 6-7, top 96.01) must carry her too.
	_teleport(player, Vector2(216, 88))
	await _tick(12)
	_check(_grounded(player), "%s: the high platform must support Warma at (216,88)" % label)
	_check(absf(player.position.y - LIFT_TOP_32_Y) <= Y_TOL,
		"%s: Warma must rest on the high platform (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_32_Y])


# --------------------------------------------------------------------- 2
## mlt_stack_freight: Lift1 at (152,128) is a static 32 px platform (top
## 96.01), Giraffe1 at (152,88) rests on it (centre 88.01), the row-4 shelf
## cols 12-15 has its top at 64.01.
func _test_mlt_stack_freight() -> void:
	var label := "mlt_stack_freight"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	var room := await _load_room(MLT_STACK_FREIGHT)
	if room == null:
		return
	var player := _room_node(room, "Player") as CharacterBody2D
	var giraffe := _room_node(room, "Giraffe1") as CharacterBody2D
	var lift := _room_node(room, "Lift1")
	_check(player != null and giraffe != null and lift != null,
		"%s: room must instantiate Player, Giraffe1 and Lift1" % label)
	if player == null or giraffe == null or lift == null:
		return
	await _tick(30)
	_check(is_equal_approx(float(lift.get("current_height")), 32.0),
		"%s: the static lift must stay fully extended at 32 (h=%.3f)" % [label, float(lift.get("current_height"))])
	var rest := giraffe.position
	_check(absf(rest.y - GIRAFFE_ON_32_Y) <= 0.1,
		"%s: the giraffe must rest on the lift top (y=%.3f, want %.2f)" % [label, rest.y, GIRAFFE_ON_32_Y])
	_check(is_zero_approx(giraffe.velocity.x) and is_zero_approx(giraffe.velocity.y),
		"%s: the giraffe must be at rest on the static lift (v=%s)" % [label, giraffe.velocity])
	await _tick(30)
	_check(giraffe.position.distance_to(rest) <= 0.05,
		"%s: the giraffe must not drift on the static lift (moved from %s to %s)" % [label, rest, giraffe.position])

	# The giraffe head (top face 80.01) must carry Warma at y ~72.01.
	_teleport(player, Vector2(152, 72))
	await _tick(12)
	_check(_grounded(player), "%s: the giraffe head must support Warma at (152,72)" % label)
	_check(absf(player.position.y - LIFT_TOP_48_Y) <= 0.1,
		"%s: Warma must stand on the giraffe head (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_48_Y])
	_check(giraffe.position.distance_to(rest) <= 0.05,
		"%s: Warma's weight must not shift the giraffe (moved to %s)" % [label, giraffe.position])

	# Jump from the head onto the row-4 shelf (top 64.01): a 25-tick hold
	# rises ~31 px and the ~43 px drift lands mid-shelf (x ~195).
	Input.action_press("move_right")
	Input.action_press("jump")
	await _tick(25)
	Input.action_release("jump")
	var outcome := await _watch_airborne(player, 120)
	_release_input()
	_check(outcome == Air.LANDED, "%s: the shelf jump must land on the shelf (%s)" % [label, _describe(outcome, player)])
	if outcome == Air.LANDED:
		_check(_grounded(player), "%s: Warma must stay grounded on the shelf" % label)
		_check(absf(player.position.y - SHELF_TOP_64_Y) <= Y_TOL,
			"%s: Warma must stand on the shelf (y=%.3f, want %.2f)" % [label, player.position.y, SHELF_TOP_64_Y])
		_check(player.position.x >= 192.0,
			"%s: the jump must reach the shelf span (x=%.2f, want >= 192)" % [label, player.position.x])
	await _tick(5)
	if is_instance_valid(giraffe):
		_check(giraffe.position.distance_to(rest) <= 0.05,
			"%s: the giraffe must stay on the lift through the jump (moved to %s)" % [label, giraffe.position])


# --------------------------------------------------------------------- 3
## mlt_elevator_relay: Bridge1 at (48,84.01) spans x 48..144 at top 80.01, the
## middle platform cols 9-11 has its top at 80.01, Btn1 (168,88) is embedded
## in it with Giraffe1 resting on top (centre 72.01), Lift1 at (216,128)
## min 3 max 48 speed 16 stays extended while the giraffe holds the plate,
## right tower cols 14-15 rows 3-8 (top 48.01).
func _test_mlt_elevator_relay() -> void:
	var label := "mlt_elevator_relay"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	var room := await _load_room(MLT_ELEVATOR_RELAY)
	if room == null:
		return
	var player := _room_node(room, "Player") as CharacterBody2D
	var giraffe := _room_node(room, "Giraffe1") as CharacterBody2D
	var button := _room_node(room, "Btn1")
	var lift := _room_node(room, "Lift1")
	var bridge := _room_node(room, "Bridge1")
	_check(player != null and giraffe != null and button != null and lift != null and bridge != null,
		"%s: room must instantiate Player, Giraffe1, Btn1, Lift1 and Bridge1" % label)
	if player == null or giraffe == null or button == null or lift == null or bridge == null:
		return
	_check(is_equal_approx(float(bridge.get("current_height")), 96.0),
		"%s: Bridge1 must start fully extended (h=%.3f)" % [label, float(bridge.get("current_height"))])
	# (48-3)/16 = 2.8125 s of growth => 337.5 ticks; 400 covers it.
	await _tick(400)
	_check(bool(button.get("activated")), "%s: the giraffe resting on Btn1 must keep it activated" % label)
	_check(is_equal_approx(float(lift.get("current_height")), 48.0),
		"%s: the latched lift must stay fully extended at 48 (h=%.3f)" % [label, float(lift.get("current_height"))])
	_check(absf(giraffe.position.x - 168.0) <= X_TOL and absf(giraffe.position.y - GIRAFFE_ON_48_Y) <= 0.1,
		"%s: the giraffe must rest on the button cell (at %s, want y %.2f)" % [label, giraffe.position, GIRAFFE_ON_48_Y])

	# Seam probe: walking from the left tower onto Bridge1 must work without a
	# jump - the bridge support plane (80.01) sits exactly flush with the block tops.
	_teleport(player, Vector2(16, 72))
	await _tick(6)
	Input.action_press("move_right")
	var crossed := false
	var observed_x := 0.0
	for _i in range(120):
		await _tick(1)
		observed_x = player.position.x
		if player.position.x > 60.0:
			crossed = true
			break
	_release_input()
	_check(crossed, "%s: walking from the left tower must cross onto Bridge1 (stopped at x=%.2f; block top 80.01 vs bridge top 80.00 forms a 0.01 px lip)" % [label, observed_x])
	if crossed:
		_check(_grounded(player), "%s: Warma must stay grounded across the seam (x=%.2f)" % [label, observed_x])

	# Bridge1's top (80.0) must carry Warma at y ~72.01 ...
	_teleport(player, Vector2(100, 72))
	await _tick(12)
	_check(_grounded(player), "%s: Bridge1 must support Warma at (100,72)" % label)
	_check(absf(player.position.y - LIFT_TOP_48_Y) <= Y_TOL,
		"%s: Warma must stand on Bridge1 (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_48_Y])
	# ... and walking right must reach the middle platform (x 144..192). The
	# walk is ~44 px => ~90 ticks; the test holds right for 120.
	Input.action_press("move_right")
	await _tick(120)
	_release_input()
	_check(player.position.x > 144.0,
		"%s: Warma must walk onto the middle platform (x=%.2f, want > 144)" % [label, player.position.x])
	_check(_grounded(player), "%s: Warma must stay grounded across the bridge seam" % label)
	_check(absf(player.position.y - LIFT_TOP_48_Y) <= Y_TOL,
		"%s: Warma must keep its height onto the platform (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_48_Y])

	# Lift1's extended top (support plane 80.01) must carry Warma at y ~72.01.
	_teleport(player, Vector2(216, 72))
	await _tick(12)
	_check(_grounded(player), "%s: Lift1's extended top must support Warma at (216,72)" % label)
	_check(absf(player.position.y - LIFT_TOP_48_Y) <= Y_TOL,
		"%s: Warma must stand on Lift1's top (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_48_Y])

	# Jump onto the right tower (top 48.01): a 30-tick hold clears the 32 px
	# face while pressed against it and lands on the tower top (x ~236).
	Input.action_press("move_right")
	Input.action_press("jump")
	await _tick(30)
	Input.action_release("jump")
	var outcome := await _watch_airborne(player, 120)
	_release_input()
	_check(outcome == Air.LANDED, "%s: the tower jump must land on the tower (%s)" % [label, _describe(outcome, player)])
	if outcome == Air.LANDED:
		_check(_grounded(player), "%s: Warma must stay grounded on the tower" % label)
		_check(absf(player.position.y - TOWER_TOP_48_Y) <= Y_TOL,
			"%s: Warma must stand on the tower top (y=%.3f, want %.2f)" % [label, player.position.y, TOWER_TOP_48_Y])
		_check(player.position.x >= 224.0,
			"%s: the jump must reach the tower span (x=%.2f, want >= 224)" % [label, player.position.x])


# --------------------------------------------------------------------- 4
## chl_musical_freight: pickup at (40,124), Giraffe1 at (72,120), Btn1 at
## (104,136) (zone x 97..111), Lift1 at (120,128) min 3 max 32 speed 24, the
## pit spans x 144..192 (no floor), far platform cols 12-15 (top 96.01).
func _test_chl_musical_freight() -> void:
	var label := "chl_musical_freight"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	var room := await _load_room(CHL_MUSICAL_FREIGHT)
	if room == null:
		return
	var player := _room_node(room, "Player") as CharacterBody2D
	var pickup := _room_node(room, "ExtinguisherPickup")
	var giraffe := _room_node(room, "Giraffe1") as CharacterBody2D
	var button := _room_node(room, "Btn1")
	var lift := _room_node(room, "Lift1")
	_check(player != null and giraffe != null and button != null and lift != null,
		"%s: room must instantiate Player, Giraffe1, Btn1 and Lift1" % label)
	_check(pickup != null, "%s: the pickup must exist while has_extinguisher is false" % label)
	if player == null or giraffe == null or button == null or lift == null:
		return
	await _tick(9)
	_check(absf(giraffe.position.x - 72.0) <= X_TOL and absf(giraffe.position.y - HEAD_ON_FLOOR_Y) <= 0.1,
		"%s: the giraffe must settle at its authored cell (at %s)" % [label, giraffe.position])
	_check(not bool(button.get("activated")), "%s: Btn1 must start released" % label)

	_teleport(player, Vector2(40, 120))
	await _tick(3)
	_check(bool(game_state.get("has_extinguisher")), "%s: the pickup must grant has_extinguisher" % label)
	_check(not is_instance_valid(pickup), "%s: the pickup must be freed after collection" % label)

	# Exactly two notes: the first from (60,113) advances the giraffe to ~94,
	# the second from (80,113) must hit before the lift extends (an extended
	# rod would block the y=113 note line). The run ends against Lift1's
	# retracted rod face (x=116 - body half-width 4 = centre ~112), inside the
	# giraffe centre window 93..115.
	await _herd_once(giraffe, label, 1, 60.0)
	await _herd_once(giraffe, label, 2, 80.0)
	var rested := await _wait_giraffe_rest(giraffe)
	_check(rested, "%s: the giraffe must come back to rest after the second note" % label)
	var final_x := giraffe.position.x
	_check(final_x >= 93.0 and final_x <= 115.0,
		"%s: two notes must herd the giraffe into Btn1's centre window 93..115 (got %.2f)" % [label, final_x])
	_check(absf(giraffe.position.y - HEAD_ON_FLOOR_Y) <= 0.1,
		"%s: the herded giraffe must stay on the floor (y=%.3f)" % [label, giraffe.position.y])
	_check(bool(button.get("activated")), "%s: the herded giraffe must press Btn1" % label)
	await _tick(200)
	_check(is_equal_approx(float(lift.get("current_height")), 32.0),
		"%s: the pressed lift must reach its full 32 px extension (h=%.3f)" % [label, float(lift.get("current_height"))])

	# The brief's literal sequence, kept as a diagnostic probe: jumping
	# directly from the lift top at (118,88) cannot reach the far bank (the
	# optimal rod-edge takeoff plus the 60 px drift tops out at ~186 vs the
	# required > 189), so this is expected to drop into the pit.
	_teleport(player, Vector2(118, 88))
	await _tick(12)
	_check(_grounded(player), "%s: the extended lift top must support Warma at (118,88)" % label)
	_check(absf(player.position.y - LIFT_TOP_32_Y) <= Y_TOL,
		"%s: Warma must rest on the lift top (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_32_Y])
	Input.action_press("move_right")
	Input.action_press("jump")
	await _tick(30)
	Input.action_release("jump")
	await _tick(60)
	Input.action_release("move_right")
	var probe := await _watch_airborne(player, 200)
	print(label, ": brief-sequence jump probe %s" % _describe(probe, player))
	if probe == Air.LANDED and is_instance_valid(player) and player.position.x > 189.0:
		_check(absf(player.position.y - LIFT_TOP_32_Y) <= Y_TOL,
			"%s: the brief-sequence jump must land on the far bank plane (y=%.3f)" % [label, player.position.y])
		_check(_grounded(player), "%s: the brief-sequence jump must end grounded" % label)
		return

	# The probe fell short as physics predicts: recover through the room's own
	# death reset and cross with the documented 0.1 s support grace instead.
	var reloaded := await _wait_pending_reset(room, player)
	_check(reloaded != null and is_instance_valid(reloaded), "%s: the room must reload after the pit death" % label)
	if reloaded == null:
		return
	await _tick(9)
	player = _room_node(reloaded, "Player") as CharacterBody2D
	giraffe = _room_node(reloaded, "Giraffe1") as CharacterBody2D
	button = _room_node(reloaded, "Btn1")
	lift = _room_node(reloaded, "Lift1")
	_check(player != null and giraffe != null and button != null and lift != null,
		"%s: the reloaded room must instantiate Player, Giraffe1, Btn1 and Lift1" % label)
	if player == null or giraffe == null or button == null or lift == null:
		return
	await _herd_once(giraffe, label, 1, 60.0)
	await _herd_once(giraffe, label, 2, 80.0)
	rested = await _wait_giraffe_rest(giraffe)
	_check(rested, "%s: the re-herded giraffe must come back to rest" % label)
	_check(bool(button.get("activated")), "%s: the re-herded giraffe must press Btn1" % label)
	await _tick(200)
	_check(is_equal_approx(float(lift.get("current_height")), 32.0),
		"%s: the re-pressed lift must reach 32 again (h=%.3f)" % [label, float(lift.get("current_height"))])

	_teleport(player, Vector2(118, 88))
	await _tick(12)
	_check(_grounded(player), "%s: the extended lift top must support Warma again" % label)
	# Support-grace crossing: walk off the rod's right edge (support range
	# ends at centre 126) and jump on the 10th unsupported tick, well inside
	# the 0.1 s (12 tick) grace. The jump must be held for the whole flight
	# (any release cuts the rise and falls ~10 px short); the landing poll
	# releases the input before the buffered re-jump frame can fire. Lands at
	# x ~191 on the far bank (top 96.01).
	var jumped := false
	Input.action_press("move_right")
	var unsupported := 0
	for _i in range(60):
		await _tick(1)
		if not is_instance_valid(player):
			break
		if _grounded(player):
			unsupported = 0
		else:
			unsupported += 1
			if unsupported == 10:
				Input.action_press("jump")
				jumped = true
				break
	_check(jumped, "%s: the support-grace jump must fire after walking off the rod edge" % label)
	var outcome := Air.GONE
	if jumped:
		outcome = await _watch_airborne(player, 200)
	_release_input()
	_check(outcome == Air.LANDED, "%s: the support-grace jump must cross the 48 px abyss (%s)" % [label, _describe(outcome, player)])
	if outcome == Air.LANDED:
		print(label, ": support-grace crossing landed at %s" % player.position)
		_check(player.position.x > 189.0,
			"%s: Warma must land on the far bank (x=%.2f, want > 189)" % [label, player.position.x])
		_check(absf(player.position.y - LIFT_TOP_32_Y) <= Y_TOL,
			"%s: Warma must land on the far bank plane (y=%.3f, want %.2f)" % [label, player.position.y, LIFT_TOP_32_Y])
		_check(_grounded(player), "%s: Warma must stay grounded on the far bank" % label)


# --------------------------------------------------------------------- 5
## chl_vertical_climb (regenerated): Lift1 (56,128) static 32 (top 96.01) with
## Giraffe1 on top (centre 88.01), pit x 96..128, stepping column A (7,6)+(7,7)
## (span 112..128, top 96.01), column B (9,5)+(9,6) (span 144..160, top 80.01),
## right tower cols 12-15 rows 3-7 (top 48.01). The full-held pit jump from
## Giraffe1's head crosses its 96.01 descent line at x~122, inside A's span.
func _test_chl_vertical_climb() -> void:
	var label := "chl_vertical_climb"
	print(label, ": running ...")
	game_state.set("has_extinguisher", false)
	var room := await _load_room(CHL_VERTICAL_CLIMB)
	if room == null:
		return
	var player := _room_node(room, "Player") as CharacterBody2D
	var giraffe1 := _room_node(room, "Giraffe1") as CharacterBody2D
	var lift1 := _room_node(room, "Lift1")
	_check(player != null and giraffe1 != null and lift1 != null,
		"%s: room must instantiate Player, Giraffe1 and Lift1" % label)
	if player == null or giraffe1 == null or lift1 == null:
		return
	await _tick(30)
	_check(is_equal_approx(float(lift1.get("current_height")), 32.0),
		"%s: Lift1 must stay extended at 32 (h=%.3f)" % [label, float(lift1.get("current_height"))])
	var rest1 := giraffe1.position
	_check(absf(rest1.x - 56.0) <= X_TOL and absf(rest1.y - GIRAFFE_ON_32_Y) <= 0.1,
		"%s: Giraffe1 must rest on Lift1's top (at %s, want y %.2f)" % [label, rest1, GIRAFFE_ON_32_Y])
	_check(is_zero_approx(giraffe1.velocity.x) and is_zero_approx(giraffe1.velocity.y),
		"%s: Giraffe1 must be at rest on the static lift" % label)
	await _tick(30)
	_check(giraffe1.position.distance_to(rest1) <= 0.05,
		"%s: Giraffe1 must not drift on its static lift (%s)" % [label, giraffe1.position])

	# Giraffe1's head (top 80.01) must carry Warma at y ~72.01.
	_teleport(player, Vector2(56, 72))
	await _tick(12)
	_check(_grounded(player), "%s: Giraffe1's head must support Warma at (56,72)" % label)
	_check(absf(player.position.y - 72.01) <= 0.1,
		"%s: Warma must stand on Giraffe1's head (y=%.3f, want 72.01)" % [label, player.position.y])

	# Full-held pit jump: the descent crosses y=96.01 at x~122, inside stepping
	# column A (112..128), so Warma must land grounded on A at y ~88.01.
	Input.action_press("move_right")
	Input.action_press("jump")
	var outcome := await _watch_airborne(player, 200)
	_release_input()
	var on_a := outcome == Air.LANDED and is_instance_valid(player) \
		and player.position.x >= 112.0 and player.position.x <= 128.0 \
		and absf(player.position.y - 88.01) <= Y_TOL
	_check(on_a,
		"%s: the pit jump must land on stepping column A (got %s)" % [label, _describe(outcome, player)])
	if not on_a or not is_instance_valid(player):
		return

	# Column A (96.01) -> column B (80.01): the full-held jump's descent crosses
	# y=80.01 at x~162, inside B's span (144..192, cols 9-11, flush with the
	# tower face).
	Input.action_press("move_right")
	Input.action_press("jump")
	outcome = await _watch_airborne(player, 200)
	_release_input()
	var on_b := outcome == Air.LANDED and is_instance_valid(player) \
		and player.position.x >= 144.0 and player.position.x <= 192.0 \
		and absf(player.position.y - 72.01) <= Y_TOL
	_check(on_b,
		"%s: the jump from column A must land on column B (got %s)" % [label, _describe(outcome, player)])
	if not on_b or not is_instance_valid(player):
		return

	# Walk to the tower face (B runs flush into it) so the climb is the proven
	# pressed-against-the-face jump: rise 32 px along the face, clear the top,
	# drift right onto the tower.
	Input.action_press("move_right")
	for _i in range(60):
		await _tick(1)
		if player.position.x >= 186.0:
			break
	_release_input()
	await _tick(6)
	_check(_grounded(player) and absf(player.position.y - 72.01) <= Y_TOL and player.position.x >= 170.0,
		"%s: Warma must wait at the tower face on column B (x=%.2f y=%.3f)" % [label, player.position.x, player.position.y])

	# Column B (80.01) -> tower (48.01): a 30-tick hold clears the 32 px rise
	# and lands on the tower.
	Input.action_press("move_right")
	Input.action_press("jump")
	await _tick(30)
	Input.action_release("jump")
	outcome = await _watch_airborne(player, 120)
	_release_input()
	_check(outcome == Air.LANDED, "%s: the tower jump from column B must land on the tower (%s)" % [label, _describe(outcome, player)])
	if outcome == Air.LANDED and is_instance_valid(player):
		_check(_grounded(player), "%s: Warma must stay grounded on the tower" % label)
		_check(absf(player.position.y - TOWER_TOP_48_Y) <= Y_TOL,
			"%s: Warma must stand on the tower top (y=%.3f, want %.2f)" % [label, player.position.y, TOWER_TOP_48_Y])
		_check(player.position.x >= 192.0,
			"%s: the jump must reach the tower span (x=%.2f, want >= 192)" % [label, player.position.x])


func _run() -> void:
	# Bound the whole run so a missing transition reports failure, not a hang.
	create_timer(SUITE_TIMEOUT_S).timeout.connect(_on_timeout)
	_release_input()
	root.get_node_or_null("GameState").reset_speed()
	game_state = root.get_node_or_null("GameState")
	_check(game_state != null, "GameState autoload must exist")
	if game_state == null:
		print("Multi/Challenge showcase checks: FAIL (1)")
		quit(1)
		return
	saved_equipment = bool(game_state.get("has_extinguisher"))
	await _test_mlt_giraffe_logistics()
	await _test_mlt_stack_freight()
	await _test_mlt_elevator_relay()
	await _test_chl_musical_freight()
	await _test_chl_vertical_climb()
	_release_input()
	game_state.set("has_extinguisher", saved_equipment)
	print("Multi/Challenge showcase checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
