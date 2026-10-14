@tool
class_name Warma2D
extends "res://objects/rect_body.gd"
## Equipment only. RectWorld2D continues to own all movement and collision.

signal extinguisher_changed(equipped: bool)

const EXTINGUISHER_TEXTURE: Texture2D = preload("res://Assets/Sprites/extinguisher.png")

@export var has_extinguisher: bool = false:
	set(value):
		if has_extinguisher == value:
			return
		has_extinguisher = value
		queue_redraw()
		extinguisher_changed.emit(has_extinguisher)


func pick_up_extinguisher() -> void:
	has_extinguisher = true


func get_equipment_transform() -> Transform2D:
	return get_sprite_transform().translated_local(Vector2(4.0, 2.0))


func get_nozzle_position() -> Vector2:
	# Outer upper edge of the black nozzle pixel, in collision-local space.
	return get_equipment_transform() * Vector2(2.0, 0.0)


func _draw() -> void:
	super._draw()
	if not has_extinguisher:
		return
	draw_set_transform_matrix(get_equipment_transform())
	draw_texture(EXTINGUISHER_TEXTURE, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO)
