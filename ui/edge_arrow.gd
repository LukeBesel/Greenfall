class_name EdgeArrow
extends Control
## [onboard2] A small filled triangle on the screen edge pointing at an off-screen waypoint
## (story/waypoint.gd). No text: the owner wants clean views.

var color := Color(0.74, 0.48, 1.0)
const SIZE: float = 11.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2.ZERO


## Centre on the edge, angle in radians (0 = pointing right), alpha 0..1.
func place(at: Vector2, angle: float, alpha: float) -> void:
	position = at
	rotation = angle
	modulate.a = alpha
	queue_redraw()


func _draw() -> void:
	var tip := Vector2(SIZE, 0)
	var a := Vector2(-SIZE * 0.6, -SIZE * 0.75)
	var b := Vector2(-SIZE * 0.6, SIZE * 0.75)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(1.5, 0), a + Vector2(-1.5, -1.5), b + Vector2(-1.5, 1.5)]), Color(0, 0, 0, 0.45))
	draw_colored_polygon(PackedVector2Array([tip, a, b]), color)
