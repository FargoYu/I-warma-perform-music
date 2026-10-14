@tool
extends "res://addons/block_painter/block_painter.gd"
## The runner enables this subclass in an isolated, real Godot editor project.

const FIXTURE_PATH := "res://fixtures/level.tscn"
const GRID_PATH := NodePath("Display/Translated/Grid")
const EDITOR_TRANSFORM := Transform2D(Vector2(3.452, 0), Vector2(0, 3.452), Vector2(169, 279))

var checks: int = 0
var cases: int = 0
var failures: Array[String] = []
var current_case: String = ""
var grid_ref: BlockGrid2D
var editor_viewport: SubViewport
var history: UndoRedo


func _enter_tree() -> void:
	super._enter_tree()
	if not OS.get_cmdline_user_args().has("--block-painter-import"):
		_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	EditorInterface.open_scene_from_path(FIXTURE_PATH)
	for frame in range(3):
		await get_tree().process_frame
	grid_ref = EditorInterface.get_edited_scene_root().get_node(GRID_PATH) as BlockGrid2D
	editor_viewport = EditorInterface.get_editor_viewport_2d()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(grid_ref)
	EditorInterface.edit_node(grid_ref)
	_edit(grid_ref)
	_make_visible(true)
	_toggle.button_pressed = true
	history = get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(grid_ref))
	for test in [_test_editor_transform, _test_drag_and_selection, _test_erase_and_history,
		_test_noop_and_shortcuts, _test_pending_save, _test_instance_override]:
		current_case = str(test.get_method()).trim_prefix("_test_")
		var before: int = failures.size()
		await test.call()
		cases += 1
		print("%s %s" % ["PASS" if failures.size() == before else "FAIL", current_case])
	print("BLOCK_PAINTER: %d cases, %d checks, %d failures" % [cases, checks, failures.size()])
	for failure in failures:
		printerr(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(current_case + ": " + message)


func _screen(cell: Vector2i) -> Vector2:
	# Independent of the painter helper: display 4x, translated group, local grid.
	var logical := (Vector2(cell) + Vector2(0.5, 0.5)) * 16.0 + Vector2(5.75, -1.25)
	return EDITOR_TRANSFORM * (logical * 4.0)


func _set_editor_transform() -> void:
	editor_viewport.global_canvas_transform = EDITOR_TRANSFORM


func _button(index: int, pressed: bool, cell: Vector2i) -> bool:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = _screen(cell)
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	return _forward_canvas_gui_input(event)


func _motion(cell: Vector2i, mask: int) -> bool:
	var event := InputEventMouseMotion.new()
	event.position = _screen(cell)
	event.button_mask = mask
	return _forward_canvas_gui_input(event)


func _selected_grid() -> bool:
	var selected := EditorInterface.get_selection().get_selected_nodes()
	return selected.size() == 1 and selected[0] == grid_ref


func _history_shortcut(redo: bool) -> bool:
	# Go through the editor so its saved-state and redo bookkeeping are updated.
	var version: int = history.get_version()
	var focused := get_tree().root.gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	var event := InputEventKey.new()
	event.keycode = KEY_Z
	event.physical_keycode = KEY_Z
	event.ctrl_pressed = true
	event.shift_pressed = redo
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
	return history.get_version() != version


func _test_editor_transform() -> void:
	_check(Engine.is_editor_hint(), "the actual editor is running, not a gameplay SceneTree mock")
	_check(grid_ref.scene_file_path == "res://fixtures/grid_base.tscn", "grid is an instanced reusable scene")
	_check(grid_ref.global_transform.origin.is_equal_approx(Vector2(23, -5)), "4x display and nested group translation are active")
	_set_editor_transform()
	var projected: Vector2 = _grid_to_viewport_transform() * Vector2(88, 56)
	_check(projected.is_equal_approx(_screen(Vector2i(5, 3))), "preview uses the same editor zoom, pan and grid transform as the mouse")
	_check(not projected.is_equal_approx(grid_ref.get_global_transform_with_canvas() * Vector2(88, 56)), "fixture exercises the omitted editor-global transform")
	_motion(Vector2i(5, 3), 0)
	_check(_hover_cell == Vector2i(5, 3), "345.2% zoom and pan hit the intended grid cell")
	_motion(Vector2i(-2, -3), 0)
	_check(_hover_cell == Vector2i(-2, -3), "negative local coordinates use floor, including translated groups")
	_check(_selected_grid(), "hover keeps the grid selected")


func _test_drag_and_selection() -> void:
	_set_editor_transform()
	var before: Array[Vector2i] = grid_ref.cells.duplicate()
	var history_count: int = history.get_history_count()
	_check(_button(MOUSE_BUTTON_LEFT, true, Vector2i(2, 2)), "paint press is consumed")
	_check(_motion(Vector2i(7, 2), MOUSE_BUTTON_MASK_LEFT), "paint drag is consumed")
	_check(_button(MOUSE_BUTTON_LEFT, false, Vector2i(7, 2)), "paint release is consumed")
	for x in range(2, 8):
		_check(grid_ref.cells.has(Vector2i(x, 2)), "fast drag fills skipped cell (%d, 2)" % x)
	_check(grid_ref.cells.size() == before.size() + 6, "paint only modifies the six targeted cells")
	_check(history.get_history_count() == history_count + 1, "one completed stroke produces one undo action")
	_check(_selected_grid(), "consumed paint input does not change selection")
	_check(EditorInterface.get_unsaved_scenes().has(FIXTURE_PATH), "completed paint marks the fixture scene unsaved")
	_check(await _history_shortcut(false), "paint can be undone through the editor scene history")
	_check(grid_ref.cells == before, "undo restores the exact pre-stroke array")
	_check(not EditorInterface.get_unsaved_scenes().has(FIXTURE_PATH), "undo to the saved baseline clears unsaved state")
	_check(await _history_shortcut(true), "paint can be redone")
	_check(grid_ref.cells.size() == before.size() + 6, "redo restores the whole stroke")


func _test_erase_and_history() -> void:
	_set_editor_transform()
	var before: Array[Vector2i] = grid_ref.cells.duplicate()
	var history_count: int = history.get_history_count()
	_check(_button(MOUSE_BUTTON_RIGHT, true, Vector2i(3, 2)), "erase press is consumed")
	_check(_motion(Vector2i(6, 2), MOUSE_BUTTON_MASK_RIGHT), "erase drag is consumed")
	_check(_button(MOUSE_BUTTON_RIGHT, false, Vector2i(6, 2)), "erase release is consumed")
	for x in range(3, 7):
		_check(not grid_ref.cells.has(Vector2i(x, 2)), "fast erase removes skipped cell (%d, 2)" % x)
	_check(grid_ref.cells.has(Vector2i(2, 2)) and grid_ref.cells.has(Vector2i(7, 2)), "erase preserves adjacent cells")
	_check(history.get_history_count() == history_count + 1, "one erase stroke produces one undo action")
	_check(await _history_shortcut(false), "erase can be undone")
	_check(grid_ref.cells == before, "erase undo restores the exact array")
	_check(await _history_shortcut(true), "erase can be redone")
	_check(grid_ref.cells.size() == before.size() - 4, "erase redo restores the exact cell count")
	_check(_selected_grid(), "erase keeps the selected node")


func _test_noop_and_shortcuts() -> void:
	_set_editor_transform()
	var history_count: int = history.get_history_count()
	_button(MOUSE_BUTTON_LEFT, true, Vector2i(2, 2))
	_button(MOUSE_BUTTON_LEFT, false, Vector2i(2, 2))
	_check(history.get_history_count() == history_count, "painting an existing cell creates no history noise")
	_button(MOUSE_BUTTON_LEFT, true, Vector2i(9, 4))
	_motion(Vector2i(10, 4), 0)
	_check(_stroke_button == 0, "lost mouse-button mask finishes the pending stroke")
	_check(grid_ref.cells.has(Vector2i(9, 4)) and not grid_ref.cells.has(Vector2i(10, 4)), "lost mask cannot paint an unintended extra cell")
	var undo_key := InputEventKey.new()
	undo_key.pressed = true
	undo_key.keycode = KEY_Z
	undo_key.ctrl_pressed = true
	_check(not _forward_canvas_gui_input(undo_key), "Ctrl+Z is left to the editor shortcut handler")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	_check(_forward_canvas_gui_input(escape), "Escape exits paint mode")
	_check(not _painting, "Escape disables painting")
	_check(not _button(MOUSE_BUTTON_LEFT, true, Vector2i(12, 4)), "inactive paint mode does not consume canvas clicks")
	_toggle.button_pressed = true


func _test_pending_save() -> void:
	_set_editor_transform()
	var before: Array[Vector2i] = grid_ref.cells.duplicate()
	var history_count: int = history.get_history_count()
	_button(MOUSE_BUTTON_LEFT, true, Vector2i(11, 5))
	_check(_stroke_button == MOUSE_BUTTON_LEFT, "test saves while a mouse stroke is still pending")
	EditorInterface.save_scene_as(FIXTURE_PATH, false)
	_check(FileAccess.file_exists(FIXTURE_PATH), "the editor saves the real edited scene")
	_check(_stroke_button == 0, "editor save calls the registered plugin apply-changes hook")
	_check(history.get_history_count() == history_count + 1, "pending stroke becomes one undo action before saving")
	_check(not EditorInterface.get_unsaved_scenes().has(FIXTURE_PATH), "successfully saved scene is clean")
	_check(await _history_shortcut(false), "saved pending stroke still supports undo")
	_check(grid_ref.cells == before, "undo after save restores the pre-stroke data")
	_check(EditorInterface.get_unsaved_scenes().has(FIXTURE_PATH), "undo away from the saved state marks the scene unsaved")
	_check(await _history_shortcut(true), "saved pending stroke still supports redo")
	_check(not EditorInterface.get_unsaved_scenes().has(FIXTURE_PATH), "redo back to the saved state clears unsaved state")


func _test_instance_override() -> void:
	var saved: PackedScene = ResourceLoader.load(FIXTURE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	_check(saved != null, "saved fixture can be loaded independently of the editor resource cache")
	var reloaded := saved.instantiate()
	var reloaded_grid := reloaded.get_node(GRID_PATH) as BlockGrid2D
	_check(reloaded_grid.cells == grid_ref.cells, "instance cell override survives saving and reloading")
	_check(reloaded_grid.position == Vector2(2.5, 1.25), "painting preserves the local instance transform")
	var base: PackedScene = ResourceLoader.load("res://fixtures/grid_base.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var base_grid := base.instantiate() as BlockGrid2D
	_check(base_grid.cells == [Vector2i.ZERO], "painting does not modify the reusable grid scene")
	var state := saved.get_state()
	var has_override := false
	for node in range(state.get_node_count()):
		if str(state.get_node_path(node)).trim_prefix("./") != str(GRID_PATH):
			continue
		for property in range(state.get_node_property_count(node)):
			if state.get_node_property_name(node, property) == &"cells":
				has_override = state.get_node_property_value(node, property) == grid_ref.cells
	_check(has_override, "saved PackedScene records cells as a per-instance override")
	reloaded.free()
	base_grid.free()
