## Autoload "GameState": game data and the player's progress, shared by all screens.
## Screens call save() after every change; it also saves when the game goes to the background.
extends Node

const GameData := preload("res://scripts/data/game_data.gd")
const SaveStorage := preload("res://scripts/save/save_storage.gd")

var data
var progress

var _page_hidden_callback  ## keeps the browser callback alive


func _ready() -> void:
	data = GameData.load_all()
	progress = SaveStorage.load_progress(data)
	if OS.has_feature("web"):
		# Closing or switching away from the browser tab does not always reach the engine as a notification.
		_page_hidden_callback = JavaScriptBridge.create_callback(_on_page_visibility_changed)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _page_hidden_callback)


func save() -> void:
	SaveStorage.save_progress(progress)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			if progress != null:
				save()


func _on_page_visibility_changed(_args: Array) -> void:
	save()
