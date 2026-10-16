## Squad formation (spec 5.4): tap a hero to put them into the next free slot, tap a hero in a slot to take
## them out. Shows the squad's «Сила», each hero's role and which clan bonuses are active. Saves after every change.
extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

const EMPTY_SLOT_COLOR := Color(1, 1, 1, 0.06)
const ACTIVE_SYNERGY_COLOR := Color("#7be08f")
const INACTIVE_SYNERGY_COLOR := Color(1, 1, 1, 0.5)


func _ready() -> void:
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	_refresh()


func _on_slot_pressed(hero_id: String) -> void:
	if hero_id == "":
		return
	if GameState.progress.formation_remove(hero_id):
		_changed()
	else:
		%Message.text = "В отряде должен остаться хотя бы один герой."


func _on_bench_hero_pressed(hero_id: String) -> void:
	if GameState.progress.formation_add(GameState.data, hero_id):
		_changed()
	else:
		%Message.text = "Все слоты заняты. Сначала убери кого-нибудь из отряда."


func _changed() -> void:
	%Message.text = ""
	GameState.save()
	_refresh()


func _refresh() -> void:
	var data = GameState.data
	var progress = GameState.progress
	%PowerLabel.text = "Сила отряда: %d" % progress.squad_power(data)
	for row in [%FrontRow, %BackRow, %Bench, %Synergies]:
		for child in row.get_children():
			child.queue_free()

	for slot in progress.formation.size():
		var hero_id: String = progress.formation[slot]
		var row: HBoxContainer = %FrontRow if progress.slot_row(data, slot) == "front" else %BackRow
		var button := _make_hero_button(hero_id)
		button.pressed.connect(_on_slot_pressed.bind(hero_id))
		row.add_child(button)

	var bench_count := 0
	for hero_id in progress.hero_levels:
		if not progress.is_in_formation(hero_id):
			var button := _make_hero_button(hero_id)
			button.size_flags_horizontal = Control.SIZE_FILL
			button.custom_minimum_size.x = 200
			button.pressed.connect(_on_bench_hero_pressed.bind(hero_id))
			%Bench.add_child(button)
			bench_count += 1
	if bench_count == 0:
		var label := _make_label("Все герои в отряде", 24, INACTIVE_SYNERGY_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%Bench.add_child(label)

	for synergy in data.clan_synergies(progress.squad_ids()):
		var text := "%s: %d из %d — %s" % [synergy["name"], synergy["count"], synergy["needed"], synergy["description"]]
		var color := ACTIVE_SYNERGY_COLOR if synergy["active"] else INACTIVE_SYNERGY_COLOR
		# Words, not a check mark: the web build's font has no ✔ glyph.
		%Synergies.add_child(_make_label(text + (" — активен" if synergy["active"] else ""), 24, color))


## A hero card: name, role and level on the class colour; an empty slot when hero_id is "".
func _make_hero_button(hero_id: String) -> Button:
	var data = GameState.data
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 150)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 24)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(12)
	if hero_id == "":
		button.text = "пусто"
		style.bg_color = EMPTY_SLOT_COLOR
	else:
		var hero: Dictionary = data.get_hero(hero_id)
		var hero_class: Dictionary = data.get_hero_class(hero)
		button.text = "%s\n%s\nур. %d" % [hero["name"], hero_class["role_short"], GameState.progress.level_of(hero_id)]
		style.bg_color = Color.html(hero_class["color"]).darkened(0.35)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, style)
	return button


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
