## M13.1 (playtest: Dmitriy took Regin out and did not see what «Поддержка» gives): the result window ends with a line
## for each support hero who fought — «Регин: броня спасла от N урона», «Эйвинд: песнь добавила N урона» — with the
## numbers the battle counted over all its waves; the window fits a 375×812 phone.
extends "res://tests/base_test.gd"

const Progress := preload("res://scripts/save/progress.gd")
const BATTLE_SCENE := "res://scenes/battle.tscn"

var _saved_progress
var _saved_window_size: Vector2i


func test_the_result_window_names_what_regin_and_eyvind_did() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	var data = game_state.data
	_saved_progress = game_state.progress
	var progress = Progress.new_game(data)
	progress.jump_to_stage(data, 24)
	progress.unlock_all_heroes(data)
	progress.formation[progress.formation.find("skadi")] = "regin"
	progress.mark_hint_shown = true
	progress.mark_all_scenes_seen(data)
	game_state.progress = progress
	game_state.selected_stage = 24
	game_state.selected_pack = ""
	_saved_window_size = tree.root.size
	tree.root.size = Vector2i(720, 1559)  # 375×812
	var screen: Control = load(BATTLE_SCENE).instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	screen.set_process(false)  # the test moves the battle on itself
	screen._battle.auto_ultimates = true
	for i in 300:  # 15 s of battle (or less if it ends)
		if screen._battle.finished:
			break
		screen._process(0.05)
	if not screen._battle.finished:
		screen.get_node("%RetreatButton").pressed.emit()
		screen._process(0.0)
	var units := {}
	for unit in screen._battle.heroes():
		units[unit.def_id] = unit
	assert_true(units["regin"].damage_prevented > 0 and units["eyvind"].damage_added > 0, "both helped (%d, %d)" % [
			units["regin"].damage_prevented, units["eyvind"].damage_added])
	var text: String = screen.get_node("%ResultHint").text
	assert_true(screen.get_node("%ResultOverlay").visible, "the result window")
	assert_true(text.ends_with("\n\nЭйвинд: песнь добавила %d урона\nРегин: броня спасла от %d урона" % [
			units["eyvind"].damage_added, units["regin"].damage_prevented]), "one line each, in squad order: %s" % text)
	await tree.process_frame
	var viewport: Rect2 = screen.get_viewport_rect()
	for node_name in ["%ResultHint", "%ResultTitle"]:
		assert_true(viewport.encloses(screen.get_node(node_name).get_global_rect()), "%s fits the 375×812 screen" % node_name)
	screen.queue_free()
	game_state.progress = _saved_progress
	tree.root.size = _saved_window_size


func test_no_line_without_a_support_hero() -> void:
	var data = (Engine.get_main_loop() as SceneTree).root.get_node("GameState").data
	var torvald = load("res://scripts/battle/battle_unit.gd").from_hero(data.get_hero("torvald"),
			data.get_hero_class(data.get_hero("torvald")))
	torvald.def_id = "torvald"
	var battle_screen := load("res://scripts/ui/battle_screen.gd")
	assert_eq(battle_screen.support_lines(data, [torvald]), [] as Array[String], "a tank gets no line")
