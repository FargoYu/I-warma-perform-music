extends AnimatableBody2D
## A narrow, continuously resizing lift anchored at its bottom edge.

@export_range(3.0, 256.0, 0.01) var max_height: float = 32.0
@export_range(3.0, 256.0, 0.01) var min_height: float = 3.0
@export_range(0.1, 256.0, 0.1) var height_speed: float = 24.0
@export var starts_extended := false
@export var button_path: NodePath
@export var elevator_color: Color = Color(0.78, 0.31, 0.16, 1.0)

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual: Polygon2D = $Visual

var current_height: float = 3.0
var button_active := false
var _button_source: Node

func _ready() -> void:
	add_to_group("elevators")
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	min_height = maxf(min_height, 3.0)
	max_height = maxf(max_height, min_height)
	current_height = max_height if starts_extended else min_height
	visual.color = elevator_color
	_apply_height(current_height)
	if not button_path.is_empty():
		var source := get_node_or_null(button_path)
		if source != null:
			set_button_source(source)

func _physics_process(delta: float) -> void:
	var pressed_target := min_height if starts_extended else max_height
	var released_target := max_height if starts_extended else min_height
	var target := pressed_target if button_active else released_target
	var next_height := move_toward(current_height, target, maxf(height_speed, 0.01) * delta)
	if is_equal_approx(next_height, current_height):
		return
	var change := next_height - current_height
	if change > 0.0:
		# Growth into a side contact pauses the lift. A body standing on its top
		# is moved by exactly the same sub-pixel increment instead, so it remains
		# supported and can still walk horizontally away from the lift.
		if _growth_blocked(next_height):
			return
		if not _can_push_supported_bodies(change):
			return
		_push_supported_bodies(change)
	_apply_height(next_height)

func set_button_source(source: Node) -> void:
	if _button_source == source:
		return
	if is_instance_valid(_button_source) and _button_source.has_signal("activation_changed"):
		var old_callable := Callable(self, "_on_button_activation_changed")
		if _button_source.is_connected("activation_changed", old_callable):
			_button_source.disconnect("activation_changed", old_callable)
	_button_source = source
	if is_instance_valid(_button_source):
		if _button_source.has_signal("activation_changed"):
			_button_source.activation_changed.connect(_on_button_activation_changed)
		button_active = bool(_button_source.get("activated"))

func _on_button_activation_changed(active: bool) -> void:
	set_button_active(active)

func set_button_active(active: bool) -> void:
	button_active = bool(active)

func is_button_active() -> bool:
	return button_active

func set_height(value: float) -> void:
	_apply_height(clampf(value, min_height, max_height))

func get_height() -> float:
	return current_height

func get_current_height() -> float:
	return current_height

func _apply_height(value: float) -> void:
	current_height = clampf(value, min_height, max_height)
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		collision_shape.shape = rectangle
	rectangle.size = Vector2(8.0, current_height)
	collision_shape.position = Vector2(0.0, -current_height * 0.5)
	visual.polygon = PackedVector2Array([
		Vector2(-4.0, 0.0), Vector2(4.0, 0.0),
		Vector2(4.0, -current_height), Vector2(-4.0, -current_height)
	])

func _growth_blocked(next_height: float) -> bool:
	var old_top := global_position.y - current_height
	var new_top := global_position.y - next_height
	for candidate in _occupants():
		var bounds := _body_bounds(candidate)
		if bounds.size.x <= 0.0:
			continue
		if bounds.end.x <= global_position.x - 4.0 or bounds.position.x >= global_position.x + 4.0:
			continue
		# The proposed vertical strip overlaps this body. A body whose feet are
		# already on the old top will be carried upward in _push_supported_bodies.
		if bounds.end.y > new_top + 0.001 and bounds.position.y < old_top - 0.001:
			if absf(bounds.end.y - old_top) <= 0.75:
				continue
			return true
	return false

func _push_supported_bodies(change: float) -> void:
	var old_top := global_position.y - current_height
	for candidate in _occupants():
		var bounds := _body_bounds(candidate)
		if bounds.end.x <= global_position.x - 4.0 or bounds.position.x >= global_position.x + 4.0:
			continue
		if absf(bounds.end.y - old_top) <= 0.75:
			candidate.global_position.y -= change
			if candidate is CharacterBody2D:
				var character := candidate as CharacterBody2D
				if character.velocity.y > 0.0:
					character.velocity.y = 0.0

func _can_push_supported_bodies(change: float) -> bool:
	for candidate in _occupants():
		var bounds := _body_bounds(candidate)
		if bounds.end.x <= global_position.x - 4.0 or bounds.position.x >= global_position.x + 4.0:
			continue
		var old_top := global_position.y - current_height
		if absf(bounds.end.y - old_top) > 0.75:
			continue
		if candidate is CharacterBody2D:
			var character := candidate as CharacterBody2D
			if character.test_move(character.global_transform, Vector2(0.0, -change), null, 0.001, true):
				return false
	return true

func _occupants() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for group_name in ["player", "giraffe"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node2D and not result.has(node):
				result.append(node)
	return result

func _body_bounds(node: Node2D) -> Rect2:
	var half_size := Vector2(3.0, 8.0)
	var shape_node := node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		half_size = (shape_node.shape as RectangleShape2D).size * 0.5
	else:
		var polygon := node.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
		if polygon != null and not polygon.polygon.is_empty():
			var rect := Rect2(polygon.polygon[0], Vector2.ZERO)
			for point in polygon.polygon:
				rect = rect.expand(point)
			half_size = rect.size * 0.5
	return Rect2(node.global_position - half_size, half_size * 2.0)
