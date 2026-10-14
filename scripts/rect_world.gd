class_name RectWorld2D
extends Node2D
const BlockGridScript = preload("res://objects/block_grid.gd")
const RectBodyScript = preload("res://objects/rect_body.gd")
## One authority for all solid rectangles. Native Godot body motion is not used.

const State = preload("res://physics/rect_state.gd")
const Solver = preload("res://physics/rect_solver.gd")
const BulletScene = preload("res://objects/bullet.tscn")
const ExtinguisherPickup = preload("res://objects/extinguisher_pickup.gd")
const DoorScript = preload("res://objects/door.gd")
const SignboardScript = preload("res://objects/signboard.gd")
const ScreenScript = preload("res://scripts/scene_screen.gd")
const GRAVITY: float = 360.0
const TERMINAL_SPEED: float = 240.0

## World-local Y coordinate where Warma's feet trigger death.
@export var fall_limit: float = 144.0
@export var horizontal_limit: float = 640.0
@export_range(0.01, 1.0, 0.01) var death_flash_duration: float = 0.08

signal shot_hit(body: Node)
signal player_fell
signal restart_requested(restart_current_room: bool)
signal room_requested(path: String)

var solver = Solver.new()
var player: Node2D
var actors: Array[Node2D] = []
var bullets: Array[Node2D] = []
var pickups: Array[Node2D] = []
var doors: Array[Node2D] = []
var signboards: Array[Node2D] = []
var active_signboard: Node2D
var _previous_signboards: Array[Node2D] = []
var transitioning := false
var frozen := false
var restarting := false
var show_contacts := false
var hits := 0
var serial := 0
var jump_buffer := 0.0
var coyote_time := 0.0
var demo_time := 0.0
var demo_direction := 0.0
var last_step_usec := 0
var setup_errors: Array[String] = []
var _contact_overlay: Node2D
var _time_speed_hud: CanvasLayer
var _time_speed_label: Label

func _ready() -> void:
	_contact_overlay = Node2D.new()
	_contact_overlay.name = "ContactOverlay"
	_contact_overlay.z_index = 100
	_contact_overlay.draw.connect(_draw_contacts.bind(_contact_overlay))
	add_child(_contact_overlay)
	_create_time_speed_hud()
	rebuild()
	if get_tree().current_scene == self and player != null and get_node("/root/GameState").has_extinguisher:
		player.pick_up_extinguisher()
	if player != null:
		player.extinguisher_changed.connect(_equipment_audio)

func _equipment_audio(equipped: bool) -> void:
	if equipped and not get_node("/root/GameState").has_extinguisher:
		_audio(&"pickup")

func _audio(cue: StringName, gain_db: float = 0.0) -> void:
	get_node("/root/AudioManager").play_sfx(cue, gain_db)

func _create_time_speed_hud() -> void:
	_time_speed_hud = CanvasLayer.new()
	_time_speed_hud.name = "TimeSpeedHUD"
	_time_speed_hud.layer = 10
	add_child(_time_speed_hud)
	_time_speed_label = Label.new()
	_time_speed_label.name = "TimeSpeed"
	_time_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	_time_speed_label.add_theme_font_override("font", font)
	_time_speed_label.add_theme_font_size_override("font_size", 10)
	_time_speed_label.add_theme_color_override("font_color", Color.BLACK)
	_time_speed_hud.add_child(_time_speed_label)
	_time_speed_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_time_speed_label.offset_left = 4.0
	_time_speed_label.offset_top = -22.0
	_time_speed_label.offset_right = 100.0
	_time_speed_label.offset_bottom = -3.0
	_time_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var run_state := get_node("/root/GameState")
	run_state.time_speed_changed.connect(_update_time_speed_label)
	_update_time_speed_label(run_state.get_time_speed())
	visibility_changed.connect(func(): _time_speed_hud.visible = is_visible_in_tree())
	_time_speed_hud.visible = is_visible_in_tree()

func _update_time_speed_label(speed: float) -> void:
	_time_speed_label.text = "x%s" % str(speed).trim_suffix(".0")

