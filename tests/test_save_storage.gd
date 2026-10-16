## Saving and loading progress as JSON (spec 2: user://save.json). Uses a separate test file.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const Progress := preload("res://scripts/save/progress.gd")
const SaveStorage := preload("res://scripts/save/save_storage.gd")

const TEST_PATH := "user://test_save.json"

var data = GameData.load_all()


func _cleanup() -> void:
	for path in [TEST_PATH, TEST_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_save_then_load_restores_progress() -> void:
	_cleanup()
	var progress = Progress.new_game(data)
	progress.silver = 777
	progress.experience = 40
	progress.cleared_stage = 2
	progress.hero_levels["sigrid"] = 5
	assert_true(SaveStorage.save_progress(progress, TEST_PATH), "saved")
	assert_true(not FileAccess.file_exists(TEST_PATH + ".tmp"), "temporary file replaced")
	var loaded = SaveStorage.load_progress(data, TEST_PATH)
	assert_eq(loaded.to_dict(), progress.to_dict(), "loaded progress")
	_cleanup()


func test_missing_save_starts_new_game() -> void:
	_cleanup()
	var loaded = SaveStorage.load_progress(data, TEST_PATH)
	assert_eq(loaded.to_dict(), Progress.new_game(data).to_dict(), "new game")


func test_damaged_save_starts_new_game() -> void:
	_cleanup()
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	var loaded = SaveStorage.load_progress(data, TEST_PATH)
	assert_eq(loaded.to_dict(), Progress.new_game(data).to_dict(), "new game instead of a crash")
	_cleanup()


func test_save_overwrites_previous_save() -> void:
	_cleanup()
	var progress = Progress.new_game(data)
	progress.silver = 1
	SaveStorage.save_progress(progress, TEST_PATH)
	progress.silver = 2
	SaveStorage.save_progress(progress, TEST_PATH)
	assert_eq(SaveStorage.load_progress(data, TEST_PATH).silver, 2, "latest save wins")
	_cleanup()


# --- settings (M8) ---------------------------------------------------------------

const Settings := preload("res://scripts/save/settings.gd")
const TEST_SETTINGS_PATH := "user://test_settings.json"


func _cleanup_settings() -> void:
	for path in [TEST_SETTINGS_PATH, TEST_SETTINGS_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_names_in_battle_are_shown_by_default() -> void:
	_cleanup_settings()
	assert_true(SaveStorage.load_settings(TEST_SETTINGS_PATH).show_names_in_battle, "no settings file: names shown")
	assert_true(SaveStorage.SETTINGS_PATH != SaveStorage.SAVE_PATH, "settings live in their own file")


func test_settings_save_then_load() -> void:
	_cleanup_settings()
	var settings = Settings.new()
	settings.show_names_in_battle = false
	assert_true(SaveStorage.save_settings(settings, TEST_SETTINGS_PATH), "saved")
	assert_eq(SaveStorage.load_settings(TEST_SETTINGS_PATH).show_names_in_battle, false, "names stay off")
	_cleanup_settings()


func test_damaged_settings_fall_back_to_defaults() -> void:
	_cleanup_settings()
	var file := FileAccess.open(TEST_SETTINGS_PATH, FileAccess.WRITE)
	file.store_string("[1, 2")
	file.close()
	assert_true(SaveStorage.load_settings(TEST_SETTINGS_PATH).show_names_in_battle, "damaged file: names shown")
	assert_true(Settings.from_dict({"show_names_in_battle": "no"}).show_names_in_battle, "a wrong value keeps the default")
	_cleanup_settings()


func test_resetting_progress_keeps_settings() -> void:
	_cleanup()
	_cleanup_settings()
	var settings = Settings.new()
	settings.show_names_in_battle = false
	SaveStorage.save_settings(settings, TEST_SETTINGS_PATH)
	var progress = Progress.new_game(data)
	progress.silver = 500
	progress.reset(data, 0)
	SaveStorage.save_progress(progress, TEST_PATH)
	assert_true(not progress.to_dict().has("show_names_in_battle"), "settings are not part of the progress")
	assert_eq(SaveStorage.load_settings(TEST_SETTINGS_PATH).show_names_in_battle, false, "names stay off after the reset")
	_cleanup()
	_cleanup_settings()
