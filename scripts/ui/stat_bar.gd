## Thin horizontal bar (HP or energy): dark back, fill and a black edge (readable on the light battlefield paper).
extends Control

const OUTLINE_COLOR := Color("#1a1a1a")
const OUTLINE_WIDTH := 2.0

var fill_color := Color.WHITE
var back_color := Color(0.1, 0.1, 0.1, 0.7)
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
	draw_rect(Rect2(Vector2.ZERO, size).grow(OUTLINE_WIDTH / 2.0), OUTLINE_COLOR, false, OUTLINE_WIDTH)
