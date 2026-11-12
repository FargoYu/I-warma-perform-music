extends CanvasLayer
## Shared keyboard/touch actions, with a control deck outside the 256x144 level.
## Use -- --touch-controls to preview the mobile layout on a desktop.

signal touch_mode_changed(enabled: bool)

const GAME_SIZE := Vector2(256, 144)
const DECK_HEIGHT := 64.0
const FONT = preload("res://Assets/Fonts/NotoSansSC.ttf")
const MOVE_ACTIONS := [&"move_left", &"move_right"]
const BACK_DEBOUNCE_MS := 250

var _touch_mode := false
var _game: Node2D
var _surface: Control
var _pause_label: Label
var _time_label: Label
var _buttons: Array[Dictionary] = []
var _pointers: Dictionary = {}
var _slide_pointers: Dictionary = {}
var _last_paused := false
var _last_back_msec := -BACK_DEBOUNCE_MS

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_touch_mode = OS.has_feature("android") or DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch-controls")
	if OS.has_feature("android"):
		get_tree().quit_on_go_back = false
	_surface = Control.new()
	_surface.name = "PlatformOverlay"
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(_draw_overlay)
	add_child(_surface)
	_pause_label = _make_label("", 12)
	_time_label = _make_label("", 8)
	get_viewport().size_changed.connect(_layout)
	get_node("/root/GameState").time_speed_changed.connect(_update_speed)
	_update_speed(get_node("/root/GameState").get_time_speed())
	_layout()

func is_touch_mode() -> bool:
	return _touch_mode

func bind_game(game: Node2D) -> void:
	release_all()
	_game = game
	_apply_viewport()
	_layout()

func unbind_game(game: Node2D) -> void:
	if _game != game:
		return
	release_all()
	_game = null
	_apply_viewport()
	_layout()

func _apply_viewport() -> void:
	var window := get_window()
	var use_deck := _touch_mode and is_instance_valid(_game)
	window.content_scale_size = Vector2i(256, 208) if use_deck else Vector2i(256, 144)
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if use_deck else Window.CONTENT_SCALE_ASPECT_KEEP

func _enable_touch() -> void:
	if _touch_mode:
		return
	_touch_mode = true
	_apply_viewport()
	_layout()
	touch_mode_changed.emit(true)

