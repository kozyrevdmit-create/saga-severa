## Main screen: silver, jarl level, the four sections and the "while you were away" window.
## A long press on the silver counter opens the debug panel (spec 5.6).
extends Control

const MAP_SCENE := "res://scenes/map.tscn"
const HEROES_SCENE := "res://scenes/heroes.tscn"
const FORMATION_SCENE := "res://scenes/formation.tscn"
const SETTLEMENT_SCENE := "res://scenes/settlement.tscn"

const JARL_BAR_COLOR := Color("#8fb8ff")
var _long_press: Timer  ## holding the silver counter this long opens the debug panel


func _ready() -> void:
	%MapButton.pressed.connect(_open.bind(MAP_SCENE))
	%HeroesButton.pressed.connect(_open.bind(HEROES_SCENE))
	%SquadButton.pressed.connect(_open.bind(FORMATION_SCENE))
	%SettlementButton.pressed.connect(_open.bind(SETTLEMENT_SCENE))
	%ClaimButton.pressed.connect(_on_claim_pressed)
	%JarlBar.fill_color = JARL_BAR_COLOR
	_long_press = Timer.new()
	_long_press.one_shot = true
	_long_press.wait_time = float(GameState.data.balance["debug_panel"]["long_press_seconds"])
	_long_press.timeout.connect(%DebugPanel.open)
	add_child(_long_press)
	%SilverLabel.gui_input.connect(_on_silver_input)
	%SilverLabel.mouse_exited.connect(_long_press.stop)
	%DebugPanel.progress_changed.connect(_on_debug_changed)
	GameState.offline_bank_changed.connect(_show_offline_income)
	_show_offline_income()
	_refresh()


## «Пока тебя не было»: shown when the game starts or comes back with offline income waiting.
func _show_offline_income() -> void:
	var bank: int = GameState.progress.offline_bank
	if bank > 0:
		%OfflineAmount.text = "+%d серебра" % bank
		%OfflineOverlay.visible = true


## Touches arrive as mouse events too (touch-to-mouse emulation is on by default).
func _on_silver_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_long_press.start()


## Letting go anywhere (also outside the counter) or sliding off the counter cancels the hold.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_long_press.stop()


func _on_debug_changed() -> void:
	%OfflineOverlay.visible = false
	_show_offline_income()
	_refresh()


func _on_claim_pressed() -> void:
	GameState.claim_offline_income()
	%OfflineOverlay.visible = false
	_refresh()


func _refresh() -> void:
	var data = GameState.data
	var progress = GameState.progress
	%SilverLabel.text = "Серебро: %d" % progress.silver
	%JarlLabel.text = "Ярл, уровень %d" % progress.jarl_level(data)
	var level_progress: Array[int] = progress.jarl_level_progress(data)
	%JarlBar.value = float(level_progress[0]) / level_progress[1]
	%JarlExpLabel.text = "%d / %d опыта · +%d%% серебра" % [
		level_progress[0], level_progress[1], roundi((progress.silver_multiplier(data) - 1.0) * 100)]


func _open(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
