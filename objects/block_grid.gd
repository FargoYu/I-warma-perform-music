@tool
class_name BlockGrid2D
extends Node2D
## Paintable static rectangles. Each cell has the same geometry as a block scene.

const BLOCK_TEXTURE: Texture2D = preload("res://Assets/Sprites/block.png")

@export var cells: Array[Vector2i] = []:
	set(value):
		cells = value
		queue_redraw()
@export_range(1, 256, 1) var cell_size: int = 16:
	set(value):
		cell_size = maxi(1, value)
		queue_redraw()
@export var color: Color = Color("44546b"):
	set(value):
		color = value
		queue_redraw()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func get_rectangles() -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			continue
		seen[cell] = true
		rectangles.append(Rect2(global_position + Vector2(cell) * cell_size, Vector2.ONE * cell_size))
	return rectangles


func _draw() -> void:
	var show_bounds := Engine.is_editor_hint() or (get_tree() != null and get_tree().debug_collisions_hint)
	for cell in cells:
		var origin := Vector2(cell) * cell_size
		draw_texture_rect(BLOCK_TEXTURE, Rect2(origin, Vector2.ONE * cell_size), true)
		if show_bounds:
			draw_rect(Rect2(origin, Vector2.ONE * cell_size), Color(0.15, 0.85, 1.0, 0.8), false, 0.25)
	if Engine.is_editor_hint() and cells.is_empty():
		draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * cell_size), Color(0.29, 0.86, 0.94, 0.4), false, 1.0)


func _get_configuration_warnings() -> PackedStringArray:
	var relative_transform := _physics_space_transform()
	if not relative_transform.x.is_equal_approx(Vector2.RIGHT) or not relative_transform.y.is_equal_approx(Vector2.DOWN):
		return PackedStringArray(["方块网格及其世界内部父节点不能旋转或缩放；RectWorld2D 的整体显示缩放可用，物理使用原始网格尺寸。"])
	return PackedStringArray()


func _physics_space_transform() -> Transform2D:
	var relative_transform := Transform2D.IDENTITY
	var ancestor: Node = self
	while ancestor != null:
		var attached_script = ancestor.get_script()
		var is_world := false
		while attached_script is Script:
			if attached_script.get_global_name() == &"RectWorld2D":
				is_world = true
				break
			attached_script = attached_script.get_base_script()
		if ancestor != self and is_world:
			break
		if ancestor is Node2D:
			relative_transform = ancestor.transform * relative_transform
		ancestor = ancestor.get_parent()
	return relative_transform
