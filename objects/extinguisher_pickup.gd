extends Area2D
## A level item that is collected as soon as Warma enters its area.
##
## The pickup glows so players notice it at a glance: a ring of sparks hugs the
## item's outline and blinks, while the sprite itself pulses. Every knob is
## exposed to the Inspector through @export, so the look can be tuned in the
## editor without touching this script.
##
## The visual is a plain CPUParticles2D node ("Sparks") plus the item sprite —
## no imported texture atlas and no external tooling involved.

@export_group("Glow Color")
## Base colour of the spark ring and the tint blended into the sprite pulse.
@export var glow_color: Color = Color(0.47, 0.94, 1.0, 1.0):
	set(value):
		glow_color = value
		_sync_color()

@export_group("Sparks")
## Toggles the whole spark ring.
@export var sparks_enabled: bool = true:
	set(value):
		sparks_enabled = value
		_sync_emitting()

## How many sparks sit on the ring.
@export_range(1, 128, 1) var spark_amount: int = 24:
	set(value):
		spark_amount = value
		_sync_sparks()

## Ring radius in logical pixels (the item itself is only about 4px tall).
@export_range(1.0, 32.0, 0.5) var spark_radius: float = 5.5:
	set(value):
		spark_radius = value
		_sync_sparks()

## Spark size in pixels.
@export_range(0.5, 4.0, 0.1) var spark_size: float = 1.0:
	set(value):
		spark_size = value
		_sync_sparks()

## Seconds a spark stays on the ring before being recycled.
@export_range(0.1, 20.0, 0.1) var spark_lifetime: float = 4.0:
	set(value):
		spark_lifetime = value
		_sync_sparks()

## How far sparks drift outward, in pixels per second.
## 0 pins them to the ring so the outline stays solid.
@export_range(0.0, 40.0, 0.1) var spark_drift_speed: float = 0.0:
	set(value):
		spark_drift_speed = value
		_sync_sparks()

## Spawn jitter for angle and speed. 0 = a perfectly even ring.
@export_range(0.0, 1.0, 0.01) var spark_randomness: float = 0.0:
	set(value):
		spark_randomness = value
		_sync_sparks()

## Ring blink speed in cycles per second. 0 keeps a steady glow.
@export_range(0.0, 8.0, 0.1) var spark_blink_speed: float = 1.6:
	set(value):
		spark_blink_speed = value
		_sync_blink()

## Lowest ring opacity during the blink (0 = fully hidden).
@export_range(0.0, 1.0, 0.05) var spark_blink_min_alpha: float = 0.15:
	set(value):
		spark_blink_min_alpha = value
		_sync_blink()

@export_group("Sprite Pulse")
## Toggles the brightness pulse on the item sprite.
@export var pulse_enabled: bool = true:
	set(value):
		pulse_enabled = value
		_sync_pulse()

## Sprite pulses per second. 0 keeps the sprite at full brightness.
@export_range(0.0, 8.0, 0.1) var pulse_speed: float = 1.6:
	set(value):
		pulse_speed = value
		_sync_pulse()

## Lowest sprite brightness during the pulse (1.0 = no dimming).
@export_range(0.0, 1.0, 0.05) var pulse_min_brightness: float = 0.35:
	set(value):
		pulse_min_brightness = value
		_sync_pulse()

## Highest sprite brightness during the pulse. Above 1.0 over-brightens it.
@export_range(0.0, 3.0, 0.05) var pulse_max_brightness: float = 1.6:
	set(value):
		pulse_max_brightness = value
		_sync_pulse()

var _sparks: CPUParticles2D
var _sprite: Sprite2D
var _time := 0.0
## Glow runs only while the item can actually be collected.
var _visible_glow := true


func _ready() -> void:
	if GameState.has_extinguisher:
		queue_free()
		return
	body_entered.connect(_on_body_entered)
	_sparks = get_node_or_null("Sparks")
	_sprite = get_node_or_null("Sprite2D")
	# Push every Inspector value into the nodes once, on spawn.
	_sync_color()
	_sync_sparks()
	_sync_emitting()


func _process(delta: float) -> void:
	if not _visible_glow:
		return
	_time += delta
	_sync_blink()
	_sync_pulse()


func _sync_blink() -> void:
	if not is_instance_valid(_sparks):
		return
	var alpha := 1.0
	if spark_blink_speed > 0.0:
		var wave := (sin(_time * spark_blink_speed * TAU) + 1.0) * 0.5
		alpha = lerpf(spark_blink_min_alpha, 1.0, wave)
	_sparks.color = Color(glow_color.r, glow_color.g, glow_color.b, alpha)


func _sync_pulse() -> void:
	if not is_instance_valid(_sprite):
		return
	if not pulse_enabled:
		_sprite.modulate = Color.WHITE
		return
	var brightness := pulse_max_brightness
	if pulse_speed > 0.0:
		var wave := (sin(_time * pulse_speed * TAU) + 1.0) * 0.5
		brightness = lerpf(pulse_min_brightness, pulse_max_brightness, wave)
	# Blend a little of the glow colour in so the sprite reads as "lit".
	_sprite.modulate = Color(
		brightness * lerpf(1.0, glow_color.r, 0.35),
		brightness * lerpf(1.0, glow_color.g, 0.35),
		brightness * lerpf(1.0, glow_color.b, 0.35),
		1.0)


func _sync_color() -> void:
	_sync_blink()


func _sync_sparks() -> void:
	if not is_instance_valid(_sparks):
		return
	_sparks.amount = spark_amount
	_sparks.lifetime = spark_lifetime
	_sparks.randomness = spark_randomness
	# Emit from a ring so sparks hug the item's outline.
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_sparks.emission_ring_radius = spark_radius
	_sparks.emission_ring_inner_radius = spark_radius
	_sparks.initial_velocity_min = spark_drift_speed * 0.5
	_sparks.initial_velocity_max = spark_drift_speed * 1.5
	_sparks.damping_min = 0.0
	_sparks.damping_max = 0.0
	_sparks.gravity = Vector2.ZERO
	_sparks.scale_amount_min = spark_size
	_sparks.scale_amount_max = spark_size


func _sync_emitting() -> void:
	if is_instance_valid(_sparks):
		_sparks.emitting = sparks_enabled and _visible_glow


func stop_glow() -> void:
	## Call before the pickup is removed, e.g. right after collection.
	_visible_glow = false
	if is_instance_valid(_sparks):
		_sparks.emitting = false


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("pick_up_extinguisher"):
		body.pick_up_extinguisher()
		queue_free()
