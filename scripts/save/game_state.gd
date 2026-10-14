## Autoload "GameState": game data and the player's progress, shared by all screens.
## Screens call save() after every change. Offline income: when the game starts or comes back from the
## background, the income for the time away goes into the bank (Progress.collect_offline_income);
## leaving or hiding the game saves the time it was last seen.
extends Node

signal offline_bank_changed  ## new offline income is waiting for «Забрать»

const GameData := preload("res://scripts/data/game_data.gd")
const SaveStorage := preload("res://scripts/save/save_storage.gd")

var data
var progress
var selected_stage := 1  ## stage the battle screen should fight (set by the chapter map)

var _visibility_callback  ## keeps the browser callback alive


func _ready() -> void:
	data = GameData.load_all()
	progress = SaveStorage.load_progress(data)
	_on_resumed()
	# While the game is open, refresh the "last seen" time now and then, in case it is closed without notice.
	var heartbeat := Timer.new()
	heartbeat.wait_time = float(data.balance["offline_income"]["last_seen_refresh_seconds"])
	heartbeat.timeout.connect(save)
	add_child(heartbeat)
	heartbeat.start()
	if OS.has_feature("web"):
		# Switching away from the browser tab and back does not always reach the engine as a notification.
		_visibility_callback = JavaScriptBridge.create_callback(_on_page_visibility_changed)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _visibility_callback)


## «Забрать»: adds the offline income bank to the silver.
func claim_offline_income() -> void:
	progress.claim_offline_bank()
	save()


func save() -> void:
	progress.last_seen_unix = _now()
	SaveStorage.save_progress(progress)


func _notification(what: int) -> void:
	if progress == null:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			save()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_on_resumed()


func _on_page_visibility_changed(_args: Array) -> void:
	if JavaScriptBridge.get_interface("document").hidden:
		save()
	else:
		_on_resumed()


## Banks the income for the time away (from the saved "last seen" time to now), then saves.
func _on_resumed() -> void:
	var gained: int = progress.collect_offline_income(data, _now())
	SaveStorage.save_progress(progress)
	if gained > 0:
		offline_bank_changed.emit()


func _now() -> int:
	return int(Time.get_unix_time_from_system())
