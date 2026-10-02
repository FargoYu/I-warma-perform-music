extends SceneTree
## Run: godot --headless --path . --script res://tests/music_bullet_test.gd

const BULLET_SCENE := "res://objects/music_bullet.tscn"
const BLOCK_SCENE := "res://objects/block.tscn"
const BLOCKS_SCENE := "res://objects/blocks.tscn"
const GIRAFFE_SCENE := "res://objects/giraffe.tscn"
const PLAYER_SCENE := "res://objects/warma.tscn"

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
		# physics_frame precedes callbacks; process_frame observes their results.
		await physics_frame
		await process_frame

func _instance(path: String) -> Node:
	var scene := load(path) as PackedScene
	_check(scene != null, "Could not load %s" % path)
	return scene.instantiate() if scene != null else null

func _new_level() -> Node2D:
	var level := Node2D.new()
	level.name = "BulletTestLevel"
	root.add_child(level)
	return level

func _clear_level(level: Node2D) -> void:
	level.queue_free()
	await process_frame
	await process_frame

func _spawn_bullet(level: Node2D, at: Vector2, direction: int, speed: float, lifetime: float = 12.0) -> Area2D:
	var bullet := _instance(BULLET_SCENE) as Area2D
	_check(bullet != null, "MusicBullet root must be Area2D")
	if bullet == null:
		return null
	bullet.position = at
	bullet.call("setup", direction, speed, 60.0)
	bullet.set("lifetime", lifetime)
	level.add_child(bullet)
	return bullet

func _trace_exit(bullet: Area2D) -> Dictionary:
	var trace := {"position": bullet.global_position, "flying": false, "exited": false}
	bullet.tree_exiting.connect(func() -> void:
		trace["position"] = bullet.global_position
		trace["flying"] = bool(bullet.get("_flying"))
		trace["exited"] = true
	)
	return trace

func _wait_for_free(node, frames: int) -> void:
	for _i in range(frames):
		if not is_instance_valid(node):
			break
		await _tick()
	await process_frame

func _add_terrain(level: Node2D, use_tiles: bool) -> Node2D:
	var terrain := _instance(BLOCKS_SCENE if use_tiles else BLOCK_SCENE) as Node2D
	if terrain == null:
		return null
	if use_tiles:
		var blocks := terrain as TileMapLayer
		_check(blocks != null, "Blocks root must be TileMapLayer")
		if blocks == null:
			terrain.free()
			return null
		blocks.position = Vector2(92, 32)
		blocks.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO, 0)
	else:
		_check(terrain is StaticBody2D, "Block root must be StaticBody2D")
		terrain.position = Vector2(100, 40)
	level.add_child(terrain)
	if terrain is TileMapLayer:
		(terrain as TileMapLayer).update_internals()
	return terrain

func _test_contract() -> void:
	var bullet := _instance(BULLET_SCENE) as Area2D
	if bullet == null:
		_check(false, "MusicBullet root must be Area2D")
		return
	_check(bullet.collision_mask == 5, "MusicBullet must scan terrain 1 and giraffe 4, not Warma or areas")
	_check(is_equal_approx(float(bullet.get("lifetime")), 12.0), "MusicBullet default lifetime must be 12 seconds")
	_check(bullet.has_method("setup"), "MusicBullet must expose setup(direction, speed, growth_duration)")
	var probe := bullet.get_node_or_null("HitProbe") as ShapeCast2D
	_check(probe != null and probe.shape != null, "MusicBullet must have a shaped HitProbe sweep")
	bullet.free()

func _test_growth_and_flight() -> void:
	var level := _new_level()
	var start := Vector2(100, 40)
	var bullet := _spawn_bullet(level, start, 1, 480.0)
	if bullet != null:
		await _tick(5)
		_check(is_instance_valid(bullet), "Unobstructed growing note must remain alive")
		if is_instance_valid(bullet):
			_check(not bool(bullet.get("_flying")), "Long growth animation must not start flight early")
			_check(bullet.global_position.is_equal_approx(start), "Growing note must stay at its spawn position")
			# Finish only animation here; all collision checks still run in actual physics.
			bullet.call("_on_growth_finished")
			await _tick(4)
			_check(is_instance_valid(bullet), "Unobstructed flying note unexpectedly disappeared")
			if is_instance_valid(bullet):
				_check(bullet.global_position.x > start.x, "Growth completion must start horizontal flight")
				_check(is_equal_approx(bullet.global_position.y, start.y), "Flying note must not fall")
	await _clear_level(level)

