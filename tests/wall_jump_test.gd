extends SceneTree
## Reproduce forced side contact, then verify jumping without crossing a wall.

var failures: Array[String] = []

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

func _release() -> void:
	for action in ["jump", "move_left", "move_right"]:
		Input.action_release(action)

func _wall_jump(kind: String, direction: int) -> void:
	_release()
	var level := Node2D.new()
	root.add_child(level)
	var floor_body := StaticBody2D.new()
	var floor_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(240, 16)
	floor_shape.shape = rectangle
	floor_body.position = Vector2(128, 136)
	floor_body.add_child(floor_shape)
	level.add_child(floor_body)
	var player := load("res://objects/warma.tscn").instantiate() as CharacterBody2D
	player.position = Vector2(100 - direction * 30, 120)
	level.add_child(player)
	var half_width := 8.0
	if kind == "giraffe":
		var giraffe := load("res://objects/giraffe.tscn").instantiate() as CharacterBody2D
		giraffe.position = Vector2(100, 120)
		level.add_child(giraffe)
		half_width = 4.0
	elif kind == "tile":
		var tiles := load("res://objects/blocks.tscn").instantiate() as TileMapLayer
		tiles.position = Vector2(92, 112)
		tiles.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
		level.add_child(tiles)
		tiles.update_internals()
	else:
		var block := load("res://objects/block.tscn").instantiate() as StaticBody2D
		block.position = Vector2(100, 120)
		if kind == "tall_block":
			block.position.y = 104.0
			var shape := block.get_node("CollisionShape2D") as CollisionShape2D
			shape.shape = shape.shape.duplicate()
			(shape.shape as RectangleShape2D).size.y = 47.98
		level.add_child(block)
	await _tick(12)
	var action := "move_right" if direction > 0 else "move_left"
	Input.action_press(action)
	await _tick(65)
	var player_side_width := 3.0 if direction > 0 else 2.0
	_check(absf(player.position.x - (100.0 - direction * (half_width + player_side_width))) < 0.05,
		"%s %d: must reach precise side contact" % [kind, direction])
	var launch_y := player.position.y
	Input.action_press("jump")
	await _tick(8)
	_check(player.position.y < launch_y - 4.0,
		"%s %d: must jump while still pressing into the wall" % [kind, direction])
	_check((player.position.x - 100.0) * direction <= -(half_width + player_side_width) + 0.05,
		"%s %d: jump must not enter the wall before clearing its top" % [kind, direction])
	_release()
	await _tick(160)
	_check(player._has_ground_support(), "%s %d: must land after releasing jump" % [kind, direction])
	level.queue_free()
	await _tick(2)

func _run() -> void:
	root.get_node("GameState").reset_speed()
	for kind in ["giraffe", "block", "tile", "tall_block"]:
		for direction in [1, -1]:
			await _wall_jump(kind, direction)
	print("Wall jump checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
