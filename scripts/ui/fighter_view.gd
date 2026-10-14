## Placeholder fighter on the battlefield: HP/energy bars above a colored rectangle with the name.
extends VBoxContainer

const StatBar := preload("res://scripts/ui/stat_bar.gd")

const WIDTH := 170.0
const BODY_HEIGHT := 120.0
const HP_COLOR := Color("#e04848")
const ENERGY_COLOR := Color("#f2c230")

var _hp_bar: StatBar
var _energy_bar: StatBar
var _body: ColorRect


func _init(unit, show_energy: bool) -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hp_bar = StatBar.new(HP_COLOR, 16)
	add_child(_hp_bar)
	_energy_bar = StatBar.new(ENERGY_COLOR, 10)
	_energy_bar.visible = show_energy
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_body.add_child(label)


func refresh(unit, max_energy: int) -> void:
	_hp_bar.value = unit.hp_fraction()
	_energy_bar.value = float(unit.energy) / max_energy
	modulate.a = 1.0 if unit.is_alive() else 0.25


## Point above the body where floating numbers start (in parent coordinates).
func popup_origin() -> Vector2:
	return position + Vector2(WIDTH / 2.0, 30.0)
