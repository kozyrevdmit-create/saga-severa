## Autoload "GameState": game data and the player's progress, shared by all screens.
## Screens call save() after every change. Offline income: when the game starts or comes back from the
## background, the income for the time away goes into the bank (Progress.collect_offline_income);
## leaving, hiding or unfocusing the game saves the time it was last seen and stops the heartbeat,
## so the time in the background is not overwritten before it is counted.
extends Node

signal offline_bank_changed  ## new offline income is waiting for «Забрать»

const GameData := preload("res://scripts/data/game_data.gd")
const SaveStorage := preload("res://scripts/save/save_storage.gd")

var data
var progress
var selected_stage := 1  ## stage the battle screen should fight (set by the chapter map)

var _visibility_callback  ## keeps the browser callback alive
var _heartbeat := Timer.new()  ## refreshes "last seen" while the game is in front
var _away := false  ## the game is in the background (between leaving and coming back)


func _ready() -> void:
	data = GameData.load_all()
	progress = SaveStorage.load_progress(data)
	# While the game is in front, refresh the "last seen" time now and then, in case it is closed without notice.
	_heartbeat.wait_time = float(data.balance["offline_income"]["last_seen_refresh_seconds"])
	_heartbeat.timeout.connect(save)
	add_child(_heartbeat)
	_bank_offline_income()
	_heartbeat.start()
	if OS.has_feature("web"):
		# Switching away from the browser tab and back does not always reach the engine as a notification.
		_visibility_callback = JavaScriptBridge.create_callback(_on_page_visibility_changed)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _visibility_callback)


## «Забрать»: adds the offline income bank to the silver.
func claim_offline_income() -> void:
	progress.claim_offline_bank()
	save()


## Debug panel «Сбросить прогресс»: a new game, saved at once.
func reset_progress() -> void:
	progress.reset(data, _now())
	selected_stage = 1
	save()


## Debug panel «+N серебра».
func debug_add_silver() -> void:
	progress.silver += int(data.balance["debug_panel"]["add_silver"])
	save()


## Debug panel «Открыть всех героев».
func debug_unlock_all_heroes() -> void:
	progress.unlock_all_heroes(data)
	save()


## Debug panel «Перейти к этапу N».
func debug_jump_to_stage(stage_id: int) -> void:
	progress.jump_to_stage(data, stage_id)
	selected_stage = progress.next_stage_id(data)
	save()


## Debug panel «Промотать время»: as if the game had been closed for skip_time_hours; the income goes
## into the bank and the «Пока тебя не было» window shows it.
func debug_skip_time() -> void:
	progress.last_seen_unix = _now() - roundi(float(data.balance["debug_panel"]["skip_time_hours"]) * 3600.0)
	_bank_offline_income()


func save() -> void:
	# In the background the "last seen" time stays at the moment the game left, so that time is counted later.
	if not _away:
		progress.last_seen_unix = _now()
	SaveStorage.save_progress(progress)


func _notification(what: int) -> void:
	if progress == null:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_on_left()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_on_returned()


func _on_page_visibility_changed(_args: Array) -> void:
	if JavaScriptBridge.get_interface("document").hidden:
		_on_left()
	else:
		_on_returned()


## The game went to the background: remember when, and stop refreshing that time until it comes back.
func _on_left() -> void:
	if _away:
		return
	save()
	_heartbeat.stop()
	_away = true


## The game came back: count the time away first, then resume refreshing "last seen".
func _on_returned() -> void:
	if not _away:
		return
	_away = false
	_bank_offline_income()
	_heartbeat.start()


## Banks the income for the time away (from the saved "last seen" time to now), then saves.
func _bank_offline_income() -> void:
	var gained: int = progress.collect_offline_income(data, _now())
	SaveStorage.save_progress(progress)
	if gained > 0:
		offline_bank_changed.emit()


func _now() -> int:
	return int(Time.get_unix_time_from_system())
