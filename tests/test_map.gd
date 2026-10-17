## M9: the chapter map is the painted map scaled to the screen height, the stages stand on their points of the trail,
## the beast packs off it. On a tall and a short phone every marker is on the screen, between the paper bars, and no
## two markers overlap; the stage states, the red recommended power and the three looks of a pack are shown.
## M11: two chapters; the map opens on the current one, the arrows switch, an arrow to a closed chapter is dimmed.
extends "res://tests/base_test.gd"

const Progress := preload("res://scripts/save/progress.gd")
const MAP_SCENE := "res://scenes/map.tscn"
const PHONE_SIZE := Vector2i(720, 1558)  ## iPhone 14 shape at the project's 720 px width
const BASE_SIZE := Vector2i(720, 1280)  ## project.godot viewport (a shorter phone)

var _saved_progress
var _saved_window_size: Vector2i


## The tap areas reach 96 px (spec) and may overlap a little on a short screen; a tap on a token or a caption still
## lands on its own marker (the topmost button under the finger).
func test_markers_fit_the_screen_without_overlapping() -> void:
	for window in [PHONE_SIZE, BASE_SIZE]:
		for shown in [[0, 1], [4, 1], [10, 1], [10, 2], [14, 2], [17, 2], [20, 2]]:
			var cleared: int = shown[0]
			var screen = await _open_map(window, cleared, ["wolves", "ironwood_wolves"])
			screen.show_chapter(shown[1])
			await (Engine.get_main_loop() as SceneTree).process_frame
			var where := "%s, chapter %d, %d stages won" % [window, shown[1], cleared]
			var screen_rect: Rect2 = screen.get_viewport_rect()
			var free_area := Rect2(0, screen.get_node("%TopBar").get_global_rect().end.y, screen_rect.size.x,
					screen.get_node("%BottomBar").get_global_rect().position.y - screen.get_node("%TopBar").get_global_rect().end.y)
			var drawn := []
			for marker in screen._markers:
				var button: Button = marker["button"]
				assert_true(button.get_global_rect().size.y >= 96.0 - 0.01, "%s: %s can be tapped, at least 96 px tall (%s)" % [
						where, _name(marker), button.get_global_rect().size.y])
				var parts: Array[Rect2] = [marker["caption"].get_global_rect()]
				if marker["token"].visible:
					parts.append(marker["token"].get_global_rect())
				for part in parts:
					assert_true(free_area.encloses(part), "%s: %s is on the screen between the bars (%s)" % [where, _name(marker), part])
					for other in drawn:
						assert_true(not other[1].intersects(part), "%s: %s and %s overlap" % [where, other[0], _name(marker)])
					assert_true(_marker_at(screen, part.get_center()) == marker, "%s: a tap on %s reaches it" % [where, _name(marker)])
				for part in parts:
					drawn.append([_name(marker), part])
				var token: Control = marker["token"]
				if token.visible:
					var center: Vector2 = token.get_global_rect().get_center()
					assert_near(center.distance_to(screen.map_point_on_screen(marker["point"])), 0.0, 1.5,
							"%s: %s stands on its map point" % [where, _name(marker)])
			_close(screen)


func test_the_map_fills_the_screen_height() -> void:
	for window in [PHONE_SIZE, BASE_SIZE]:
		var screen = await _open_map(window, 0, [])
		var picture: Control = screen.get_node("%MapPicture")
		assert_near(picture.size.y, window.y, 0.5, "%s: the map is as tall as the screen" % window)
		assert_true(picture.size.x > window.x, "%s: the sides are cut off" % window)
		assert_near(picture.position.x + picture.size.x / 2.0, window.x / 2.0, 0.5, "%s: the map is centred" % window)
		_close(screen)


