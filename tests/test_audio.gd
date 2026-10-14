extends SceneTree
## Audio resource, event, concurrency and scene-lifetime regression checks.

var failures: Array[String] = []
var checks := 0
var heard: Array[StringName] = []
var audio: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	audio = root.get_node("AudioManager")
	audio.sfx_played.connect(func(cue: StringName): heard.append(cue))
	check(audio.get_child_count() == 16, "only the sound effect pool is created")
	for voice in audio.get_children():
		check(not voice.playing and voice.bus == &"SFX", "startup has no automatic audio playback")
	check(AudioServer.get_bus_index(&"SFX") > 0, "SFX bus exists")
	check(AudioServer.get_bus_effect_count(0) == 1, "master limiter exists")
	var unused: Array[StringName] = [&"jump", &"sign", &"step_01", &"step_02"]
	for cue in unused:
		check(not audio.SOUNDS.has(cue), "%s is not registered" % cue)
	var files := DirAccess.get_files_at("res://Assets/Audio/SFX")
	var wav_count := 0
	for file in files:
		if file.ends_with(".wav"):
			wav_count += 1
			check(audio.SOUNDS.has(StringName(file.get_basename())), "%s is used by the game" % file)
	check(wav_count == audio.SOUNDS.size(), "every registered sound has exactly one WAV asset")
	for cue in audio.SOUNDS:
		var stream = audio.SOUNDS[cue]
		check(stream.get_length() > .04, "%s has audio" % cue)
		check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s is a one-shot" % cue)
		audio.play_sfx(cue)
		check(heard.has(cue), "%s can play" % cue)
	audio.set_puzzle_paused(true)
	check(heard.has(&"pause"), "pause plays feedback")
	audio.set_puzzle_paused(false)
	check(heard.has(&"resume"), "resume plays feedback")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	root.get_node("GameState").has_extinguisher = false
	heard.clear()
	game.world.grant_extinguisher()
	check(heard.has(&"pickup"), "equipment acquisition triggers pickup")
	heard.clear()
	for index in 3:
		game.world.fire()
	check(heard == [&"shoot_01", &"shoot_02", &"shoot_03"], "rapid shots cycle through three pitches")
	heard.clear()
	game.world.room_requested.connect(func(_path: String): pass)
	game.world.request_room("res://levels/level_02.tscn")
	check(heard.has(&"door"), "valid room transition plays door")
	await process_frame
	game.world.set_physics_process(false)
	check(root.get_node("AudioManager") == audio, "room transition retains sound effect manager")
	check(not heard.has(&"pickup"), "restoring equipment does not replay pickup")
	game.queue_free()
	await process_frame
	var screen = load("res://end.tscn").instantiate()
	root.add_child(screen)
	check(heard.has(&"complete"), "ending plays completion")
	root.get_node("GameState").change_time_speed(-1)
	for voice in audio._voices:
		check(voice.pitch_scale == 1.0, "slow motion leaves sound effect pitch unchanged")
	check(heard.has(&"time_down"), "speed change plays feedback")
	Engine.time_scale = 1.0
	for i in 40:
		audio.play_shot()
	check(audio._voices.size() == 16, "rapid input keeps a bounded voice pool")
	screen.queue_free()
	await process_frame
	print("AUDIO: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)
