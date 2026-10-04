extends SceneTree
## Regenerates every room under rooms/showcase/ from tools/showcase_room_defs.gd.
##
## The definitions are the source of truth; this script only validates them and
## emits plain .tscn text built from reusable object scenes. Run after editing
## the definitions:
##
##   godot --headless --path . --script res://tools/generate_showcase_rooms.gd
##
## Generated rooms compose existing scenes only (block instances for terrain,
## object scenes for entities); the generator owns no gameplay logic.

const DEFS := preload("res://tools/showcase_room_defs.gd")
const OUT_DIR := "res://rooms/showcase"
const ROOM_SCRIPT := "res://rooms/room.gd"
const NAV_PLAYER_CELL := Vector2i(0, 7)

# ext_resource id per reusable scene, emitted only when a room actually uses it.
const SCENES := {
	"background": "res://objects/background.tscn",
	"hud": "res://objects/hud.tscn",
	"player": "res://objects/warma.tscn",
	"door": "res://objects/door.tscn",
	"block": "res://objects/block.tscn",
	"text": "res://objects/screen_text.tscn",
	"sign": "res://objects/signboard.tscn",
	"giraffe": "res://objects/giraffe.tscn",
	"elevator_up": "res://objects/elevator_up.tscn",
	"elevator_down": "res://objects/elevator_down.tscn",
	"elevator_left": "res://objects/elevator_left.tscn",
	"elevator_right": "res://objects/elevator_right.tscn",
	"button": "res://objects/button.tscn",
	"pickup": "res://objects/extinguisher_pickup.tscn",
}
const SCENE_IDS := {
	"background": "2_bg", "hud": "3_hud", "player": "4_player", "door": "5_door",
	"block": "6_block", "text": "7_text", "sign": "8_sign", "giraffe": "9_grf",
	"elevator_up": "10_elvu", "elevator_down": "11_elvd", "elevator_left": "12_elvl",
	"elevator_right": "13_elvr", "button": "14_btn", "pickup": "15_pck",
}

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rooms := DEFS.all_rooms()
	var by_name := {}
	for room in rooms:
		if by_name.has(room.name):
			_fail("Duplicate room name '%s'" % room.name)
		by_name[room.name] = room

	var written := 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for source in rooms:
		# Navigation rooms carry doors but no authored things; give them a spawn.
		var room: Dictionary = source.duplicate(true)
		if not room.has("things"):
			room["things"] = []
		var has_player := false
		for thing in room.things:
			if thing.type == "player":
				has_player = true
				break
		if not has_player:
			room.things.append({"type": "player", "cell": NAV_PLAYER_CELL})

		var errors := _validate(room, by_name)
		if not errors.is_empty():
			for error in errors:
				_fail("%s: %s" % [room.name, error])
			continue
		_write(room)
		written += 1

	if failures.is_empty():
		print("Generated %d showcase rooms in %s" % [written, OUT_DIR])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("Generation failed with %d error(s)" % failures.size())
		quit(1)

func _fail(message: String) -> void:
	failures.append(message)

