extends SceneTree
## Run with the matching Godot tools executable and --main-pack exported.exe.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	var audio = root.get_node("AudioManager")
	check(audio.SOUNDS.size() == 15, "release includes 15 active sound effects")
	for cue in audio.SOUNDS:
		check(audio.SOUNDS[cue].get_length() > 0.04, "%s decodes in release" % cue)
	for path in ["res://Assets/Audio/SFX/jump.wav", "res://Assets/Audio/SFX/sign.wav",
		"res://Assets/Audio/SFX/step_01.wav", "res://Assets/Audio/SFX/step_02.wav",
		"res://Assets/Audio/Music/puzzle_picnic.ogg", "res://tests/test_game.gd",
		"res://tools/generate_audio.py", "res://addons/block_painter/block_painter.gd"]:
		check(not ResourceLoader.exists(path), "release excludes %s" % path)
	var start = load("res://start.tscn").instantiate()
	root.add_child(start)
	current_scene = start
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	key.pressed = true
	start._unhandled_input(key)
	await process_frame
	await process_frame
	var game = current_scene
	check(game != null and game.scene_file_path == "res://main.tscn", "start screen opens game")
	for room in range(1, 17):
		if not is_instance_valid(game):
			check(false, "game remains active through room 16")
			break
		game.world.set_physics_process(false)
		check(game.world.scene_file_path == "res://levels/level_%02d.tscn" % room, "release enters room %02d" % room)
		check(game.world.setup_errors.is_empty(), "room %02d has valid physics layout" % room)
		if room == 1:
			game.world.grant_extinguisher()
			game.world.fire()
			check(game.world.bullets.size() == 1, "release fires after equipment pickup")
		game.world.enter_first_door()
		await process_frame
		await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://end.tscn", "release route reaches end screen")
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	print("RELEASE SMOKE: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)
