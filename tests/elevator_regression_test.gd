extends SceneTree
## Regression checks for elevator support, contact seams, blocking, stacking, and reset.
## Run: godot --headless --path . --script res://tests/elevator_regression_test.gd

const ELEVATOR_SCENE := "res://objects/elevator_up.tscn"
const ELEVATOR_DIRECTION_SCENES := [
	"res://objects/elevator_up.tscn",
	"res://objects/elevator_down.tscn",
	"res://objects/elevator_left.tscn",
	"res://objects/elevator_right.tscn",
]
const WARMA_SCENE := "res://objects/warma.tscn"
const GIRAFFE_SCENE := "res://objects/giraffe.tscn"
const BLOCK_SCENE := "res://objects/block.tscn"
const FLOOR_Y := 140.0

var failures: Array[String] = []
var level: Node2D

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
	for action in ["jump", "move_left", "move_right"]:
		Input.action_release(action)

func _new_level() -> Node2D:
	_release_input()
	level = Node2D.new()
	root.add_child(level)
	return level

func _cleanup() -> void:
	_release_input()
	if is_instance_valid(level):
		level.queue_free()
	await _tick(2)
	level = null

func _elevator(at: Vector2, height: float = 3.0) -> AnimatableBody2D:
	var lift := load(ELEVATOR_SCENE).instantiate() as AnimatableBody2D
	lift.position = at
	lift.set("min_height", height)
	lift.set("max_height", height)
	level.add_child(lift)
	return lift

func _warma(at: Vector2) -> CharacterBody2D:
	var player := load(WARMA_SCENE).instantiate() as CharacterBody2D
	player.position = at
	player.set("fall_limit", 1000.0)
	level.add_child(player)
	return player

func _giraffe(at: Vector2) -> CharacterBody2D:
	var giraffe := load(GIRAFFE_SCENE).instantiate() as CharacterBody2D
	giraffe.position = at
	giraffe.set("gravity", 300.0)
	level.add_child(giraffe)
	return giraffe

func _block(at: Vector2) -> StaticBody2D:
	var block := load(BLOCK_SCENE).instantiate() as StaticBody2D
	block.position = at
	level.add_child(block)
	return block

func _stack_on_static_lift() -> void:
	_new_level()
	var lift := _elevator(Vector2(100, FLOOR_Y), 32.0)
	var giraffe := _giraffe(Vector2(100, FLOOR_Y - 32.0 - 8.0))
	var player := _warma(Vector2(100, FLOOR_Y - 32.0 - 24.0))
	player.set_physics_process(false)
	giraffe.set_physics_process(false)
	await _tick(15)
	_check(player._has_ground_support(), "Warma standing on a giraffe over an elevator must be grounded")
	_check(absf(giraffe.position.y - (FLOOR_Y - 40.0)) < 0.1,
		"Giraffe must settle on the elevator")
	var launch_y := player.position.y
	player.set_physics_process(true)
	Input.action_press("jump")
	await _tick(8)
	Input.action_release("jump")
	_check(player.position.y < launch_y - 4.0 and player.velocity.y < 0.0,
		"Warma must jump from a giraffe supported by an elevator")
	await _cleanup()

func _moving_stack_stays_supported() -> void:
	_new_level()
	var lift := load(ELEVATOR_SCENE).instantiate() as AnimatableBody2D
	lift.position = Vector2(100, FLOOR_Y)
	lift.set("starts_extended", true)
	lift.set("height_speed", 24.0)
	level.add_child(lift)
	var giraffe := _giraffe(Vector2(100, FLOOR_Y - 32.0 - 8.0))
	var player := _warma(Vector2(100, FLOOR_Y - 32.0 - 24.0))
	giraffe.set_physics_process(false)
	player.set_physics_process(false)
	await _tick(3)
	var starting_height := float(lift.get("current_height"))
	var starting_giraffe_y := giraffe.position.y
	var starting_player_y := player.position.y
	lift.call("set_button_active", true)
	await _tick(30)
	var height_change := starting_height - float(lift.get("current_height"))
	_check(height_change > 0.1, "A retracting elevator must move while carrying a stack")
	_check(absf(giraffe.position.y - (starting_giraffe_y + height_change)) < 0.1,
		"Elevator must carry the giraffe while retracting")
	_check(absf(player.position.y - (starting_player_y + height_change)) < 0.1,
		"Elevator must carry Warma and its rider stack together")
	_check(player._has_ground_support(), "Warma must remain grounded on a moving giraffe stack")
	await _cleanup()

