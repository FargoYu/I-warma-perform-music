extends Area2D
## Music bullet: a horizontal, gravity-free note emitted by the extinguisher.

const BULLET_TEXTURE := preload("res://Assets/Sprites/musicBullet.png")

@export var speed: float = 24.0
@export var growth_duration: float = 0.24

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var direction: int = 1
var _flying := false

func _ready() -> void:
	add_to_group("music_bullet")
	_build_growth_animation()
	body_entered.connect(_on_body_entered)
	monitoring = false

	# setup() is called before the node is added to the scene tree. Keeping this
	# deferred also makes the scene safe to instantiate directly in tests.
	call_deferred("_start_growth")

func setup(facing_direction: int, flight_speed: float, animation_duration: float) -> void:
	direction = -1 if facing_direction < 0 else 1
	speed = flight_speed
	growth_duration = maxf(animation_duration, 0.03)

func _start_growth() -> void:
	if not is_inside_tree():
		return
	sprite.flip_h = direction < 0
	sprite.speed_scale = 1.0 / growth_duration
	sprite.animation_finished.connect(_on_growth_finished, CONNECT_ONE_SHOT)
	sprite.play("grow")

func _physics_process(delta: float) -> void:
	if not _flying:
		return
	global_position.x += float(direction) * speed * delta
	if global_position.x < -24.0 or global_position.x > 280.0:
		queue_free()

func _on_growth_finished() -> void:
	_flying = true
	monitoring = true
	sprite.frame = 2

func _on_body_entered(body: Node2D) -> void:
	if not _flying or not body.is_in_group("giraffe"):
		return
	if body.has_method("run_in_direction"):
		body.run_in_direction(direction)
	elif body.has_method("apply_external_impulse"):
		body.apply_external_impulse(Vector2(direction * 24.0, 0.0))
	queue_free()

func _build_growth_animation() -> void:
	var frames := SpriteFrames.new()
	frames.add_animation("grow")
	frames.set_animation_loop("grow", false)
	frames.set_animation_speed("grow", 3.0)
	for mask in [0, 1, 2]:
		frames.add_frame("grow", _make_frame(mask))
	sprite.sprite_frames = frames

func _make_frame(stage: int) -> Texture2D:
	var image := Image.create(3, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var source_image := BULLET_TEXTURE.get_image()
	# The supplied note is kept as the final frame. Earlier frames reveal the
	# same pixels from the nozzle downward, so no filtered scaling is involved.
	for y in range(4):
		for x in range(3):
			var visible := false
			if stage == 0:
				visible = x == 1 and y == 0
			elif stage == 1:
				visible = (x == 1 and y == 0) or (y == 1 and (x == 1 or x == 2))
			else:
				visible = source_image.get_pixel(x, y).a > 0.0
			if visible:
				image.set_pixel(x, y, source_image.get_pixel(x, y) if stage == 2 else Color.BLACK)
	return ImageTexture.create_from_image(image)
