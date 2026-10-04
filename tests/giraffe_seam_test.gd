extends SceneTree
## Regression check: a music-run giraffe must cross a side-by-side seam.
##
## Layout: two giraffes stand touching on the same floor; a third sits exactly
## aligned on the left one. To the eye the rider's feet are flush with the
## right giraffe's head, but editor placement is grid-free: the neighbour can
## sit a fraction of a pixel tall, leaving a real sub-pixel overlap at the
## seam. Shot right, the rider must still run — the neighbour's head is a
## platform to continue onto, not a wall; the physics resolve carries the
## rider up onto it. Shot left it must run freely over open floor.
## Run: godot --headless --path . --script res://tests/giraffe_seam_test.gd

const GIRAFFE_SCENE := "res://objects/giraffe.tscn"
const BLOCK_SCENE := "res://objects/block.tscn"
const FLOOR_Y := 140.0

var failures: Array[String] = []
var level: Node2D

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _tick(count: int = 1) -> void:
	for _i in range(count):
		await physics_frame
		await process_frame

func _block(at: Vector2) -> StaticBody2D:
	var block := load(BLOCK_SCENE).instantiate() as StaticBody2D
	block.position = at
	level.add_child(block)
	return block

func _giraffe(at: Vector2) -> CharacterBody2D:
	var giraffe := load(GIRAFFE_SCENE).instantiate() as CharacterBody2D
	giraffe.position = at
	giraffe.set("gravity", 300.0)
	level.add_child(giraffe)
	return giraffe

func _seam_run(direction: int, raise: float) -> void:
	level = Node2D.new()
	root.add_child(level)
	for x in [72, 88, 96, 112, 120, 136, 152, 168, 184, 200, 216, 232, 248]:
		_block(Vector2(x, FLOOR_Y))
	var left := _giraffe(Vector2(96, FLOOR_Y - 16.0))
	var right := _giraffe(Vector2(104, FLOOR_Y - 16.0 - raise))
	var top := _giraffe(Vector2(96, FLOOR_Y - 32.0))
	if raise > 0.0:
		# A raised neighbour is still settling toward the floor while the run
		# starts, so the overlap it presents at the seam is the spawned one.
		# Two ticks of free fall shave a few hundredths off the spawn raise.
		await _tick(2)
		_check(right.position.y <= left.position.y - 0.15,
			"raised neighbour must still present its overlap (dy=%.3f)" % (left.position.y - right.position.y))
	else:
		await _tick(20)
		_check(absf(right.position.y - left.position.y) <= 0.05,
			"supports must settle level (dy=%.3f)" % absf(right.position.y - left.position.y))
	_check(absf((top.position.y + 8.0) - (left.position.y - 8.0)) <= 0.05,
		"rider must rest flush on its support (gap=%.3f)" % ((top.position.y + 8.0) - (left.position.y - 8.0)))
	_check(absf((right.position.x - left.position.x) - 8.0) <= 0.05,
		"supports must stay touching (dx=%.3f)" % (right.position.x - left.position.x))
	var start_x := top.position.x
	top.call("run_in_direction", direction)
	for i in range(150):
		await _tick()
		if raise > 0.0 and i % 15 == 14:
			print("tick %d top=(%.3f,%.3f) right=(%.3f,%.3f) left=(%.3f,%.3f)" % [
				i + 1, top.position.x, top.position.y, right.position.x, right.position.y, left.position.x, left.position.y])
	var travelled := (top.position.x - start_x) * float(direction)
	_check(travelled > 8.0,
		"rider must run %s across the touching platform seam, raise=%.2f (travelled %.2fpx)" % [
			"right" if direction > 0 else "left", raise, travelled])
	level.queue_free()
	await _tick(2)

func _run() -> void:
	# The reported case: the touching neighbour's head sits a hair above the
	# rider's feet, so the seam reads back as a side wall with a real overlap.
	await _seam_run(1, 0.5)
	await _seam_run(-1, 0.5)
	# Perfectly level geometry already slides; keep it as a guard.
	await _seam_run(1, 0.0)
	await _seam_run(-1, 0.0)
	print("Giraffe seam checks: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
