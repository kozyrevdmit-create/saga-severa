## M14: the beginner's tutorial (data/tutorial.json, scripts/ui/tutorial_hint.gd). Twelve hints, each once per game at
## its moment, one at a time, word for word from docs/TUTORIAL_M14.md; the battle stands still under a hint; the defeat
## hint gives way to a tip of hints.json; an old save that has passed stage 1 has no tutorial (but the settlement's hint
## while construction is open); the old target mark hint counts as hint 5; «Сбросить обучение» shows them again;
## «Как играть» in «Настройки» lists them; the chapter map shows the chapter's goal.
extends "res://tests/base_test.gd"

const Progress := preload("res://scripts/save/progress.gd")
const TutorialHint := preload("res://scripts/ui/tutorial_hint.gd")
const SettingsScreen := preload("res://scripts/ui/settings_screen.gd")
const TUTORIAL_MD := "res://docs/TUTORIAL_M14.md"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const MAP_SCENE := "res://scenes/map.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const FORMATION_SCENE := "res://scenes/formation.tscn"
const SETTLEMENT_SCENE := "res://scenes/settlement.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const PHONE_812 := Vector2i(720, 1559)  ## 375×812 (the size the texts must fit, TUTORIAL_M14.md) at the 720 px width
const BASE_SIZE := Vector2i(720, 1280)  ## project.godot viewport (a shorter phone)
const HINTS := ["open_map", "pick_stage", "auto_battle", "ultimate", "mark_target", "silver", "beast_pack",
	"recommended_power", "formation_rows", "auto_and_speed", "defeat", "build"]

var _saved_progress
var _saved_window_size: Vector2i


# --- texts ----------------------------------------------------------------------

## The twelve hints of the table in TUTORIAL_M14.md (approved by Dmitriy), in its order, word for word.
func test_texts_match_tutorial_md_word_for_word() -> void:
	var data = await _data()
	var md := FileAccess.get_file_as_string(TUTORIAL_MD)
	assert_true(md.contains("утверждено Дмитрием"), "TUTORIAL_M14.md is approved by Dmitriy")
	var expected := _table_column(md, "## 1. Подсказки обучения", 4)
	assert_eq(expected.size(), 12, "twelve hints in TUTORIAL_M14.md")
	assert_eq(data.tutorial_hint_ids(), HINTS, "twelve hints in tutorial.json, in the table's order")
	for i in mini(expected.size(), data.tutorial_hint_ids().size()):
		assert_eq(data.get_tutorial_hint(data.tutorial_hint_ids()[i])["text"], expected[i], "hint %d: text" % (i + 1))
	assert_eq(data.tutorial_text("got_it"), "Понятно", "the button")
	assert_eq(data.tutorial_text("how_to_play"), "Как играть", "the settings item")


## «Цель: …» under the chapter's name: stages.json → chapters[].goal, word for word from TUTORIAL_M14.md (section 2).
func test_chapter_goals_match_tutorial_md() -> void:
	var data = await _data()
	var goals := _table_column(FileAccess.get_file_as_string(TUTORIAL_MD), "## 2. Цель главы", 2)
	assert_eq(goals.size(), data.chapter_ids().size(), "a goal for every chapter")
	for i in mini(goals.size(), data.chapter_ids().size()):
		assert_eq(data.get_chapter(data.chapter_ids()[i])["goal"], goals[i], "chapter %d: goal" % (i + 1))


# --- rules (Progress) -------------------------------------------------------------

