## Settlement (spec 5.1: in the prototype only offline income): how much silver it brings while the game is closed.
extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	var data = GameState.data
	var progress = GameState.progress
	var max_hours := float(data.balance["offline_income"]["max_hours"])
	if progress.cleared_stage == 0:
		%Info.text = "Поселение начнёт приносить серебро после первого пройденного этапа."
	else:
		var per_minute: float = progress.offline_income_per_minute(data)
		%Info.text = ("Пока тебя нет в игре, поселение приносит %s серебра в минуту.\n\n"
			+ "Доход копится до %d часов, потом перестаёт расти — заходи, чтобы забрать.\n\n"
			+ "Доход растёт с каждым пройденным этапом и с уровнем ярла (сейчас +%d%%).") % [
				_format_rate(per_minute), int(max_hours), roundi((progress.silver_multiplier(data) - 1.0) * 100)]
		%Total.text = "За %d часов: %d серебра" % [int(max_hours), floori(per_minute * max_hours * 60.0)]
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))


func _format_rate(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
