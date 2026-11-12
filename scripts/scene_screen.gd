extends Node2D
## Opening and completion screens support keyboard, mouse, and touch.

@export_file("*.tscn") var target_scene: String = "res://main.tscn"
@export var is_ending: bool = false

var transitioning := false
var _accept_input_after: int = 0

func _ready() -> void:
	# Wall-clock time is deliberate: the previous room may be at 0.1x speed.
	# Ignore a held pointer's synthetic mouse press during scene transitions.
	_accept_input_after = Time.get_ticks_msec() + 250
	get_node("/root/AudioManager").play_music(false)
	if is_ending:
		get_node("/root/AudioManager").play_sfx(&"complete")
	else:
		get_node("/root/GameState").reset_run()
	var touch: bool = get_node("/root/PlatformControls").is_touch_mode()
	var destination := "返回标题" if is_ending else "开始"
	$Prompt.text = ("轻触屏幕" if touch else "按任意键或点击") + destination

func _unhandled_input(event: InputEvent) -> void:
	if transitioning or Time.get_ticks_msec() < _accept_input_after:
		return
	var activate := false
	if event is InputEventKey:
		activate = event.pressed and not event.echo
	elif event is InputEventScreenTouch:
		activate = event.pressed and not event.canceled
	elif event is InputEventMouseButton:
		activate = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not activate:
		return
	get_viewport().set_input_as_handled()
	var scene = load(target_scene) if ResourceLoader.exists(target_scene) else null
	if not scene is PackedScene or not scene.can_instantiate():
		push_warning("画面场景的 Target Scene 无效：%s" % target_scene)
		return
	transitioning = true
	get_node("/root/AudioManager").play_sfx(&"confirm", -2.0)
	get_tree().change_scene_to_packed.call_deferred(scene)
