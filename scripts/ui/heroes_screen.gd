## Heroes screen: every unlocked hero's portrait, role, level, stats, «Сила», ultimate and passive; level-up for silver
## (the button shows the power the level adds). Saves after every level-up.
extends Control

const Art := preload("res://scripts/ui/art.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const PORTRAIT_SIZE := 128.0
const PORTRAIT_PAPER := Color("#efe3c8")

const DESCRIPTION_COLOR := Color(1, 1, 1, 0.75)

var _rows := {}  ## hero id -> {level, stats, button}


func _ready() -> void:
	for hero_id in GameState.progress.hero_levels:
		_add_row(hero_id)
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	_refresh()


func _on_level_up_pressed(hero_id: String) -> void:
	if GameState.progress.level_up(GameState.data, hero_id):
		GameState.save()
	_refresh()


func _refresh() -> void:
	var data = GameState.data
	var progress = GameState.progress
	%SilverLabel.text = "Серебро: %d" % progress.silver
	for hero_id in _rows:
		var row: Dictionary = _rows[hero_id]
		var hero: Dictionary = data.get_hero(hero_id)
		var level: int = progress.level_of(hero_id)
		var multiplier: float = data.hero_stat_multiplier(level)
		var hero_class: Dictionary = data.get_hero_class(hero)
		row["level"].text = "%s · Уровень %d" % [hero["role_detail"], level]
		if not progress.is_in_formation(hero_id):
			row["level"].text += " · не в отряде"
		row["stats"].text = "HP %d · Атака %d · Сила %d" % [
			roundi(hero["hp"] * multiplier), roundi(hero["attack"] * multiplier), progress.hero_power(data, hero_id)]
		var button: Button = row["button"]
		if progress.is_max_level(data, hero_id):
			button.text = "Макс.\nуровень"
			button.disabled = true
		else:
			button.text = "Улучшить\n%d сер.\n+%d силы" % [progress.level_up_cost(data, hero_id), progress.level_up_power_gain(data, hero_id)]
			button.disabled = not progress.can_level_up(data, hero_id)


func _add_row(hero_id: String) -> void:
	var data = GameState.data
	var hero: Dictionary = data.get_hero(hero_id)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.06)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	# A finger dragged over a card must reach the ScrollContainer (a panel stops it by default).
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	%List.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	box.add_child(line)

	line.add_child(make_portrait(hero, PORTRAIT_SIZE))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(info)
	info.add_child(_make_wrapping_label("%s · %s" % [hero["name"], data.get_hero_class(hero)["name"]], 30))
	var level_label := _make_wrapping_label("", 22)
	info.add_child(level_label)
	var stats_label := _make_wrapping_label("", 22)
	info.add_child(stats_label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(180, 120)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(_on_level_up_pressed.bind(hero_id))
	# The drag passes on to the ScrollContainer too; once the list starts scrolling, the press is cancelled.
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(button)

	var ultimate: Dictionary = hero["ultimate"]
	box.add_child(_make_description("Ульта «%s»: %s" % [ultimate["name"], ultimate["description"]]))
	var passive: Dictionary = hero.get("passive", {})
	box.add_child(_make_description("Пассивка: %s" % passive["description"] if not passive.is_empty() else "Пассивки нет"))

	_rows[hero_id] = {"level": level_label, "stats": stats_label, "button": button}


## Head and shoulders of the hero on old paper (the picture's own background colour, docs/ART_STYLE.md).
## Also used by the formation screen.
static func make_portrait(hero: Dictionary, side: float) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PORTRAIT_PAPER
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color("#1a1a1a")
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var picture := TextureRect.new()
	picture.texture = Art.hero_portrait(hero)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(side, side)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	return frame


func _make_description(text_value: String) -> Label:
	var label := _make_wrapping_label(text_value, 22)
	label.add_theme_color_override("font_color", DESCRIPTION_COLOR)
	return label


## Wraps instead of widening the row past the phone screen.
func _make_wrapping_label(text_value: String, font_size: int) -> Label:
	var label := _make_label(text_value, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1
	return label


func _make_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	return label
