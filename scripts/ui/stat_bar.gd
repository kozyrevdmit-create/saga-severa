## Thin horizontal bar (HP or energy) drawn as two rectangles.
extends Control

var fill_color := Color.WHITE
var back_color := Color(0, 0, 0, 0.55)
var value := 1.0:  ## 0..1
	set(v):
		v = clampf(v, 0.0, 1.0)
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()


func _init(color: Color = Color.WHITE, height := 14.0) -> void:
	fill_color = color
	custom_minimum_size = Vector2(0, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), back_color)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), fill_color)