## A new player's way, moment by moment: each hint comes at its moment, once; at a moment only the first due hint
## shows, the next one waits for its own next moment.
func test_each_hint_comes_at_its_moment_once() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	var now := 1_000_000
	_expect_due(progress, data, "main_menu", "open", {}, ["open_map"], "1: the first main screen")
	_show(progress, "open_map")
	_expect_due(progress, data, "main_menu", "open", {}, [], "the main screen again: nothing before the first win")
	_expect_due(progress, data, "map", "open", {"now": now}, ["pick_stage"], "2: the first map (the wolves wait for a win)")
	_show(progress, "pick_stage")
	var before: Array[String] = progress.tutorial_shown.duplicate()
	_expect_due(progress, data, "battle", "start", {"shown_before": before}, ["auto_battle"], "3: the first battle")
	_show(progress, "auto_battle")
	_expect_due(progress, data, "battle", "start", {"shown_before": before}, [], "not twice in the same battle")
	_expect_due(progress, data, "battle", "ultimate_ready", {}, ["ultimate"], "4: the first ultimate charged")
	_show(progress, "ultimate")
	progress.apply_victory(data, 1)
	_expect_due(progress, data, "map", "open", {"now": now, "shown_before": progress.tutorial_shown.duplicate()},
			["beast_pack"], "7: the map with a pack after the first win")
	_show(progress, "beast_pack")
	before = progress.tutorial_shown.duplicate()
	_expect_due(progress, data, "battle", "start", {"shown_before": before}, ["mark_target"], "5: the second battle")
	_show(progress, "mark_target")
	_expect_due(progress, data, "main_menu", "open", {}, ["silver"], "6: the main screen after the first win")
	_show(progress, "silver")
	_expect_due(progress, data, "formation", "open", {}, ["formation_rows"], "9: the first «Отряд»")
	_show(progress, "formation_rows")
	_expect_due(progress, data, "map", "open", {"now": now, "shown_before": progress.tutorial_shown.duplicate()},
			["recommended_power"], "8: the next map after hint 7")
	_show(progress, "recommended_power")
	_expect_due(progress, data, "battle", "start", {"shown_before": progress.tutorial_shown.duplicate()},
			["auto_and_speed"], "10: the third battle")
	_show(progress, "auto_and_speed")
	_expect_due(progress, data, "battle", "defeat", {"defeat_tip": true}, [], "11 gives way to a tip of hints.json")
	_expect_due(progress, data, "battle", "defeat", {"defeat_tip": false}, ["defeat"], "11: a defeat without a tip")
	_show(progress, "defeat")
	_expect_due(progress, data, "settlement", "open", {}, [], "12: not while construction is closed")
	progress.jump_to_stage(data, 11)
	_expect_due(progress, data, "settlement", "open", {}, [], "12: not before «Зерно нового мира»")
	progress.start_scene("settlement_intro")
	_expect_due(progress, data, "settlement", "open", {}, ["build"], "12: after the settlement's scene")
	_show(progress, "build")
	assert_eq(progress.tutorial_shown.size(), 12, "all twelve")
	assert_true(HINTS.all(func(hint_id): return progress.is_tutorial_hint_shown(hint_id)), "each of them")
	for screen in ["main_menu", "map", "battle", "formation", "settlement"]:
		for moment in ["open", "start", "ultimate_ready", "defeat"]:
			_expect_due(progress, data, screen, moment, {"now": now, "shown_before": HINTS}, [], "%s %s: no hint twice" % [screen, moment])


## Hint 7 needs a pack that can be fought now: while every pack of the chapter is away, it waits.
func test_the_pack_hint_waits_for_a_pack_on_the_map() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.apply_victory(data, 1)
	var now := 1_000_000
	progress.apply_pack_victory(data, "wolves", now)
	_expect_due(progress, data, "map", "open", {"now": now}, ["pick_stage"], "the wolves are away: no pack hint")
	_show(progress, "pick_stage")
	_expect_due(progress, data, "map", "open", {"now": now + 3 * 3600}, ["beast_pack"], "the wolves are back")


## A save from before M14 that has passed stage 1 has no tutorial: every hint counts as shown. A save that has not won
## a stage yet gets the whole tutorial.
func test_an_old_save_past_stage_one_has_no_tutorial() -> void:
	var data = await _data()
	var old: Dictionary = _old_save(data, 5)
	var progress = Progress.from_dict(old, data)
	assert_eq(progress.tutorial_shown, HINTS, "stage 5: every hint counts as shown")
	var fresh = Progress.from_dict(_old_save(data, 0), data)
	assert_eq(fresh.tutorial_shown, [] as Array[String], "no stage won yet: the whole tutorial")


