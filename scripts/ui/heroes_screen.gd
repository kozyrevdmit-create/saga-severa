## Heroes screen: every unlocked hero's role, level, stats, «Сила», ultimate and passive; level-up for silver
## (the button shows the power the level adds). Saves after every level-up.
extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

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
	%List.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	box.add_child(line)

	var swatch := ColorRect.new()
	swatch.color = Color.html(data.get_hero_class(hero)["color"])
	swatch.custom_minimum_size = Vector2(24, 0)
	line.add_child(swatch)

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
	line.add_child(button)

	var ultimate: Dictionary = hero["ultimate"]
	box.add_child(_make_description("Ульта «%s»: %s" % [ultimate["name"], ultimate["description"]]))
	var passive: Dictionary = hero.get("passive", {})
	box.add_child(_make_description("Пассивка: %s" % passive["description"] if not passive.is_empty() else "Пассивки нет"))

	_rows[hero_id] = {"level": level_label, "stats": stats_label, "button": button}


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
