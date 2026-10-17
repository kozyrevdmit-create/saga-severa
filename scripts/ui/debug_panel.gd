## Debug panel (spec 5.6), opened by a long press on the silver counter of the main screen:
## add silver, unlock all heroes, jump to stage N, mark all saga scenes seen, skip time, reset the progress
## («Точно сбросить?» first). Unlocking heroes and jumping to a stage play no saga scenes.
## Amounts come from balance.json → debug_panel.
extends Control

signal progress_changed  ## the panel changed the progress; the screen behind should refresh

var _jump_stage := 1  ## stage chosen with − / +


func _ready() -> void:
	visible = false
	%ConfirmBox.visible = false
	var debug: Dictionary = GameState.data.balance["debug_panel"]
	%AddSilverButton.text = "+%s серебра" % _thousands(int(debug["add_silver"]))
	%SkipTimeButton.text = "Промотать время на %s ч" % _number(float(debug["skip_time_hours"]))
	%AddSilverButton.pressed.connect(_on_add_silver)
	%UnlockHeroesButton.pressed.connect(_on_unlock_heroes)
	%UnlockScenesButton.pressed.connect(_on_unlock_scenes)
	%StageDownButton.pressed.connect(_change_jump_stage.bind(-1))
	%StageUpButton.pressed.connect(_change_jump_stage.bind(1))
	%JumpButton.pressed.connect(_on_jump)
	%SkipTimeButton.pressed.connect(_on_skip_time)
	%ResetButton.pressed.connect(func(): %ConfirmBox.visible = true)
	%ConfirmYesButton.pressed.connect(_on_reset_confirmed)
	%ConfirmNoButton.pressed.connect(func(): %ConfirmBox.visible = false)
	%CloseButton.pressed.connect(close)


func open() -> void:
	%ConfirmBox.visible = false
	%Status.text = ""
	_jump_stage = GameState.progress.next_stage_id(GameState.data)
	_change_jump_stage(0)
	visible = true


func close() -> void:
	visible = false


func _on_add_silver() -> void:
	GameState.debug_add_silver()
	_done("Серебро: %d" % GameState.progress.silver)


func _on_unlock_heroes() -> void:
	var before: int = GameState.progress.hero_levels.size()
	GameState.debug_unlock_all_heroes()
	var joined: int = GameState.progress.hero_levels.size() - before
	_done("Открыто героев: %d" % joined if joined > 0 else "Все герои уже в дружине")


## «Открыть все сцены»: all saga scenes can be watched from «Настройки» → «Сцены саги».
func _on_unlock_scenes() -> void:
	GameState.debug_mark_all_scenes_seen()
	_done("Сцены — в «Настройки» → «Сцены саги»")


func _change_jump_stage(step: int) -> void:
	_jump_stage = clampi(_jump_stage + step, 1, GameState.data.stage_count())
	%JumpButton.text = "Перейти к этапу %d" % _jump_stage


func _on_jump() -> void:
	GameState.debug_jump_to_stage(_jump_stage)
	_done("Следующий бой — этап %d" % _jump_stage)


## Closes the panel so the «Пока тебя не было» window behind it shows the income.
func _on_skip_time() -> void:
	GameState.debug_skip_time()
	progress_changed.emit()
	close()


func _on_reset_confirmed() -> void:
	GameState.reset_progress()
	%ConfirmBox.visible = false
	progress_changed.emit()
	close()


func _done(status: String) -> void:
	%Status.text = status
	progress_changed.emit()


static func _thousands(value: int) -> String:
	var digits := str(value)
	var result := ""
	while digits.length() > 3:
		result = " " + digits.right(3) + result
		digits = digits.left(digits.length() - 3)
	return digits + result


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