func rebuild() -> void:
	solver = Solver.new()
	actors.clear()
	pickups.clear()
	for signboard in signboards:
		if is_instance_valid(signboard):
			signboard.show_message(false)
	doors.clear()
	signboards.clear()
	_previous_signboards.clear()
	active_signboard = null
	player = null
	serial = 0
	setup_errors.clear()
	for bullet in bullets:
		bullet.queue_free()
	bullets.clear()
	_collect(self)
	if not setup_errors.is_empty():
		frozen = true
		for error in setup_errors:
			push_error("%s: %s" % [scene_file_path if not scene_file_path.is_empty() else str(name), error])
	solver.refresh_contacts()
	sync_visuals()
	# Registration/restarts teleport the visuals. Begin interpolation here.
	for body in actors:
		body.reset_physics_interpolation()

func _collect(parent: Node) -> void:
	for child in parent.get_children():
		if child is DoorScript:
			doors.append(child)
		elif child is SignboardScript:
			signboards.append(child)
		elif child is ExtinguisherPickup:
			if not child.is_queued_for_deletion():
				pickups.append(child)
		elif child is BlockGridScript:
			var seen: Dictionary = {}
			var grid_origin: Vector2 = to_local(child.global_position)
			for cell in child.cells:
				if seen.has(cell):
					continue
				seen[cell] = true
				var local: Vector2 = grid_origin + Vector2(cell * child.cell_size)
				_add_state(null, local.x, local.y, child.cell_size, child.cell_size, true, "block")
		elif child is RectBodyScript:
			# Body nodes use the world's local coordinate system; nested translated groups work too.
			var local: Vector2 = to_local(child.global_position)
			var state = _add_state(child, local.x, local.y, child.body_width, child.body_height, child.fixed, child.kind)
			child.state = state
			if state != null and not child.fixed:
				actors.append(child)
				if child.kind == "warma" and player == null:
					player = child
		else:
			_collect(child)

func _add_state(body: Node, px: float, py: float, width: float, height: float, is_fixed: bool, kind: String):
	var state = State.new()
	serial += 1
	state.id = serial
	state.x = px
	state.y = py
	state.w = width
	state.h = height
	state.fixed = is_fixed
	state.kind = kind
	state.node = body
	if solver.add_body(state):
		return state
	var source := str(get_path_to(body)) if body != null else kind
	var reason: String = solver.diagnostics.back()
	setup_errors.append("初始布局不合法：%s 位于 (%.2f, %.2f)。%s" % [source, px, py, reason])
	return null

func _physics_process(delta: float) -> void:
	if frozen or restarting or transitioning or not setup_errors.is_empty():
		return
	var was_grounded: bool = player != null and player.state != null and player.state.grounded
	var impact_speed: float = player.state.vy if player != null and player.state != null else 0.0
	var jumped := false
	jump_buffer = maxf(0.0, jump_buffer - delta)
	if Input.is_action_just_pressed("jump"):
		jump_buffer = 0.1
	if player != null and player.state != null:
		if player.state.grounded:
			coyote_time = 0.07
		else:
			coyote_time = maxf(0.0, coyote_time - delta)
	var before: Dictionary = {}
	for body in actors:
		var state = body.state
		before[state.id] = Vector2(state.x, state.y)
		state.vy = minf(state.vy + GRAVITY * delta, TERMINAL_SPEED)
		if body == player:
			var axis: float = Input.get_axis("move_left", "move_right")
			if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("shoot"):
				demo_time = 0.0
			if demo_time > 0.0:
				axis = demo_direction
			state.intent_x = axis * body.move_speed
			if axis != 0.0:
				body.direction = int(signf(axis))
			# Holding jump retries as soon as support grants another jump.
			if (Input.is_action_pressed("jump") or jump_buffer > 0.0) and coyote_time > 0.0:
				state.vy = -body.jump_speed
				jump_buffer = 0.0
				coyote_time = 0.0
				jumped = true
			if Input.is_action_just_released("jump") and state.vy < -68.0:
				state.vy = -68.0
		else:
			state.intent_x = body.step_movement(delta)
	demo_time = maxf(0.0, demo_time - delta)
	var start: int = Time.get_ticks_usec()
	solver.step(delta)
	last_step_usec = Time.get_ticks_usec() - start
	if player != null and player.state != null:
		if player.state.grounded and not was_grounded and not jumped and impact_speed > 40.0:
			_audio(&"land", -5.0)
	_step_bullets(delta, before)
	_step_pickups()
	_step_signboards()
	sync_visuals()
	for body in actors.duplicate():
		if body == player:
			if body.state.y + body.state.h >= fall_limit or absf(body.state.x) > horizontal_limit:
				request_restart(true)
				player_fell.emit()
				break
		elif body.state.y > fall_limit or absf(body.state.x) > horizontal_limit:
			solver.remove_body(body.state)
			actors.erase(body)
			body.queue_free()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_LEFT, KEY_RIGHT:
				get_node("/root/GameState").change_time_speed(-1 if event.physical_keycode == KEY_LEFT else 1)
				get_viewport().set_input_as_handled()
				return
		if frozen or restarting or transitioning:
			return
		# Handle each press immediately so fast taps between physics ticks are kept.
		# Keyboard echo is excluded above, so holding K never repeats a shot.
		if event.is_action_pressed("shoot"):
			demo_time = 0.0
			fire()
			get_viewport().set_input_as_handled()
			return
		match event.physical_keycode:
			KEY_N:
				grant_extinguisher()
				get_viewport().set_input_as_handled()
			KEY_M:
				enter_first_door()
				get_viewport().set_input_as_handled()
			KEY_W:
				enter_touching_door()
				get_viewport().set_input_as_handled()
	# Standalone F6 levels have no game entry point to handle their restart key.
	if get_tree().current_scene == self and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_viewport().set_input_as_handled()
		request_restart()