func _descending_lift_jump() -> void:
	_new_level()
	var lift := _elevator(Vector2(100, FLOOR_Y), 32.0)
	lift.set("starts_extended", true)
	lift.set("height_speed", 24.0)
	# Re-run _ready after setting exported values before adding occupants.
	lift.queue_free()
	await _tick()
	lift = load(ELEVATOR_SCENE).instantiate() as AnimatableBody2D
	lift.position = Vector2(100, FLOOR_Y)
	lift.set("starts_extended", true)
	lift.set("height_speed", 24.0)
	lift.set("max_height", 32.0)
	lift.set("min_height", 3.0)
	level.add_child(lift)
	var player := _warma(Vector2(100, FLOOR_Y - 32.0 - 8.0))
	await _tick(8)
	var starting_height := float(lift.get("current_height"))
	lift.call("set_button_active", true)
	Input.action_press("jump")
	var launched := false
	for _frame in range(100):
		await _tick()
		if player.velocity.y < -20.0:
			launched = true
			break
	Input.action_release("jump")
	_check(launched, "Warma holding jump must launch while the elevator descends")
	_check(float(lift.get("current_height")) < starting_height - 0.1,
		"Elevator must actually descend while carrying Warma")
	await _cleanup()

func _seam_walk() -> void:
	_new_level()
	# Match the block's 15.98px body top to the elevator top exactly: both
	# surfaces are at y=132, so this exercises the real seam rather than a gap.
	var lift := _elevator(Vector2(100, FLOOR_Y), 8.0)
	_block(Vector2(112, FLOOR_Y))
	var player := _warma(Vector2(99, FLOOR_Y - 8.0 - 8.0))
	await _tick(15)
	_check(player._has_ground_support(), "Warma must stand on the elevator before crossing its seam")
	Input.action_press("move_right")
	await _tick(80)
	Input.action_release("move_right")
	_check(player.position.x > 112.0, "Warma must walk across a continuous block/elevator seam")
	await _cleanup()

func _rise_blocked() -> void:
	_new_level()
	# starts_extended=false means an active button EXTENDS the lift upward; an
	# inactive button lets it shrink back. Growth must stop before the carried
	# Warma is pushed into the overhead block.
	var lift := load(ELEVATOR_SCENE).instantiate() as AnimatableBody2D
	lift.position = Vector2(100, FLOOR_Y)
	lift.set("min_height", 3.0)
	lift.set("max_height", 32.0)
	lift.set("height_speed", 120.0)
	level.add_child(lift)
	var block := _block(Vector2(100, 96.0))
	var player := _warma(Vector2(100, FLOOR_Y - 3.0 - 8.0))
	await _tick(8)
	lift.call("set_button_active", true)
	await _tick(80)
	_check(float(lift.get("current_height")) < 32.0 - 0.1,
		"Elevator must stop before pushing Warma into an overhead block")
	_check(player.position.y - 8.0 >= block.position.y + 7.9 - 0.05,
		"Warma must remain below the overhead block when growth is blocked")
	await _cleanup()

func _giraffe_stacks() -> void:
	_new_level()
	_elevator(Vector2(100, FLOOR_Y), 32.0)
	var lower := _giraffe(Vector2(100, FLOOR_Y - 32.0 - 8.0))
	var upper := _giraffe(Vector2(100, FLOOR_Y - 32.0 - 24.0))
	await _tick(30)
	_check(absf(lower.position.y - 100.0) < 0.1,
		"Giraffe must settle on the elevator")
	_check(absf(upper.position.y - 84.0) < 0.1,
		"A second giraffe must settle on the first giraffe")
	await _cleanup()

