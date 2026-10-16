## M8: «Настройки» opened by the gear on the main screen. The names toggle is on by default, changes the setting
## and saves it apart from the progress.
extends "res://tests/base_test.gd"

const Settings := preload("res://scripts/save/settings.gd")
const SaveStorage := preload("res://scripts/save/save_storage.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"


func test_gear_on_the_main_screen_opens_settings() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await _game_state()
	var menu: Control = load(MAIN_MENU_SCENE).instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	var gear: Button = menu.get_node("%SettingsButton")
	assert_true(gear.icon != null, "the button shows a gear")
	assert_true(gear.size.x >= 88.0 and gear.size.y >= 88.0, "big enough for a finger")
	assert_eq(menu.SETTINGS_SCENE, SETTINGS_SCENE, "it leads to «Настройки»")
	menu.queue_free()


func test_names_toggle_changes_and_saves_the_setting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = await _game_state()
	var saved_settings = game_state.settings
	game_state.settings = Settings.new()
	var screen: Control = load(SETTINGS_SCENE).instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	var button: Button = screen.get_node("%NamesButton")
	assert_true(button.button_pressed, "names are shown by default")
	assert_eq(button.text, "Показывать имена в бою: вкл", "the button says so")
	button.button_pressed = false
	assert_eq(game_state.settings.show_names_in_battle, false, "off")
	assert_eq(button.text, "Показывать имена в бою: выкл", "the button says off")
	assert_eq(SaveStorage.load_settings().show_names_in_battle, false, "saved to the settings file at once")
	button.button_pressed = true
	assert_true(SaveStorage.load_settings().show_names_in_battle, "and back on")
	screen.queue_free()
	game_state.settings = saved_settings
	game_state.save_settings()


func _game_state() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	return game_state
