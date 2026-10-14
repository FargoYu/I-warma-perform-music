@tool
class_name RectBody2D
extends Node2D
## The position is the upper-left corner of the full, unshrunk physics rectangle.
## RectWorld2D owns movement; this node only stores configuration and draws it.

const WARMA_TEXTURE: Texture2D = preload("res://Assets/Sprites/warma.png")
const GIRAFFE_TEXTURE: Texture2D = preload("res://Assets/Sprites/giraffe.png")
const BLOCK_TEXTURE: Texture2D = preload("res://Assets/Sprites/block.png")

@export_enum("block", "warma", "giraffe") var kind: String = "block":
	set(value):
		kind = value
		queue_redraw()
@export var body_width: float = 16.0:
	set(value):
		body_width = maxf(value, 0.001)
		queue_redraw()
@export var body_height: float = 16.0:
	set(value):
		body_height = maxf(value, 0.001)
		queue_redraw()
@export var fixed: bool = true
@export var tint: Color = Color("44546b"):
	set(value):
		tint = value
		queue_redraw()
@export var move_speed: float = 46.0
@export var jump_speed: float = 132.0
@export_range(0.0, 10.0, 0.05, "or_greater") var hit_move_duration: float = 0.8

## Horizontal facing only; flipping preserves the upper-left physics anchor.
@export_enum("Left:-1", "Right:1") var direction: int = 1:
	set(value):
		direction = 1 if value >= 0 else -1
		queue_redraw()

var state
var move_direction: int = 0
var _hit_move_remaining: float = 0.0
var _flash_remaining: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	queue_redraw()


func hit_by_bullet(shot_direction: int) -> void:
	if kind != "giraffe" or shot_direction == 0:
		return
	move_direction = 1 if shot_direction > 0 else -1
	direction = move_direction
	_hit_move_remaining = maxf(0.0, hit_move_duration)
	_flash_remaining = 0.16
	set_process(true)
	queue_redraw()


func step_movement(delta: float) -> float:
	if kind != "giraffe":
		return move_direction * move_speed
	if delta <= 0.0:
		return 0.0
	# The world advances this timer only while gameplay is running. A partial
	# final tick uses its remaining time, so movement cannot outlast the hit.
	var active_time := minf(delta, _hit_move_remaining)
	var speed := move_direction * move_speed
	_hit_move_remaining = maxf(0.0, _hit_move_remaining - delta)
	if _hit_move_remaining <= 0.000000001:
		_hit_move_remaining = 0.0
		move_direction = 0
	return speed * active_time / delta


func _process(delta: float) -> void:
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	queue_redraw()
	if _flash_remaining <= 0.0:
		set_process(false)


func get_sprite_transform() -> Transform2D:
	var source_body_size := Vector2(8.0, 16.0) if kind == "giraffe" else Vector2(5.0, 16.0)
	var sprite_scale := Vector2(body_width, body_height) / source_body_size
	# Warma's source faces right; Giraffe's source faces left.
	var mirrored := direction > 0 if kind == "giraffe" else direction < 0
	return Transform2D(
		Vector2(-sprite_scale.x if mirrored else sprite_scale.x, 0.0),
		Vector2(0.0, sprite_scale.y),
		Vector2(body_width, 0.0) if mirrored else Vector2.ZERO)


func _draw() -> void:
	var dimensions := Vector2(body_width, body_height)
	if kind == "block":
		draw_texture_rect(BLOCK_TEXTURE, Rect2(Vector2.ZERO, dimensions), true)
	else:
		var character_texture: Texture2D = GIRAFFE_TEXTURE if kind == "giraffe" else WARMA_TEXTURE
		var source_offset := Vector2(-0.5, 0.0) if kind == "giraffe" else Vector2(-1.0, -1.0)
		draw_set_transform_matrix(get_sprite_transform())
		var modulation := Color(1.65, 1.65, 1.65, 1.0) if _flash_remaining > 0.0 else Color.WHITE
		draw_texture(character_texture, source_offset, modulation)
		draw_set_transform(Vector2.ZERO)
	if Engine.is_editor_hint() or (get_tree() != null and get_tree().debug_collisions_hint):
		draw_rect(Rect2(Vector2.ZERO, dimensions), Color(0.15, 0.85, 1.0, 0.8), false, 0.25)


func _get_configuration_warnings() -> PackedStringArray:
	# RectWorld2D may scale its whole canvas for display; only transforms inside
	# that world's coordinate system can invalidate the unscaled AABB geometry.
	var relative_transform := _physics_space_transform()
	if not relative_transform.x.is_equal_approx(Vector2.RIGHT) or not relative_transform.y.is_equal_approx(Vector2.DOWN):
		return PackedStringArray(["矩形及其世界内部父节点不能旋转或缩放；RectWorld2D 的整体显示缩放可用。请通过 Body Width / Body Height 改变尺寸。"])
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
