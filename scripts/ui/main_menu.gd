## Main screen: silver, jarl level, the four sections and the "while you were away" window.
extends Control

const MAP_SCENE := "res://scenes/map.tscn"
const HEROES_SCENE := "res://scenes/heroes.tscn"
const FORMATION_SCENE := "res://scenes/formation.tscn"
const SETTLEMENT_SCENE := "res://scenes/settlement.tscn"

const JARL_BAR_COLOR := Color("#8fb8ff")


func _ready() -> void:
	%MapButton.pressed.connect(_open.bind(MAP_SCENE))
	%HeroesButton.pressed.connect(_open.bind(HEROES_SCENE))
	%SquadButton.pressed.connect(_open.bind(FORMATION_SCENE))
	%SettlementButton.pressed.connect(_open.bind(SETTLEMENT_SCENE))
	%ClaimButton.pressed.connect(_on_claim_pressed)
	%JarlBar.fill_color = JARL_BAR_COLOR
	GameState.offline_bank_changed.connect(_show_offline_income)
	_show_offline_income()
	_refresh()


## «Пока тебя не было»: shown when the game starts or comes back with offline income waiting.
func _show_offline_income() -> void:
	var bank: int = GameState.progress.offline_bank
	if bank > 0:
		%OfflineAmount.text = "+%d серебра" % bank
		%OfflineOverlay.visible = true


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
