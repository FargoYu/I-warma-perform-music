@tool
extends CanvasLayer
## Foreground messages share one slot; persistent HUD controls use another layer.

const MESSAGE_GROUP := "foreground_messages"

@export_multiline var message: String = "场景提示":
	set(value):
		message = value
		refresh_text()
@export var text_position := Vector2(128.0, 72.0):
	set(value):
		text_position = value
		refresh_text()
@export_range(6, 64, 1) var font_size: int = 16:
	set(value):
		font_size = value
		refresh_text()
@export var text_color := Color.BLACK:
	set(value):
		text_color = value
		refresh_text()
@export_range(16.0, 512.0, 1.0) var text_width: float = 240.0:
	set(value):
		text_width = value
		refresh_text()
## Compact signs use their text's natural width, capped by text_width.
@export var fit_text_width := false:
	set(value):
		fit_text_width = value
		refresh_text()
## When centered, text_position is the center of the text, in viewport pixels.
@export var centered := true:
	set(value):
		centered = value
		refresh_text()
## Center room introductions in the current viewport instead of a fixed position.
## Signs disable this to anchor their messages above the sign sprite.
@export var center_on_screen := true:
	set(value):
		center_on_screen = value
		refresh_text()
@export var keep_on_screen := false:
	set(value):
		keep_on_screen = value
		_position_text()
@export var show_on_enter := true
## Seconds of game time; zero keeps the message visible until hide_message().
@export_range(0.0, 60.0, 0.1) var display_duration: float = 3.0

var _remaining_time := 0.0
var _timed := false

func _ready() -> void:
	$Message.resized.connect(_position_text)
	get_viewport().size_changed.connect(refresh_text)
	refresh_text()
	if Engine.is_editor_hint():
		$Message.visible = show_on_enter
	else:
		add_to_group(MESSAGE_GROUP)
		if show_on_enter:
			show_message()
		else:
			hide_message()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and _timed:
		_remaining_time -= delta
		if _remaining_time <= 0.0:
			hide_message()

func refresh_text() -> void:
	var label := get_node_or_null("Message") as Label
	if label == null:
		return
	label.text = message
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	var width := text_width
	if fit_text_width:
		var font := label.get_theme_font("font")
		var natural_width := 0.0
		for line in message.split("\n"):
			natural_width = maxf(natural_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
		width = minf(text_width, maxf(natural_width, 1.0))
	label.size = Vector2(width, 0.0)
	label.size.y = maxf(float(font_size + 4), label.get_minimum_size().y)
	_position_text()

func _position_text() -> void:
	var label := get_node_or_null("Message") as Label
	if label == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(256, 144)
	var anchor := viewport_size * 0.5 if centered and center_on_screen else text_position
	label.position = anchor - label.size * 0.5 if centered else anchor
	if keep_on_screen:
		if label.size.x <= viewport_size.x:
			label.position.x = clampf(label.position.x, 0.0, viewport_size.x - label.size.x)
		if label.size.y <= viewport_size.y:
			label.position.y = clampf(label.position.y, 0.0, viewport_size.y - label.size.y)

func show_message() -> void:
	# Hide synchronously before showing the new label, including its old timer.
	# Restrict arbitration to this viewport so separate previews stay independent.
	if not Engine.is_editor_hint() and is_inside_tree():
		for other in get_tree().get_nodes_in_group(MESSAGE_GROUP):
			if other != self and other.get_viewport() == get_viewport():
				other.hide_message()
	refresh_text()
	$Message.visible = true
	_remaining_time = display_duration
	_timed = display_duration > 0.0

func hide_message() -> void:
	$Message.visible = false
	_timed = false
