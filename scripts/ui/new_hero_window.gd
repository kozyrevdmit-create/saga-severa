## «Новый герой присоединился к дружине» over any screen, for heroes who join outside a battle (M13: Regin at the end of
## his scene «ch3_intro» on the chapter map). Looks like the battle screen's window: portrait, name, class, role, clan,
## ultimate and where the hero stands. «Отлично!» shows the next hero; after the last one the window closes
## and `closed` is emitted.
extends ColorRect

const HeroesScreen := preload("res://scripts/ui/heroes_screen.gd")

const BACKGROUND := Color(0.05, 0.06, 0.09, 0.96)
const TITLE_COLOR := Color(1, 0.85, 0.3, 1)
const PORTRAIT_SIZE := 260.0
const SIDE_MARGIN := 48.0

signal closed

var _heroes: Array[String] = []
var _portrait := CenterContainer.new()
var _name := Label.new()
var _info: Label
var _button := Button.new()


## Opens the window over `screen` for these heroes, one after another. Returns it (already on screen).
static func open(screen: Node, hero_ids: Array[String]) -> Control:
	var window = new()
	window._heroes = hero_ids.duplicate()
	screen.add_child(window)
	return window


## «Кузнец · Поддержка · род Свартальфхейм», the ultimate and where the hero stands (also the battle screen's window).
static func info_text(data, progress, hero_id: String) -> String:
	var hero: Dictionary = data.get_hero(hero_id)
	var hero_class: Dictionary = data.get_hero_class(hero)
	var where := "Уже в отряде." if progress.is_in_formation(hero_id) else "Поставь в отряд на экране «Отряд»."
	return "%s · %s · род %s\nУльта: %s\n%s" % [hero_class["name"], hero_class["role_short"],
		data.heroes["clans"][hero["clan"]]["name"], hero["ultimate"]["name"], where]


func _ready() -> void:
	color = BACKGROUND
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = SIDE_MARGIN
	box.offset_right = -SIDE_MARGIN
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	add_child(box)
	var title := _make_label("Новый герой присоединился к дружине!", 44)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	box.add_child(title)
	box.add_child(_portrait)
	_name.add_theme_font_size_override("font_size", 56)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name)
	_info = _make_label("", 28)
	box.add_child(_info)
	_button.text = "Отлично!"
	_button.custom_minimum_size = Vector2(0, 120)
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 40)
	_button.pressed.connect(_show_next)
	box.add_child(_button)
	_show_next()


func shown_hero() -> String:
	return _name.get_meta("hero_id", "")


func press_button() -> void:
	_button.pressed.emit()


func _show_next() -> void:
	if _heroes.is_empty():
		closed.emit()
		queue_free()
		return
	var hero_id: String = _heroes.pop_front()
	var data = GameState.data
	for old in _portrait.get_children():
		old.queue_free()
	_portrait.add_child(HeroesScreen.make_portrait(data.get_hero(hero_id), PORTRAIT_SIZE))
	_name.text = data.get_hero(hero_id)["name"]
	_name.set_meta("hero_id", hero_id)
	_info.text = info_text(data, GameState.progress, hero_id)


func _make_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label