func _validate(room: Dictionary, by_name: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var map: Array = room.map
	if map.size() != 9:
		errors.append("map must have 9 rows, got %d" % map.size())
		return errors
	var blocks := {}
	for y in map.size():
		var row: String = map[y]
		if row.length() != 16:
			errors.append("map row %d must be 16 chars, got %d" % [y, row.length()])
			continue
		for x in 16:
			if row[x] == "#":
				blocks[Vector2i(x, y)] = true
			elif row[x] != ".":
				errors.append("map row %d has unknown glyph '%s'" % [y, row[x]])

	var things: Array = room.get("things", [])
	var doors: Array = room.get("doors", [])
	var has_player := false
	var has_door := doors.size() > 0
	var used_cells := {}
	for thing in things:
		var type: String = thing.type
		var has_cell: bool = thing.has("cell")
		if has_cell:
			var cell: Vector2i = thing.cell
			if cell.x < 0 or cell.x > 15 or cell.y < 0 or cell.y > 8:
				errors.append("%s at %s is out of bounds" % [type, cell])
			if used_cells.has(cell):
				errors.append("%s at %s shares a cell with another thing" % [type, cell])
			used_cells[cell] = true
		elif type != "lift":
			errors.append("%s thing is missing cell" % type)
			continue
		var on_block: bool = has_cell and blocks.has(thing.cell)
		match type:
			"player":
				has_player = true
				if on_block:
					errors.append("player at %s overlaps a block" % thing.cell)
			"door":
				has_door = true
				if on_block:
					errors.append("door at %s overlaps a block" % thing.cell)
				errors.append_array(_validate_target(thing.target, by_name))
			"giraffe":
				if on_block:
					errors.append("giraffe '%s' at %s overlaps a block" % [thing.name, thing.cell])
				if not thing.has("name"):
					errors.append("giraffe at %s needs a name" % thing.cell)
			"button":
				if not on_block:
					errors.append("button '%s' at %s must be embedded in a '#' cell" % [thing.name, thing.cell])
				if not thing.has("name") or not thing.has("target"):
					errors.append("button at %s needs name and target" % thing.cell)
			"lift":
				if not thing.has("name"):
					errors.append("lift needs a name")
			"pickup", "sign":
				if on_block:
					errors.append("%s at %s overlaps a block" % [type, thing.cell])
	if not has_player:
		errors.append("room must define a player")
	if not has_door:
		errors.append("room must define at least one door")
	for door in doors:
		errors.append_array(_validate_target(door.target, by_name))
		if blocks.has(door.cell):
			errors.append("door at %s overlaps a block" % door.cell)
	return errors

func _validate_target(target: String, by_name: Dictionary) -> Array[String]:
	if target.begins_with("res://"):
		if not FileAccess.file_exists(target):
			return ["door target '%s' does not exist" % target]
		return []
	if not by_name.has(target):
		return ["door target '%s' is not a defined room" % target]
	return []

func _write(room: Dictionary) -> void:
	var path := "%s/%s.tscn" % [OUT_DIR, room.name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not open %s: %d" % [path, FileAccess.get_open_error()])
		return
	file.store_string(_emit(room))
	file.close()

func _pascal(room_name: String) -> String:
	var parts := room_name.split("_", false)
	for i in parts.size():
		parts[i] = parts[i].capitalize()
	return "".join(parts)

## Cell anchors: player/giraffe/door/sign stand in the cell (feet on its bottom
## edge); buttons embed in a block cell; pickups rest on the cell bottom;
## vertical lifts anchor on the cell edge facing their stretch direction.
func _thing_position(thing: Dictionary) -> Vector2:
	if not thing.has("cell"):
		return thing.pos
	var cell: Vector2i = thing.cell
	var center := Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)
	match String(thing.type):
		"pickup":
			return center + Vector2(0.0, 4.0)
		"lift":
			match String(thing.dir):
				"up":
					return Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0)
				"down":
					return Vector2(cell.x * 16.0 + 8.0, (cell.y + 1) * 16.0)
				"left":
					return Vector2(cell.x * 16.0, cell.y * 16.0 + 8.0)
				"right":
					return Vector2((cell.x + 1) * 16.0, cell.y * 16.0 + 8.0)
			return center
		_:
			return center

