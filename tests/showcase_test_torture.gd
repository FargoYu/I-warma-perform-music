extends SceneTree
## Deep physical stress tests for the three TORTURE showcase rooms:
## trt_elevator, trt_giraffe and trt_precision.
## Run: godot --headless --path . --script res://tests/showcase_test_torture.gd
##
## Timing facts used throughout (the project runs 120 physics ticks per second,
## and one _tick() waits exactly one physics step, i.e. 1/120 s of simulation):
##   - lift growth: height_speed px/s => speed 12 = 0.1px/tick (3->40 in ~370
##     ticks), speed 16 = 0.1333px/tick (3->68 in ~487), speed 48 = 0.4px/tick.
##   - block collision is 16x15.98, so a floor row tops at y=128.01 and a
##     standing Warma centres at y=120.01.
##   - a note hit makes a giraffe run 24px/s for 0.8s (~19.2px) plus a friction
##     slide (~3px), so one note advances a resting giraffe ~22px.
##   - a button's pressure zone is 14x4 centred at (x, y-6); a standing Warma
##     (feet 128.01) presses it, and a giraffe body (8x16) while |dx| <= 11.
##   - the bullet's HitProbe is 3x4 offset (0.5, 2): a note spawned at y=113
##     sweeps y 113..117, hitting a floor giraffe (box top 112.01) but passing
##     0.99px below a stacked giraffe (box bottom 112.01).

const ROOM_DIR := "res://rooms/showcase/"
const BULLET_SCENE := "res://objects/music_bullet.tscn"

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

func _on_timeout() -> void:
	_check(false, "Timed out during torture showcase checks")
	print("Torture showcase checks: FAIL (timeout)")
	quit(1)

func _release_input() -> void:
	for action in ["move_left", "move_right", "jump", "fire_music", "interact", "reset"]:
		Input.action_release(action)

func _node(node_name: String) -> Node:
	if current_scene == null:
		return null
	return current_scene.get_node_or_null(node_name)

func _load_room(room_name: String) -> bool:
	_release_input()
	var path := ROOM_DIR + room_name + ".tscn"
	var error := change_scene_to_file(path)
	_check(error == OK, "%s: change_scene_to_file failed: %s" % [room_name, error_string(error)])
	if error != OK:
		return false
	await scene_changed
	await _tick(3)
	var loaded := current_scene != null and current_scene.scene_file_path == path
	_check(loaded, "%s: expected the room to become current_scene" % room_name)
	return loaded

func _teleport(at: Vector2) -> CharacterBody2D:
	var where := String(current_scene.scene_file_path) if current_scene != null else "<no scene>"
	var player := _node("Player") as CharacterBody2D
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

func _lift_height(lift: Node) -> float:
	return float(lift.get("current_height"))

func _fire_note(from: Vector2, direction: int) -> void:
	var bullet := (load(BULLET_SCENE) as PackedScene).instantiate() as Area2D
	_check(bullet != null, "music_bullet.tscn must instantiate")
	if bullet == null:
		return
	bullet.call("setup", direction, 480.0, 0.03)
	current_scene.add_child(bullet)
	bullet.global_position = from


