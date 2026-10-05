extends RefCounted
## Scalar logical geometry. Vector2/Rect2 are query/render conversions only.
## A shared Y anchor plus dimension offsets preserves exact chain spacing.

var x: float
var y_anchor: float
var y_offset: float = 0.0
var width: float
var height: float

func _init(left: float, top: float, w: float, h: float) -> void:
	x = left
	y_anchor = top
	width = w
	height = h

func valid() -> bool:
	return is_finite(x) and is_finite(y_anchor) and is_finite(y_offset) and is_finite(width) and is_finite(height) and is_finite(right()) and is_finite(top()) and is_finite(bottom()) and width > 0.0 and height > 0.0

func left() -> float:
	return x

func right() -> float:
	return x + width

func top() -> float:
	return y_anchor + y_offset

func bottom() -> float:
	return y_anchor + (y_offset + height)

func copy():
	var result = get_script().new(x, y_anchor, width, height)
	result.y_offset = y_offset
	return result

func query_rect() -> Rect2:
	return Rect2(Vector2(left(), top()), Vector2(width, height))

func coordinates() -> Array:
	return [left(), top(), right(), bottom()]

static func overlaps(a, b) -> bool:
	return a.left() < b.right() and b.left() < a.right() and a.top() < b.bottom() and b.top() < a.bottom()

static func cross_overlap(a, b, axis: int) -> bool:
	if axis == 0:
		return minf(a.bottom(), b.bottom()) > maxf(a.top(), b.top())
	return minf(a.right(), b.right()) > maxf(a.left(), b.left())

static func touches_envelope(a, edges: Array) -> bool:
	return a.right() >= edges[0] and a.left() <= edges[2] and a.bottom() >= edges[1] and a.top() <= edges[3]
