## Autoload "GameState": game data and the player's progress, shared by all screens.
## Screens call save() after every change; it also saves regularly and when the game goes to the background,
## so the "last seen" time used for offline income stays fresh.
extends Node

const GameData := preload("res://scripts/data/game_data.gd")
const SaveStorage := preload("res://scripts/save/save_storage.gd")

const HEARTBEAT_SECONDS := 60.0  ## how often the open game refreshes its "last seen" time

var data
var progress
var selected_stage := 1  ## stage the battle screen should fight (set by the chapter map)
var pending_offline_income := 0  ## silver earned while away, waiting for «Забрать»

var _page_hidden_callback  ## keeps the browser callback alive


func _ready() -> void:
	data = GameData.load_all()
	progress = SaveStorage.load_progress(data)
	pending_offline_income = progress.offline_income(data, _now())
	save()
	var heartbeat := Timer.new()
	heartbeat.wait_time = HEARTBEAT_SECONDS
	heartbeat.timeout.connect(save)
	add_child(heartbeat)
	heartbeat.start()
	if OS.has_feature("web"):
		# Closing or switching away from the browser tab does not always reach the engine as a notification.
		_page_hidden_callback = JavaScriptBridge.create_callback(_on_page_visibility_changed)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _page_hidden_callback)


## Adds the offline income to the silver (the «Забрать» button).
func claim_offline_income() -> void:
	progress.silver += pending_offline_income
	pending_offline_income = 0
	save()


func save() -> void:
	# While offline income waits to be claimed, keep the old "last seen" time so it is not lost.
	if pending_offline_income == 0:
		progress.last_seen_unix = _now()
	SaveStorage.save_progress(progress)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			if progress != null:
				save()


func _on_page_visibility_changed(_args: Array) -> void:
	save()


func _now() -> int:
	return int(Time.get_unix_time_from_system())
