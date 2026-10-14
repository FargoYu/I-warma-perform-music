@tool
class_name ExtinguisherPickup2D
extends Node2D
## A collectible rectangle queried by RectWorld2D; never a physics body.

const PICKUP_RECT := Rect2(-4.0, -4.0, 8.0, 8.0)
const EXTINGUISHER_TEXTURE: Texture2D = preload("res://Assets/Sprites/extinguisher.png")

@export_group("Glow")
@export var glow_color: Color = Color(0.47, 0.94, 1.0, 1.0)
@export var sparks_enabled: bool = true
@export_range(1, 128, 1) var spark_amount: int = 24
@export_range(1.0, 32.0, 0.5) var spark_radius: float = 5.0
@export_range(0.5, 4.0, 0.1) var spark_size: float = 1.0
@export_range(0.0, 8.0, 0.1) var spark_blink_speed: float = 1.6
@export_range(0.0, 1.0, 0.05) var spark_blink_min_alpha: float = 0.15

@export_group("Sprite Pulse")
@export var pulse_enabled: bool = true
@export_range(0.0, 8.0, 0.1) var pulse_speed: float = 1.6
@export_range(0.0, 1.0, 0.05) var pulse_min_brightness: float = 0.35
@export_range(0.0, 3.0, 0.05) var pulse_max_brightness: float = 1.6

var _time: float = 0.0
var _collected: bool = false


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func get_world_rect(world: Node2D) -> Rect2:
	var relative_transform := world.global_transform.affine_inverse() * global_transform
	return relative_transform * PICKUP_RECT


func collect(player: Node) -> bool:
	if _collected or is_queued_for_deletion() or not is_instance_valid(player):
		return false
	if not player is RectBody2D:
		return false
	var body := player as RectBody2D
	if body.kind != "warma" or not body.has_method("pick_up_extinguisher"):
		return false
	_collected = true
	body.call("pick_up_extinguisher")
	hide()
	set_process(false)
	queue_free()
	return true


func _draw() -> void:
	if _collected:
		return
	if sparks_enabled:
		var ring_color := glow_color
		ring_color.a *= _pulse(spark_blink_speed, spark_blink_min_alpha, 1.0)
		for index in range(spark_amount):
			var angle := TAU * float(index) / float(spark_amount)
			var point := Vector2(cos(angle), sin(angle)) * spark_radius
			var corner := (point - Vector2.ONE * spark_size * 0.5).round()
			draw_rect(Rect2(corner, Vector2.ONE * spark_size), ring_color)
	var sprite_color := Color.WHITE
	if pulse_enabled:
		var brightness := _pulse(pulse_speed, pulse_min_brightness, pulse_max_brightness)
		sprite_color = Color(
			brightness * lerpf(1.0, glow_color.r, 0.35),
			brightness * lerpf(1.0, glow_color.g, 0.35),
			brightness * lerpf(1.0, glow_color.b, 0.35),
			1.0)
	draw_texture(EXTINGUISHER_TEXTURE, Vector2(-1.0, -2.0), sprite_color)


func _pulse(speed: float, minimum: float, maximum: float) -> float:
	if speed <= 0.0:
		return maximum
	var wave := (sin(_time * speed * TAU) + 1.0) * 0.5
	return lerpf(minimum, maximum, wave)
