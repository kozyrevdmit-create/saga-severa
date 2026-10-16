## «Настройки», opened with the gear on the main screen. Saved apart from the progress (GameState.save_settings),
## so «Сбросить прогресс» keeps them.
extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	%NamesButton.button_pressed = GameState.settings.show_names_in_battle
	%NamesButton.toggled.connect(_on_names_toggled)
	_show_names_state()
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))


func _on_names_toggled(enabled: bool) -> void:
	GameState.settings.show_names_in_battle = enabled
	GameState.save_settings()
	_show_names_state()


func _show_names_state() -> void:
	%NamesButton.text = "Показывать имена в бою: %s" % ("вкл" if %NamesButton.button_pressed else "выкл")
