extends Control

const BATTLE_SCENE := "res://scenes/battle.tscn"


func _ready() -> void:
	%BattleButton.pressed.connect(func(): get_tree().change_scene_to_file(BATTLE_SCENE))