# ---------------------------------------------------------------- trt_elevator
func _torture_elevator() -> void:
	print("trt_elevator: running ...")
	if not await _load_room("trt_elevator"):
		return
	var lift_a := _node("LiftA")
	var lift_b := _node("LiftB")
	var lift_c := _node("LiftC")
	var lift_d := _node("LiftD")
	var lift_e := _node("LiftE")
	var giraffe := _node("Giraffe1") as CharacterBody2D
	var button_a := _node("BtnA")
	_check(lift_a != null and lift_b != null and lift_c != null and lift_d != null and lift_e != null,
		"trt_elevator: must expose LiftA, LiftB, LiftC, LiftD and LiftE")
	_check(giraffe != null and button_a != null, "trt_elevator: must expose Giraffe1 and BtnA")
	if lift_a == null or lift_b == null or lift_c == null or lift_d == null or lift_e == null or giraffe == null:
		return

	# a) Rest state: idle rods at min 3 (LiftA/B top 125.01, giraffe centre
	# 117.01) and the two starts_extended bridges fully out at 32 (tops y=96,
	# meeting mid-air at x=192).
	await _tick(100)
	_check(is_equal_approx(_lift_height(lift_a), 3.0),
		"a: LiftA must rest at min 3 (got %s)" % _lift_height(lift_a))
	_check(is_equal_approx(_lift_height(lift_b), 3.0),
		"a: LiftB must rest at min 3 (got %s)" % _lift_height(lift_b))
	_check(is_equal_approx(_lift_height(lift_d), 32.0),
		"a: LiftD must start fully extended at 32 (got %s)" % _lift_height(lift_d))
	_check(is_equal_approx(_lift_height(lift_e), 32.0),
		"a: LiftE must start fully extended at 32 (got %s)" % _lift_height(lift_e))
	_check(absf(giraffe.global_position.y - 117.01) <= 0.5,
		"a: the giraffe must settle on LiftA's min top at y~117.01 (got %s)" % giraffe.global_position.y)
	_check(absf(giraffe.velocity.x) <= 0.001 and absf(giraffe.velocity.y) <= 0.001,
		"a: the resting giraffe must have zero velocity (got %s)" % giraffe.velocity)

	# b) One button, two lifts: standing on BtnA must extend BOTH rods, each at
	# its own speed, and LiftA (0.1px/tick) must carry the giraffe to its top.
	var presser := await _teleport(Vector2(24, 120))
	if presser == null:
		return
	await _tick(6)
	_check(bool(button_a.get("activated")), "b: Warma standing on BtnA must activate it")
	_check(bool(lift_a.call("is_button_active")) and bool(lift_b.call("is_button_active")),
		"b: BtnA must drive both LiftA and LiftB through their button wiring")
	await _tick(420)  # LiftA needs ~370 ticks for 3 -> 40 at 0.1px/tick.
	_check(is_equal_approx(_lift_height(lift_a), 40.0),
		"b: pressed LiftA must clamp at max 40 (got %s)" % _lift_height(lift_a))
	_check(is_equal_approx(_lift_height(lift_b), 24.0),
		"b: pressed LiftB must clamp at max 24 (got %s)" % _lift_height(lift_b))
	_check(giraffe.global_position.y < 95.0,
		"b: the rising LiftA must carry the giraffe above y=95 (got %s)" % giraffe.global_position.y)

	# c) Adjacent-lift synchronized carry + double-push probe (core).
	# LiftA (36..44) and LiftB (48..56) are 4px apart; a Warma centred at
	# x=45.5 spans 43.5..48.5 and is therefore inside BOTH support ranges.
	# Unify both rods to min 3 / max 24 / speed 12, let LiftA retract 40 -> 24
	# (160 ticks at 0.1px/tick), then stand Warma exactly on the shared plane
	# (128 - 24 = 104 feet, centre 96). Leaving BtnA releases both rods: they
	# retract in sync carrying the seam rider, and re-pressing grows them in
	# sync. If both rods pushed Warma without compensation the rider would rise
	# at twice the plane speed and drift off the 1.5px tracking window.
	for lift in [lift_a, lift_b]:
		lift.set("min_height", 3.0)
		lift.set("max_height", 24.0)
		lift.set("height_speed", 12.0)
		lift.call("set_button_active", true)
	await _tick(210)
	_check(absf(_lift_height(lift_a) - 24.0) <= 0.05,
		"c: unified LiftA must settle at 24 (got %s)" % _lift_height(lift_a))
	_check(absf(_lift_height(lift_b) - 24.0) <= 0.05,
		"c: unified LiftB must settle at 24 (got %s)" % _lift_height(lift_b))
	# Open 6px of growth headroom first: with the rider still off the seam,
	# release both rods and let them retract 24 -> 18 (60 ticks at 0.1px/tick).
	for lift in [lift_a, lift_b]:
		lift.call("set_button_active", false)
	await _tick(60)
	var seam_h := _lift_height(lift_a)
	_check(absf(seam_h - 18.0) <= 0.5,
		"c: the released rods must open growth headroom (height %.3f)" % seam_h)
	# Stand Warma exactly on the shared plane: feet at 128 - h, i.e. centre
	# 128 - h - 8 (h=18 puts the centre at 102). Both support ranges
	# [36,44] and [48,56] overlap the 43.5..48.5 body.
	var rider := await _teleport(Vector2(45.5, 128.0 - seam_h - 8.0))
	if rider == null:
		return
	await _tick(6)
	_check(_is_grounded(rider),
		"c: Warma straddling the LiftA|LiftB seam must be supported by the rods")
	# Growth phase (core double-push probe): both rods rise in sync at
	# 0.1px/tick under the straddling rider.
	for lift in [lift_a, lift_b]:
		lift.call("set_button_active", true)
	var grow_ride := await _record_seam_ride(rider, lift_a, lift_b, 20)
	_evaluate_seam_ride(grow_ride, "grow", true)
	# Retract phase: release both rods under the straddling rider and record.
	for lift in [lift_a, lift_b]:
		lift.call("set_button_active", false)
	var retract_ride := await _record_seam_ride(rider, lift_a, lift_b, 20)
	_evaluate_seam_ride(retract_ride, "retract", false)

	# d) Downward growth must stop before swallowing the rider-to-be. LiftC is
	# anchored at (104,48) extending down; Warma's head top is 112.01, and the
	# block check allows the rod end within 0.75px, so growth must clamp in
	# (64.6267, 64.76] (rod end 112.72, just above the head).
	var blocker := await _teleport(Vector2(104, 120))
	if blocker == null:
		return
	await _tick(4)
	var button_c := _node("BtnC")
	_check(button_c != null and bool(button_c.get("activated")),
		"d: Warma on BtnC must activate it")
	await _tick(550)  # unobstructed 3 -> 68 needs 487 ticks at 0.1333px/tick.
	var blocked_h := _lift_height(lift_c)
	print("trt_elevator d: LiftC blocked at height %.4f (rod end %.3f vs head 112.01)" % [blocked_h, 48.0 + blocked_h])
	_check(blocked_h >= 60.0 and blocked_h <= 64.75,
		"d: LiftC must stop growing before swallowing Warma (height %s, rod end %.3f)" % [blocked_h, 48.0 + blocked_h])
	_check(absf(blocker.global_position.y - 120.0) <= 0.1,
		"d: Warma must stay at y=120 under the stopped rod (got %s)" % blocker.global_position.y)
	# Leaving the plate releases the rod: it must retract to min 3. With nobody
	# under it, a fresh press must then reach the full 68 extension.
	blocker = await _teleport(Vector2(220, 120))
	if blocker == null:
		return
	await _tick(550)
	_check(is_equal_approx(_lift_height(lift_c), 3.0),
		"d: released LiftC must retract to min 3 (got %s)" % _lift_height(lift_c))
	lift_c.call("set_button_active", true)
	await _tick(550)
	_check(is_equal_approx(_lift_height(lift_c), 68.0),
		"d: unobstructed LiftC must extend to full 68 (got %s)" % _lift_height(lift_c))
	lift_c.call("set_button_active", false)

	# e) Walking the sky seam: LiftD (160..192) and LiftE (192..224) both hold
	# their tops at y=96 while extended, then the right base column (224..240,
	# top 96.01) continues the same plane.
	var walker := await _teleport(Vector2(176, 88))
	if walker == null:
		return
	await _tick(12)
	_check(_is_grounded(walker),
		"e: Warma must stand on LiftD's extended top at (176,88)")
	_check(absf(walker.global_position.y - 88.0) <= 0.1,
		"e: LiftD's top must hold Warma at y~88 (got %.3f)" % walker.global_position.y)
	Input.action_press("move_right")
	var walk_ok := true
	for _i in range(40):
		await _tick(1)
		if not _is_grounded(walker) or absf(walker.global_position.y - 88.0) > 0.5:
			walk_ok = false
	_check(walk_ok and walker.global_position.x > 192.0,
		"e: Warma must cross the D|E sky seam grounded at y~88 (x=%.2f)" % walker.global_position.x)
	var boarded := false
	for _i in range(120):
		await _tick(1)
		if not _is_grounded(walker) or absf(walker.global_position.y - 88.0) > 0.5:
			walk_ok = false
		if walker.global_position.x >= 226.0:
			boarded = true
			break
	Input.action_release("move_right")
	await _tick(4)
	_check(boarded and walker.global_position.x > 224.0,
		"e: Warma must board the right base column past x=224 (x=%.2f)" % walker.global_position.x)
	_check(walk_ok and _is_grounded(walker) and absf(walker.global_position.y - 88.0) <= 0.5,
		"e: the whole sky walk must stay grounded at y~88 (final y=%.3f)" % walker.global_position.y)

	# f) Every lift instance must own its collision shape resource; a shared
	# RectangleShape2D would make one lift's resize corrupt every other rod.
	var shape_ids: Array[int] = []
	for lift_name in ["LiftA", "LiftB", "LiftD", "LiftE"]:
		var lift := _node(lift_name)
		var shape_node := (lift.get_node_or_null("CollisionShape2D") as CollisionShape2D) if lift != null else null
		_check(shape_node != null and shape_node.shape != null,
			"f: %s must own a CollisionShape2D with a shape" % lift_name)
		shape_ids.append(shape_node.shape.get_instance_id() if shape_node != null else 0)
	var isolated := true
	for i in range(shape_ids.size()):
		for j in range(i + 1, shape_ids.size()):
			if shape_ids[i] == shape_ids[j]:
				isolated = false
	_check(isolated,
		"f: LiftA/LiftB/LiftD/LiftE collision shapes must be pairwise distinct instances (got %s)" % [shape_ids])