func _test_terrain(direction: int, use_tiles: bool, speed: float) -> void:
	var kind := "TileMapLayer" if use_tiles else "independent Block"
	var label := "%s direction=%d speed=%.1f" % [kind, direction, speed]
	var level := _new_level()
	var terrain := _add_terrain(level, use_tiles)
	await _tick(2)
	var bullet := _spawn_bullet(level, Vector2(100 - direction * 36, 38), direction, speed)
	if terrain != null and bullet != null:
		var trace := _trace_exit(bullet)
		await _tick()
		if is_instance_valid(bullet):
			bullet.call("_on_growth_finished")
		await _wait_for_free(bullet, 24)
		_check(not is_instance_valid(bullet), "Note must be freed on %s" % label)
		_check(bool(trace["exited"]), "Missing note exit on %s" % label)
		var exit_position: Vector2 = trace["position"]
		_check((exit_position.x - 100.0) * direction <= -7.5, "Note tunneled past the near face of %s" % label)
		_check(is_instance_valid(terrain), "Note must not delete %s" % kind)
	await _clear_level(level)

func _test_growth_inside_terrain(use_tiles: bool) -> void:
	var kind := "TileMapLayer" if use_tiles else "independent Block"
	var level := _new_level()
	var terrain := _add_terrain(level, use_tiles)
	await _tick(2)
	var bullet := _spawn_bullet(level, Vector2(99.5, 38), 1, 480.0)
	if terrain != null and bullet != null:
		var trace := _trace_exit(bullet)
		await _wait_for_free(bullet, 4)
		_check(not is_instance_valid(bullet), "Growing note overlapping %s must be freed" % kind)
		_check(bool(trace["exited"]) and not bool(trace["flying"]), "Terrain must stop the note before growth finishes: %s" % kind)
		_check(is_instance_valid(terrain), "Growth collision must preserve %s" % kind)
	await _clear_level(level)

func _test_giraffe(direction: int, overlap_during_growth: bool = false) -> void:
	var level := _new_level()
	var giraffe := _instance(GIRAFFE_SCENE) as CharacterBody2D
	if giraffe == null:
		_check(false, "Giraffe root must be CharacterBody2D")
		await _clear_level(level)
		return
	giraffe.position = Vector2(100, 40)
	giraffe.set("gravity", 0.0)
	level.add_child(giraffe)
	await _tick(2)
	var start := Vector2(99.5, 38) if overlap_during_growth else Vector2(100 - direction * 28, 38)
	var bullet := _spawn_bullet(level, start, direction, 480.0)
	if bullet != null:
		await _tick(5)
		_check(is_instance_valid(bullet), "Growing note must not hit giraffe, direction=%d" % direction)
		_check(giraffe.global_position.is_equal_approx(Vector2(100, 40)), "Growing note must not move giraffe")
		_check(is_zero_approx(giraffe.velocity.x), "Growing note must not trigger giraffe running")
		if is_instance_valid(bullet):
			bullet.call("_on_growth_finished")
			await _wait_for_free(bullet, 20)
			_check(not is_instance_valid(bullet), "Flying note must be freed on giraffe, direction=%d" % direction)
			await _tick(3)
			_check(int(giraffe.get("_music_run_direction")) == direction, "Giraffe must run in note direction %d" % direction)
			_check(float(giraffe.get("_music_run_time")) > 0.0, "Music hit must retain giraffe run duration")
			_check(is_equal_approx(giraffe.velocity.x, direction * float(giraffe.get("music_run_speed"))), "Music hit must retain giraffe run speed")
			_check((giraffe.global_position.x - 100.0) * direction > 0.0, "Music hit must actually move giraffe, direction=%d" % direction)
			_check(is_equal_approx(giraffe.global_position.y, 40.0), "Zero-gravity giraffe should retain height")
	await _clear_level(level)

func _test_player_is_ignored(direction: int) -> void:
	var level := _new_level()
	var player := _instance(PLAYER_SCENE) as CharacterBody2D
	if player == null:
		_check(false, "Warma root must be CharacterBody2D")
		await _clear_level(level)
		return
	player.name = "Player"
	player.position = Vector2(100, 40)
	level.add_child(player)
	player.set_physics_process(false)
	await _tick(2)
	var bullet := _spawn_bullet(level, Vector2(100 - direction * 36, 38), direction, 480.0)
	if bullet != null:
		await _tick()
		if is_instance_valid(bullet):
			bullet.call("_on_growth_finished")
		await _tick(20)
		_check(is_instance_valid(bullet), "Note must pass through Warma, direction=%d" % direction)
		if is_instance_valid(bullet):
			_check((bullet.global_position.x - player.global_position.x) * direction > 12.0, "Note did not cross Warma body")
		_check(player.global_position.is_equal_approx(Vector2(100, 40)), "Note must not move Warma")
	await _clear_level(level)

