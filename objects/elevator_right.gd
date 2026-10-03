extends "res://objects/elevator.gd"
## Rightward lift: anchored at its left edge, extends right.

func _axis() -> Vector2:
	return Vector2.RIGHT