func _four_direction_shapes_and_horizontal_jump() -> void:
	_new_level()
	for direction in [0, 1, 2, 3]:
		var lift := load(ELEVATOR_DIRECTION_SCENES[direction]).instantiate() as AnimatableBody2D
		lift.position = Vector2(100, 100)
		lift.set("min_height", 8.0)
		lift.set("max_height", 8.0)
		level.add_child(lift)
		await _tick(1)
		var rectangle := lift.get_node("CollisionShape2D").shape as RectangleShape2D
		var expected := Vector2(8.0, 7.98) if direction < 2 else Vector2(7.98, 8.0)
		_check(rectangle.size.is_equal_approx(expected),
			"Direction %d scene must orient its collision along its own axis" % direction)
		lift.queue_free()
		await _tick(1)
	await _cleanup()

	_new_level()
	var downward := load("res://objects/elevator_down.tscn").instantiate() as AnimatableBody2D
	downward.position = Vector2(100, 100)
	downward.set("min_height", 24.0)
	downward.set("max_height", 24.0)
	level.add_child(downward)
	var downward_player := _warma(Vector2(100, 92))
	await _tick(15)
	_check(downward_player._has_ground_support(), "Warma must be grounded on a downward elevator")
	var downward_launch_y := downward_player.position.y
	Input.action_press("jump")
	await _tick(8)
	Input.action_release("jump")
	_check(downward_player.position.y < downward_launch_y - 4.0,
		"Warma must jump from a downward elevator")
	await _cleanup()

	for direction in [0, 1, 2, 3]:
		_new_level()
		var moving := load(ELEVATOR_DIRECTION_SCENES[direction]).instantiate() as AnimatableBody2D
		moving.position = Vector2(100, 100)
		moving.set("min_height", 3.0)
		moving.set("max_height", 12.0)
		moving.set("height_speed", 120.0)
		level.add_child(moving)
		moving.call("set_button_active", true)
		await _tick(15)
		_check(is_equal_approx(float(moving.get("current_height")), 12.0),
			"Direction %d must extend to its configured maximum" % direction)
		await _cleanup()

	# A telescoping rod is not a wall: a Block in its path must not stop it.
	for direction in [2, 3]:
		_new_level()
		var through := load(ELEVATOR_DIRECTION_SCENES[direction]).instantiate() as AnimatableBody2D
		through.position = Vector2(100, 100)
		through.set("min_height", 3.0)
		through.set("max_height", 24.0)
		through.set("height_speed", 120.0)
		level.add_child(through)
		_block(Vector2(80 if direction == 2 else 120, 100))
		through.call("set_button_active", true)
		await _tick(40)
		_check(is_equal_approx(float(through.get("current_height")), 24.0),
			"Horizontal direction %d must extend through a solid block" % direction)
		await _cleanup()

	# The reported case: a rod whose own anchor sits inside a Block must still grow.
	for direction in [0, 1, 2, 3]:
		_new_level()
		var inside := load(ELEVATOR_DIRECTION_SCENES[direction]).instantiate() as AnimatableBody2D
		inside.position = Vector2(100, 100)
		inside.set("min_height", 3.0)
		inside.set("max_height", 24.0)
		inside.set("height_speed", 120.0)
		level.add_child(inside)
		_block(Vector2(100, 100))
		inside.call("set_button_active", true)
		await _tick(40)
		_check(is_equal_approx(float(inside.get("current_height")), 24.0),
			"Direction %d must grow even when its anchor is inside a Block" % direction)
		await _cleanup()

	for direction in [2, 3]:
		_new_level()
		var horizontal := load(ELEVATOR_DIRECTION_SCENES[direction]).instantiate() as AnimatableBody2D
		horizontal.position = Vector2(100, 100)
		horizontal.set("min_height", 24.0)
		horizontal.set("max_height", 24.0)
		level.add_child(horizontal)
		var player := _warma(Vector2(88 if direction == 2 else 108, 88))
		await _tick(15)
		_check(player._has_ground_support(),
			"Warma must be grounded on horizontal direction %d" % direction)
		var launch_y := player.position.y
		Input.action_press("jump")
		await _tick(8)
		Input.action_release("jump")
		_check(player.position.y < launch_y - 4.0 and player.velocity.y < 0.0,
			"Warma must jump from horizontal direction %d" % direction)
		await _cleanup()

