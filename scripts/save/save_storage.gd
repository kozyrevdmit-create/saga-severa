## Reads and writes the player's progress and settings as JSON (user://save.json and user://settings.json;
## in the browser they live in IndexedDB). Two files, so resetting the progress leaves the settings alone.
extends RefCounted

const Progress := preload("res://scripts/save/progress.gd")
const Settings := preload("res://scripts/save/settings.gd")

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.json"


## A missing or damaged save starts a new game instead of failing.
static func load_progress(data, path := SAVE_PATH) -> RefCounted:
	var values = _read(path)
	return Progress.new_game(data) if values == null else Progress.from_dict(values, data)


static func save_progress(progress, path := SAVE_PATH) -> bool:
	return _write(progress.to_dict(), path)


## Missing or damaged settings fall back to the defaults.
static func load_settings(path := SETTINGS_PATH) -> RefCounted:
	var values = _read(path)
	return Settings.new() if values == null else Settings.from_dict(values)


static func save_settings(settings, path := SETTINGS_PATH) -> bool:
	return _write(settings.to_dict(), path)


## The file's JSON object, or null if there is no file or it is damaged.
static func _read(path: String):
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()  # unlike JSON.parse_string, does not report a damaged file as an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_warning("File is damaged, using defaults: %s" % path)
		return null
	return json.data


## Writes a temporary file first and then swaps it in, so an interrupted write cannot damage the file.
static func _write(values: Dictionary, path: String) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write %s: %s" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(values, "  "))
	file.close()
	var error := DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		push_warning("Cannot replace %s: %s" % [path, error_string(error)])
		return false
	return true