func grant_extinguisher() -> void:
	if not is_instance_valid(player):
		return
	player.pick_up_extinguisher()
	get_node("/root/GameState").has_extinguisher = true

func enter_first_door() -> void:
	for door in doors:
		if is_instance_valid(door) and not door.is_queued_for_deletion():
			request_room(door.target_room)
			return

func enter_touching_door() -> void:
	if player == null or player.state == null:
		return
	var state = player.state
	var rect := Rect2(state.x, state.y, state.w, state.h)
	for door in doors:
		if is_instance_valid(door) and not door.is_queued_for_deletion() and rect.intersects(door.get_world_rect(self)):
			request_room(door.target_room)
			return

func request_room(path: String) -> void:
	if frozen or restarting or transitioning or path.is_empty():
		return
	var scene = load(path) if ResourceLoader.exists(path) else null
	if not scene is PackedScene or not scene.can_instantiate():
		push_warning("门的目标房间不是有效场景：%s" % path)
		return
	var candidate = scene.instantiate()
	var valid_room: bool = candidate is RectWorld2D or candidate.get_script() == ScreenScript
	candidate.free()
	if not valid_room:
		push_warning("门的目标必须是矩形房间、开场或结束场景：%s" % path)
		return
	transitioning = true
	if player != null:
		get_node("/root/GameState").has_extinguisher = player.has_extinguisher
	if room_requested.has_connections():
		_audio(&"door", -2.0)
		room_requested.emit(path)
	elif get_tree().current_scene == self:
		_audio(&"door", -2.0)
		get_tree().change_scene_to_file.call_deferred(path)
	else:
		transitioning = false

func _step_signboards() -> void:
	var touching: Array[Node2D] = []
	if player != null and player.state != null:
		var state = player.state
		var rect := Rect2(state.x, state.y, state.w, state.h)
		for signboard in signboards:
			if is_instance_valid(signboard) and not signboard.is_queued_for_deletion() and rect.intersects(signboard.get_world_rect(self)):
				touching.append(signboard)
	var selected: Node2D = active_signboard if touching.has(active_signboard) else null
	# A newly entered sign replaces the old one, even when their ranges overlap.
	for signboard in touching:
		if not _previous_signboards.has(signboard):
			selected = signboard
			break
	if selected == null and not touching.is_empty():
		selected = touching[0]
	for signboard in signboards:
		if is_instance_valid(signboard):
			signboard.show_message(signboard == selected)
	active_signboard = selected
	_previous_signboards = touching

func request_restart(restart_current_room: bool = true) -> void:
	if restarting:
		return
	restarting = true
	frozen = true
	_audio(&"restart", -2.0)
	if is_instance_valid(player):
		# Keep acquired equipment across both hosted and standalone room reloads.
		var run_state := get_node("/root/GameState")
		run_state.has_extinguisher = run_state.has_extinguisher or player.has_extinguisher
		var was_visible: bool = player.visible
		for flash in range(2):
			player.visible = false
			await get_tree().create_timer(maxf(death_flash_duration, 0.01)).timeout
			if not is_instance_valid(player):
				break
			player.visible = was_visible
			await get_tree().create_timer(maxf(death_flash_duration, 0.01)).timeout
	# Hosts restore their own scene/layout; F6 levels can reload themselves.
	if restart_requested.has_connections():
		restart_requested.emit(restart_current_room)
	elif get_tree().current_scene == self:
		get_tree().reload_current_scene.call_deferred()

