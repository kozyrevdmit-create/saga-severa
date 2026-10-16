## Chapter map: a vertical path of the chapter's stages from the bottom up.
## Won stages are marked and can be replayed, the next stage is highlighted, later ones are locked.
## The last stage shows the boss. Every stage shows its «Рекомендуемая сила». Placeholder shapes only.
extends Control

const BATTLE_SCENE := "res://scenes/battle.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

const NODE_SIZE := Vector2(320, 88)
const BOSS_NODE_SIZE := Vector2(360, 112)
const ZIGZAG := [0.3, 0.7]  ## node centre x as a share of the path width, alternating
const CLEARED_COLOR := Color("#2f7d4a")
const CURRENT_COLOR := Color("#c99a2e")
const LOCKED_COLOR := Color("#2a2f38")
const BOSS_COLOR := Color("#7a2a2a")
const PATH_DONE_COLOR := Color("#4fa36a")
const PATH_TODO_COLOR := Color(1, 1, 1, 0.15)


## Lines between the stage nodes, drawn under them.
class PathLines extends Control:
	var points: Array[Vector2] = []
	var done_segments := 0

	func _draw() -> void:
		for i in range(points.size() - 1):
			var color := PATH_DONE_COLOR if i < done_segments else PATH_TODO_COLOR
			draw_line(points[i], points[i + 1], color, 10.0, true)


## Placeholder boss icon: a crown.
class CrownIcon extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var crown := PackedVector2Array([
			Vector2(0, h), Vector2(0, h * 0.3), Vector2(w * 0.25, h * 0.6), Vector2(w * 0.5, 0),
			Vector2(w * 0.75, h * 0.6), Vector2(w, h * 0.3), Vector2(w, h)])
		draw_colored_polygon(crown, Color("#e8c547"))


var _nodes: Array[Button] = []
var _lines := PathLines.new()
var _crown := CrownIcon.new()


func _ready() -> void:
	var data = GameState.data
	var progress = GameState.progress
	var stage: Dictionary = data.get_stage(1)
	%Title.text = "Глава %d · %s" % [int(stage["chapter"]), data.get_chapter(int(stage["chapter"]))["name"]]
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Path.add_child(_lines)
	for stage_id in range(1, data.stage_count() + 1):
		var node := _make_node(stage_id, data, progress)
		%Path.add_child(node)
		_nodes.append(node)
	_crown.custom_minimum_size = Vector2(72, 56)
	_crown.size = _crown.custom_minimum_size
	_crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Path.add_child(_crown)
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%Path.resized.connect(_layout)
	_layout()


func _make_node(stage_id: int, data, progress) -> Button:
	var is_boss: bool = stage_id == data.stage_count()
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.size = BOSS_NODE_SIZE if is_boss else NODE_SIZE
	button.add_theme_font_size_override("font_size", 22)
	var color := LOCKED_COLOR
	var state := ""
	if progress.is_replay(stage_id):
		color = CLEARED_COLOR
		state = "пройден"
	elif progress.is_stage_open(data, stage_id):
		color = CURRENT_COLOR
		state = "в бой!"
	button.text = "Этап %d · %s" % [stage_id, state] if state != "" else "Этап %d" % stage_id
	if is_boss:
		button.text += "\n" + data.get_enemy(data.get_stage(stage_id)["waves"].back()[0])["name"]
		if not progress.is_replay(stage_id) and not progress.is_stage_open(data, stage_id):
			color = BOSS_COLOR.darkened(0.4)
	button.text += "\nРекомендуемая сила %d" % data.recommended_power(stage_id)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(48)
	if progress.is_stage_open(data, stage_id) and not progress.is_replay(stage_id):
		style.set_border_width_all(8)
		style.border_color = Color("#ffe27a")
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state_name, style)
	button.disabled = not progress.is_stage_open(data, stage_id)
	button.pressed.connect(_on_stage_pressed.bind(stage_id))
	return button


func _on_stage_pressed(stage_id: int) -> void:
	GameState.selected_stage = stage_id
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _layout() -> void:
	var area: Vector2 = %Path.size
	var step := area.y / _nodes.size()
	var centers: Array[Vector2] = []
	for i in _nodes.size():
		var node := _nodes[i]
		var center := Vector2(area.x * ZIGZAG[i % ZIGZAG.size()], area.y - (i + 0.5) * step)
		node.position = center - node.size / 2.0
		centers.append(center)
	var boss: Button = _nodes.back()
	_crown.position = Vector2(boss.position.x - _crown.size.x - 12, boss.position.y + (boss.size.y - _crown.size.y) / 2.0)
	_lines.size = area
	_lines.points = centers
	_lines.done_segments = GameState.progress.cleared_stage
	_lines.queue_redraw()
