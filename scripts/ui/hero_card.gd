## Hero card at the bottom of the battle screen. Glows when the ultimate is ready; tap to use it.
## Badges in the top right corner while an effect is on the hero: a web (a cave spider's «Паутина»), a drop of poison
## (Fafnir's breath), an anvil (Regin's «Закалка»); a card under «Закалка» also gets an orange frame.
extends Button

const StatBar := preload("res://scripts/ui/stat_bar.gd")

const READY_BORDER := Color("#ffd84a")
const TEMPER_BORDER := Color("#ff8a3c")
const BADGE_SIZE := 34.0
const BADGE_GAP := 4.0
const BADGE_INK := Color("#1a1a1a")
const WEB_COLOR := Color("#efe3c8")
const POISON_COLOR := Color("#8fd14f")
const TEMPER_COLOR := Color("#ff8a3c")


## Small drawn badges (the game's font has no such symbols): "web", "poison", "temper".
class Badges extends Control:
	var shown: Array[String] = []

	func _draw() -> void:
		var x := size.x
		for badge in shown:
			x -= BADGE_SIZE
			var rect := Rect2(x, 0, BADGE_SIZE, BADGE_SIZE)
			draw_circle(rect.get_center(), BADGE_SIZE / 2.0, BADGE_INK)
			match badge:
				"web":
					_draw_web(rect.get_center(), BADGE_SIZE * 0.4)
				"poison":
					_draw_drop(rect.get_center(), BADGE_SIZE * 0.36)
				"temper":
					_draw_anvil(rect.get_center(), BADGE_SIZE * 0.4)
			x -= BADGE_GAP

	func _draw_web(c: Vector2, r: float) -> void:
		for i in 6:
			draw_line(c, c + Vector2.from_angle(TAU * i / 6.0) * r, WEB_COLOR, 2.0, true)
		for ring in [0.45, 0.9]:
			var points := PackedVector2Array()
			for i in 7:
				points.append(c + Vector2.from_angle(TAU * i / 6.0) * r * ring)
			draw_polyline(points, WEB_COLOR, 2.0, true)

	func _draw_drop(c: Vector2, r: float) -> void:
		draw_circle(c + Vector2(0, r * 0.35), r * 0.62, POISON_COLOR)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(-r * 0.55, r * 0.2),
				c + Vector2(r * 0.55, r * 0.2)]), POISON_COLOR)

	func _draw_anvil(c: Vector2, r: float) -> void:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r, -r * 0.45), c + Vector2(r, -r * 0.45),
				c + Vector2(r * 0.55, 0), c + Vector2(r * 0.3, 0), c + Vector2(r * 0.3, r * 0.4), c + Vector2(r * 0.6, r * 0.75),
				c + Vector2(-r * 0.6, r * 0.75), c + Vector2(-r * 0.3, r * 0.4), c + Vector2(-r * 0.3, 0),
				c + Vector2(-r * 0.8, 0)]), TEMPER_COLOR)

var unit_id: int
var _energy_bar: StatBar
var _style_idle := StyleBoxFlat.new()
var _style_ready := StyleBoxFlat.new()
var _style_temper := StyleBoxFlat.new()
var _style_shown: StyleBoxFlat
var _badges := Badges.new()


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
	_style_temper.bg_color = _style_idle.bg_color
	_style_temper.set_corner_radius_all(12)
	_style_temper.set_border_width_all(8)
	_style_temper.border_color = TEMPER_BORDER
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

	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_badges.offset_top = 4
	_badges.offset_right = -6
	_badges.custom_minimum_size.y = BADGE_SIZE
	add_child(_badges)


## The ready glow wins over the «Закалка» frame (the player needs to see the ultimate is ready).
func refresh(unit, can_use: bool) -> void:
	_energy_bar.value = float(unit.energy) / unit.ultimate_cost()
	disabled = not unit.is_alive()
	modulate.a = 1.0 if unit.is_alive() else 0.35
	var shown := badges_of(unit)
	if shown != _badges.shown:
		_badges.shown = shown
		_badges.queue_redraw()
	var style := _style_ready if can_use else (_style_temper if "temper" in shown else _style_idle)
	if style != _style_shown:
		_apply_style(style)


## The badges a hero has now, in a fixed order; none on a fallen hero.
static func badges_of(unit) -> Array[String]:
	var shown: Array[String] = []
	if not unit.is_alive():
		return shown
	if unit.is_webbed():
		shown.append("web")
	if unit.is_poisoned():
		shown.append("poison")
	if unit.has_badge("temper"):
		shown.append("temper")
	return shown


func badges_shown() -> Array[String]:
	return _badges.shown


func _apply_style(style: StyleBoxFlat) -> void:
	_style_shown = style
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
