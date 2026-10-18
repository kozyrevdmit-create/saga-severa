## Phone-sized screens with all seven heroes (M13: Regin): every hero card can be reached, and a finger dragged over the cards
## scrolls the list (nothing inside the scroll area swallows the touch). M6.2: on the iPhone the 5th and 6th
## heroes could not be reached on «Герои».
## M9.1: the lists move exactly with the finger, glide on after it lifts and stop; a drag that starts on a button
## does not press it (no level-up, no squad change), a plain tap still does.
extends "res://tests/base_test.gd"

const Progress := preload("res://scripts/save/progress.gd")
const HEROES_SCENE := "res://scenes/heroes.tscn"
const FORMATION_SCENE := "res://scenes/formation.tscn"


func test_every_hero_on_the_heroes_screen_can_be_reached() -> void:
	var screen = await _open(HEROES_SCENE, false)
	var buttons: Array = screen._rows.values().map(func(row): return row["button"])
	assert_eq(buttons.size(), 7, "seven hero cards")
	await _check_reachable(screen, buttons, "«Герои»")
	_close(screen)


func test_every_hero_on_the_formation_screen_can_be_reached_with_a_full_bench() -> void:
	var screen = await _open(FORMATION_SCENE, true)
	var buttons: Array = []
	for row in [screen.get_node("%FrontRow"), screen.get_node("%BackRow"), screen.get_node("%Bench")]:
		buttons.append_array(row.get_children().filter(func(c): return c is Button))
	assert_eq(buttons.size(), 2 + 3 + 6, "five slots and six heroes on the bench")
	var bench: Control = screen.get_node("%Bench")
	assert_true(bench.size.x <= screen.get_node("%Scroll").size.x, "the bench wraps instead of widening the screen")
	await _check_reachable(screen, buttons, "«Отряд»")
	_close(screen)


func test_the_heroes_list_follows_the_finger_and_a_drag_does_not_level_up() -> void:
	var screen = await _open(HEROES_SCENE, false)
	var progress = _game_state().progress
	progress.silver = 1000000
	screen._refresh()  # «Улучшить» becomes active
	var hero_id: String = screen._rows.keys()[1]
	var button: Button = screen._rows[hero_id]["button"]
	var level: int = progress.level_of(hero_id)
	assert_true(not button.disabled, "«Улучшить» can be pressed")
	await _check_drag(screen, button, "«Герои»")
	assert_eq(progress.level_of(hero_id), level, "«Герои»: dragging from «Улучшить» does not level the hero up")
	assert_eq(progress.silver, 1000000, "«Герои»: no silver is spent by a drag")
	_close(screen)


func test_a_tap_on_level_up_still_works() -> void:
	var screen = await _open(HEROES_SCENE, false)
	var progress = _game_state().progress
	progress.silver = 1000000
	screen._refresh()  # «Улучшить» becomes active
	var hero_id: String = screen._rows.keys()[1]
	var level: int = progress.level_of(hero_id)
	await _tap(screen._rows[hero_id]["button"])
	assert_eq(progress.level_of(hero_id), level + 1, "a tap on «Улучшить» levels the hero up")
	_close(screen)


func test_the_formation_screen_follows_the_finger_and_a_drag_does_not_change_the_squad() -> void:
	var screen = await _open(FORMATION_SCENE, true)
	var progress = _game_state().progress
	var squad: Array = progress.squad_ids().duplicate()
	var bench_hero: Button = screen.get_node("%Bench").get_children().filter(func(c): return c is Button)[0]
	await _check_drag(screen, bench_hero, "«Отряд»")
	assert_eq(progress.squad_ids(), squad, "«Отряд»: dragging over a hero on the bench does not put them in the squad")
	_close(screen)


