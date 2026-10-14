extends Node2D
## A small game entry point around the existing rectangular world.

@export var level: PackedScene = preload("res://levels/level_01.tscn")

var world: Node2D

func _ready() -> void:
	_load_room(level)
	if OS.get_cmdline_user_args().has("--capture"):
		_capture.call_deferred()

func _load_room(scene: PackedScene) -> void:
	world = scene.instantiate()
	add_child(world)
	world.restart_requested.connect(_restart_scene)
	world.room_requested.connect(_room_requested)
	var run_state := get_node("/root/GameState")
	if world.player != null:
		world.player.has_extinguisher = run_state.has_extinguisher
		world.player.extinguisher_changed.connect(_equipment_changed)
	world.reset_physics_interpolation()

func _room_requested(path: String) -> void:
	_switch_room.call_deferred(path)

func _switch_room(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		world.transitioning = false
		return
	var candidate = scene.instantiate()
	var is_screen: bool = candidate.get_script() == preload("res://scripts/scene_screen.gd")
	candidate.free()
	if is_screen:
		get_tree().change_scene_to_packed(scene)
		return
	var contacts: bool = world.show_contacts
	remove_child(world)
	world.queue_free()
	_load_room(scene)
	world.show_contacts = contacts

func _equipment_changed(equipped: bool) -> void:
	get_node("/root/GameState").has_extinguisher = equipped

func _restart_scene(restart_current_room: bool) -> void:
	if restart_current_room:
		_switch_room.call_deferred(world.scene_file_path)
	else:
		get_tree().reload_current_scene.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if world.restarting:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				world.request_restart()
			KEY_P:
				world.frozen = not world.frozen
				get_node("/root/AudioManager").set_puzzle_paused(world.frozen)
			KEY_F1:
				world.show_contacts = not world.show_contacts
				world.queue_redraw()

func _capture() -> void:
	world.set_physics_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	get_viewport().get_texture().get_image().save_png("res://artifacts/game_overview.png")
	world.player.pick_up_extinguisher()
	world.player.direction = -1
	world.show_contacts = true
	world.fire()
	world.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/game_equipped.png")
	get_tree().quit()
