## «Настройки», opened with the gear on the main screen. Saved apart from the progress (GameState.save_settings),
## so «Сбросить прогресс» keeps them.
## «Сцены саги»: the saga scenes already seen, by their titles (story.json → title); a tap plays the scene again.
## «Как играть» (M14): every text of the beginner's tutorial (data/tutorial.json) as a list, in the tutorial's order,
## then the heroes' roles («Танк — Стоит впереди и принимает удары на себя.»: heroes.json → classes, each role once).
extends Control

const StoryPlayer := preload("res://scripts/ui/story_player.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SCENE_BUTTON_HEIGHT := 104.0
const SCENE_FONT_SIZE := 32
const HOW_TO_FONT_SIZE := 30
const HOW_TO_HEADING_FONT_SIZE := 38
const HOW_TO_TEXT_COLOR := Color(1, 1, 1, 0.92)
const HOW_TO_HEADING_COLOR := Color(1, 0.85, 0.3, 1)


func _ready() -> void:
	%NamesButton.button_pressed = GameState.settings.show_names_in_battle
	%NamesButton.toggled.connect(_on_names_toggled)
	_show_names_state()
	%ScenesButton.pressed.connect(open_scenes)
	%ScenesBackButton.pressed.connect(func(): %ScenesOverlay.visible = false)
	var data = GameState.data
	%HowToButton.text = data.tutorial_text("how_to_play")
	%HowToTitle.text = data.tutorial_text("how_to_play")
	%HowToBackButton.text = data.tutorial_text("how_to_play_back")
	%HowToButton.pressed.connect(open_how_to)
	%HowToBackButton.pressed.connect(func(): %HowToOverlay.visible = false)
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))


func _on_names_toggled(enabled: bool) -> void:
	GameState.settings.show_names_in_battle = enabled
	GameState.save_settings()
	_show_names_state()


func _show_names_state() -> void:
	%NamesButton.text = "Показывать имена в бою: %s" % ("вкл" if %NamesButton.button_pressed else "выкл")


## The list of seen scenes, in story order.
func open_scenes() -> void:
	for old in %SceneList.get_children():
		%SceneList.remove_child(old)
		old.queue_free()
	var data = GameState.data
	var seen: Array[String] = GameState.progress.seen_scene_ids(data)
	for scene_id in seen:
		var button := Button.new()
		button.text = data.get_scene(scene_id)["title"]
		button.custom_minimum_size = Vector2(0, SCENE_BUTTON_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", SCENE_FONT_SIZE)
		button.pressed.connect(StoryPlayer.play.bind(self, scene_id))
		%SceneList.add_child(button)
	%NoScenesLabel.visible = seen.is_empty()
	%ScenesOverlay.visible = true


## «Как играть»: the tutorial's texts, then «Роли героев».
func open_how_to() -> void:
	for old in %HowToList.get_children():
		%HowToList.remove_child(old)
		old.queue_free()
	for line in how_to_lines(GameState.data):
		%HowToList.add_child(_make_how_to_label(line[1], line[0] == "heading"))
	%HowToScroll.scroll_vertical = 0
	%HowToOverlay.visible = true


## The lines of «Как играть»: [["text", hint text] × 12, ["heading", «Роли героев»], ["text", role line] × 4].
static func how_to_lines(data) -> Array:
	var lines := []
	for hint_id in data.tutorial_hint_ids():
		lines.append(["text", data.get_tutorial_hint(hint_id)["text"]])
	lines.append(["heading", data.tutorial_text("how_to_play_roles")])
	var roles: Array[String] = []
	for hero_class in data.heroes["classes"].values():
		if not hero_class["role_short"] in roles:
			roles.append(hero_class["role_short"])
			lines.append(["text", data.tutorial_text("how_to_play_role_line") % [hero_class["role_short"],
					hero_class["role_description"]]])
	return lines


func _make_how_to_label(text_value: String, heading: bool) -> Label:
	var label := Label.new()
	label.text = text_value
	label.custom_minimum_size.x = 1
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", HOW_TO_HEADING_FONT_SIZE if heading else HOW_TO_FONT_SIZE)
	label.add_theme_color_override("font_color", HOW_TO_HEADING_COLOR if heading else HOW_TO_TEXT_COLOR)
	return label