## …but with construction open the settlement's hint is still due once (the settlement has not been opened since
## the update).
func test_an_old_save_with_construction_open_keeps_the_settlement_hint() -> void:
	var data = await _data()
	var progress = Progress.from_dict(_old_save(data, 24), data)
	var expected: Array[String] = []
	for hint_id in HINTS:
		if hint_id != "build":
			expected.append(hint_id)
	assert_eq(progress.tutorial_shown, expected, "every hint but the settlement's")
	progress.start_scene("settlement_intro")
	_expect_due(progress, data, "settlement", "open", {}, ["build"], "the settlement's hint on the next visit")
	var again = Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())), data)
	assert_true(not again.is_tutorial_hint_shown("build"), "a new save keeps its flags as they are (no second migration)")


## M6.1's mark hint (mark_hint_shown) is hint 5 now: shown there, shown here; a broken flag counts as not shown.
func test_the_old_mark_hint_counts_as_hint_five() -> void:
	var data = await _data()
	var old: Dictionary = _old_save(data, 0)
	old["mark_hint_shown"] = true
	assert_eq(Progress.from_dict(old, data).tutorial_shown, ["mark_target"] as Array[String], "hint 5 counts as shown")
	old["mark_hint_shown"] = "yes"
	assert_eq(Progress.from_dict(old, data).tutorial_shown, [] as Array[String], "a broken flag: not shown")
	assert_true(not Progress.new_game(data).to_dict().has("mark_hint_shown"), "the old flag is not saved any more")


## The flags are saved (unknown ids dropped); «Сбросить прогресс» starts the tutorial again; «Сбросить обучение» too,
## but keeps the progress.
func test_flags_are_saved_and_both_resets_start_the_tutorial_again() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.apply_victory(data, 1)
	_show(progress, "open_map")
	_show(progress, "silver")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(progress.to_dict()))
	assert_eq(saved["tutorial_shown"], ["open_map", "silver"], "in the save")
	saved["tutorial_shown"] = ["silver", "no_such_hint", 5]
	assert_eq(Progress.from_dict(saved, data).tutorial_shown, ["silver"] as Array[String], "unknown ids are dropped")
	progress.reset_tutorial()
	assert_eq(progress.tutorial_shown, [] as Array[String], "«Сбросить обучение»: every hint is due again")
	assert_eq(progress.cleared_stage, 1, "the progress stays")
	_show(progress, "open_map")
	progress.reset(data, 1000)
	assert_eq(progress.tutorial_shown, [] as Array[String], "«Сбросить прогресс»: the tutorial starts again")


## The debug panel's «Сбросить обучение» (GameState.debug_reset_tutorial) on a save of chapter 3.
func test_the_debug_panel_resets_the_tutorial() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.jump_to_stage(data, 25)
	progress.mark_all_scenes_seen(data)
	progress.finish_tutorial(data)
	var game_state = _use(progress, BASE_SIZE)
	var screen: Control = load(MAIN_MENU_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	await _frames(3)
	var panel: Control = screen.get_node("%DebugPanel")
	panel.open()
	var button: Button = panel.get_node("%ResetTutorialButton")
	assert_eq(button.text, "Сбросить обучение", "the button")
	button.pressed.emit()
	assert_eq(game_state.progress.tutorial_shown, [] as Array[String], "every hint is due again")
	assert_eq(game_state.progress.cleared_stage, 24, "the stages stay")
	assert_true(not TutorialHint.is_on(screen), "no hint while the panel is open")
	panel.close()
	await _frames(3)
	var hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "open_map", "once the panel is closed, hint 1 is on the main screen")
	screen.queue_free()
	_restore()


# --- screens ----------------------------------------------------------------------

