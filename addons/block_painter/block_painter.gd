@tool
extends EditorPlugin
## The paint tool handles input only for the selected BlockGrid2D while enabled.

var _grid: BlockGrid2D
var _toolbar: HBoxContainer
var _toggle: Button
var _hint: Label
var _painting: bool = false
var _stroke_button: int = 0
var _before: Array[Vector2i] = []
var _last_cell := Vector2i.ZERO
var _hover_cell := Vector2i.ZERO
var _has_hover: bool = false


func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	_toggle = Button.new()
	_toggle.text = "方块画笔"
	_toggle.toggle_mode = true
	_toggle.tooltip_text = "开启后左键拖动绘制，右键拖动擦除；Esc 退出画笔。"
	_toggle.toggled.connect(_on_toggled)
	_toolbar.add_child(_toggle)
	_hint = Label.new()
	_hint.text = "  左键绘制 · 右键擦除 · Ctrl+Z 撤销 · Esc 退出  "
	_toolbar.add_child(_hint)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	_toolbar.hide()


func _exit_tree() -> void:
	_finish_stroke()
	if is_instance_valid(_toolbar):
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()


func _handles(object: Object) -> bool:
	return object is BlockGrid2D


func _edit(object: Object) -> void:
	_finish_stroke()
	_grid = object as BlockGrid2D
	_has_hover = false
	update_overlays()


func _clear() -> void:
	_edit(null)
	_make_visible(false)


func _apply_changes() -> void:
	_finish_stroke()


func _make_visible(visible: bool) -> void:
	_toolbar.visible = visible
	if not visible:
		_finish_stroke()
		_painting = false
		_toggle.set_pressed_no_signal(false)
		_toggle.text = "方块画笔"
		_has_hover = false
	update_overlays()


func _on_toggled(enabled: bool) -> void:
	_finish_stroke()
	_painting = enabled
	_toggle.text = "画笔已开启" if enabled else "方块画笔"
	update_overlays()


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _painting or not is_instance_valid(_grid):
		return false
	if event is InputEventKey and event.pressed:
		_finish_stroke()
		if event.keycode == KEY_ESCAPE:
			_toggle.button_pressed = false
			return true
		return false
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
			return false
		_update_hover(event.position)
		if event.pressed:
			_finish_stroke()
			_before = _grid.cells.duplicate()
			_stroke_button = event.button_index
			_last_cell = _hover_cell
			_paint_line(_last_cell, _hover_cell)
		elif event.button_index == _stroke_button:
			_finish_stroke()
		return true
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		if _stroke_button != 0:
			var expected_mask: int = MOUSE_BUTTON_MASK_LEFT if _stroke_button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
			if (event.button_mask & expected_mask) == 0:
				_finish_stroke()
			else:
				_paint_line(_last_cell, _hover_cell)
				_last_cell = _hover_cell
				return true
	return false


func _update_hover(viewport_position: Vector2) -> void:
	var local_position: Vector2 = _grid_to_viewport_transform().affine_inverse() * viewport_position
	_hover_cell = Vector2i(floori(local_position.x / _grid.cell_size), floori(local_position.y / _grid.cell_size))
	_has_hover = true
	update_overlays()


func _grid_to_viewport_transform() -> Transform2D:
	# Editor pan/zoom live in the viewport's global canvas transform, not the node's canvas transform.
	var editor_viewport := EditorInterface.get_editor_viewport_2d()
	return editor_viewport.global_canvas_transform * _grid.get_global_transform_with_canvas()


func _paint_line(start: Vector2i, finish: Vector2i) -> void:
	# Bresenham fills skipped cells when a drag crosses multiple cells per event.
	var updated: Array[Vector2i] = _grid.cells.duplicate()
	var cursor: Vector2i = start
	var dx: int = absi(finish.x - start.x)
	var dy: int = -absi(finish.y - start.y)
	var step_x: int = 1 if start.x < finish.x else -1
	var step_y: int = 1 if start.y < finish.y else -1
	var error: int = dx + dy
	while true:
		if _stroke_button == MOUSE_BUTTON_LEFT:
			if not updated.has(cursor):
				updated.append(cursor)
		else:
			while updated.has(cursor):
				updated.erase(cursor)
		if cursor == finish:
			break
		var twice_error: int = 2 * error
		if twice_error >= dy:
			error += dy
			cursor.x += step_x
		if twice_error <= dx:
			error += dx
			cursor.y += step_y
	_grid.cells = updated
	update_overlays()


func _finish_stroke() -> void:
	if _stroke_button == 0:
		return
	var was_erasing: bool = _stroke_button == MOUSE_BUTTON_RIGHT
	_stroke_button = 0
	if not is_instance_valid(_grid) or _before == _grid.cells:
		return
	var undo := get_undo_redo()
	undo.create_action("擦除矩形方块" if was_erasing else "绘制矩形方块", UndoRedo.MERGE_DISABLE, _grid)
	undo.add_do_property(_grid, "cells", _grid.cells.duplicate())
	undo.add_undo_property(_grid, "cells", _before.duplicate())
	undo.commit_action(false)
	_grid.notify_property_list_changed()


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not _painting or not _has_hover or not is_instance_valid(_grid):
		return
	var transform: Transform2D = _grid_to_viewport_transform()
	var origin := Vector2(_hover_cell) * _grid.cell_size
	var size: float = _grid.cell_size
	var corners := PackedVector2Array([
		transform * origin,
		transform * (origin + Vector2(size, 0)),
		transform * (origin + Vector2(size, size)),
		transform * (origin + Vector2(0, size)),
		transform * origin
	])
	var preview_color := Color("f89880") if _stroke_button == MOUSE_BUTTON_RIGHT else Color("6bdfef")
	overlay.draw_polyline(corners, preview_color, 2.0)
