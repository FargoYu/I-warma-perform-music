extends Node2D
## A small game entry point around the existing rectangular world.

@export var level: PackedScene = preload("res://levels/level_01.tscn")

var world: Node2D

func _ready() -> void:
	get_node("/root/AudioManager").play_music(true)
	_load_room(level)
	get_node("/root/PlatformControls").bind_game(self)

func _exit_tree() -> void:
	var controls := get_node_or_null("/root/PlatformControls")
	if controls != null:
		controls.unbind_game(self)

func _load_room(scene: PackedScene) -> void:
	get_node("/root/PlatformControls").release_all()
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

func is_paused() -> bool:
	return is_instance_valid(world) and world.frozen and not world.restarting

func set_paused(value: bool) -> void:
	if not is_instance_valid(world) or world.restarting or world.transitioning or not world.setup_errors.is_empty():
		return
	if world.frozen == value:
		return
	world.frozen = value
	get_node("/root/PlatformControls").release_all()
	get_node("/root/AudioManager").set_puzzle_paused(value)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(world) or world.restarting:
		return
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		world.request_restart()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		set_paused(not world.frozen)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		world.show_contacts = not world.show_contacts
		world.queue_redraw()
		get_viewport().set_input_as_handled()
