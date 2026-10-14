## Debug panel (spec 5.6), opened by a long press on the silver counter of the main screen.
## «Сбросить прогресс» asks «Точно сбросить?» first.
extends Control

signal progress_changed  ## the panel changed the progress; the screen behind should refresh


func _ready() -> void:
	visible = false
	%ConfirmBox.visible = false
	%ResetButton.pressed.connect(func(): %ConfirmBox.visible = true)
	%ConfirmYesButton.pressed.connect(_on_reset_confirmed)
	%ConfirmNoButton.pressed.connect(func(): %ConfirmBox.visible = false)
	%CloseButton.pressed.connect(close)


func open() -> void:
	%ConfirmBox.visible = false
	visible = true


func close() -> void:
	visible = false


func _on_reset_confirmed() -> void:
	GameState.reset_progress()
	%ConfirmBox.visible = false
	progress_changed.emit()
	close()
