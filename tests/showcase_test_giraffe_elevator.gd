extends SceneTree
## Physical smoke tests for the three GIRAFFE and three ELEVATOR showcase rooms.
## Run: godot --headless --path . --script res://tests/showcase_test_giraffe_elevator.gd
##
## Physics runs at 120 Hz (project.godot), so 60 px/s walking moves 0.5 px per
## tick, a 12 px/s lift moves 0.1 px per tick and a 16 px/s lift moves 0.1333 px
## per tick. A full held jump rises 37.5 px (apex at tick 60). Assertions
## therefore target settled or clamped states instead of mid-motion instants.
## Block bodies are 16x15.98, so a row-y block's top face sits at y*16+0.01: a
## resting Warma stands at 120.01 on the floor and a resting giraffe settles
## 0.01 below its authored cell centre.
##
## Task-brief deviations kept honest against tools/showcase_room_defs.gd and the
## generated rooms/showcase/*.tscn:
##   - elv_horizontal Bridge1 is authored at (48,84) and spans x 48..128 at top
##     80.0, flush with the left tower's right face and the middle platform's
##     left face (an earlier draft anchored it 16 px off the face, which left a
##     hole a walking Warma would fall into; the room was regenerated).
##   - elv_down: releasing the button RETRACTS a lift that does not start
##     extended (elevator.gd released_target = min_height), so the brief's
##     "height == 68 after leaving the button" cannot happen; the retract to
##     3 px is asserted instead, and the unobstructed full 68 px extension is
##     verified through the documented set_button_active(true) contract with
##     Warma standing clear of the rod.
##   - elv_horizontal: the jump onto Bridge2 holds the jump 20 ticks, not the
##     brief's 30: Bridge2's support range ends at x=207.99 and a 30-tick hold
##     drifts the 48 px flight to x~210, overflying Bridge2 onto the right
##     tower's row-5 shoulder (top 80.01; the tower's row 4 spans only
##     cols 14-15). A 20-tick hold lands mid-bridge at the 64 px level.
##   - fnd_giraffe_bump was regenerated after the first draft hid the giraffe
##     behind a pedestal block: the bump rule (warma.gd _lift_giraffes_above)
##     sweeps only ~1.3 px beyond the head on the launch tick, so the giraffe
##     must already rest on Warma's head. The room now spawns Warma directly
##     beneath Giraffe1, which settles flush onto the head at 104.01.

const FND_GIRAFFE_CONTACT := "res://rooms/showcase/fnd_giraffe_contact.tscn"
const FND_GIRAFFE_STACK := "res://rooms/showcase/fnd_giraffe_stack.tscn"
const FND_GIRAFFE_BUMP := "res://rooms/showcase/fnd_giraffe_bump.tscn"
const ELV_UP := "res://rooms/showcase/elv_up.tscn"
const ELV_DOWN := "res://rooms/showcase/elv_down.tscn"
const ELV_HORIZONTAL := "res://rooms/showcase/elv_horizontal.tscn"

const STAND_Y_GROUND := 120.01   # row 8 floor top face at 128.01
const GIRAFFE1_REST_Y := 120.01  # giraffe centre resting on the floor
const GIRAFFE2_REST_Y := 104.01  # giraffe centre resting on giraffe 1
const GIRAFFE3_REST_Y := 88.01   # giraffe 3 falls from 72 onto giraffe 2
const X_TOL := 0.1
const Y_TOL := 0.3

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