func test_after_pulling_past_the_top_the_list_turns_back_with_the_finger() -> void:
	var screen = await _open(HEROES_SCENE, false)
	var tree := Engine.get_main_loop() as SceneTree
	var scroll: ScrollContainer = _find_scroll(screen)
	var bar := scroll.get_v_scroll_bar()
	bar.value = 0.0
	await tree.process_frame
	var was_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var point := scroll.get_global_rect().get_center()
	_push_button(point, true)
	await tree.process_frame
	for i in 4:  # finger down: the list is already at its top and stays
		point.y += 40.0
		_push_motion(point, Vector2(0, 40.0))
		await tree.process_frame
	assert_eq(bar.value, 0.0, "the list does not move past its top")
	point.y -= 30.0
	_push_motion(point, Vector2(0, -30.0))
	await tree.process_frame
	assert_near(bar.value, 30.0, 0.01, "turning the finger back moves the list at once")
	_push_button(point, false)
	await tree.process_frame
	Input.emulate_touch_from_mouse = was_touch
	_close(screen)


func _game_state() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


## Presses on the button, moves the finger in steps, lifts it: while the finger is down the list moves exactly as far
## as the finger; after it lifts the list glides on in the same direction, slower and slower, and stops.
func _check_drag(screen: Control, button: Button, where: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var scroll: ScrollContainer = _find_scroll(screen)
	var bar := scroll.get_v_scroll_bar()
	var room := bar.max_value - bar.page
	assert_true(room > 300.0, "%s: the list has room to scroll (%d)" % [where, room])
	scroll.ensure_control_visible(button)
	await tree.process_frame
	var start := bar.value
	# Finger up (the list moves on) when there is room below, else finger down (the list moves back).
	var direction := 1.0 if start < room / 2.0 else -1.0
	var was_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true  # a phone: the scroll lists take finger drags
	var point := button.get_global_rect().get_center()
	_push_button(point, true)
	await tree.process_frame
	var moved := 0.0
	for step in [12.0, 20.0, 25.0, 30.0, 30.0]:
		point.y -= step * direction
		moved += step
		_push_motion(point, Vector2(0, -step * direction))
		await tree.process_frame
		assert_near(bar.value, start + moved * direction, 0.01, "%s: the list moves exactly with the finger" % where)
	_push_button(point, false)
	var glide = scroll._glide
	assert_true(glide.velocity * direction > 0.0, "%s: after the finger lifts, the list glides on" % where)
	var previous_speed: float = absf(glide.velocity)
	var previous_value := bar.value
	var started := Time.get_ticks_msec()
	while glide.velocity != 0.0 and Time.get_ticks_msec() - started < 5000:
		await tree.process_frame
		if absf(glide.velocity) > previous_speed or (bar.value - previous_value) * direction < 0.0:
			failures.append("%s: the glide only slows down and keeps its direction" % where)
			break
		previous_speed = absf(glide.velocity)
		previous_value = bar.value
	assert_eq(glide.velocity, 0.0, "%s: the glide stops" % where)
	assert_true((bar.value - start) * direction > moved, "%s: the list glided on after the finger lifted" % where)
	await tree.process_frame
	Input.emulate_touch_from_mouse = was_touch


func _tap(button: Button) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var was_touch := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var point := button.get_global_rect().get_center()
	_push_button(point, true)
	await tree.process_frame
	_push_button(point, false)
	await tree.process_frame
	Input.emulate_touch_from_mouse = was_touch


func _push_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = point
	event.global_position = point
	(Engine.get_main_loop() as SceneTree).root.push_input(event)


func _push_motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = point
	event.global_position = point
	event.relative = relative
	(Engine.get_main_loop() as SceneTree).root.push_input(event)


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
				"%s: «%s» can be scrolled into view" % [where, _caption(button)])
	for blocker in _touch_blockers(scroll):
		failures.append("%s: %s stops a finger drag (mouse_filter STOP inside the scroll area)" % [where, blocker.get_path()])


## The button's text, or the text of its labels (hero cards on «Отряд» show a portrait and a label).
func _caption(button: Button) -> String:
	var parts := PackedStringArray([button.text])
	for label in button.find_children("*", "Label", true, false):
		parts.append(label.text)
	return " ".join(parts).replace("\n", " ").strip_edges()


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