func _test_areas_are_ignored(direction: int) -> void:
	var level := _new_level()
	var pickup := _instance("res://objects/extinguisher_pickup.tscn") as Area2D
	var door := _instance("res://objects/door.tscn") as Area2D
	if pickup == null or door == null:
		if pickup != null:
			pickup.free()
		if door != null:
			door.free()
		await _clear_level(level)
		return
	pickup.position = Vector2(88, 40)
	door.position = Vector2(120, 40)
	level.add_child(pickup)
	level.add_child(door)
	await _tick(2)
	var start := Vector2(64, 38) if direction > 0 else Vector2(144, 38)
	var bullet := _spawn_bullet(level, start, direction, 480.0)
	if bullet != null:
		await _tick()
		if is_instance_valid(bullet):
			bullet.call("_on_growth_finished")
		await _tick(36)
		_check(is_instance_valid(bullet), "Note must pass through pickup and door areas, direction=%d" % direction)
		if is_instance_valid(bullet):
			_check(bullet.global_position.x > 132.0 if direction > 0 else bullet.global_position.x < 80.0, "Note did not cross both area shapes")
		_check(is_instance_valid(pickup), "Note must not collect extinguisher pickup")
		_check(is_instance_valid(door) and not bool(door.get("player_inside")), "Note must not activate door")
		_check(not bool(game_state.get("has_extinguisher")), "Note must not change persistent equipment state")
	await _clear_level(level)

func _test_lifetime_and_room_independence(direction: int) -> void:
	var level := _new_level()
	var start := Vector2(400, 40) if direction > 0 else Vector2(-120, 40)
	var bullet := _spawn_bullet(level, start, direction, 240.0)
	if bullet != null:
		await _tick()
		if is_instance_valid(bullet):
			bullet.call("_on_growth_finished")
		await _tick(5)
		_check(is_instance_valid(bullet), "Note outside old main-room X bounds must remain alive, direction=%d" % direction)
		if is_instance_valid(bullet):
			_check((bullet.global_position.x - start.x) * direction > 0.0, "Standalone note must keep flying outside main room")
	await _clear_level(level)
	level = _new_level()
	bullet = _spawn_bullet(level, Vector2(100, 40), direction, 240.0, 0.06)
	if bullet != null:
		await _tick()
		if is_instance_valid(bullet):
			bullet.call("_on_growth_finished")
		await _wait_for_free(bullet, 20)
		_check(not is_instance_valid(bullet), "Note must expire using configurable lifetime without terrain")
	await _clear_level(level)

func _test_block_protects_giraffe(direction: int, use_tiles: bool) -> void:
	var level := _new_level()
	var terrain := _add_terrain(level, use_tiles)
	var giraffe := _instance(GIRAFFE_SCENE) as CharacterBody2D
	if terrain == null or giraffe == null:
		if giraffe != null:
			giraffe.free()
		await _clear_level(level)
		return
	var giraffe_position := Vector2(100 + direction * 32, 40)
	giraffe.position = giraffe_position
	giraffe.set("gravity", 0.0)
	level.add_child(giraffe)
	await _tick(2)
	var bullet := _spawn_bullet(level, Vector2(100 - direction * 36, 38), direction, float(Engine.physics_ticks_per_second) * 128.0)
	if bullet != null:
		await _tick()
		if is_instance_valid(bullet):
			bullet.call("_on_growth_finished")
		await _wait_for_free(bullet, 4)
		_check(not is_instance_valid(bullet), "Terrain must consume a note before it reaches the giraffe")
		_check(is_zero_approx(float(giraffe.get("_music_run_time"))), "Blocked note must not trigger a giraffe behind terrain")
		_check(giraffe.global_position.is_equal_approx(giraffe_position), "Blocked note must not move the protected giraffe")
	await _clear_level(level)

func _test_automatic_growth() -> void:
	var level := _new_level()
	var bullet := _instance(BULLET_SCENE) as Area2D
	if bullet != null:
		bullet.position = Vector2(100, 40)
		bullet.call("setup", 1, 24.0, 0.03)
		level.add_child(bullet)
		await _tick(16)
		_check(is_instance_valid(bullet), "Naturally animated note must remain alive in empty space")
		if is_instance_valid(bullet):
			_check(bool(bullet.get("_flying")), "Animation completion must automatically start flight")
			_check(bullet.global_position.x > 100.0, "Automatically grown note must move horizontally")
	await _clear_level(level)

func _run() -> void:
	game_state = root.get_node_or_null("GameState")
	_check(game_state != null, "GameState autoload must exist")
	if game_state == null:
		quit(1)
		return
	var saved_equipment := bool(game_state.get("has_extinguisher"))
	game_state.set("has_extinguisher", false)
	_test_contract()
	await _test_growth_and_flight()
	await _test_automatic_growth()
	for direction in [1, -1]:
		for use_tiles in [false, true]:
			await _test_terrain(direction, use_tiles, 480.0)
			# One physics tick crosses eight full brick widths.
			await _test_terrain(direction, use_tiles, float(Engine.physics_ticks_per_second) * 128.0)
			await _test_block_protects_giraffe(direction, use_tiles)
		await _test_giraffe(direction)
		await _test_player_is_ignored(direction)
		await _test_areas_are_ignored(direction)
		await _test_lifetime_and_room_independence(direction)
	for use_tiles in [false, true]:
		await _test_growth_inside_terrain(use_tiles)
	await _test_giraffe(1, true)
	game_state.set("has_extinguisher", saved_equipment)
	print("Music bullet physics checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
