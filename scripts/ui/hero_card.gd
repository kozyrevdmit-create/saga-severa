## Hero card at the bottom of the battle screen. Glows when the ultimate is ready; tap to use it.
extends Button

const StatBar := preload("res://scripts/ui/stat_bar.gd")

const READY_BORDER := Color("#ffd84a")

var unit_id: int
var _energy_bar: StatBar
var _style_idle := StyleBoxFlat.new()
var _style_ready := StyleBoxFlat.new()
var _ready_shown := false


func _init(unit) -> void:
	unit_id = unit.id
	custom_minimum_size = Vector2(0, 200)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_NONE

	_style_idle.bg_color = unit.color.darkened(0.55)
	_style_idle.set_corner_radius_all(12)
	_style_idle.set_border_width_all(4)
	_style_idle.border_color = unit.color.darkened(0.2)
	_style_ready.bg_color = unit.color.darkened(0.15)
	_style_ready.set_corner_radius_all(12)
	_style_ready.set_border_width_all(8)
	_style_ready.border_color = READY_BORDER
	_apply_style(_style_idle)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_top = 12
	box.offset_right = -8
	box.offset_bottom = -12
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var name_label := _make_label(unit.display_name, 21)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF  # five cards in a row: keep the name on one line
	box.add_child(name_label)
	box.add_child(_make_label(unit.ultimate["name"], 18))
	_energy_bar = StatBar.new(READY_BORDER, 18)
	box.add_child(_energy_bar)


func refresh(unit, can_use: bool) -> void:
	_energy_bar.value = float(unit.energy) / unit.ultimate_cost()
	disabled = not unit.is_alive()
	modulate.a = 1.0 if unit.is_alive() else 0.35
	if can_use != _ready_shown:
		_ready_shown = can_use
		_apply_style(_style_ready if can_use else _style_idle)


func _apply_style(style: StyleBoxFlat) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, style)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _make_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