## Main screen: hint 1 points at «Карта главы», hint 6 at «Герои»; only one per visit; a tap beside the window does
## nothing; «Понятно» closes it.
func test_the_main_screen_shows_one_hint_per_visit() -> void:
	var data = await _data()
	for window in [PHONE_812, BASE_SIZE]:
		var progress = _beginner(data)
		progress.apply_victory(data, 1)  # hint 6 is due too, but waits for the next visit
		progress.mark_all_scenes_seen(data)
		var game_state = _use(progress, window)
		var screen = await _open(MAIN_MENU_SCENE)
		var hint = _hint_on(screen)
		assert_true(hint != null and hint.hint_id == "open_map", "%s: hint 1" % window)
		if hint == null:
			screen.queue_free()
			continue
		_check_overlay(hint, [screen.get_node("%MapButton")], "%s: hint 1" % window)
		assert_eq(hint.text(), "Открой карту — там этапы саги.", "the text")
		var pressed := [0]
		screen.get_node("%MapButton").pressed.connect(func(): pressed[0] += 1)
		await _tap(screen.get_node("%MapButton").get_global_rect().get_center())
		assert_eq(pressed[0], 0, "%s: a tap on the button under the hint does nothing" % window)
		await _tap(Vector2(window.x / 2.0, 4.0))
		assert_true(TutorialHint.is_on(screen), "%s: a tap beside the window does not close it" % window)
		hint.press_button()
		await _frames(2)
		assert_true(not TutorialHint.is_on(screen), "%s: «Понятно» closes it" % window)
		assert_true(game_state.progress.is_tutorial_hint_shown("open_map"), "saved as shown")
		assert_true(not game_state.progress.is_tutorial_hint_shown("silver"), "%s: hint 6 waits" % window)
		screen.queue_free()
		await _frames(1)
		screen = await _open(MAIN_MENU_SCENE)
		hint = _hint_on(screen)
		assert_true(hint != null and hint.hint_id == "silver", "%s: hint 6 on the next visit" % window)
		if hint != null:
			_check_overlay(hint, [screen.get_node("%HeroesButton")], "%s: hint 6" % window)
		screen.queue_free()
		await _frames(1)
		_restore()


## No hint over the intro: hint 1 comes once the intro is over.
func test_hint_one_comes_after_the_intro() -> void:
	var data = await _data()
	_use(Progress.new_game(data), BASE_SIZE)
	var screen = await _open(MAIN_MENU_SCENE)
	assert_true(not TutorialHint.is_on(screen), "the intro first")
	var player: Control = screen.get_children().filter(func(child): return child.get("scene_id") == "intro")[0]
	player.close()
	await _frames(3)
	var hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "open_map", "hint 1 after the intro")
	screen.queue_free()
	_restore()


## The map: hint 2 on the first stage, then (after the first win) hint 7 on the wolves, then hint 8 on the stage's caption.
func test_the_map_hints() -> void:
	var data = await _data()
	var progress = _beginner(data)
	_show(progress, "open_map")
	_use(progress, PHONE_812)
	var screen = await _open(MAP_SCENE)
	var hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "pick_stage", "hint 2")
	if hint != null:
		_check_overlay(hint, [screen._stage_markers[1]["token"]], "hint 2")
	screen.queue_free()
	await _frames(1)
	progress.apply_victory(data, 1)
	screen = await _open(MAP_SCENE)
	hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "beast_pack", "hint 7")
	if hint != null:
		_check_overlay(hint, [screen._pack_markers["wolves"]["token"]], "hint 7")
		hint.press_button()
	await _frames(2)
	assert_true(not TutorialHint.is_on(screen), "hint 8 waits for the next opening of the map")
	screen.queue_free()
	await _frames(1)
	screen = await _open(MAP_SCENE)
	hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "recommended_power", "hint 8")
	if hint != null:
		_check_overlay(hint, [screen._stage_markers[2]["caption"]], "hint 8")
	screen.queue_free()
	_restore()


## The battle stands still under a hint and goes on after «Понятно»; the start hints of the first three battles.
func test_the_battle_stands_still_under_a_hint() -> void:
	var data = await _data()
	var progress = _beginner(data)
	for hint_id in ["open_map", "pick_stage"]:
		_show(progress, hint_id)
	var game_state = _use(progress, PHONE_812)
	var expected := ["auto_battle", "mark_target", "auto_and_speed", ""]
	for battle_number in expected.size():
		game_state.selected_stage = 1
		game_state.selected_pack = ""
		var screen = await _open(BATTLE_SCENE)
		var hint = _hint_on(screen)
		var where := "battle %d" % (battle_number + 1)
		if expected[battle_number] == "":
			assert_true(hint == null, "%s: no start hint" % where)
			screen.queue_free()
			await _frames(1)
			continue
		assert_true(hint != null and hint.hint_id == expected[battle_number], "%s: %s" % [where, expected[battle_number]])
		if hint == null:
			screen.queue_free()
			continue
		match hint.hint_id:
			"auto_battle":
				_check_overlay(hint, [screen.get_node("%Field")], where)
			"mark_target":
				_check_overlay(hint, [screen._views[screen._battle.enemies()[0].id]], where)
			"auto_and_speed":
				_check_overlay(hint, [screen.get_node("%AutoButton"), screen.get_node("%SpeedButton")], where)
		var time: float = screen._battle.time
		for i in 5:
			screen._process(1.0)
		assert_eq(screen._battle.time, time, "%s: the battle stands still under the hint" % where)
		hint.press_button()
		await _frames(1)
		screen._process(1.0)
		assert_true(screen._battle.time > time, "%s: and goes on after «Понятно»" % where)
		screen.queue_free()
		await _frames(1)
	_restore()


