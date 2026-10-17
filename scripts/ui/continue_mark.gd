## The «нажми, чтобы продолжить» mark of a saga scene (M10.1): a small triangle pointing down, drawn rather than taken
## from the font (the game's font has no arrows). It fills its own rect; StoryPlayer sets its colour and blinks it.
extends Control

@export var color := Color.BLACK:
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), Vector2(size.x / 2.0, size.y)]), color)
