extends Area2D
## Music bullet: a horizontal, gravity-free note emitted by the extinguisher.

const BULLET_TEXTURE := preload("res://Assets/Sprites/musicBullet.png")
const TERRAIN_LAYER := 1
const GIRAFFE_LAYER := 4

@export var speed: float = 24.0
@export var growth_duration: float = 0.24
@export var lifetime: float = 12.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_probe: ShapeCast2D = $HitProbe

var direction: int = 1
var _flying := false
var _hit := false
var _age := 0.0

func _ready() -> void:
	add_to_group("music_bullet")
	_build_growth_animation()
	body_entered.connect(_on_body_entered)
	monitoring = true
	# setup() can run before the bullet enters the tree.
	_start_growth.call_deferred()

func setup(facing_direction: int, flight_speed: float, animation_duration: float) -> void:
	direction = -1 if facing_direction < 0 else 1
	speed = flight_speed
	growth_duration = maxf(animation_duration, 0.03)

func _start_growth() -> void:
	if not is_inside_tree() or _hit:
		return
	sprite.flip_h = direction < 0
	sprite.speed_scale = 1.0 / growth_duration
	sprite.animation_finished.connect(_on_growth_finished, CONNECT_ONE_SHOT)
	sprite.play("grow")

func _physics_process(delta: float) -> void:
	if _hit:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var motion := Vector2(float(direction) * speed * delta, 0.0) if _flying else Vector2.ZERO
	# Sweep the full note shape before moving so fast notes cannot cross a block.
	# A zero-length sweep also catches notes growing inside terrain.
	hit_probe.collision_mask = TERRAIN_LAYER | GIRAFFE_LAYER if _flying else TERRAIN_LAYER
	hit_probe.target_position = motion
	hit_probe.force_shapecast_update()
	if hit_probe.is_colliding():
		global_position += motion * hit_probe.get_closest_collision_safe_fraction()
		for index in hit_probe.get_collision_count():
			var body := hit_probe.get_collider(index)
			if _is_terrain(body):
				_handle_hit(body)
				return
		for index in hit_probe.get_collision_count():
			_handle_hit(hit_probe.get_collider(index))
			if _hit:
				return
	global_position += motion

func _on_growth_finished() -> void:
	if _hit:
		return
	_flying = true
	sprite.frame = 2

func _on_body_entered(body: Node2D) -> void:
	_handle_hit(body)

func _is_terrain(body: Object) -> bool:
	if body is TileMapLayer:
		return true
	return body is CollisionObject2D and ((body as CollisionObject2D).collision_layer & TERRAIN_LAYER) != 0

func _handle_hit(body: Object) -> void:
	if _hit:
		return
	if not _is_terrain(body):
		if not _flying or not body is Node or not (body as Node).is_in_group("giraffe"):
			return
		if body.has_method("run_in_direction"):
			body.call("run_in_direction", direction)
		elif body.has_method("apply_external_impulse"):
			body.call("apply_external_impulse", Vector2(direction * 24.0, 0.0))
	_hit = true
	queue_free()

func _build_growth_animation() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("grow")
	frames.set_animation_loop("grow", false)
	frames.set_animation_speed("grow", 3.0)
	for stage in [0, 1, 2]:
		frames.add_frame("grow", _make_frame(stage))
	sprite.sprite_frames = frames

func _make_frame(stage: int) -> Texture2D:
	var image := Image.create(3, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var source_image := BULLET_TEXTURE.get_image()
	# Reveal the supplied note's pixels without filtered scaling.
	for y in range(4):
		for x in range(3):
			var pixel_visible := false
			if stage == 0:
				pixel_visible = x == 1 and y == 0
			elif stage == 1:
				pixel_visible = (x == 1 and y == 0) or (y == 1 and (x == 1 or x == 2))
			else:
				pixel_visible = source_image.get_pixel(x, y).a > 0.0
			if pixel_visible:
				image.set_pixel(x, y, source_image.get_pixel(x, y) if stage == 2 else Color.BLACK)
	return ImageTexture.create_from_image(image)