## Hint 4 the first time a hero's ultimate is charged, pointing at that hero's card; the battle stands still.
func test_the_ultimate_hint_points_at_the_glowing_card() -> void:
	var data = await _data()
	var progress = _beginner(data)
	progress.finish_tutorial(data)
	progress.tutorial_shown.erase("ultimate")
	var game_state = _use(progress, PHONE_812)
	game_state.selected_stage = 1
	var screen = await _open(BATTLE_SCENE)
	assert_true(not TutorialHint.is_on(screen), "no start hint in this battle")
	var hero = screen._battle.heroes()[1]
	hero.energy = hero.ultimate_cost()
	screen._process(0.0)
	var hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "ultimate", "hint 4")
	if hint != null:
		await _frames(2)
		_check_overlay(hint, [screen._cards[hero.id]], "hint 4")
		var time: float = screen._battle.time
		screen._process(1.0)
		assert_eq(screen._battle.time, time, "the battle stands still")
	screen.queue_free()
	_restore()


## Hint 11 after a defeat without a tip, pointing at «На карту»; after a defeat with a tip of hints.json (cave spiders)
## the tip is shown as before and hint 11 waits.
func test_the_defeat_hint_gives_way_to_a_tip() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.jump_to_stage(data, 21)  # stage 21: cave spiders → a tip
	progress.mark_all_scenes_seen(data)
	progress.finish_tutorial(data)
	progress.tutorial_shown.erase("defeat")
	var game_state = _use(progress, PHONE_812)
	game_state.selected_stage = 21
	game_state.selected_pack = ""
	var screen = await _open(BATTLE_SCENE)
	await _retreat(screen)
	assert_true(screen.get_node("%ResultHint").text.contains("Совет: пауки"), "the spiders' tip")
	assert_true(not TutorialHint.is_on(screen), "no hint 11 with a tip")
	assert_true(not progress.is_tutorial_hint_shown("defeat"), "hint 11 waits")
	screen.queue_free()
	await _frames(1)
	game_state.selected_stage = 1
	screen = await _open(BATTLE_SCENE)
	await _retreat(screen)
	var hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "defeat", "hint 11 after a defeat without a tip")
	if hint != null:
		await _frames(2)
		_check_overlay(hint, [screen.get_node("%MenuButton")], "hint 11")
	screen.queue_free()
	_restore()


## «Отряд»: hint 9 on the front row, the first time.
func test_the_formation_hint() -> void:
	var data = await _data()
	_use(_beginner(data), BASE_SIZE)
	var screen = await _open(FORMATION_SCENE)
	var hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "formation_rows", "hint 9")
	if hint != null:
		_check_overlay(hint, [screen.get_node("%FrontRow")], "hint 9")
	screen.queue_free()
	await _frames(1)
	screen = await _open(FORMATION_SCENE)
	assert_true(not TutorialHint.is_on(screen), "once")
	screen.queue_free()
	_restore()


## The settlement: hint 12 after «Зерно нового мира», pointing at an empty plot.
func test_the_settlement_hint_comes_after_its_scene() -> void:
	var data = await _data()
	var progress = _beginner(data)
	progress.jump_to_stage(data, 11)
	progress.mark_all_scenes_seen(data)
	progress.seen_scenes.erase("settlement_intro")
	_use(progress, PHONE_812)
	var screen = await _open(SETTLEMENT_SCENE)
	var players: Array = screen.get_children().filter(func(child): return child.get("scene_id") == "settlement_intro")
	assert_eq(players.size(), 1, "the scene first")
	assert_true(not TutorialHint.is_on(screen), "no hint over the scene")
	if not players.is_empty():
		players[0].close()
	await _frames(3)
	var hint = _hint_on(screen)
	assert_true(hint != null and hint.hint_id == "build", "hint 12 after the scene")
	if hint != null:
		var first_open: String = data.building_ids().filter(func(id): return progress.is_building_open(data, id))[0]
		_check_overlay(hint, [screen._buildings[first_open]["caption"]], "hint 12")
	screen.queue_free()
	_restore()