func _giraffe_lands_on_each_direction() -> void:
	var settings := [
		["elevator_up", Vector2(100, 100), Vector2(100, 60)],
		["elevator_down", Vector2(100, 100), Vector2(100, 92)],
		["elevator_left", Vector2(100, 100), Vector2(88, 88)],
		["elevator_right", Vector2(100, 100), Vector2(112, 88)],
	]
	for setting in settings:
		_new_level()
		var lift := load("res://objects/%s.tscn" % setting[0]).instantiate() as AnimatableBody2D
		lift.position = setting[1]
		lift.set("min_height", 24.0)
		lift.set("max_height", 24.0)
		level.add_child(lift)
		var giraffe := _giraffe(setting[2])
		await _tick(60)
		_check(absf(giraffe.position.y - lift.call("get_support_surface_y") + 8.0) < 0.1,
			"Giraffe must land flush on %s" % setting[0])
		await _cleanup()

func _direction_button_links() -> void:
	for scene_name in ["elevator_up", "elevator_down", "elevator_left", "elevator_right"]:
		_new_level()
		var lift := load("res://objects/%s.tscn" % scene_name).instantiate() as AnimatableBody2D
		lift.name = "Elevator"
		lift.position = Vector2(100, 100)
		lift.set("min_height", 3.0)
		lift.set("max_height", 12.0)
		lift.set("height_speed", 120.0)
		lift.set("button_path", NodePath("../Button"))
		var button := load("res://objects/button.tscn").instantiate() as Area2D
		button.name = "Button"
		button.position = Vector2(180, 120)
		button.set("target_elevator", NodePath("../Elevator"))
		level.add_child(lift)
		level.add_child(button)
		await _tick(2)
		button.set_physics_process(false)
		button.call("set_activated", true)
		await _tick(12)
		_check(float(lift.get("current_height")) > 3.0,
			"Button must activate %s without direction-specific wiring" % scene_name)
		await _cleanup()

func _reset_restores_lift() -> void:
	# The room reset path must restore the authored elevator height and actors.
	_release_input()
	var error := change_scene_to_file("res://rooms/roomX.tscn")
	_check(error == OK, "RoomX must load for elevator reset regression")
	if error != OK:
		return
	await scene_changed
	var room := current_scene as Node2D
	var lift := room.get_node_or_null("Elevator")
	var giraffe := room.get_node_or_null("Giraffe") as CharacterBody2D
	var player := room.get_node_or_null("Player") as CharacterBody2D
	_check(lift != null and giraffe != null and player != null, "RoomX must expose elevator and actors for reset")
	if lift == null or giraffe == null or player == null:
		return
	var initial_height := float(lift.get("current_height"))
	var initial_giraffe := giraffe.global_position
	# Hold the authored short state so the comparison is independent of the
	# room's normal automatic extension while the button is unpressed.
	lift.call("set_button_active", true)
	await _tick(3)
	lift.call("set_height", float(lift.get("max_height")))
	room.call("reset_scene")
	await scene_changed
	var reset_room := current_scene
	var reset_lift := reset_room.get_node_or_null("Elevator")
	var reset_giraffe := reset_room.get_node_or_null("Giraffe") as CharacterBody2D
	_check(reset_lift != null and is_equal_approx(float(reset_lift.get("current_height")), initial_height),
		"Room reset must restore the elevator's authored height")
	_check(reset_giraffe != null and reset_giraffe.global_position.distance_to(initial_giraffe) < 0.1,
		"Room reset must restore giraffe position")

func _shape_resource_isolation() -> void:
	_new_level()
	# Two instances of the same scene must own independent collision shapes;
	# otherwise resizing one lift corrupts every other lift in the room.
	var first := load("res://objects/elevator_up.tscn").instantiate() as AnimatableBody2D
	var second := load("res://objects/elevator_up.tscn").instantiate() as AnimatableBody2D
	first.position = Vector2(100, 100)
	second.position = Vector2(200, 100)
	level.add_child(first)
	level.add_child(second)
	first.call("set_height", 24.0)
	await _tick(2)
	var first_shape := first.get_node("CollisionShape2D").shape as RectangleShape2D
	var second_shape := second.get_node("CollisionShape2D").shape as RectangleShape2D
	_check(first_shape != second_shape,
		"Each elevator instance must own a distinct collision shape resource")
	_check(second_shape.size.is_equal_approx(Vector2(8.0, 3.0 - 0.02)),
		"Resizing one elevator must not change another instance's shape")
	await _cleanup()

