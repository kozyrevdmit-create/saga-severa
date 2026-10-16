## Phone-sized screens with all six heroes: every hero card can be reached, and a finger dragged over the cards
## scrolls the list (nothing inside the scroll area swallows the touch). M6.2: on the iPhone the 5th and 6th
## heroes could not be reached on «Герои».
extends "res://tests/base_test.gd"

const Progress := preload("res://scripts/save/progress.gd")
const HEROES_SCENE := "res://scenes/heroes.tscn"
const FORMATION_SCENE := "res://scenes/formation.tscn"


func test_every_hero_on_the_heroes_screen_can_be_reached() -> void:
	var screen = await _open(HEROES_SCENE, false)
	var buttons: Array = screen._rows.values().map(func(row): return row["button"])
	assert_eq(buttons.size(), 6, "six hero cards")
	await _check_reachable(screen, buttons, "«Герои»")
	_close(screen)


func test_every_hero_on_the_formation_screen_can_be_reached_with_a_full_bench() -> void:
	var screen = await _open(FORMATION_SCENE, true)
	var buttons: Array = []
	for row in [screen.get_node("%FrontRow"), screen.get_node("%BackRow"), screen.get_node("%Bench")]:
		buttons.append_array(row.get_children().filter(func(c): return c is Button))
	assert_eq(buttons.size(), 2 + 3 + 5, "five slots and five heroes on the bench")
	var bench: Control = screen.get_node("%Bench")
	assert_true(bench.size.x <= screen.get_node("%Scroll").size.x, "the bench wraps instead of widening the screen")
	await _check_reachable(screen, buttons, "«Отряд»")
	_close(screen)


# --- helpers -----------------------------------------------------------------

var _saved_progress  ## the player's progress, put back after the test
var _saved_window_size: Vector2i


## A screen at the 720×1280 base size (the project's viewport) with all six heroes; bench_most = only Torvald in the squad.
func _open(scene_path: String, bench_most: bool) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:  # the autoload gets ready once the main loop runs
		await tree.process_frame
	_saved_progress = game_state.progress
	var progress = Progress.new_game(game_state.data)
	progress.unlock_all_heroes(game_state.data)
	if bench_most:
		for hero_id in progress.squad_ids().duplicate():
			if hero_id != "torvald":
				progress.formation_remove(hero_id)
	game_state.progress = progress
	# Headless, the window is not the phone's shape: make it the project's base size for the test.
	_saved_window_size = tree.root.size
	tree.root.size = Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var screen: Control = load(scene_path).instantiate()
	tree.root.add_child(screen)
	for i in 3:
		await tree.process_frame
	assert_eq(screen.get_viewport_rect().size, Vector2(720, 1280), "the screen has the phone base size (project.godot)")
	return screen


func _close(screen: Control) -> void:
	screen.queue_free()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.get_node("GameState").progress = _saved_progress
	tree.root.size = _saved_window_size


## Each button can be scrolled fully into view, and no control between the scroll area and the cards stops a touch.
func _check_reachable(screen: Control, buttons: Array, where: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scroll: ScrollContainer = _find_scroll(screen)
	assert_true(scroll != null, "%s scrolls" % where)
	if scroll == null:
		return
	assert_true(scroll.get_v_scroll_bar().max_value > scroll.size.y, "%s: the content is taller than the screen, so scrolling matters" % where)
	for button in buttons:
		scroll.ensure_control_visible(button)
		await tree.process_frame
		assert_true(scroll.get_global_rect().grow(1).encloses(button.get_global_rect()),
				"%s: «%s» can be scrolled into view" % [where, button.text.replace("\n", " ")])
	for blocker in _touch_blockers(scroll):
		failures.append("%s: %s stops a finger drag (mouse_filter STOP inside the scroll area)" % [where, blocker.get_path()])


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for child in node.get_children():
		var found := _find_scroll(child)
		if found != null:
			return found
	return null


func _touch_blockers(node: Node) -> Array:
	var result := []
	for child in node.get_children():
		if child is Control and not child is ScrollBar:
			if child.mouse_filter == Control.MOUSE_FILTER_STOP:
				result.append(child)
			result.append_array(_touch_blockers(child))
	return result
