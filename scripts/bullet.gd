@tool
class_name LabBullet
extends Node2D

const TEXTURE: Texture2D = preload("res://Assets/Sprites/musicBullet.png")

var direction: int = 1
## Horizontal travel speed in pixels per second; Giraffe defaults to 20.
@export_range(0.0, 200.0, 1.0, "or_greater") var speed: float = 24.0
var lifetime: float = 70.0
const SIZE := Vector2(3, 2)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _draw() -> void:
	# The 3x4 note is centered on the existing 3x2 projectile rectangle.
	draw_texture(TEXTURE, (SIZE - TEXTURE.get_size()) * 0.5)
	if Engine.is_editor_hint() or (get_tree() != null and get_tree().debug_collisions_hint):
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.15, 0.85, 1.0, 0.8), false, 0.25)
