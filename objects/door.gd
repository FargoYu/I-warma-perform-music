@tool
extends Node2D
## Non-solid interaction rectangle, positioned by its top-left corner.

const TEXTURE = preload("res://Assets/Sprites/door.png")

## Select a room scene. A path avoids circular PackedScene dependencies between rooms.
@export_file("*.tscn") var target_room: String = ""
@export var interaction_rect := Rect2(0, 0, 16, 16)

func get_world_rect(world: Node2D) -> Rect2:
	return (world.global_transform.affine_inverse() * global_transform) * interaction_rect

func _draw() -> void:
	draw_texture(TEXTURE, Vector2.ZERO)

func _get_configuration_warnings() -> PackedStringArray:
	if target_room.is_empty():
		return PackedStringArray(["请在 Target Room 中选择目标房间场景。"])
	return PackedStringArray()
