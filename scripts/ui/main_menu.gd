## Main screen: silver, jarl level, the squad's «Сила», the four sections, the gear for «Настройки»
## and the "while you were away" window.
## A long press on the silver counter opens the debug panel (spec 5.6).
## Saga scenes waiting in the queue are played over this screen: the intro on a new game (also once for a save from
## before M10 and after «Сбросить прогресс»), or a scene left unseen when the game was closed.
extends Control

const StoryPlayer := preload("res://scripts/ui/story_player.gd")

const MAP_SCENE := "res://scenes/map.tscn"
const HEROES_SCENE := "res://scenes/heroes.tscn"
const FORMATION_SCENE := "res://scenes/formation.tscn"
const SETTLEMENT_SCENE := "res://scenes/settlement.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

const JARL_BAR_COLOR := Color("#8fb8ff")
var _long_press: Timer  ## holding the silver counter this long opens the debug panel
var _story: Control  ## the saga scene on screen, if any


func _ready() -> void:
	%MapButton.pressed.connect(_open.bind(MAP_SCENE))
	%HeroesButton.pressed.connect(_open.bind(HEROES_SCENE))
	%SquadButton.pressed.connect(_open.bind(FORMATION_SCENE))
	%SettlementButton.pressed.connect(_open.bind(SETTLEMENT_SCENE))
	%SettingsButton.pressed.connect(_open.bind(SETTINGS_SCENE))
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
	_play_queued_scene()


## Plays the queued scenes one after another.
func _play_queued_scene() -> void:
	if is_instance_valid(_story) and not _story.is_queued_for_deletion():
		return
	var scene_id: String = GameState.progress.queued_scene(GameState.data)
	if scene_id != "":
		_story = StoryPlayer.play(self, scene_id)
		_story.finished.connect(_play_queued_scene, CONNECT_DEFERRED)


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
	_play_queued_scene()  # after «Сбросить прогресс» the intro is due again


func _on_claim_pressed() -> void:
	GameState.claim_offline_income()
	%OfflineOverlay.visible = false
	_refresh()


func _refresh() -> void:
	var data = GameState.data
	var progress = GameState.progress
	%SilverLabel.text = "Серебро: %d" % progress.silver
	%JarlLabel.text = "Ярл, уровень %d" % progress.jarl_level(data)
	%PowerLabel.text = "Сила отряда: %d" % progress.squad_power(data)
	var level_progress: Array[int] = progress.jarl_level_progress(data)
	%JarlBar.value = float(level_progress[0]) / level_progress[1]
	%JarlExpLabel.text = "%d / %d опыта · +%d%% серебра" % [
		level_progress[0], level_progress[1], roundi((progress.silver_multiplier(data) - 1.0) * 100)]


func _open(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
