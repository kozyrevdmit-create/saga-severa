## Placeholder fighter on the battlefield: HP/energy bars above a colored rectangle with the name.
extends VBoxContainer

const StatBar := preload("res://scripts/ui/stat_bar.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")

const WIDTH := 180.0
const BODY_HEIGHT := 120.0
const NAME_FONT_SIZE := 24
const NAME_MIN_FONT_SIZE := 14
const NAME_PADDING := 16.0
const HP_COLOR := Color("#e04848")
const ENERGY_COLOR := Color("#f2c230")
const MARK_COLOR := Color("#ffe27a")
const MARK_BORDER := 6

signal tapped

var _hp_bar: StatBar
var _energy_bar: StatBar
var _body: ColorRect
var _mark: Panel  ## frame and «цель» on the enemy the player marked


func _init(unit) -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hp_bar = StatBar.new(HP_COLOR, 16)
	add_child(_hp_bar)
	_energy_bar = StatBar.new(ENERGY_COLOR, 10)
	_energy_bar.visible = unit.has_ultimate()
	add_child(_energy_bar)

	_body = ColorRect.new()
	_body.color = unit.color
	_body.custom_minimum_size = Vector2(WIDTH, BODY_HEIGHT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	var label := Label.new()
	label.text = unit.display_name
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# One line, shrunk to fit: the web build does not wrap at hyphens and would split a word.
	label.add_theme_font_size_override("font_size", _fitting_font_size(label, unit.display_name))
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_body.add_child(label)

	_mark = Panel.new()
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(MARK_BORDER)
	frame.border_color = MARK_COLOR
	_mark.add_theme_stylebox_override("panel", frame)
	_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	var mark_label := Label.new()
	mark_label.text = "ЦЕЛЬ"
	mark_label.position = Vector2(MARK_BORDER + 4, MARK_BORDER)
	mark_label.add_theme_font_size_override("font_size", 22)
	mark_label.add_theme_color_override("font_color", MARK_COLOR)
	mark_label.add_theme_constant_override("outline_size", 6)
	mark_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_mark.add_child(mark_label)
	_body.add_child(_mark)

	# Enemies can be tapped to mark them as the squad's target.
	if unit.team == BattleUnit.Team.ENEMIES:
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(_on_gui_input)


func refresh(unit, marked := false) -> void:
	_mark.visible = marked and unit.is_alive()
	_hp_bar.value = unit.hp_fraction()
	if unit.has_ultimate():
		_energy_bar.value = float(unit.energy) / unit.ultimate_cost()
	modulate.a = 1.0 if unit.is_alive() else 0.25


## Touches arrive as mouse events too (touch-to-mouse emulation is on by default).
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tapped.emit()
		accept_event()


## Point above the body where floating numbers start (in parent coordinates).
func popup_origin() -> Vector2:
	return position + Vector2(WIDTH / 2.0, 30.0)


func _fitting_font_size(label: Label, text_value: String) -> int:
	var font := label.get_theme_font("font")
	var font_size := NAME_FONT_SIZE
	while font_size > NAME_MIN_FONT_SIZE and font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > WIDTH - NAME_PADDING:
		font_size -= 1
	return font_size