func _make_label(caption: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f2f6fa"))
	_surface.add_child(label)
	return label

func _add_button(action: StringName, caption: String, rect: Rect2) -> void:
	var label := _make_label(caption, 9)
	label.position = rect.position
	label.size = rect.size
	_buttons.append({"action": action, "rect": rect, "label": label})

func _layout() -> void:
	if not is_instance_valid(_surface):
		return
	# Resizing/orientation changes must never leave a virtual key held down.
	release_all()
	for button in _buttons:
		button.label.queue_free()
	_buttons.clear()
	var viewport_size := get_viewport().get_visible_rect().size
	_surface.size = viewport_size
	var in_game := is_instance_valid(_game)
	var show_deck := _touch_mode and in_game
	_time_label.visible = show_deck
	_pause_label.visible = in_game and _game.is_paused()
	if in_game:
		_game.position = Vector2((viewport_size.x - GAME_SIZE.x) * 0.5, maxf(0.0, (viewport_size.y - GAME_SIZE.y - (DECK_HEIGHT if show_deck else 0.0)) * 0.5))
		_pause_label.position = _game.position + Vector2(0, 48)
		_pause_label.size = Vector2(256, 48)
		_pause_label.text = "已暂停\n点“继续”或按 P" if show_deck else "已暂停\n按 P / Esc 继续"
	if show_deck:
		var base := viewport_size.y - DECK_HEIGHT
		_add_button(&"time_slower", "减速", Rect2(6, base + 4, 32, 22))
		_add_button(&"time_faster", "加速", Rect2(42, base + 4, 32, 22))
		_time_label.position = Vector2(78, base + 4)
		_time_label.size = Vector2(viewport_size.x - 192, 22)
		_add_button(&"restart", "重来", Rect2(viewport_size.x - 110, base + 4, 50, 22))
		_add_button(&"pause", "继续" if _game.is_paused() else "暂停", Rect2(viewport_size.x - 56, base + 4, 50, 22))
		_add_button(&"move_left", "左", Rect2(6, base + 30, 36, 30))
		_add_button(&"move_right", "右", Rect2(46, base + 30, 36, 30))
		_add_button(&"interact", "进门", Rect2((viewport_size.x - 40) * 0.5, base + 30, 40, 30))
		_add_button(&"shoot", "演奏", Rect2(viewport_size.x - 94, base + 30, 42, 30))
		_add_button(&"jump", "跳跃", Rect2(viewport_size.x - 48, base + 30, 42, 30))
	_surface.queue_redraw()

func _update_speed(speed: float) -> void:
	if is_instance_valid(_time_label):
		_time_label.text = "×%s" % str(speed).trim_suffix(".0")

func _process(_delta: float) -> void:
	var paused: bool = is_instance_valid(_game) and _game.is_paused()
	if paused == _last_paused:
		return
	_last_paused = paused
	_pause_label.visible = paused
	for button in _buttons:
		if button.action == &"pause":
			button.label.text = "继续" if paused else "暂停"
	_surface.queue_redraw()

func _draw_overlay() -> void:
	if not is_instance_valid(_game):
		return
	if _game.is_paused():
		_surface.draw_rect(Rect2(_game.position, GAME_SIZE), Color(0.03, 0.07, 0.12, 0.68))
	if not _touch_mode:
		return
	_surface.draw_rect(Rect2(0, _surface.size.y - DECK_HEIGHT, _surface.size.x, DECK_HEIGHT), Color("132331"))
	for button in _buttons:
		var pressed := _pointers.values().has(button.action)
		var color := Color("397f92") if pressed else Color("2a4254")
		_surface.draw_style_box(_button_style(color), button.rect)

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style

func _action_at(point: Vector2) -> StringName:
	for button in _buttons:
		if button.rect.has_point(point):
			return button.action
	return &""

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_enable_touch()
		if not is_instance_valid(_game):
			return
		if event.pressed and not event.canceled:
			var action := _action_at(event.position)
			if action != &"":
				_slide_pointers[event.index] = action in MOVE_ACTIONS
				get_viewport().set_input_as_handled()
				_set_pointer(event.index, action)
		elif _pointers.has(event.index):
			get_viewport().set_input_as_handled()
			_set_pointer(event.index, &"")
			_pointers.erase(event.index)
			_slide_pointers.erase(event.index)
	elif event is InputEventScreenDrag and _pointers.has(event.index):
		_drag_pointer(event.index, event.position)
		get_viewport().set_input_as_handled()
	elif _touch_mode and is_instance_valid(_game) and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		if event.pressed:
			var action := _action_at(event.position)
			if action != &"":
				_slide_pointers[-1] = action in MOVE_ACTIONS
				get_viewport().set_input_as_handled()
				_set_pointer(-1, action)
		elif _pointers.has(-1):
			get_viewport().set_input_as_handled()
			_set_pointer(-1, &"")
			_pointers.erase(-1)
			_slide_pointers.erase(-1)
	elif event is InputEventMouseMotion and _pointers.has(-1):
		_drag_pointer(-1, event.position)
		get_viewport().set_input_as_handled()

func _drag_pointer(index: int, point: Vector2) -> void:
	var next_action := _action_at(point)
	if _slide_pointers.get(index, false):
		_set_pointer(index, next_action if next_action in MOVE_ACTIONS else &"")
	elif next_action != _pointers[index]:
		_set_pointer(index, &"")

func _set_pointer(index: int, action: StringName) -> void:
	var previous: StringName = _pointers.get(index, &"")
	if previous == action:
		return
	var was_pressed := _pointers.values().has(action)
	_pointers[index] = action
	if previous != &"" and not _pointers.values().has(previous):
		_emit_action(previous, false)
	if action != &"" and not was_pressed:
		_emit_action(action, true)
	_surface.queue_redraw()

func _emit_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)

func release_all() -> void:
	var actions: Array = _pointers.values()
	_pointers.clear()
	_slide_pointers.clear()
	for action in actions:
		if action != &"":
			_emit_action(action, false)
	if is_instance_valid(_surface):
		_surface.queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		release_all()
		if is_instance_valid(_game):
			_game.set_paused(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and is_instance_valid(_game):
		# Godot 4.7 / Android API 36 can deliver one Back press twice through
		# the key and navigation callbacks (godotengine/godot#123454).
		# Use wall-clock time so slow-motion gameplay does not affect the guard.
		var now := Time.get_ticks_msec()
		if now - _last_back_msec < BACK_DEBOUNCE_MS:
			return
		_last_back_msec = now
		_game.set_paused(not _game.is_paused())

