## «Настройки», opened with the gear on the main screen. Saved apart from the progress (GameState.save_settings),
## so «Сбросить прогресс» keeps them.
## «Сцены саги»: the saga scenes already seen, by their titles (story.json → title); a tap plays the scene again.
extends Control

const StoryPlayer := preload("res://scripts/ui/story_player.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SCENE_BUTTON_HEIGHT := 104.0
const SCENE_FONT_SIZE := 32


func _ready() -> void:
	%NamesButton.button_pressed = GameState.settings.show_names_in_battle
	%NamesButton.toggled.connect(_on_names_toggled)
	_show_names_state()
	%ScenesButton.pressed.connect(open_scenes)
	%ScenesBackButton.pressed.connect(func(): %ScenesOverlay.visible = false)
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