func fire() -> void:
	if frozen or restarting or transitioning or not setup_errors.is_empty() or player == null or player.state == null:
		return
	if not player.has_extinguisher:
		return
	var bullet = BulletScene.instantiate()
	bullet.direction = player.direction
	var state = player.state
	var nozzle: Vector2 = player.get_nozzle_position()
	bullet.position = Vector2(state.x, state.y) + nozzle
	if bullet.direction < 0:
		bullet.position.x -= bullet.SIZE.x
	add_child(bullet)
	bullet.reset_physics_interpolation()
	bullets.append(bullet)
	get_node("/root/AudioManager").play_shot()

func _step_pickups() -> void:
	if player == null or player.state == null:
		return
	var state = player.state
	var player_rect := Rect2(state.x, state.y, state.w, state.h)
	for pickup in pickups.duplicate():
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			pickups.erase(pickup)
		elif player_rect.intersects(pickup.get_world_rect(self)) and pickup.collect(player):
			pickups.erase(pickup)

func _step_bullets(delta: float, before: Dictionary) -> void:
	for bullet in bullets.duplicate():
		var start: Vector2 = bullet.position
		var motion := Vector2(bullet.direction * bullet.speed * delta, 0)
		var nearest := 2.0
		var target = null
		for state in solver.bodies:
			if state.kind == "warma":
				continue
			var old: Vector2 = before.get(state.id, Vector2(state.x, state.y))
			var body_motion := Vector2(state.x, state.y) - old
			var t: float = swept_fraction(start, motion - body_motion, old, Vector2(state.w, state.h))
			if t < nearest:
				nearest = t
				target = state
		if nearest <= 1.0:
			if target.kind == "giraffe" and is_instance_valid(target.node):
				target.node.hit_by_bullet(bullet.direction)
				_audio(&"giraffe_hit", -3.0)
				hits += 1
				shot_hit.emit(target.node)
			else:
				_audio(&"wall_hit", -8.0)
			bullets.erase(bullet)
			bullet.queue_free()
		else:
			bullet.position += motion
			bullet.lifetime -= delta
			if bullet.lifetime <= 0.0:
				bullets.erase(bullet)
				bullet.queue_free()

static func swept_fraction(origin: Vector2, motion: Vector2, target: Vector2, size: Vector2) -> float:
	# Minkowski expansion for a 3x2 bullet; relative swept test also covers falling giraffes.
	var low := target - Vector2(3, 2)
	var high := target + size
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		if absf(motion[axis]) < 0.00000001:
			if origin[axis] <= low[axis] or origin[axis] >= high[axis]:
				return 2.0
		else:
			var t1: float = (low[axis] - origin[axis]) / motion[axis]
			var t2: float = (high[axis] - origin[axis]) / motion[axis]
			enter = maxf(enter, minf(t1, t2))
			leave = minf(leave, maxf(t1, t2))
			if enter > leave:
				return 2.0
	return enter if leave >= 0.0 and enter <= 1.0 else 2.0

func sync_visuals() -> void:
	for body in actors:
		if is_instance_valid(body) and body.state != null:
			body.global_position = to_global(Vector2(body.state.x, body.state.y))
			body.queue_redraw()

func _draw() -> void:
	if is_instance_valid(_contact_overlay):
		_contact_overlay.queue_redraw()

func _draw_contacts(canvas: Node2D) -> void:
	if not show_contacts:
		return
	# Keep the outline one pixel wide when the world is scaled for display.
	var line_width := 1.0 / maxf(absf(global_scale.x), 0.001)
	for state in solver.bodies:
		if state.fixed:
			continue
		var rect := Rect2(state.x, state.y, state.w, state.h)
		canvas.draw_rect(rect, Color("e7fffc"), false, line_width)
		if state.grounded:
			canvas.draw_line(Vector2(state.x, state.y + state.h), Vector2(state.x + state.w, state.y + state.h), Color("9aff9c"), line_width)
		canvas.draw_line(rect.get_center(), rect.get_center() + Vector2(state.vx, state.vy) * 0.09, Color("ff86ad"), line_width)