func _rising_body_is_not_supported() -> void:
	_new_level()
	var lift := load(ELEVATOR_SCENE).instantiate() as AnimatableBody2D
	lift.position = Vector2(100, FLOOR_Y)
	lift.set("min_height", 32.0)
	lift.set("max_height", 32.0)
	level.add_child(lift)
	var player := _warma(Vector2(100, FLOOR_Y - 32.0 - 8.0))
	player.set_physics_process(false)
	await _tick(2)
	player.velocity = Vector2(0.0, -150.0)
	_check(not bool(lift.call("supports_body", player, 0.75)),
		"A rising body must not be re-snapped onto the elevator support plane")
	await _cleanup()

func _growth_freezes_clear_of_grounded_bodies() -> void:
	# The reported crush: a downward rod extending onto grounded Warma froze
	# only after penetrating the head by the support tolerance, and that lasting
	# overlap let physics depenetration grind Warma into the floor. Only the
	# upward lift carries its obstruction; every other direction must freeze at
	# a clearance BEFORE touching a body in its growth corridor.
	for direction in [1, 2, 3]:
		_new_level()
		var lift := load(ELEVATOR_DIRECTION_SCENES[direction]).instantiate() as AnimatableBody2D
		lift.position = Vector2(100, 100)
		lift.set("min_height", 3.0)
		lift.set("max_height", 60.0)
		lift.set("height_speed", 16.0)
		level.add_child(lift)
		var body_at := Vector2(100, 132)
		var stand_on := Vector2(100, 148)
		match direction:
			1:
				stand_on = Vector2(100, 148)
				body_at = Vector2(100, 132)
			2:
				stand_on = Vector2(48, 112)
				body_at = Vector2(48, 96)
			3:
				stand_on = Vector2(152, 112)
				body_at = Vector2(152, 96)
		_block(stand_on)
		var player := _warma(body_at)
		await _tick(15)
		lift.call("set_button_active", true)
		await _tick(600)
		var height := float(lift.get("current_height"))
		_check(height < 59.0,
			"Direction %d must freeze before reaching the grounded body (h=%.3f)" % [direction, height])
		var shape_node := lift.get_node("CollisionShape2D") as CollisionShape2D
		var rectangle := shape_node.shape as RectangleShape2D
		var rod_rect := Rect2(lift.global_position + shape_node.position - rectangle.size * 0.5, rectangle.size)
		var body_rect: Rect2 = lift.call("_body_bounds", player)
		_check(not rod_rect.intersects(body_rect),
			"Direction %d rod (rect %s) must never overlap the grounded body (rect %s)" % [direction, rod_rect, body_rect])
		_check(absf(player.position.x - body_at.x) < 0.05 and absf(player.position.y - body_at.y) < 0.05,
			"Direction %d must not shove the grounded body (at %s, want %s)" % [direction, player.position, body_at])
		await _cleanup()