func _record_seam_ride(player: CharacterBody2D, lift_a: Node, lift_b: Node, ticks: int) -> Dictionary:
	var start_y := player.global_position.y
	var start_ha := _lift_height(lift_a)
	var start_hb := _lift_height(lift_b)
	var ys: Array[float] = []
	var has: Array[float] = []
	var hbs: Array[float] = []
	for _i in range(ticks):
		await _tick(1)
		ys.append(player.global_position.y)
		has.append(_lift_height(lift_a))
		hbs.append(_lift_height(lift_b))
	return {
		"start_y": start_y, "start_ha": start_ha, "start_hb": start_hb,
		"ys": ys, "has": has, "hbs": hbs,
	}

func _evaluate_seam_ride(ride: Dictionary, phase: String, require_motion: bool) -> void:
	var end_y: float = ride.ys.back()
	var end_ha: float = ride.has.back()
	var end_hb: float = ride.hbs.back()
	var lift_travel: float = end_ha - ride.start_ha
	var player_travel: float = ride.start_y - end_y
	var feet_offset: float = (end_y + 8.0) - (128.0 - end_ha)
	var max_offset := 0.0
	for i in range(ride.ys.size()):
		max_offset = maxf(max_offset, absf((ride.ys[i] + 8.0) - (128.0 - ride.has[i])))
	if absf(lift_travel) < 0.5:
		print("trt_elevator c [%s]: JAMMED - zero rod travel over 20 ticks (rider wedges both rods; feet offset %.3f, heights A=%.3f B=%.3f)" % [phase, feet_offset, end_ha, end_hb])
	else:
		var ratio: float = player_travel / lift_travel
		print("trt_elevator c [%s]: player/plane displacement ratio=%.3f feet offset end=%.3f max=%.3f" % [phase, ratio, feet_offset, max_offset])
	if require_motion:
		_check(absf(lift_travel) >= 1.0,
			"c [%s]: the rods must travel ~2px over the 20-tick probe (travel %.3f) - the probe ran against frozen rods" % [phase, lift_travel])
	_check(absf(feet_offset) <= 1.5,
		"c [%s]: Warma's feet must track 128 - LiftA.height while both rods carry the seam (end offset %.3fpx)" % [phase, feet_offset])
	_check(max_offset <= 1.5,
		"c [%s]: the seam feet offset must stay within 1.5px across the whole ride (max %.3fpx)" % [phase, max_offset])
	_check(absf(end_ha - end_hb) <= 0.5,
		"c [%s]: the two unified rods must stay height-synchronized (A=%.3f B=%.3f)" % [phase, end_ha, end_hb])