## Every hint's window fits the phone (375×812 and the shorter base screen) next to an element at the top, in the
## middle, at the bottom, and over the whole battlefield.
func test_every_window_fits_the_phone() -> void:
	var data = await _data()
	for window in [PHONE_812, BASE_SIZE]:
		var tree := Engine.get_main_loop() as SceneTree
		_use(Progress.new_game(data), window)
		for hint_id in HINTS:
			for target_rect in [Rect2(300, 40, 120, 100), Rect2(40, window.y / 2.0 - 60, 640, 120),
					Rect2(260, window.y - 140, 200, 104), Rect2(0, 180, 720, window.y - 480)]:
				var screen := Control.new()
				screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				tree.root.add_child(screen)
				var target := Control.new()
				target.position = target_rect.position
				target.size = target_rect.size
				screen.add_child(target)
				var hint = _force(screen, data, hint_id, target)
				assert_true(hint != null, "%s: shown" % hint_id)
				if hint != null:
					await _frames(2)
					_check_overlay(hint, [target], "%s %s at %s" % [window, hint_id, target_rect])
				screen.queue_free()
		_restore()


## «Как играть» in «Настройки»: the twelve texts in order, then «Роли героев» with the four roles.
func test_how_to_play_lists_every_hint_and_the_roles() -> void:
	var data = await _data()
	_use(Progress.new_game(data), BASE_SIZE)
	var screen = await _open(SETTINGS_SCENE)
	assert_eq(screen.get_node("%HowToButton").text, "Как играть", "the item next to «Сцены саги»")
	assert_eq(screen.get_node("%HowToButton").get_index(), screen.get_node("%ScenesButton").get_index() + 1, "right under it")
	screen.open_how_to()
	await _frames(2)
	var texts: Array = screen.get_node("%HowToList").get_children().map(func(label): return label.text)
	var expected: Array = HINTS.map(func(hint_id): return data.get_tutorial_hint(hint_id)["text"])
	expected.append_array(["Роли героев", "Танк — Стоит впереди и принимает удары на себя.",
		"Урон — Главная сила дружины — бьёт врагов.", "Лекарь — Лечит дружину в бою.",
		"Поддержка — Сам бьёт слабо, но делает сильнее всю дружину."])
	assert_eq(texts, expected, "every text, then the roles")
	assert_true(screen.get_node("%HowToOverlay").visible, "on the screen")
	assert_true(not TutorialHint.is_on(screen), "no fingers or dimming")
	screen.get_node("%HowToBackButton").pressed.emit()
	assert_true(not screen.get_node("%HowToOverlay").visible, "«Назад» closes it")
	screen.queue_free()
	_restore()


## The map shows the chapter's goal under «Глава N · Название», in a smaller font, on one line.
func test_the_map_shows_the_chapters_goal() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.jump_to_stage(data, 30)
	progress.mark_all_scenes_seen(data)
	progress.finish_tutorial(data)
	_use(progress, PHONE_812)
	var screen = await _open(MAP_SCENE)
	for chapter_id in data.chapter_ids():
		screen.show_chapter(chapter_id)
		await _frames(2)
		var goal: Label = screen.get_node("%GoalLabel")
		var title: Label = screen.get_node("%Title")
		assert_eq(goal.text, data.get_chapter(chapter_id)["goal"], "chapter %d: the goal" % chapter_id)
		assert_eq(goal.get_index(), title.get_index() + 1, "right under the title")
		assert_true(goal.get_theme_font_size("font_size") < title.get_theme_font_size("font_size"), "smaller")
		assert_eq(goal.get_line_count(), 1, "chapter %d: one line" % chapter_id)
	screen.queue_free()
	_restore()


# --- helpers ----------------------------------------------------------------------