func _lifts_jam_and_resume_vertically() -> void:
	# The requested contract: rods extending toward each other must jam (both
	# stop, neither abandons its button target), and when one retracts the
	# other resumes toward its own target. Blocks stay pass-through; only
	# another lift is solid.
	_new_level()
	var rising := load(ELEVATOR_SCENE).instantiate() as AnimatableBody2D
	rising.position = Vector2(100, 140)
	rising.set("min_height", 3.0)
	rising.set("max_height", 60.0)
	rising.set("height_speed", 24.0)
	level.add_child(rising)
	var descending := load("res://objects/elevator_down.tscn").instantiate() as AnimatableBody2D
	descending.position = Vector2(100, 60)
	descending.set("min_height", 3.0)
	descending.set("max_height", 60.0)
	descending.set("height_speed", 24.0)
	level.add_child(descending)
	await _tick(2)
	rising.call("set_button_active", true)
	descending.call("set_button_active", true)
	await _tick(400)
	var rising_end := 140.0 - float(rising.get("current_height"))
	var descending_end := 60.0 + float(descending.get("current_height"))
	# The rising tip comes from below, so at the jam it must still sit below
	# the descending tip (larger world y) by at least the clearance.
	_check(rising_end - descending_end >= 0.05,
		"Jammed rods must keep a clearance gap (gap=%.3f)" % (rising_end - descending_end))
	_check(float(rising.get("current_height")) < 59.0 and float(descending.get("current_height")) < 59.0,
		"Both rods must stop before crossing (up h=%.3f, down h=%.3f)" % [float(rising.get("current_height")), float(descending.get("current_height"))])
	descending.call("set_button_active", false)
	await _tick(400)
	_check(is_equal_approx(float(rising.get("current_height")), 60.0),
		"The rising rod must extend fully once the other retracts (h=%.3f)" % float(rising.get("current_height")))
	_check(is_equal_approx(float(descending.get("current_height")), 3.0),
		"The released rod must retract to its minimum (h=%.3f)" % float(descending.get("current_height")))
	descending.call("set_button_active", true)
	await _tick(400)
	var down_end := 60.0 + float(descending.get("current_height"))
	_check(down_end <= rising_end - 0.04,
		"The descending rod must stop clear above the extended rod (end y=%.3f, tip y=%.3f)" % [down_end, rising_end])
	rising.call("set_button_active", false)
	await _tick(400)
	_check(is_equal_approx(float(descending.get("current_height")), 60.0),
		"The descending rod must extend fully once the rising rod retracts (h=%.3f)" % float(descending.get("current_height")))
	await _cleanup()

func _lifts_jam_and_resume_horizontally() -> void:
	# The same jam-and-resume contract along the horizontal axes: a left-growing
	# rod and a right-growing rod stop clear of one another, and the survivor
	# continues toward its target when the other side retracts.
	_new_level()
	var leftward := load("res://objects/elevator_left.tscn").instantiate() as AnimatableBody2D
	leftward.position = Vector2(140, 100)
	leftward.set("min_height", 3.0)
	leftward.set("max_height", 60.0)
	leftward.set("height_speed", 24.0)
	level.add_child(leftward)
	var rightward := load("res://objects/elevator_right.tscn").instantiate() as AnimatableBody2D
	rightward.position = Vector2(60, 100)
	rightward.set("min_height", 3.0)
	rightward.set("max_height", 60.0)
	rightward.set("height_speed", 24.0)
	level.add_child(rightward)
	await _tick(2)
	leftward.call("set_button_active", true)
	rightward.call("set_button_active", true)
	await _tick(400)
	var left_end := 140.0 - float(leftward.get("current_height"))
	var right_end := 60.0 + float(rightward.get("current_height"))
	_check(left_end - right_end >= 0.05,
		"Jammed horizontal rods must keep a clearance gap (gap=%.3f)" % (left_end - right_end))
	_check(float(leftward.get("current_height")) < 59.0 and float(rightward.get("current_height")) < 59.0,
		"Both horizontal rods must stop before crossing (left h=%.3f, right h=%.3f)" % [float(leftward.get("current_height")), float(rightward.get("current_height"))])
	rightward.call("set_button_active", false)
	await _tick(400)
	_check(is_equal_approx(float(leftward.get("current_height")), 60.0),
		"The leftward rod must extend fully once the rightward rod retracts (h=%.3f)" % float(leftward.get("current_height")))
	leftward.call("set_button_active", false)
	await _cleanup()

func _static_lift_is_solid_to_growing_lifts() -> void:
	# A fully extended (static) rod is terrain for other rods: growth must stop
	# at a clearance before its underside, in contrast to blocks and tiles,
	# which rods telescope straight through.
	_new_level()
	var bridge := load("res://objects/elevator_left.tscn").instantiate() as AnimatableBody2D
	bridge.position = Vector2(120, 70)
	bridge.set("min_height", 40.0)
	bridge.set("max_height", 40.0)
	level.add_child(bridge)
	var rising := load(ELEVATOR_SCENE).instantiate() as AnimatableBody2D
	rising.position = Vector2(100, 140)
	rising.set("min_height", 3.0)
	rising.set("max_height", 80.0)
	rising.set("height_speed", 24.0)
	level.add_child(rising)
	await _tick(2)
	rising.call("set_button_active", true)
	await _tick(500)
	var height := float(rising.get("current_height"))
	var tip_y := 140.0 - height
	_check(tip_y >= 74.0 + 0.04,
		"The rising rod must stop clear below the static rod's underside (tip y=%.3f)" % tip_y)
	_check(height < 79.0,
		"The rising rod must not pass through a static rod (h=%.3f)" % height)
	await _cleanup()