# ----------------------------------------------------------------- trt_giraffe
func _torture_giraffe() -> void:
	print("trt_giraffe: running ...")
	if not await _load_room("trt_giraffe"):
		return
	var giraffes: Array[CharacterBody2D] = []
	for giraffe_name in ["Giraffe1", "Giraffe2", "Giraffe3", "Giraffe4"]:
		var giraffe := _node(giraffe_name) as CharacterBody2D
		_check(giraffe != null, "trt_giraffe: must expose %s" % giraffe_name)
		giraffes.append(giraffe)
	if giraffes.any(func(g: CharacterBody2D) -> bool: return g == null):
		return

	# a) Rest state: g1 on the floor (120.01), g2 stacked on g1 (104.01), g3 on
	# the pedestal brick (184,112) (top 112.01 => 104.01), g4 on the floor.
	await _tick(90)
	var rest_y := [120.01, 104.01, 104.01, 120.01]
	for i in range(4):
		_check(absf(giraffes[i].global_position.y - rest_y[i]) <= 0.1,
			"a: Giraffe%d must rest at y~%s (got %.3f)" % [i + 1, rest_y[i], giraffes[i].global_position.y])
		_check(absf(giraffes[i].velocity.x) <= 0.001 and absf(giraffes[i].velocity.y) <= 0.001,
			"a: Giraffe%d must rest with zero velocity (got %s)" % [i + 1, giraffes[i].velocity])

	# b) Shoot the base giraffe out from under its rider: the note passes 0.99px
	# below stacked Giraffe2 and hits Giraffe1, which runs right ~22px; Giraffe2
	# must drop straight down once the carrier slides past its footprint.
	var g1 := giraffes[0]
	var g2 := giraffes[1]
	await _fire_note(Vector2(95.0, 113.0), 1)
	var max_rider_vx := 0.0
	var fell := false
	for _i in range(400):
		await _tick(1)
		max_rider_vx = maxf(max_rider_vx, absf(g2.velocity.x))
		if g2.global_position.y > 115.0:
			fell = true
			break
	_check(fell,
		"b: Giraffe2 must lose its carrier and fall (y=%.3f after 400 ticks)" % g2.global_position.y)
	await _tick(20)
	print("trt_giraffe b: Giraffe1.x=%.2f Giraffe2=(%.2f, %.2f) max rider |vx|=%.4f" % [g1.global_position.x, g2.global_position.x, g2.global_position.y, max_rider_vx])
	_check(g1.global_position.x > 130.0,
		"b: the note must drive Giraffe1 right past x=130 (got %.2f)" % g1.global_position.x)
	_check(g2.global_position.y > 115.0 and absf(g2.velocity.y) <= 0.001,
		"b: the fallen Giraffe2 must rest on the floor with zero vertical velocity (y=%.3f vy=%.4f)" % [g2.global_position.y, g2.velocity.y])
	_check(max_rider_vx <= 0.001,
		"b: the falling rider must never be dragged sideways (max |vx| %.4f)" % max_rider_vx)
	_check(absf(g2.global_position.x - 120.0) <= 0.1,
		"b: the rider must fall straight down at x=120 (got %.3f)" % g2.global_position.x)

	# c) The pedestal giraffe acts as a stepping stone: Warma mounts it (feet on
	# 96.01), stands grounded, and jumping away must NOT lift it - the lift
	# impulse only fires from a flush head-resting launch, never from a rider.
	var g3 := giraffes[2]
	var bumper := await _teleport(Vector2(184, 88))
	if bumper == null:
		return
	await _tick(12)
	_check(_is_grounded(bumper) and absf(bumper.global_position.y - 88.01) <= 0.3,
		"c: Warma must stand on the pedestal giraffe (y=%.3f, want 88.01)" % bumper.global_position.y)
	var g3_before := g3.global_position
	Input.action_press("jump")
	await _tick(10)
	Input.action_release("jump")
	# A full held jump needs ~120 ticks of airtime before the next landing.
	var landed_again := false
	for _i in range(150):
		await _tick(1)
		if _is_grounded(bumper):
			landed_again = true
			break
	_check(g3.global_position.distance_to(g3_before) <= 0.1,
		"c: jumping off the pedestal giraffe must not lift or shift it (moved to %s)" % g3.global_position)
	_check(landed_again and absf(bumper.global_position.y - 88.01) <= 0.3,
		"c: Warma must land back on the pedestal giraffe (y=%.3f)" % bumper.global_position.y)

	# d) Side contact: walking left into Giraffe4 (216,120, box right edge 220)
	# must stop Warma at x~222 without moving the giraffe.
	var g4 := giraffes[3]
	var pusher := await _teleport(Vector2(248, 120))
	if pusher == null:
		return
	await _tick(4)
	Input.action_press("move_left")
	var stalled := false
	for _i in range(120):
		await _tick(1)
		if absf(pusher.velocity.x) < 0.01:
			stalled = true
			break
	Input.action_release("move_left")
	await _tick(2)
	print("trt_giraffe d: Warma stopped at x=%.3f (Giraffe4.x=%.3f)" % [pusher.global_position.x, g4.global_position.x])
	_check(stalled and pusher.global_position.x > 219.0 and pusher.global_position.x < 222.5,
		"d: Warma must be stopped by Giraffe4's right face just past x=219 (x=%.3f, stalled=%s)" % [pusher.global_position.x, stalled])
	_check(absf(g4.global_position.x - 216.0) <= 0.1,
		"d: Giraffe4 must hold its ground at x=216 (got %.3f)" % g4.global_position.x)