## fnd_giraffe_contact: side contact blocks Warma without dragging the giraffe,
## the head carries Warma, and walking away leaves the giraffe untouched.
func _test_fnd_giraffe_contact() -> void:
	var room := _load_room(FND_GIRAFFE_CONTACT)
	if room == null:
		return
	await _tick(12)
	var player := room.get_node("Player") as CharacterBody2D
	var giraffe := room.get_node("Giraffe1") as CharacterBody2D
	_check(player != null and giraffe != null,
		"fnd_giraffe_contact: room must instantiate Player and Giraffe1")
	if player == null or giraffe == null:
		await _unload_room(room)
		return
	_check(absf(giraffe.position.x - 136.0) <= X_TOL and absf(giraffe.position.y - GIRAFFE1_REST_Y) <= 0.1,
		"fnd_giraffe_contact: the giraffe must settle at its authored cell (at %s)" % giraffe.position)

	# Walking right into the giraffe's left face (x 132.0) must stop Warma with
	# its right body edge (x + 3) at the face, at x = 129.0.
	_teleport(player, Vector2(100, 120))
	await _tick(2)
	Input.action_press("move_right")
	await _tick(60)
	_release_input()
	_check(absf(player.position.x - 129.0) <= X_TOL,
		"fnd_giraffe_contact: walking into the giraffe must stop at its face (x=%.3f, want 129.0)" % player.position.x)
	_check(_grounded(player),
		"fnd_giraffe_contact: Warma must stay grounded while blocked by the giraffe")
	_check(absf(giraffe.position.x - 136.0) <= X_TOL,
		"fnd_giraffe_contact: side contact must not push the giraffe (x=%.3f)" % giraffe.position.x)
	_check(is_zero_approx(giraffe.velocity.x),
		"fnd_giraffe_contact: the giraffe must keep zero horizontal velocity (vx=%.3f)" % giraffe.velocity.x)

	# The giraffe head (top face at 112.01) must carry Warma at y ~104.01.
	_teleport(player, Vector2(136, 104))
	await _tick(12)
	_check(_grounded(player), "fnd_giraffe_contact: the giraffe head must support Warma")
	_check(absf(player.position.y - 104.01) <= 0.1,
		"fnd_giraffe_contact: Warma must stand on the giraffe head (y=%.3f, want 104.01)" % player.position.y)

	# Walking off the head must drop Warma to the floor and leave the giraffe
	# exactly where it stood.
	Input.action_press("move_right")
	await _tick(20)
	_release_input()
	var landed := false
	for _i in range(60):
		await _tick(1)
		if _grounded(player):
			landed = true
			break
	_check(landed, "fnd_giraffe_contact: Warma must land on the floor after walking off")
	_check(player.position.x > 141.0,
		"fnd_giraffe_contact: Warma must walk past the giraffe (x=%.3f)" % player.position.x)
	_check(absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_giraffe_contact: Warma must rest on the floor (y=%.3f, want %.2f)" % [player.position.y, STAND_Y_GROUND])
	_check(absf(giraffe.position.x - 136.0) <= X_TOL and absf(giraffe.position.y - GIRAFFE1_REST_Y) <= 0.1,
		"fnd_giraffe_contact: walking over the giraffe must not move it (at %s)" % giraffe.position)
	await _unload_room(room)

## fnd_giraffe_stack: three giraffes settle into a stable tower at 120.01 /
## 104.01 / 88.01 (the third is authored a tier higher and falls onto the
## second), and the tower must hold Warma without shifting.
func _test_fnd_giraffe_stack() -> void:
	var room := _load_room(FND_GIRAFFE_STACK)
	if room == null:
		return
	await _tick(90)
	var player := room.get_node("Player") as CharacterBody2D
	var giraffes: Array[CharacterBody2D] = [
		room.get_node("Giraffe1") as CharacterBody2D,
		room.get_node("Giraffe2") as CharacterBody2D,
		room.get_node("Giraffe3") as CharacterBody2D,
	]
	var all_found := player != null
	for giraffe in giraffes:
		all_found = all_found and giraffe != null
	_check(all_found, "fnd_giraffe_stack: room must instantiate Player and Giraffe1..3")
	if not all_found:
		await _unload_room(room)
		return
	var expected_y := [GIRAFFE1_REST_Y, GIRAFFE2_REST_Y, GIRAFFE3_REST_Y]
	for index in giraffes.size():
		var giraffe := giraffes[index]
		_check(absf(giraffe.position.x - 136.0) < 0.1 and absf(giraffe.position.y - float(expected_y[index])) < 0.1,
			"fnd_giraffe_stack: giraffe %d must settle stacked (at %s, want x 136.0 y %.2f)" % [index + 1, giraffe.position, float(expected_y[index])])
		_check(is_zero_approx(giraffe.velocity.y),
			"fnd_giraffe_stack: giraffe %d must be at rest (vy=%.3f)" % [index + 1, giraffe.velocity.y])

	# The stack top (giraffe 3 top face at 80.01) must carry Warma at y ~72.01.
	_teleport(player, Vector2(136, 72))
	await _tick(12)
	_check(_grounded(player), "fnd_giraffe_stack: the stack top must support Warma")
	_check(absf(player.position.y - 72.01) <= 0.1,
		"fnd_giraffe_stack: Warma must stand on the stack top (y=%.3f, want 72.01)" % player.position.y)

	# The tower must not shift under Warma's weight.
	var snapshot: Array[Vector2] = [giraffes[0].position, giraffes[1].position, giraffes[2].position]
	await _tick(30)
	for index in giraffes.size():
		_check(giraffes[index].position.distance_to(snapshot[index]) <= 0.05,
			"fnd_giraffe_stack: giraffe %d must hold still under Warma (moved from %s to %s)" % [index + 1, snapshot[index], giraffes[index].position])
	await _unload_room(room)

## fnd_giraffe_bump: Warma spawns directly beneath Giraffe1, which settles
## flush onto Warma's head (centre 104.01) at load. The bump rule
## (warma.gd _lift_giraffes_above) sweeps only ~1.3 px beyond the head on the
## launch tick, so this flush resting contact is the geometry that makes the
## advertised jump-bump work; the giraffe falls back onto the head afterwards.
func _test_fnd_giraffe_bump() -> void:
	var room := _load_room(FND_GIRAFFE_BUMP)
	if room == null:
		return
	await _tick(12)
	var player := room.get_node("Player") as CharacterBody2D
	var giraffe := room.get_node("Giraffe1") as CharacterBody2D
	_check(player != null and giraffe != null,
		"fnd_giraffe_bump: room must instantiate Player and Giraffe1")
	if player == null or giraffe == null:
		await _unload_room(room)
		return
	var head_rest_y := 104.01
	_check(absf(giraffe.position.y - head_rest_y) <= 0.1,
		"fnd_giraffe_bump: the giraffe must rest flush on Warma's head (y=%.3f, want %.2f)" % [giraffe.position.y, head_rest_y])
	_check(_grounded(player) and absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_giraffe_bump: Warma must stand on the floor under the giraffe (y=%.3f)" % player.position.y)

	# A held jump bumps the giraffe upward through the explicit vertical
	# impulse, both bodies rise together, and the giraffe falls back onto the
	# head - the room's advertised repeatable bump.
	var launched := false
	Input.action_press("jump")
	var minimum_giraffe_y := giraffe.position.y
	for _i in range(90):
		await _tick(1)
		minimum_giraffe_y = minf(minimum_giraffe_y, giraffe.position.y)
		if giraffe.position.y < 70.0:
			launched = true
			break
	Input.action_release("jump")
	_check(launched and minimum_giraffe_y < 70.0,
		"fnd_giraffe_bump: a held jump must bump the head-resting giraffe upward (min y=%.3f)" % minimum_giraffe_y)
	var back_on_head := false
	for _i in range(180):
		await _tick(1)
		if absf(giraffe.position.y - head_rest_y) <= 0.5:
			back_on_head = true
			break
	_check(back_on_head and absf(giraffe.position.x - 136.0) <= X_TOL,
		"fnd_giraffe_bump: the giraffe must fall back onto Warma's head (y=%.3f x=%.3f)" % [giraffe.position.y, giraffe.position.x])
	_check(_grounded(player) and absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"fnd_giraffe_bump: Warma must land back on the floor (y=%.3f)" % player.position.y)

	# Sliding out from beneath the giraffe drops it: support loss stays honest.
	Input.action_press("move_left")
	await _tick(20)
	Input.action_release("move_left")
	await _tick(60)
	_check(absf(giraffe.position.y - GIRAFFE1_REST_Y) <= 0.1,
		"fnd_giraffe_bump: after Warma slides out the giraffe must rest on the floor (y=%.3f)" % giraffe.position.y)
	await _unload_room(room)

## elv_up: Lift1 (min 3, max 24, 12 px/s) extends while Btn1 is held; Lift2 is a
## static 16 px platform flush with the (11,7)/(12,7) block tops at ~112.
func _test_elv_up() -> void:
	var room := _load_room(ELV_UP)
	if room == null:
		return
	await _tick(12)
	var player := room.get_node("Player") as CharacterBody2D
	var button := room.get_node("Btn1")
	var lift1 := room.get_node("Lift1")
	var lift2 := room.get_node("Lift2")
	_check(player != null and button != null and lift1 != null and lift2 != null,
		"elv_up: room must instantiate Player, Btn1, Lift1 and Lift2")
	if player == null or button == null or lift1 == null or lift2 == null:
		await _unload_room(room)
		return
	_check(not bool(button.get("activated")), "elv_up: Btn1 must start released")
	_check(is_equal_approx(float(lift1.get("current_height")), 3.0),
		"elv_up: Lift1 must start at its 3 px minimum (h=%.3f)" % float(lift1.get("current_height")))
	_check(is_equal_approx(float(lift2.get("current_height")), 16.0),
		"elv_up: Lift2 must start fully extended (h=%.3f)" % float(lift2.get("current_height")))
	_check(absf(float(lift2.call("get_support_surface_y")) - 112.005) <= 0.01,
		"elv_up: Lift2's support surface must sit at its 16 px top (y=%.3f)" % float(lift2.call("get_support_surface_y")))

	# Lift2 must carry Warma on its top (support plane 112.005 -> y ~104.005).
	_teleport(player, Vector2(212, 104))
	await _tick(12)
	_check(_grounded(player), "elv_up: Lift2 must support Warma")
	_check(absf(player.position.y - 104.01) <= 0.05,
		"elv_up: Warma must stand on Lift2's top (y=%.3f, want 104.01)" % player.position.y)
	_check(bool(lift2.call("supports_body", player, 0.75)),
		"elv_up: Lift2 must report Warma as supported")

	# Walking right must cross Lift2's right edge (x 216) and drop to the floor.
	Input.action_press("move_right")
	await _tick(25)
	_release_input()
	var landed := false
	for _i in range(90):
		await _tick(1)
		if _grounded(player):
			landed = true
			break
	_check(landed, "elv_up: Warma must land on the floor after leaving Lift2")
	_check(player.position.x > 216.0,
		"elv_up: Warma must clear Lift2's right edge (x=%.3f)" % player.position.x)
	_check(absf(player.position.y - STAND_Y_GROUND) <= Y_TOL,
		"elv_up: Warma must rest on the floor (y=%.3f, want %.2f)" % [player.position.y, STAND_Y_GROUND])

	# Standing on Btn1 (pressure zone y 128..132 above the plate) extends the
	# 12 px/s lift: 252 ticks cover the 210 needed for the 3 -> 24 travel.
	_teleport(player, Vector2(104, 120))
	await _tick(2)
	_check(bool(button.get("activated")), "elv_up: standing on Btn1 must activate it")
	await _tick(250)
	var height := float(lift1.get("current_height"))
	_check(is_equal_approx(height, 24.0),
		"elv_up: the held plate must extend Lift1 to its 24 px clamp (h=%.3f after 250 ticks)" % height)
	_check(height <= 24.001,
		"elv_up: Lift1 must clamp at its 24 px maximum (h=%.3f)" % height)
	await _unload_room(room)

## elv_down: the rod hangs from (104,48) and grows downward at 16 px/s while
## Btn1 (directly underneath) is held. The swallow rule must freeze the growth
## before the rod end passes Warma's head, releasing the button must retract
## the rod to its 3 px minimum, and an unobstructed press must reach 68 px.
func _test_elv_down() -> void:
	var room := _load_room(ELV_DOWN)
	if room == null:
		return
	await _tick(2)
	var player := room.get_node("Player") as CharacterBody2D
	var button := room.get_node("Btn1")
	var lift1 := room.get_node("Lift1")
	_check(player != null and button != null and lift1 != null,
		"elv_down: room must instantiate Player, Btn1 and Lift1")
	if player == null or button == null or lift1 == null:
		await _unload_room(room)
		return
	_check(is_equal_approx(float(lift1.get("current_height")), 3.0),
		"elv_down: Lift1 must start at its 3 px minimum (h=%.3f)" % float(lift1.get("current_height")))
	_check(absf(float(lift1.call("get_support_surface_y")) - 48.005) <= 0.01,
		"elv_down: a downward lift must support from its anchored top end (y=%.3f)" % float(lift1.call("get_support_surface_y")))

	# Warma stands on the button directly under the rod: the plate activates,
	# the rod extends and must freeze BEFORE its end reaches the body top
	# (112.0). A lift that cannot carry its obstruction must never overlap it:
	# the old head-plus-0.75-tolerance stop left the rod inside Warma's head
	# and physics depenetration ground him into the floor every frame.
	_teleport(player, Vector2(104, 120))
	await _tick(2)
	_check(bool(button.get("activated")), "elv_down: standing on Btn1 must activate it")
	await _tick(550)
	var height := float(lift1.get("current_height"))
	var rod_end_y := float(lift1.global_position.y) + height
	var head_y := float(player.position.y) - 8.0
	_check(height >= 60.0 and height <= 64.0,
		"elv_down: the rod must freeze just above Warma's head (h=%.3f, want 60..64)" % height)
	_check(rod_end_y <= head_y - 0.04,
		"elv_down: the rod end must stop clear above Warma's head (end y=%.3f, head y=%.3f)" % [rod_end_y, head_y])
	_check(absf(player.position.y - 120.0) <= 0.1 and _grounded(player),
		"elv_down: Warma must stay grounded on the floor (y=%.3f)" % player.position.y)

	# Leaving the plate releases the button: the lift must retract to its
	# 3 px minimum (61.7 px back at 0.1333 px/tick fits in 550 ticks).
	_teleport(player, Vector2(220, 120))
	await _tick(2)
	_check(not bool(button.get("activated")), "elv_down: leaving Btn1 must release it")
	await _tick(550)
	height = float(lift1.get("current_height"))
	_check(height >= 2.99 and height < 3.5,
		"elv_down: the released lift must retract to its 3 px minimum (h=%.3f)" % height)

	# Negative control: with the button held and nobody under the rod the same
	# lift must extend to its full 68 px maximum (488 ticks needed).
	lift1.call("set_button_active", true)
	await _tick(550)
	height = float(lift1.get("current_height"))
	_check(height > 67.95,
		"elv_down: an unobstructed pressed lift must extend fully (h=%.3f, want 68)" % height)
	lift1.call("set_button_active", false)
	await _unload_room(room)

## elv_horizontal: two always-extended bridges. Bridge1 (authored at (48,84))
## spans x 48..128 at top 80.0, flush with the left tower's right face and the
## middle platform's left face; Bridge2 spans x 176..208 at top 64.0, flush
## with the middle platform's right face and the right tower.
func _test_elv_horizontal() -> void:
	var room := _load_room(ELV_HORIZONTAL)
	if room == null:
		return
	await _tick(12)
	var player := room.get_node("Player") as CharacterBody2D
	var bridge1 := room.get_node("Bridge1")
	var bridge2 := room.get_node("Bridge2")
	_check(player != null and bridge1 != null and bridge2 != null,
		"elv_horizontal: room must instantiate Player, Bridge1 and Bridge2")
	if player == null or bridge1 == null or bridge2 == null:
		await _unload_room(room)
		return
	_check(is_equal_approx(float(bridge1.get("current_height")), 80.0),
		"elv_horizontal: Bridge1 must start fully extended (h=%.3f)" % float(bridge1.get("current_height")))
	_check(is_equal_approx(float(bridge2.get("current_height")), 32.0),
		"elv_horizontal: Bridge2 must start fully extended (h=%.3f)" % float(bridge2.get("current_height")))

	# Bridge1's top (80.0) must carry Warma at y ~72.01.
	_teleport(player, Vector2(112, 72))
	await _tick(12)
	_check(_grounded(player), "elv_horizontal: Bridge1 must support Warma")
	_check(absf(player.position.y - 72.01) <= Y_TOL,
		"elv_horizontal: Warma must stand on Bridge1 (y=%.3f, want 72.01)" % player.position.y)

	# Walking right 100 ticks (50 px) must reach the middle platform
	# (cols 8-10, x 128..176, same top height) still grounded.
	Input.action_press("move_right")
	await _tick(100)
	_release_input()
	_check(player.position.x > 128.0,
		"elv_horizontal: Warma must cross onto the middle platform (x=%.3f)" % player.position.x)
	_check(_grounded(player), "elv_horizontal: Warma must stay grounded on the middle platform")
	_check(absf(player.position.y - 72.01) <= Y_TOL,
		"elv_horizontal: Warma must keep its height across the seam (y=%.3f, want 72.01)" % player.position.y)

	# Jump from the middle platform onto Bridge2 (16 px higher, top 64): a
	# 20-tick hold keeps the ~39 px drift inside Bridge2's support range
	# (x 176.01..207.99); the brief's 30-tick hold lands at x~210, past the
	# bridge, on the right tower's row-5 shoulder at 80.01.
	Input.action_press("move_right")
	Input.action_press("jump")
	await _tick(20)
	Input.action_release("jump")
	var landed := false
	for _i in range(150):
		await _tick(1)
		if _grounded(player):
			landed = true
			break
	_release_input()
	_check(landed, "elv_horizontal: Warma must land on Bridge2 or the right tower")
	_check(absf(player.position.y - 56.01) <= Y_TOL,
		"elv_horizontal: Warma must stand on the upper level (y=%.3f, want 56.01)" % player.position.y)
	_check(player.position.x > 192.0,
		"elv_horizontal: Warma must reach the far bridge or tower (x=%.3f)" % player.position.x)
	await _unload_room(room)

func _run() -> void:
	game_state = root.get_node("GameState")
	game_state.reset_speed()
	_release_input()
	await _test_fnd_giraffe_contact()
	await _test_fnd_giraffe_stack()
	await _test_fnd_giraffe_bump()
	await _test_elv_up()
	await _test_elv_down()
	await _test_elv_horizontal()
	print("Giraffe/Elevator showcase checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
