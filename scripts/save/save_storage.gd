## Reads and writes the player's progress as JSON (user://save.json; in the browser it lives in IndexedDB).
extends RefCounted

const Progress := preload("res://scripts/save/progress.gd")

const SAVE_PATH := "user://save.json"


## A missing or damaged save starts a new game instead of failing.
static func load_progress(data, path := SAVE_PATH) -> RefCounted:
	if not FileAccess.file_exists(path):
		return Progress.new_game(data)
	var json := JSON.new()  # unlike JSON.parse_string, does not report a damaged save as an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_warning("Save file is damaged, starting a new game: %s" % path)
		return Progress.new_game(data)
	return Progress.from_dict(json.data, data)


## Writes a temporary file first and then swaps it in, so an interrupted write cannot damage the save.
static func save_progress(progress, path := SAVE_PATH) -> bool:
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write save %s: %s" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(progress.to_dict(), "  "))
	file.close()
	var error := DirAccess.rename_absolute(temp_path, path)
	if error != OK:
		push_warning("Cannot replace save %s: %s" % [path, error_string(error)])
		return false
	return true
