extends SceneTree
## Exercises the real renderer: headless tests cannot detect logical-pixel jumps.

const MainScene = preload("res://main.tscn")
const SCALE: int = 4
const COLOR_EPS: float = 0.01

var game
var checks: int = 0
var cases: int = 0
var failures: Array[String] = []
var current_case: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.get_node("GameState").reset_run()
	game = MainScene.instantiate()
	root.add_child(game)
	game.world.set_physics_process(false)
	game.world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	for test in [_test_window_render_size, _test_character_and_equipment_faces,
		_test_fractional_render_motion, _test_rebuild_teleport, _test_first_bullet_frame,
		_test_signboard_message, _test_time_speed_hud, _test_screens]:
		current_case = str(test.get_method()).trim_prefix("_test_")
		var before: int = failures.size()
		await test.call()
		cases += 1
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", current_case])
	game.queue_free()
	await process_frame
	print("DISPLAY: %d cases, %d checks, %d failures" % [cases, checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(current_case + ": " + message)

func _test_signboard_message() -> void:
	var signboard = game.world.get_node("Signboard")
	game.world.player.state.x = signboard.position.x
	game.world.player.state.y = signboard.position.y
	game.world.sync_visuals()
	game.world._step_signboards()
	await process_frame
	await process_frame
	var image := await _capture()
	image.save_png("res://artifacts/game_signboard.png")
	_check(signboard._panel.visible, "signboard message is visible")
	_check(signboard._panel.size.y < 80, "short message has no inflated layout height")
	var label_rect: Rect2 = signboard._label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, signboard._label.size)
	label_rect.position *= SCALE
	label_rect.size *= SCALE
	var black_pixels := 0
	for y in range(int(label_rect.position.y), int(label_rect.end.y)):
		for x in range(int(label_rect.position.x), int(label_rect.end.x)):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and image.get_pixel(x, y).get_luminance() < 0.05:
				black_pixels += 1
	_check(black_pixels > 100, "black glyph pixels render inside message")
	_check(black_pixels < label_rect.get_area() * 0.4, "message has no dark background filling its area")
	_check(game.world.doors[0].z_index > game.world.get_node("Background").z_index and game.world.doors[0].z_index < game.world.player.z_index, "door renders between background and Warma")
	_check(signboard._panel.position.y + signboard._panel.size.y < 0, "message is above board")
	_check(signboard._panel.get_global_transform_with_canvas().origin.x >= 0, "message near left screen edge stays readable")
	var original_position: Vector2 = signboard.position
	for board_position in [Vector2(120, 100), Vector2(0, 0), Vector2(240, 0), Vector2(240, 128)]:
		signboard.position = board_position
		await _capture()
		var message_rect: Rect2 = signboard._panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, signboard._panel.size)
		var viewport_rect: Rect2 = signboard.get_viewport_rect()
		_check(viewport_rect.grow(0.01).encloses(message_rect), "message stays inside viewport at " + str(board_position))
		if board_position == Vector2(120, 100):
			_check(absf(signboard._panel.position.x + signboard._panel.size.x * 0.5 - 8.0) < 0.01, "message is centered over the board")
			_check(absf(signboard._panel.position.y + signboard._panel.size.y + signboard.text_gap) < 0.01, "message preserves the configured gap above the board")
	root.size = Vector2i(800, 600)
	await _capture()
	var resized_rect: Rect2 = signboard._panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, signboard._panel.size)
	_check(signboard.get_viewport_rect().grow(0.01).encloses(resized_rect), "visible message stays on screen after resizing")
	root.size = Vector2i(1024, 576)
	signboard.position = original_position
	await _capture()

func _test_time_speed_hud() -> void:
	var run_state := root.get_node("GameState")
	var label: Label = game.world._time_speed_label
	var signboard = game.world.get_node("Signboard")
	_check(label.get_theme_color("font_color") == signboard._label.get_theme_color("font_color"), "speed label uses the same black text as signboards")
	_check(label.get_theme_font_size("font_size") == signboard.font_size, "speed label uses the default signboard font size")
	_check(label.get_theme_constant("outline_size") == 0, "speed label has no outline")
	for window_size in [Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(800, 600)]:
		root.size = window_size
		await process_frame
		await _capture()
		var rect := label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, label.size)
		var viewport_size: Vector2 = label.get_viewport_rect().size
		_check(rect.position.x == 4.0, "HUD stays at the left viewport edge after resizing")
		_check(absf(viewport_size.y - rect.end.y - 3.0) < 0.01, "HUD stays at the bottom viewport edge after resizing")
		_check(rect.position.y >= 0 and rect.end.x <= viewport_size.x, "HUD fits inside the resized viewport")
	root.size = Vector2i(1024, 576)
	await process_frame
	for speed in [0.5, 0.2, 0.1]:
		run_state.change_time_speed(-1)
		var image := await _capture()
		image.save_png("res://artifacts/game_time_speed_%s.png" % str(speed))
		_check(label.text == "x%s" % str(speed), "HUD renders the selected slow-motion speed")
		var glyph_rect: Rect2 = label.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, label.size)
		var black_pixels := 0
		for y in range(int(glyph_rect.position.y * SCALE), int(glyph_rect.end.y * SCALE)):
			for x in range(int(glyph_rect.position.x * SCALE), int(glyph_rect.end.x * SCALE)):
				if image.get_pixel(x, y).get_luminance() < 0.05:
					black_pixels += 1
		_check(black_pixels > 100, "black speed glyphs render at the lower left")
	for step in range(3):
		run_state.change_time_speed(1)
	game.hide()
	_check(not game.world._time_speed_hud.visible, "HUD follows the game visibility")
	game.show()


