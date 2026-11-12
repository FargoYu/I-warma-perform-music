@tool
extends Node2D
## Text visibility is selected centrally by RectWorld2D.

const TEXTURE = preload("res://Assets/Sprites/signboard.png")
const UI_FONT = preload("res://Assets/Fonts/NotoSansSC.ttf")

@export_multiline var text: String = "告示牌"
@export var interaction_rect := Rect2(0, 0, 16, 16)
@export_range(40, 240, 1) var text_width: int = 120
@export_range(6, 24, 1) var font_size: int = 10
@export var text_gap: float = 4.0

var _panel: Panel
var _label: Label

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_panel = Panel.new()
	_panel.name = "Message"
	_panel.z_index = 50
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color.BLACK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UI_FONT)
	_panel.add_child(_label)
	add_child(_panel)
	_label.position = Vector2(4, 3)
	_label.minimum_size_changed.connect(_fit_message.call_deferred)
	_panel.hide()
	get_viewport().size_changed.connect(_fit_message.call_deferred)

func _process(_delta: float) -> void:
	if is_instance_valid(_panel) and _panel.visible:
		_position_message()

func get_world_rect(world: Node2D) -> Rect2:
	return (world.global_transform.affine_inverse() * global_transform) * interaction_rect

func show_message(show_text: bool) -> void:
	if not is_instance_valid(_panel):
		return
	if _panel.visible == show_text:
		return
	_panel.visible = show_text
	if show_text:
		_label.add_theme_font_size_override("font_size", font_size)
		_label.size = Vector2(text_width - 8, 0)
		_label.text = _input_hint()
		_fit_message()

func _input_hint() -> String:
	var controls := get_node_or_null("/root/PlatformControls")
	if controls == null or not controls.is_touch_mode():
		return text.replace("按上键进门", "按W进门")
	# Keep authored level text intact while describing the controls in use.
	return text.replace("按A/D移动", "按左 / 右按钮移动") \
		.replace("长按J", "长按「跳跃」") \
		.replace("按住J", "按住「跳跃」") \
		.replace("按J跳跃", "点按「跳跃」") \
		.replace("按K演奏灭火器", "点按「演奏」吹灭火器") \
		.replace("按R重置", "点按「重来」重置") \
		.replace("按上键进门", "靠近门，点按「进门」") \
		.replace("按W进门", "靠近门，点按「进门」") \
		.replace("按Left/Right可以控制时间流速，用于精细操作", "点按「减速 / 加速」控制时间流速，用于精细操作")

func _fit_message() -> void:
	if not is_inside_tree() or not is_instance_valid(_label):
		return
	# A short message should stay centered over the sign even near an edge.
	var font := _label.get_theme_font("font")
	var natural_width := 0.0
	for line in _label.text.split("\n"):
		natural_width = maxf(natural_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var canvas_transform := get_global_transform_with_canvas()
	var available_width := _message_bounds().size.x / maxf(canvas_transform.x.length(), 0.001)
	var width := minf(minf(text_width, natural_width + 8.0), available_width)
	_label.size = Vector2(maxf(1.0, width - 8.0), 0)
	_label.size.y = _label.get_minimum_size().y
	_panel.size = Vector2(width, _label.size.y + 6)
	_position_message()

func _position_message() -> void:
	_panel.position = Vector2(TEXTURE.get_width() * 0.5 - _panel.size.x * 0.5, -text_gap - _panel.size.y)
	# Keep signs near the screen edges readable at any window/display scale.
	var canvas_transform := get_global_transform_with_canvas()
	var screen_rect := canvas_transform * Rect2(_panel.position, _panel.size)
	var viewport_rect := _message_bounds()
	var clamped_position := Vector2(
		clampf(screen_rect.position.x, viewport_rect.position.x, maxf(viewport_rect.position.x, viewport_rect.end.x - screen_rect.size.x)),
		clampf(screen_rect.position.y, viewport_rect.position.y, maxf(viewport_rect.position.y, viewport_rect.end.y - screen_rect.size.y)))
	_panel.position += canvas_transform.basis_xform_inv(clamped_position - screen_rect.position)

func _message_bounds() -> Rect2:
	# Touch layouts center the room inside a larger viewport. Keep the black
	# sign text over the room background rather than the dark side margins.
	var ancestor := get_parent() as Node2D
	while ancestor != null:
		if ancestor.has_method("request_room"):
			return ancestor.get_global_transform_with_canvas() * Rect2(0, 0, 256, 144)
		ancestor = ancestor.get_parent() as Node2D
	return get_viewport_rect()

func _draw() -> void:
	draw_texture(TEXTURE, Vector2.ZERO)
