## M13.1: the game is shown to other people now, so on the site the long press on the silver opens the debug panel
## (with «Сбросить прогресс») only when the page was opened with ?debug=1. In the editor and local builds — always.
extends "res://tests/base_test.gd"

const GameStateScript := preload("res://scripts/save/game_state.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func test_the_site_needs_debug_1_in_the_address() -> void:
	assert_true(not GameStateScript.debug_allowed_for(true, ""), "the site without a query: no panel")
	assert_true(not GameStateScript.debug_allowed_for(true, "?debug=0"), "?debug=0: no panel")
	assert_true(not GameStateScript.debug_allowed_for(true, "?debugger=1"), "another parameter: no panel")
	assert_true(GameStateScript.debug_allowed_for(true, "?debug=1"), "?debug=1: the panel")
	assert_true(GameStateScript.debug_allowed_for(true, "?lang=ru&debug=1"), "debug=1 among other parameters: the panel")
	assert_true(GameStateScript.debug_allowed_for(false, ""), "the editor and local builds: always")


func test_the_long_press_opens_the_panel_only_when_allowed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	var saved: bool = game_state.debug_allowed
	for allowed in [false, true]:
		game_state.debug_allowed = allowed
		var menu: Control = load(MAIN_MENU_SCENE).instantiate()
		tree.root.add_child(menu)
		await tree.process_frame
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		menu._on_silver_input(press)  # the finger stays on the silver counter
		await tree.create_timer(float(game_state.data.balance["debug_panel"]["long_press_seconds"]) + 0.2).timeout
		assert_eq(menu.get_node("%DebugPanel").visible, allowed, "debug allowed %s: the panel %s" % [allowed,
				"opens" if allowed else "stays closed"])
		menu.queue_free()
		await tree.process_frame
	game_state.debug_allowed = saved
