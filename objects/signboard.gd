@tool
extends Node2D
## Text visibility is selected centrally by RectWorld2D.

const TEXTURE = preload("res://Assets/Sprites/signboard.png")

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
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	_label.add_theme_font_override("font", font)
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
		_label.text = text
		_fit_message()

func _fit_message() -> void:
	if not is_inside_tree() or not is_instance_valid(_label):
		return
	# A short message should stay centered over the sign even near an edge.
	var font := _label.get_theme_font("font")
	var natural_width := 0.0
	for line in _label.text.split("\n"):
		natural_width = maxf(natural_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var canvas_transform := get_global_transform_with_canvas()
	var available_width := get_viewport_rect().size.x / maxf(canvas_transform.x.length(), 0.001)
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
	var viewport_rect := get_viewport_rect()
	var clamped_position := Vector2(
		clampf(screen_rect.position.x, viewport_rect.position.x, maxf(viewport_rect.position.x, viewport_rect.end.x - screen_rect.size.x)),
		clampf(screen_rect.position.y, viewport_rect.position.y, maxf(viewport_rect.position.y, viewport_rect.end.y - screen_rect.size.y)))
	_panel.position += canvas_transform.basis_xform_inv(clamped_position - screen_rect.position)

func _draw() -> void:
	draw_texture(TEXTURE, Vector2.ZERO)