func _emit(room: Dictionary) -> String:
	var map: Array = room.map
	var blocks: Array[Vector2i] = []
	for y in map.size():
		var row: String = map[y]
		for x in 16:
			if row[x] == "#":
				blocks.append(Vector2i(x, y))

	var things: Array = room.get("things", []).duplicate()
	for door in room.get("doors", []):
		things.append({"type": "door", "cell": door.cell, "target": door.target})

	var used := {"background": true, "hud": true, "player": true}
	for thing in things:
		match String(thing.type):
			"door": used["door"] = true
			"giraffe": used["giraffe"] = true
			"button": used["button"] = true
			"pickup": used["pickup"] = true
			"lift": used["elevator_%s" % thing.dir] = true
	if not blocks.is_empty():
		used["block"] = true
	if String(room.entry) != "" or room.has("doors"):
		used["sign"] = true
	if String(room.entry) != "":
		used["text"] = true

	var lines: Array[String] = []
	lines.append("[gd_scene format=3]")
	lines.append("")
	lines.append("[ext_resource type=\"Script\" path=\"%s\" id=\"1_room\"]" % ROOM_SCRIPT)
	for scene_key in SCENES:
		if used.get(scene_key, false):
			lines.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]"
				% [SCENES[scene_key], SCENE_IDS[scene_key]])
	lines.append("")

	lines.append("[node name=\"%s\" type=\"Node2D\"]" % _pascal(room.name))
	lines.append("script = ExtResource(\"1_room\")")
	lines.append("")
	lines.append("[node name=\"Background\" parent=\".\" instance=ExtResource(\"2_bg\")]")
	lines.append("visible = false")
	lines.append("")
	lines.append("[node name=\"HUD\" parent=\".\" instance=ExtResource(\"3_hud\")]")
	lines.append("")

	if not blocks.is_empty():
		lines.append("[node name=\"Terrain\" parent=\".\" type=\"Node2D\"]")
		for i in blocks.size():
			var cell := blocks[i]
			lines.append("[node name=\"Block%d\" parent=\"Terrain\" instance=ExtResource(\"6_block\")]" % (i + 1))
			lines.append("position = Vector2(%d, %d)" % [cell.x * 16 + 8, cell.y * 16 + 8])
		lines.append("")

	var counters := {}
	for thing in things:
		var type := String(thing.type)
		var pos := _thing_position(thing)
		match type:
			"door":
				# Each door needs a unique node name: duplicate Area2D names in one
				# scene make Godot register only the last one, silencing the rest.
				counters["door"] = int(counters.get("door", 0)) + 1
				lines.append("[node name=\"Door%d\" parent=\".\" instance=ExtResource(\"5_door\")]" % counters["door"])
				lines.append("position = Vector2(%s, %s)" % [pos.x, pos.y])
				lines.append("next_room = \"%s\"" % _target_path(thing.target))
			"player":
				lines.append("[node name=\"Player\" parent=\".\" instance=ExtResource(\"4_player\")]")
				lines.append("position = Vector2(%s, %s)" % [pos.x, pos.y])
			"giraffe":
				lines.append("[node name=\"%s\" parent=\".\" instance=ExtResource(\"9_grf\")]" % thing.name)
				lines.append("position = Vector2(%s, %s)" % [pos.x, pos.y])
			"button":
				lines.append("[node name=\"%s\" parent=\".\" instance=ExtResource(\"14_btn\")]" % thing.name)
				lines.append("position = Vector2(%s, %s)" % [pos.x, pos.y])
				lines.append("target_elevator = NodePath(\"../%s\")" % thing.target)
			"lift":
				var scene_id: String = SCENE_IDS["elevator_%s" % thing.dir]
				lines.append("[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [thing.name, scene_id])
				lines.append("position = Vector2(%s, %s)" % [pos.x, pos.y])
				if thing.has("min"):
					lines.append("min_height = %s" % _float_text(thing.min))
				if thing.has("max"):
					lines.append("max_height = %s" % _float_text(thing.max))
				if thing.has("speed"):
					lines.append("height_speed = %s" % _float_text(thing.speed))
				if thing.get("starts_extended", false):
					lines.append("starts_extended = true")
				if thing.has("button"):
					lines.append("button_path = NodePath(\"../%s\")" % thing.button)
			"pickup":
				lines.append("[node name=\"ExtinguisherPickup\" parent=\".\" instance=ExtResource(\"15_pck\")]")
				lines.append("position = Vector2(%s, %s)" % [pos.x, pos.y])
			"sign":
				counters[type] = int(counters.get(type, 0)) + 1
				lines.append("[node name=\"Sign%d\" parent=\".\" instance=ExtResource(\"8_sign\")]" % counters[type])
				lines.append("position = Vector2(%s, %s)" % [pos.x, pos.y])
				lines.append("message = \"%s\"" % thing.text)

	if room.has("doors"):
		# Navigation rooms label each door with a signboard above it.
		for door in room.doors:
			if not door.has("label"):
				continue
			counters["sign"] = int(counters.get("sign", 0)) + 1
			var cell: Vector2i = door.cell
			lines.append("[node name=\"Sign%d\" parent=\".\" instance=ExtResource(\"8_sign\")]" % counters["sign"])
			lines.append("position = Vector2(%d, %d)" % [cell.x * 16 + 8, cell.y * 16 - 24])
			lines.append("message = \"%s\"" % door.label)

	if String(room.entry) != "":
		lines.append("")
		lines.append("[node name=\"EntryText\" parent=\".\" instance=ExtResource(\"7_text\")]")
		lines.append("message = \"%s\"" % room.entry)
		lines.append("display_duration = 2.5")
	return "\n".join(lines) + "\n"

func _target_path(target: String) -> String:
	return target if target.begins_with("res://") else "%s/%s.tscn" % [OUT_DIR, target]

func _float_text(value: float) -> String:
	return "%.1f" % value if is_equal_approx(value, roundf(value)) else "%s" % value
