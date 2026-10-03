extends "res://objects/elevator.gd"
## Downward lift: anchored at its top edge, extends downward.

func _axis() -> Vector2:
	return Vector2.DOWN
