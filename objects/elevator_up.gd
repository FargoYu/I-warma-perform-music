extends "res://objects/elevator.gd"
## Upward lift: anchored at its bottom edge, extends upward.

func _axis() -> Vector2:
	return Vector2.UP