# --------------------------------------------------------------- trt_precision
func _torture_precision() -> void:
	print("trt_precision: running ...")
	if not await _load_room("trt_precision"):
		return
	var door := _node("Door1")
	_check(door != null, "trt_precision: must expose Door1")
	if door == null:
		return

	# a) Jump into the 16px wall slot at cell (6,5): the wall column x 96..112
	# must bound an 80..96 tunnel; entering the slot column (97..111) demands
	# y~88 grounded, and the exit must drop Warma back to the floor past x=112.
	var slot_evidence := _slot_blocker_evidence()
	var runner := await _teleport(Vector2(80, 120))
	if runner == null:
		return
	await _tick(4)
	Input.action_press("move_right")
	Input.action_press("jump")
	var entered := false
	var exited := false
	var exit_ok := false
	var slot_ticks := 0
	for i in range(120):
		await _tick(1)
		if i == 34:
			Input.action_release("jump")  # hold the jump for 35 ticks, keep running
		var x := runner.global_position.x
		if x > 97.0 and x < 111.0:
			entered = true
			slot_ticks += 1
			_check(absf(runner.global_position.y - 88.0) <= 0.1,
				"a: inside the slot column Warma must ride at y~88 (tick %d: y=%.3f)" % [i, runner.global_position.y])
			_check(_is_grounded(runner),
				"a: Warma must be grounded inside the slot (tick %d)" % i)
		if x > 112.0:
			exited = true
			break
	Input.action_release("move_right")
	# Past the wall the runner may land on the floor (120.01) or chain-jump onto
	# the first one-cell ledge (9,6) at 88.01 - both are valid resting heights.
	var rest_ok := false
	var rest_y := 0.0
	for _i in range(180):
		await _tick(1)
		if _is_grounded(runner):
			rest_y = runner.global_position.y
			rest_ok = absf(rest_y - 120.01) <= 0.3 or absf(rest_y - 88.01) <= 0.3
			break
	await _tick(2)
	print("trt_precision a: entered slot=%s slot_ticks=%d exited=%s rest=(%.2f, %.2f)" % [entered, slot_ticks, exited, runner.global_position.x, rest_y])
	_check(entered and exited and rest_ok,
		"a: Warma must jump into the 16px wall slot, cross it and come to rest beyond x=112 on the floor or the first ledge (entered=%s exited=%s rest y=%.2f). Slot evidence: %s" % [entered, exited, rest_y, slot_evidence])

	# b) One-cell ledge (9,6), top 96.01: with the centre at 158.5 only ~3.5px
	# of foot rests on the block, which must still count as full support.
	var edger := await _teleport(Vector2(158.5, 88))
	if edger == null:
		return
	await _tick(20)
	_check(_is_grounded(edger),
		"b: Warma must be grounded with only ~3.5px of foot on the (9,6) ledge")
	_check(absf(edger.global_position.y - 88.0) <= 0.1,
		"b: the ledge edge must hold Warma at y~88 (got %.3f)" % edger.global_position.y)
	Input.action_press("jump")
	await _tick(5)
	var launched := edger.velocity.y < -50.0 and edger.global_position.y < 87.0
	Input.action_release("jump")
	_check(launched,
		"b: Warma must launch from the ledge edge (vy=%.1f y=%.3f)" % [edger.velocity.y, edger.global_position.y])
	await _tick(40)

	# c) Ascending chain up the single cells to the exit door.
	var climber := await _teleport(Vector2(184, 72))
	if climber == null:
		return
	await _tick(6)
	_check(_is_grounded(climber),
		"c: Warma must stand on the (11,5) cell top at (184,72)")
	climber = await _teleport(Vector2(216, 56))
	if climber == null:
		return
	await _tick(6)
	_check(_is_grounded(climber),
		"c: Warma must stand on the (13,4) platform top at (216,56)")
	_check(String(door.get("next_room")) != "",
		"c: the exit door must carry a next_room target (got '%s')" % String(door.get("next_room")))

func _slot_blocker_evidence() -> String:
	var terrain := _node("Terrain")
	if terrain == null:
		return "room has no Terrain node"
	var parts: Array[String] = []
	for child in terrain.get_children():
		var block := child as Node2D
		if block != null and absf(block.position.x - 104.0) < 0.01 and absf(block.position.y - 88.0) < 0.01:
			parts.append("%s sits at (104, 88), filling slot cell (6,5)" % String(block.name))
	return "; ".join(parts) if not parts.is_empty() else "no block found at (104, 88)"


func _run() -> void:
	# Bound the whole run so a stuck transition reports failure, not a hang.
	create_timer(300.0).timeout.connect(_on_timeout)
	_release_input()
	game_state = root.get_node_or_null("GameState")
	_check(game_state != null, "GameState autoload must exist")
	if game_state != null and game_state.has_method("reset_speed"):
		game_state.call("reset_speed")
	await _torture_elevator()
	await _torture_giraffe()
	await _torture_precision()
	_release_input()
	print("Torture showcase checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
