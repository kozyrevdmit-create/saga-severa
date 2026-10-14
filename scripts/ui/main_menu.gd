extends Control

const BATTLE_SCENE := "res://scenes/battle.tscn"
const HEROES_SCENE := "res://scenes/heroes.tscn"


func _ready() -> void:
	var progress = GameState.progress
	%SilverLabel.text = "Серебро: %d" % progress.silver
	%BattleButton.text = "В бой · Этап %d" % progress.next_stage_id(GameState.data)
	%BattleButton.pressed.connect(func(): get_tree().change_scene_to_file(BATTLE_SCENE))
	%HeroesButton.pressed.connect(func(): get_tree().change_scene_to_file(HEROES_SCENE))