func _test_screens() -> void:
	game.hide()
	for path in ["res://start.tscn", "res://end.tscn"]:
		var screen = load(path).instantiate()
		root.add_child(screen)
		var image := await _capture()
		image.save_png("res://artifacts/" + path.get_file().get_basename() + ".png")
		_check(screen.get_node("Prompt").visible, "keyboard prompt is visible: " + path)
		screen.queue_free()
		await process_frame
	game.show()


func _same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= COLOR_EPS and absf(a.g - b.g) <= COLOR_EPS and absf(a.b - b.b) <= COLOR_EPS


func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _sample(image: Image, logical_position: Vector2) -> Color:
	return image.get_pixel(int(logical_position.x * SCALE), int(logical_position.y * SCALE))


func _check_sprite(image: Image, origin: Vector2, direction: int) -> void:
	var source: Image = game.world.player.WARMA_TEXTURE.get_image()
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var color: Color = source.get_pixel(x, y)
			if color.a < 1.0:
				continue
			var local := Vector2(x - 0.5, y - 0.5)
			if direction < 0:
				local.x = 5.0 - local.x
			_check(_same_color(_sample(image, origin + local), color), "rendered Warma source pixel (%d, %d) has the expected facing" % [x, y])


func _test_window_render_size() -> void:
	var image := await _capture()
	_check(root.size == Vector2i(1024, 576), "default physical window is 1024 by 576")
	_check(root.content_scale_size == Vector2i(256, 144), "logical playfield matches sixteen 16-pixel blocks")
	_check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "canvas draws directly at physical window resolution")
	_check(image.get_size() == Vector2i(1024, 576), "4x content exactly fills the default 1024 by 576 window")
	image.save_png("res://artifacts/game_display.png")


func _test_character_and_equipment_faces() -> void:
	var player = game.world.player
	player.state.x = 24.0
	player.state.y = 112.0
	game.world.sync_visuals()
	var equipment_source: Image = player.EXTINGUISHER_TEXTURE.get_image()
	for direction in [1, -1]:
		player.direction = direction
		player.has_extinguisher = false
		var bare := await _capture()
		_check_sprite(bare, Vector2(24, 112), direction)
		player.has_extinguisher = true
		var equipped := await _capture()
		var nozzle := Vector2(5.5 if direction > 0 else -0.5, 2.5)
		_check(_same_color(_sample(equipped, player.position + nozzle), equipment_source.get_pixel(1, 0)), "black nozzle points outward next to Warma's face")
		for y in range(1, 4):
			var tank_pixel := Vector2(4.5 if direction > 0 else 0.5, 2.5 + y)
			_check(_same_color(_sample(equipped, player.position + tank_pixel), equipment_source.get_pixel(0, y)), "tank pixel %d follows the reference hand alignment" % y)
		var label: String = "right" if direction > 0 else "left"
		equipped.get_region(Rect2i(64, 424, 80, 112)).save_png("res://artifacts/warma_%s.png" % label)
		equipped.save_png("res://artifacts/game_%s.png" % label)


func _test_fractional_render_motion() -> void:
	var player = game.world.player
	player.direction = 1
	player.state.x = 24.0
	game.world.sync_visuals()
	var before := await _capture()
	player.state.x += 0.25
	game.world.sync_visuals()
	var after := await _capture()
	var moved_pixels: int = 0
	var wrong_pixels: int = 0
	for y in range(440, 512):
		for x in range(84, 140):
			if not _same_color(before.get_pixel(x, y), after.get_pixel(x, y)):
				moved_pixels += 1
			if not _same_color(before.get_pixel(x, y), after.get_pixel(x + 1, y)):
				wrong_pixels += 1
	_check(moved_pixels > 0, "a quarter logical pixel produces visible movement")
	_check(wrong_pixels == 0, "a quarter logical pixel moves every drawn character pixel by exactly one screen pixel")
	after.get_region(Rect2i(64, 424, 80, 112)).save_png("res://artifacts/warma_subpixel.png")


func _test_rebuild_teleport() -> void:
	game.world.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	game.world.player.has_extinguisher = false
	await physics_frame
	await physics_frame
	await _capture()
	game.world.player.position = Vector2(80, 96)
	game.world.rebuild()
	var image := await _capture()
	_check_sprite(image, Vector2(80, 96), game.world.player.direction)
	_check(game.world.player.state.x == 80.0, "rebuild keeps the new position as physics authority")


func _test_first_bullet_frame() -> void:
	var player = game.world.player
	player.pick_up_extinguisher()
	player.direction = 1
	await physics_frame
	await physics_frame
	await _capture()
	game.world.fire()
	_check(game.world.bullets.size() == 1, "equipped player creates a rendered projectile")
	if game.world.bullets.is_empty():
		return
	var bullet = game.world.bullets[0]
	var image := await _capture()
	var source: Image = bullet.TEXTURE.get_image()
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var color: Color = source.get_pixel(x, y)
			if color.a < 1.0:
				continue
			var pixel: Vector2 = bullet.position + Vector2(x + 0.5, y - 0.5)
			_check(_same_color(_sample(image, pixel), color), "first rendered bullet frame starts at the nozzle, with no interpolation from the world origin")