func test_stage_states_and_red_recommended_power() -> void:
	var screen = await _open_map(PHONE_SIZE, 4, [])
	var progress = screen.get_node("/root/GameState").progress
	var data = screen.get_node("/root/GameState").data
	for stage_id in screen._stage_buttons:
		var button: Button = screen._stage_buttons[stage_id]
		assert_eq(button.disabled, stage_id > 5, "stage %d: open up to the next stage" % stage_id)
		var text := _texts(button)
		if stage_id <= 4:
			assert_true("пройден" in text, "stage %d is marked won" % stage_id)
		elif stage_id == 5:
			assert_true("в бой!" in text, "stage 5 is the next battle")
		var number: Label = button.find_child("RecommendedPower", true, false)
		assert_eq(number.text, str(data.recommended_power(stage_id)), "stage %d: recommended power" % stage_id)
		var red: bool = number.get_theme_color("font_color") == screen.TOO_WEAK_COLOR
		assert_eq(red, progress.is_below_recommended(data, stage_id), "stage %d: red only while the squad is weaker" % stage_id)
	assert_true(data.get_enemy("draugr_king")["name"] in _texts(screen._stage_buttons[10]), "the boss is named")
	assert_eq(screen._stage_buttons.keys(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "only chapter 1's stages")
	_close(screen)


## M11: the map opens on the chapter of the next stage to win (the last chapter once everything is won); chapter 2
## opens with the first win on stage 10; the arrows switch between open chapters, an arrow to a closed chapter is
## dimmed and does nothing, there is no arrow where there is no chapter.
func test_two_chapters_and_the_switch() -> void:
	var screen = await _open_map(PHONE_SIZE, 9, [])
	assert_eq(screen.shown_chapter(), 1, "chapter 1 while stage 10 is not won")
	assert_eq(screen.get_node("%Title").text, "Глава 1 · Мидгард", "its title")
	assert_true(screen._next_arrow.disabled and screen._next_arrow.modulate.a > 0.0, "the arrow to chapter 2 is there but dimmed")
	assert_true(screen._previous_arrow.modulate.a == 0.0, "no arrow back from chapter 1")
	screen.show_chapter(2)
	assert_eq(screen.shown_chapter(), 1, "a closed chapter does not open")
	_close(screen)

	screen = await _open_map(PHONE_SIZE, 10, [])
	var data = screen.get_node("/root/GameState").data
	assert_eq(screen.shown_chapter(), 2, "after the first win over the draugr king: chapter 2")
	assert_eq(screen.get_node("%Title").text, "Глава 2 · Ётунхейм", "its title")
	assert_eq(screen._stage_buttons.keys(), data.chapter_stage_ids(2), "stages 11–20")
	assert_true("Этап 11 · в бой!" in _texts(screen._stage_buttons[11]), "the numbers go on")
	assert_eq(screen._pack_markers.keys(), data.pack_ids(2), "Jotunheim's packs")
	assert_true(data.get_enemy("thjazi")["name"] in _texts(screen._stage_buttons[20]), "Thjazi is named on stage 20")
	var crown = load("res://scripts/ui/map_screen.gd").CrownIcon
	assert_true(screen._stage_buttons[20].find_children("*", "Control", true, false).any(func(node): return is_instance_of(node, crown)),
			"with a crown")
	assert_true(not screen._previous_arrow.disabled, "the arrow back to chapter 1 works")
	assert_true(screen._next_arrow.modulate.a == 0.0, "there is no chapter 3 yet")
	screen._previous_arrow.pressed.emit()
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_eq(screen.shown_chapter(), 1, "back to Midgard")
	assert_eq(screen._stage_buttons.keys(), data.chapter_stage_ids(1), "its stages, all can be replayed")
	assert_true(screen._stage_buttons.values().all(func(button): return not button.disabled), "every won stage opens")
	assert_eq(screen._pack_markers.keys(), data.pack_ids(1), "Midgard's packs stay on its map")
	screen._next_arrow.pressed.emit()
	assert_eq(screen.shown_chapter(), 2, "and forward again")
	_close(screen)

	screen = await _open_map(PHONE_SIZE, 20, [])
	assert_eq(screen.shown_chapter(), 2, "everything won: the last chapter")
	_close(screen)


func test_pack_looks_ready_away_locked() -> void:
	var screen = await _open_map(PHONE_SIZE, 4, ["wolves"])
	var wolves: Dictionary = screen._pack_markers["wolves"]
	assert_eq(wolves["state"], "away", "the beaten wolves are away")
	assert_true(not wolves["token"].visible, "no portrait while away")
	assert_true(wolves["button"].disabled, "an away pack cannot be fought")
	assert_eq(wolves["status"].text, "через 2:00", "the timer where the pack stood")
	var boars: Dictionary = screen._pack_markers["boars"]
	assert_eq(boars["state"], "ready", "the boars are on the map after stage 3")
	assert_true(boars["token"].visible and not boars["button"].disabled, "a ready pack shows its beast and can be tapped")
	var bear: Dictionary = screen._pack_markers["bear"]
	assert_eq(bear["state"], "locked", "the bear waits for stage 6")
	assert_true(bear["button"].disabled, "a locked pack cannot be fought")
	assert_eq(bear["status"].text, "после этапа 6", "it says when it opens")
	# Skipping the time (debug panel) brings the wolves back without leaving the map.
	screen.get_node("/root/GameState").progress.skip_pack_timers(screen.get_node("/root/GameState").data.pack_respawn_seconds())
	screen._refresh_packs()
	assert_eq(wolves["state"], "ready", "the wolves are back")
	assert_true(wolves["token"].visible, "with the portrait")
	_close(screen)


func test_clock_text() -> void:
	var map_script = load("res://scripts/ui/map_screen.gd")
	assert_eq(map_script.clock_text(7200), "2:00", "two hours")
	assert_eq(map_script.clock_text(84 * 60), "1:24", "an hour and 24 minutes")
	assert_eq(map_script.clock_text(84 * 60 - 30), "1:24", "rounded up to a whole minute")
	assert_eq(map_script.clock_text(59), "0:01", "the last minute is not 0:00")


# --- helpers -----------------------------------------------------------------

## The map with `cleared` stages won and the packs in `beaten` just beaten.
func _open_map(window: Vector2i, cleared: int, beaten: Array) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	_saved_progress = game_state.progress
	var progress = Progress.new_game(game_state.data)
	if cleared > 0:
		progress.jump_to_stage(game_state.data, cleared + 1)
		progress.cleared_stage = cleared
	for pack_id in beaten:
		progress.apply_pack_victory(game_state.data, pack_id, game_state.now())
	progress.mark_all_scenes_seen(game_state.data)  # no saga scene over the map
	game_state.progress = progress
	_saved_window_size = tree.root.size
	tree.root.size = window
	var screen: Control = load(MAP_SCENE).instantiate()
	tree.root.add_child(screen)
	for i in 3:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.queue_free()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.get_node("GameState").progress = _saved_progress
	tree.root.size = _saved_window_size


## The marker whose button a tap at `point` reaches: the topmost one (the last child of the board) under the finger.
func _marker_at(screen: Control, point: Vector2):
	var found = null
	for marker in screen._markers:
		if marker["button"].get_global_rect().has_point(point) and (found == null
				or marker["button"].get_index() > found["button"].get_index()):
			found = marker
	return found


func _texts(node: Node) -> String:
	return " ".join(node.find_children("*", "Label", true, false).map(func(label): return label.text))


func _name(marker: Dictionary) -> String:
	return _texts(marker["button"]).left(24)
