extends Area2D
## A pressure plate that stays active while Warma or the giraffe overlaps it.

@export var target_elevator: NodePath
@export var pressure_size: Vector2 = Vector2(14.0, 4.0)

signal activation_changed(active: bool)
var activated := false

@onready var plate_sprite: Sprite2D = $Sprite2D
@onready var pressure_shape: CollisionShape2D = $PressureShape

func _ready() -> void:
	add_to_group("buttons")
	monitoring = true
	# Each instance owns its pressure shape; otherwise multiple buttons sharing
	# this scene would also share one RectangleShape2D resource.
	if pressure_shape != null and pressure_shape.shape != null:
		pressure_shape.shape = pressure_shape.shape.duplicate()
	_apply_pressure_size()
	_set_visual(false)
	# An explicitly assigned elevator receives the signal without requiring
	# scene-specific glue code. Elevator.button_path remains a second option.
	if not target_elevator.is_empty():
		var elevator := get_node_or_null(target_elevator)
		if elevator != null and elevator.has_method("set_button_source"):
			elevator.call("set_button_source", self)

func _physics_process(_delta: float) -> void:
	var pressed := false
	var has_group_body := false
	for group_name in ["player", "giraffe"]:
		for body in get_tree().get_nodes_in_group(group_name):
			has_group_body = true
			if body is Node2D and _bounds_overlap(body as Node2D):
				pressed = true
				break
		if pressed:
			break
	if not pressed and not has_group_body:
		for body in get_overlapping_bodies():
			if body != null and body.collision_layer & (2 | 4) != 0:
				pressed = true
				break
	set_activated(pressed)

func set_activated(value: bool) -> void:
	value = bool(value)
	if value == activated:
		return
	activated = value
	_set_visual(activated)
	activation_changed.emit(activated)

func activate() -> void:
	set_activated(true)

func deactivate() -> void:
	set_activated(false)

func is_activated() -> bool:
	return activated

func set_pressed(value: bool) -> void:
	set_activated(value)

func is_pressed() -> bool:
	return activated

func _apply_pressure_size() -> void:
	if pressure_shape == null:
		return
	var rectangle := pressure_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		pressure_shape.shape = rectangle
	rectangle.size = pressure_size

func _set_visual(active: bool) -> void:
	if plate_sprite == null:
		return
	plate_sprite.texture = load("res://Assets/Sprites/buttonActive.png" if active else "res://Assets/Sprites/buttonInactive.png")

func _bounds_overlap(body: Node2D) -> bool:
	var bounds := _body_bounds(body)
	var center := global_position + pressure_shape.position
	var half := pressure_size * 0.5
	return bounds.end.x >= center.x - half.x and bounds.position.x <= center.x + half.x and bounds.end.y >= center.y - half.y and bounds.position.y <= center.y + half.y

func _body_bounds(body: Node2D) -> Rect2:
	var shape_node := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var shape := shape_node.shape as RectangleShape2D
		var half_size := shape.size * 0.5
		return Rect2(body.global_position + shape_node.position - half_size, shape.size)
	var polygon := body.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if polygon != null and not polygon.polygon.is_empty():
		var rect := Rect2(polygon.polygon[0], Vector2.ZERO)
		for point in polygon.polygon:
			rect = rect.expand(point)
		return Rect2(body.global_position + rect.position, rect.size)
	var half_size := Vector2(3.0, 8.0)
	return Rect2(body.global_position - half_size, half_size * 2.0)