## The cells of `column` (1-based) of the table under `heading`, without the «» around them.
static func _table_column(md: String, heading: String, column: int) -> Array:
	var cells := []
	var inside := false
	for line in md.split("\n"):
		if line.begins_with("## "):
			inside = line.begins_with(heading)
		elif inside and line.begins_with("|") and not line.begins_with("|---"):
			var cell: String = line.split("|")[column].strip_edges()
			if cell.begins_with("«") and cell.ends_with("»"):
				cells.append(cell.substr(1, cell.length() - 2))
	return cells


func _expect_due(progress, data, screen: String, moment: String, facts: Dictionary, expected: Array, message: String) -> void:
	var due: Array[String] = progress.tutorial_hints_due(data, screen, moment, facts)
	var first: Array[String] = []
	first.assign(expected)
	assert_eq(due.slice(0, 1), first, message)


func _show(progress, hint_id: String) -> void:
	progress.show_tutorial_hint(hint_id)


## A save as written before M14 (no tutorial flags) with `cleared` stages won.
func _old_save(data, cleared: int) -> Dictionary:
	var progress = Progress.new_game(data)
	if cleared > 0:
		progress.jump_to_stage(data, cleared + 1)
	var saved: Dictionary = progress.to_dict()
	saved.erase("tutorial_shown")
	return JSON.parse_string(JSON.stringify(saved))


## A new game with the intro seen (so that no scene plays over the screens).
func _beginner(data):
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	return progress


## Shows the hint over `screen` whatever its conditions (for the size checks).
func _force(screen: Control, data, hint_id: String, target: Control) -> Control:
	for child in screen.get_children():
		if child.is_in_group(TutorialHint.GROUP):
			child.queue_free()
			screen.remove_child(child)
	var overlay = TutorialHint.new()
	overlay.hint_id = hint_id
	overlay._text = data.get_tutorial_hint(hint_id)["text"]
	overlay._button_text = data.tutorial_text("got_it")
	overlay._targets = [target]
	screen.add_child(overlay)
	return overlay


## The hole is around every target, the window is on the screen and (with the arrow) beside the hole, not over it.
func _check_overlay(hint, targets: Array, where: String) -> void:
	var area := Rect2(Vector2.ZERO, hint.size)
	for target in targets:
		var rect: Rect2 = hint.get_global_transform().affine_inverse() * target.get_global_rect()
		assert_true(hint.hole().grow(0.5).encloses(rect.intersection(area)), "%s: the hole is around the element" % where)
	var window: Rect2 = hint.window_rect()
	assert_true(area.grow(0.5).encloses(window), "%s: the window is on the screen (%s in %s)" % [where, window, area])
	if hint.has_arrow():
		assert_true(not window.intersects(hint.hole()), "%s: the window is beside the element" % where)
	else:
		assert_true(hint.hole().size.y > area.size.y * 0.4, "%s: no room beside only for a big element" % where)
	assert_eq(hint.modulate.a, 1.0, "%s: on the screen" % where)


func _hint_on(screen: Node):
	for child in screen.get_children():
		if child.is_in_group(TutorialHint.GROUP) and not child.is_queued_for_deletion():
			return child
	return null


func _retreat(battle: Control) -> void:
	battle.get_node("%RetreatButton").pressed.emit()
	for event in battle._battle.take_events():
		battle._show_event(event)
	await _frames(1)


## A real tap (mouse press and release, as a touch arrives) at `point` of the window.
func _tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		(Engine.get_main_loop() as SceneTree).root.push_input(event)
		await _frames(1)


func _open(path: String) -> Control:
	var screen: Control = load(path).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	await _frames(4)
	return screen


func _frames(count: int) -> void:
	for i in count:
		await (Engine.get_main_loop() as SceneTree).process_frame


func _data():
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	return game_state.data


## Puts `progress` into GameState and the window at `window` for the test (restored by _restore); returns GameState.
func _use(progress, window: Vector2i) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	if _saved_progress == null:
		_saved_progress = game_state.progress
		_saved_window_size = tree.root.size
	game_state.progress = progress
	tree.root.size = window
	return game_state


func _restore() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _saved_progress != null:
		tree.root.get_node("GameState").progress = _saved_progress
		tree.root.size = _saved_window_size
	_saved_progress = null
