extends "res://objects/elevator.gd"
## Leftward lift: anchored at its right edge, extends left.

func _axis() -> Vector2:
	return Vector2.LEFT
