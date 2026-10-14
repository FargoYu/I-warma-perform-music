class_name RectState
extends RefCounted
## Scalar doubles are authoritative. Node2D.position is only a rendering output.

var id: int = 0
var x: float = 0.0
var y: float = 0.0
var w: float = 16.0
var h: float = 16.0
var vx: float = 0.0
var vy: float = 0.0
var intent_x: float = 0.0
var fixed: bool = false
var grounded: bool = false
var kind: String = "dynamic"
var node: Node = null


func _init(px: float = 0.0, py: float = 0.0, width: float = 16.0,
		height: float = 16.0, is_fixed: bool = false) -> void:
	x = px
	y = py
	w = width
	h = height
	fixed = is_fixed


func right() -> float:
	return x + w


func bottom() -> float:
	return y + h