func _scenes_are_authored_per_direction() -> void:
	# Each direction scene must be saved already rotated, so dropping it into a
	# map shows the final orientation before the game ever runs.
	var expected := [
		["elevator_up", Vector2(8.0, 3.0), Vector2(0.0, -1.5),
			PackedVector2Array([Vector2(-4, 0), Vector2(4, 0), Vector2(4, -3), Vector2(-4, -3)])],
		["elevator_down", Vector2(8.0, 3.0), Vector2(0.0, 1.5),
			PackedVector2Array([Vector2(4, 0), Vector2(4, 3), Vector2(-4, 3), Vector2(-4, 0)])],
		["elevator_left", Vector2(3.0, 8.0), Vector2(-1.5, 0.0),
			PackedVector2Array([Vector2(0, 4), Vector2(-3, 4), Vector2(-3, -4), Vector2(0, -4)])],
		["elevator_right", Vector2(3.0, 8.0), Vector2(1.5, 0.0),
			PackedVector2Array([Vector2(0, -4), Vector2(3, -4), Vector2(3, 4), Vector2(0, 4)])],
	]
	for entry in expected:
		var packed := load("res://objects/%s.tscn" % entry[0]) as PackedScene
		_check(packed != null, "%s must load" % entry[0])
		if packed == null:
			continue
		# instantiate() copies the authored values but does not run _ready, so
		# this inspects exactly what a map placement would show.
		var root := packed.instantiate() as Node2D
		var shape_node := root.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var shape: RectangleShape2D = null
		if shape_node != null:
			shape = shape_node.shape as RectangleShape2D
		_check(shape != null and shape.size.is_equal_approx(entry[1]),
			"%s must be authored with its own collision size" % entry[0])
		_check(shape_node != null and shape_node.position.is_equal_approx(entry[2]),
			"%s must be authored with its own anchor offset" % entry[0])
		var visual := root.get_node_or_null("Visual") as Polygon2D
		_check(visual != null and visual.polygon == entry[3],
			"%s must be authored already rotated for its direction" % entry[0])
		root.free()

func _death_freeze_stops_lift() -> void:
	# room.freeze_for_death() must stop lift motion: PROCESS_MODE_ALWAYS would
	# bypass the room's DISABLED mode and keep the rod moving while Warma's
	# death animation plays.
	_release_input()
	level = load("res://rooms/roomX.tscn").instantiate() as Node2D
	root.add_child(level)
	await _tick(2)
	var lift := level.get_node_or_null("Elevator") as AnimatableBody2D
	_check(lift != null, "RoomX must expose Elevator for the death-freeze check")
	if lift == null:
		await _cleanup()
		return
	level.call("freeze_for_death")
	await _tick(2)
	var frozen_height := float(lift.get("current_height"))
	lift.call("set_button_active", true)
	await _tick(30)
	_check(is_equal_approx(float(lift.get("current_height")), frozen_height),
		"A frozen room's elevator must not keep moving during death")
	level.process_mode = Node.PROCESS_MODE_INHERIT
	await _cleanup()

func _run() -> void:
	await _stack_on_static_lift()
	await _moving_stack_stays_supported()
	await _giraffe_stacks()
	await _descending_lift_jump()
	await _seam_walk()
	await _four_direction_shapes_and_horizontal_jump()
	await _giraffe_lands_on_each_direction()
	await _direction_button_links()
	await _scenes_are_authored_per_direction()
	await _rise_blocked()
	await _shape_resource_isolation()
	await _rising_body_is_not_supported()
	await _growth_freezes_clear_of_grounded_bodies()
	await _lifts_jam_and_resume_vertically()
	await _lifts_jam_and_resume_horizontally()
	await _static_lift_is_solid_to_growing_lifts()
	await _reset_restores_lift()
	await _death_freeze_stops_lift()
	print("Elevator regression checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)



