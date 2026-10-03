extends Area2D
## A reusable sign that shows an editable message while Warma is inside it.

@export_multiline var message: String = "A/D 移动   J 跳跃   W 进门   R 重置"
## Top-left position of the 240px-wide centered text box in viewport pixels.
@export var text_position: Vector2 = Vector2(8.0, 62.0)
@export_range(6, 64, 1) var font_size: int = 16
@export var text_color: Color = Color(0.03, 0.03, 0.03, 1.0)
@export var area_size: Vector2 = Vector2(28.0, 20.0)

@onready var message_label: Label = $MessageLayer/Message
@onready var trigger_shape: CollisionShape2D = $TriggerShape

var player_inside := false

func _ready() -> void:
	add_to_group("signboards")
	monitoring = true
	_apply_area_size()
	_apply_message()
	message_label.visible = false

func _process(_delta: float) -> void:
	# Polling is more reliable than one-shot body_entered signals for tiny
	# pixel-perfect CharacterBody2D contacts and also handles a body teleported
	# into a sign by a reset or a moving platform.
	# Use the bodies' current transforms directly. This also handles a room reset
	# or a scripted teleport on the same frame, before Area2D overlap caches are
	# refreshed by the physics server.
	var inside := false
	var has_group_player := false
	for body in get_tree().get_nodes_in_group("player"):
		has_group_player = true
		if body is Node2D and _bounds_overlap(body as Node2D):
			inside = true
			break
	# Keep the object usable with a custom player body that has not opted into
	# the project's player group. Grouped players still use the direct transform
	# test above, so stale Area2D overlap caches cannot keep their message alive.
	if not inside and not has_group_player:
		for body in get_overlapping_bodies():
			if body != null and body.collision_layer & 2 != 0:
				inside = true
				break
	if inside != player_inside:
		player_inside = inside
		message_label.visible = player_inside

func _bounds_overlap(body: Node2D) -> bool:
	var body_half := Vector2(3.0, 8.0)
	var polygon := body.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if polygon != null and not polygon.polygon.is_empty():
		var bounds := Rect2(polygon.polygon[0], Vector2.ZERO)
		for point in polygon.polygon:
			bounds = bounds.expand(point)
		body_half = bounds.size * 0.5
	return absf(body.global_position.x - global_position.x) <= area_size.x * 0.5 + body_half.x \
		and absf(body.global_position.y - global_position.y) <= area_size.y * 0.5 + body_half.y

func _apply_area_size() -> void:
	if trigger_shape == null:
		return
	var rectangle := trigger_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		trigger_shape.shape = rectangle
	rectangle.size = area_size

func _apply_message() -> void:
	if message_label == null:
		return
	message_label.text = message
	message_label.size = Vector2(0.0, 0.0)
	message_label.add_theme_font_size_override("font_size", font_size)
	message_label.add_theme_color_override("font_color", text_color)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A wide, centered control keeps the position stable when the editable
	# message changes length. text_position directly controls its top-left.
	message_label.position = text_position
	message_label.size.x = 240.0
	message_label.size.y = maxf(float(font_size + 4), message_label.get_combined_minimum_size().y)

func set_message(value: String) -> void:
	message = value
	_apply_message()

func set_text_position(value: Vector2) -> void:
	text_position = value
	_apply_message()
