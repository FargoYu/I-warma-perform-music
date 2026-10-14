extends Node2D
## Keyboard-driven opening/ending scenes; targets stay editable in Inspector.

@export_file("*.tscn") var target_scene: String = "res://main.tscn"
@export var quit_on_key: bool = false

var transitioning := false

func _ready() -> void:
	if quit_on_key:
		get_node("/root/AudioManager").play_sfx(&"complete")

func _unhandled_input(event: InputEvent) -> void:
	if transitioning or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if quit_on_key:
		transitioning = true
		get_tree().quit()
		return
	var scene = load(target_scene) if ResourceLoader.exists(target_scene) else null
	if not scene is PackedScene or not scene.can_instantiate():
		push_warning("开场场景的 Target Scene 无效：%s" % target_scene)
		return
	transitioning = true
	get_node("/root/AudioManager").play_sfx(&"confirm", -2.0)
	get_tree().change_scene_to_packed.call_deferred(scene)
