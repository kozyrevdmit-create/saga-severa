## M10: saga scenes of chapter 1 (data/story.json); M11: of chapter 2. The texts are word for word from
## docs/STORY_M10.md and docs/STORY_M11.md; each scene
## is shown once per game at its moment (the intro on a new game and once for an old save, a hero's scene after their
## «Новый герой» window, the boss's scenes before the first battle and after the first win); the debug panel and an
## old save's heroes bring no scenes; «Пропустить» closes the scene; «Сцены саги» in «Настройки» plays seen scenes
## again; «Сбросить прогресс» forgets them. Every line fits a phone screen. M10.1: under every speaker's name a caption
## word for word from docs/LORE.md («6а. Кто есть кто»); a drawn «продолжить» mark blinks once a line is typed out.
## M11: Jotunheim's scene the first time its map is shown (also for an old save), the eagles' scene before the first
## battle with carrion eagles (a stage or a pack), Thjazi's scenes before the first battle on stage 20 and after the
## first win there; Thjazi speaks with his head from the enemy picture.
## M12: «Зерно нового мира» (docs/STORY_M12.md) the first time the settlement is entered with construction open
## (tests/test_settlement.gd plays it).
extends "res://tests/base_test.gd"

const Progress := preload("res://scripts/save/progress.gd")
const StoryPlayer := preload("res://scripts/ui/story_player.gd")
const Art := preload("res://scripts/ui/art.gd")
const STORY_MDS := ["res://docs/STORY_M10.md", "res://docs/STORY_M11.md", "res://docs/STORY_M12.md"]
const LORE_MD := "res://docs/LORE.md"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const MAP_SCENE := "res://scenes/map.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const PHONE_SIZE := Vector2i(720, 1558)  ## iPhone 14 shape at the project's 720 px width
const BASE_SIZE := Vector2i(720, 1280)  ## project.godot viewport (a shorter phone)
const SCENES := ["intro", "join_angrboda", "join_skadi", "join_hrungnir", "boss_before", "boss_after",
	"ch2_intro", "ch2_eagles", "ch2_boss_before", "ch2_boss_after", "settlement_intro"]

var _saved_progress
var _saved_window_size: Vector2i


# --- texts ----------------------------------------------------------------------

## docs/STORY_M10.md, STORY_M11.md and STORY_M12.md are byte copies of Dmitriy's approved texts (../docs/). Every scene, title,
## speaker, look («[страница саги]» / «[диалог]»), line and the end card match word for word.
func test_texts_match_story_md_word_for_word() -> void:
	var data = await _data()
	var md := ""
	for path in STORY_MDS:
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.contains("утверждено Дмитрием"), "%s: the texts are approved by Dmitriy" % path)
		md += text + "\n"
	var heading := RegEx.create_from_string("^## (?:\\d+\\. )?`(\\w+)` — «(.+)»$")  # STORY_M12.md: one scene, no number
	var spoken := RegEx.create_from_string("^- \\*\\*(.+?):\\*\\* (.+)$")
	var card := RegEx.create_from_string("^Финальная карточка: \\*\\*«(.+)»\\*\\*")
	var expected := []
	var view := ""
	for line in md.split("\n"):
		var found := heading.search(line)
		if found:
			expected.append({"id": found.get_string(1), "title": found.get_string(2), "lines": [], "end_card": ""})
			view = ""
		elif line == "[страница саги]":
			view = "page"
		elif line == "[диалог]":
			view = "dialog"
		elif not expected.is_empty() and view != "" and spoken.search(line):
			found = spoken.search(line)
			expected.back()["lines"].append([view, found.get_string(1), found.get_string(2)])
		elif not expected.is_empty() and card.search(line):
			expected.back()["end_card"] = card.search(line).get_string(1)
	assert_eq(expected.map(func(scene): return scene["id"]), SCENES, "six scenes in STORY_M10.md, four in STORY_M11.md, one in STORY_M12.md")
	assert_eq(data.scene_ids(), SCENES, "the same eleven scenes in story.json, in the same order")
	for scene in expected:
		if not data.has_scene(scene["id"]):
			continue
		var actual: Dictionary = data.get_scene(scene["id"])
		assert_eq(actual["title"], scene["title"], "%s: title" % scene["id"])
		assert_eq(actual.get("end_card", ""), scene["end_card"], "%s: end card" % scene["id"])
		var lines: Array = actual["lines"].map(func(line): return [line["view"], data.speaker_name(line["speaker"]), line["text"]])
		assert_eq(lines.size(), scene["lines"].size(), "%s: number of lines" % scene["id"])
		for i in mini(lines.size(), scene["lines"].size()):
			assert_eq(lines[i], scene["lines"][i], "%s: line %d" % [scene["id"], i + 1])
	assert_eq(data.get_scene("boss_after")["end_card"], "Сага продолжится. Глава 2 — Ётунхейм", "the end card")
	assert_eq(data.get_scene("ch2_boss_after")["end_card"], "Сага продолжится. Глава 3 — Свартальфхейм", "chapter 2's end card")


## Page lines are the ravens'; dialog lines are heroes', ravens' or Thjazi's; every scene has its moment.
func test_speakers_looks_and_moments_are_valid() -> void:
	var data = await _data()
	var hero_ids: Array = data.heroes["heroes"].map(func(hero): return hero["id"])
	for scene_id in data.scene_ids():
		var scene: Dictionary = data.get_scene(scene_id)
		for line in scene["lines"]:
			assert_true(line["view"] in ["page", "dialog"], "%s: a known look" % scene_id)
			assert_true(data.is_raven(line["speaker"]) or line["speaker"] in hero_ids or data.speaker_enemy(line["speaker"]) != "",
					"%s: %s speaks" % [scene_id, line["speaker"]])
			if line["view"] == "page":
				assert_true(data.is_raven(line["speaker"]), "%s: only ravens speak on a saga page" % scene_id)
			assert_true(not String(line["text"]).is_empty(), "%s: a line has text" % scene_id)
	assert_eq(data.scene_ids_shown_at("new_game"), ["intro"] as Array[String], "intro on a new game")
	for hero_id in ["angrboda", "skadi", "hrungnir"]:
		assert_eq(data.scene_ids_shown_at("hero_joined", hero_id), ["join_" + hero_id] as Array[String], "%s's scene" % hero_id)
	for hero_id in ["torvald", "sigrid", "eyvind"]:
		assert_eq(data.scene_ids_shown_at("hero_joined", hero_id), [] as Array[String], "%s has no joining scene" % hero_id)
	assert_eq(data.scene_ids_shown_at("before_first_battle", 10), ["boss_before"] as Array[String], "before the boss")
	assert_eq(data.scene_ids_shown_at("first_victory", 10), ["boss_after"] as Array[String], "after the boss")
	assert_eq(data.scene_ids_shown_at("before_first_battle", 9), [] as Array[String], "nothing before stage 9")
	assert_eq(data.scene_ids_shown_at("first_victory", 3), [] as Array[String], "nothing after stage 3 itself")
	assert_eq(data.scene_ids_shown_at("chapter_map", 2), ["ch2_intro"] as Array[String], "Jotunheim's map")
	assert_eq(data.scene_ids_shown_at("chapter_map", 1), [] as Array[String], "nothing on Midgard's map")
	assert_eq(data.scene_ids_shown_at("before_battle_with", "carrion_eagle"), ["ch2_eagles"] as Array[String], "the eagles")
	assert_eq(data.scene_ids_shown_at("before_battle_with", "ice_troll"), [] as Array[String], "nothing before the troll")
	assert_eq(data.scene_ids_shown_at("before_first_battle", 20), ["ch2_boss_before"] as Array[String], "before Thjazi")
	assert_eq(data.scene_ids_shown_at("first_victory", 20), ["ch2_boss_after"] as Array[String], "after Thjazi")
	assert_eq(data.scene_ids_shown_at("settlement"), ["settlement_intro"] as Array[String], "the settlement's scene")
	assert_eq(data.speaker_enemy("thjazi"), "thjazi", "Thjazi's portrait is his enemy picture's head")
	assert_true(not data.is_raven("thjazi"), "Thjazi is not a raven")
	var story: Dictionary = data.visual["story"]
	assert_true(float(story["letters_per_second"]) >= 20.0, "the text is typed fast")
	assert_near(float(story["quiet_raven_alpha"]), 0.4, 0.1, "the quiet raven is faded to about 40%")


## The captions «кто есть кто» are word for word the table of docs/LORE.md, section 6а, and every speaker in story.json
## has one.
func test_captions_match_the_lore_word_for_word() -> void:
	var data = await _data()
	var lore := {}  ## name → caption, from the table of section 6а
	var in_section := false
	var row := RegEx.create_from_string("^\\| (.+?) \\| (.+?)( \\(.+\\))? \\|$")  # a note in brackets is not the caption
	for line in FileAccess.get_file_as_string(LORE_MD).split("\n"):
		if line.begins_with("## "):
			in_section = line.begins_with("## 6а. Кто есть кто")
		elif in_section and row.search(line) and not line.begins_with("| Имя |"):
			lore[row.search(line).get_string(1)] = row.search(line).get_string(2)
	assert_eq(lore.size(), 9, "nine captions in the lore table")
	assert_eq(lore.get("Хугин", ""), "ворон Одина · Мысль", "the table is read")
	assert_eq(lore.get("Тьяцци", ""), "великан, отец Скади", "Thjazi's caption without the note in brackets")
	var captions: Dictionary = data.story["captions"]
	assert_eq(captions.size(), lore.size(), "story.json has a caption for each row of the table, no more")
	for speaker_id in captions:
		var name: String = data.speaker_name(speaker_id)
		assert_true(lore.has(name), "%s is in the lore table" % name)
		assert_eq(data.speaker_caption(speaker_id), lore.get(name, ""), "%s: the caption word for word" % name)
	for scene_id in data.scene_ids():
		for line in data.get_scene(scene_id)["lines"]:
			assert_true(not data.speaker_caption(line["speaker"]).is_empty(), "%s: %s has a caption" % [scene_id, line["speaker"]])


# --- when scenes are shown ----------------------------------------------------------

func test_a_new_game_starts_with_the_intro() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	assert_eq(progress.queued_scene(data), "intro", "the intro is due on the first start")
	progress.start_scene("intro")
	assert_eq(progress.queued_scene(data), "", "and only once")
	assert_true(progress.is_scene_seen("intro"), "it counts as seen as soon as it starts")


func test_joining_heroes_bring_their_scene_once() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	progress.cleared_stage = 2
	progress.apply_victory(data, 3)
	assert_eq(progress.queued_scene(data, "hero_joined", "angrboda"), "join_angrboda", "Angrboda's scene after stage 3")
	assert_eq(progress.queued_scene(data, "hero_joined", "skadi"), "", "not Skadi's")
	progress.start_scene("join_angrboda")
	assert_eq(progress.queued_scene(data), "", "nothing else is due")
	progress.apply_victory(data, 3)
	assert_eq(progress.queued_scene(data), "", "a replay brings no scene")
	# Angrboda joins once more (the debug panel sent the game back to stage 3): her scene has been seen.
	progress.hero_levels.erase("angrboda")
	progress.cleared_stage = 2
	progress.apply_victory(data, 3)
	assert_eq(progress.queued_scene(data), "", "a seen scene is not shown again")
	for stage in [6, 9]:
		progress.cleared_stage = stage - 1
		progress.apply_victory(data, stage)
	assert_eq(progress.scene_queue, ["join_skadi", "join_hrungnir"] as Array[String], "Skadi's and Hrungnir's scenes")


func test_the_boss_scenes() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	assert_eq(progress.scenes_before_battle(data, 9), [] as Array[String], "no scene before stage 9")
	progress.cleared_stage = 9
	assert_eq(progress.scenes_before_battle(data, 10), ["boss_before"] as Array[String], "the first tap on stage 10")
	progress.start_scene("boss_before")
	assert_eq(progress.scenes_before_battle(data, 10), [] as Array[String], "not after a defeat or a retreat")
	assert_eq(progress.queued_scene(data), "", "nothing queued by the scene before the battle")
	progress.apply_victory(data, 10)
	assert_eq(progress.queued_scene(data, "first_victory", 10), "boss_after", "the first win over the boss")
	progress.start_scene("boss_after")
	progress.apply_victory(data, 10)
	assert_eq(progress.queued_scene(data), "", "a replay of stage 10 brings no scene")
	var won := Progress.new_game(data)
	won.cleared_stage = 10
	assert_eq(won.scenes_before_battle(data, 10), [] as Array[String], "no scene before a replay of a won boss stage")


## M11: Jotunheim's scene the first time chapter 2's map is shown; the eagles' scene before the first battle where
## carrion eagles fight (a stage or the scavengers' pack), not before chapter 1's battles or the troll's pack;
## Thjazi's scenes before the first battle on stage 20 and after the first win there (not after a replay).
func test_the_scenes_of_chapter_two() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.mark_all_scenes_seen(data)
	progress.seen_scenes.clear()
	progress.cleared_stage = 9
	assert_eq(progress.scene_on_chapter_map(data, 1), "", "nothing on Midgard's map")
	assert_eq(progress.scene_on_chapter_map(data, 2), "ch2_intro", "Jotunheim's scene with its map")
	progress.start_scene("ch2_intro")
	assert_eq(progress.scene_on_chapter_map(data, 2), "", "once")
	var first_eagles := 0
	for stage_id in data.chapter_stage_ids(2):
		if data.stage_has_enemy(stage_id, "carrion_eagle"):
			first_eagles = stage_id
			break
	assert_true(first_eagles > 11, "the carrion eagles come after the first stage of chapter 2")
	for stage_id in range(1, first_eagles):
		assert_true(not "ch2_eagles" in progress.scenes_before_battle(data, stage_id), "no eagles' scene before stage %d" % stage_id)
	assert_eq(progress.scenes_before_battle(data, first_eagles), ["ch2_eagles"] as Array[String], "the eagles' scene before stage %d" % first_eagles)
	assert_eq(progress.scenes_before_battle(data, 0, "scavengers"), ["ch2_eagles"] as Array[String], "or before the scavengers' pack")
	assert_eq(progress.scenes_before_battle(data, 0, "troll"), [] as Array[String], "not before the troll")
	assert_eq(progress.scenes_before_battle(data, 0, "wolves"), [] as Array[String], "not before Midgard's wolves")
	progress.start_scene("ch2_eagles")
	assert_eq(progress.scenes_before_battle(data, first_eagles), [] as Array[String], "once")
	progress.cleared_stage = 19
	assert_eq(progress.scenes_before_battle(data, 20), ["ch2_boss_before"] as Array[String], "the first tap on stage 20")
	progress.start_scene("ch2_boss_before")
	progress.apply_victory(data, 20)
	assert_eq(progress.queued_scene(data, "first_victory", 20), "ch2_boss_after", "the first win over Thjazi")
	progress.start_scene("ch2_boss_after")
	progress.apply_victory(data, 20)
	assert_eq(progress.queued_scene(data), "", "a replay of stage 20 brings no scene")
	var fresh = Progress.new_game(data)
	fresh.cleared_stage = 19
	fresh.seen_scenes.append("ch2_boss_before")
	assert_eq(fresh.scenes_before_battle(data, 20), ["ch2_eagles"] as Array[String],
			"a battle with eagles still brings their scene, even on the boss stage")


func test_the_debug_panel_brings_no_scenes() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	progress.jump_to_stage(data, 10)
	progress.unlock_all_heroes(data)
	assert_eq(progress.hero_levels.size(), 6, "all heroes joined")
	assert_eq(progress.scene_queue, [] as Array[String], "jumping to a stage and unlocking heroes queue no scenes")
	assert_eq(progress.seen_scenes, ["intro"] as Array[String], "and mark none seen")
	progress.mark_all_scenes_seen(data)
	assert_eq(progress.seen_scene_ids(data), data.scene_ids(), "«Открыть все сцены» marks every scene seen")
	assert_eq(progress.scene_queue, [] as Array[String], "and plays none")


func test_an_old_save_gets_the_intro_and_no_scenes_of_heroes_it_has() -> void:
	var data = await _data()
	var old := Progress.new_game(data)
	old.jump_to_stage(data, 10)
	old.cleared_stage = 10  # the chapter is done, as on Dmitriy's iPhone
	var saved: Dictionary = old.to_dict()
	saved.erase("seen_scenes")
	saved.erase("scene_queue")
	var progress = Progress.from_dict(saved, data)
	assert_eq(progress.scene_queue, ["intro"] as Array[String], "only the intro, once after the update")
	assert_eq(progress.seen_scenes, [] as Array[String], "nothing seen yet")
	assert_eq(progress.scenes_before_battle(data, 10), [] as Array[String], "the won boss stage brings no scene")
	assert_eq(progress.scene_on_chapter_map(data, 2), "ch2_intro", "Jotunheim's scene the first time its map is shown")
	var again = Progress.from_dict(progress.to_dict(), data)
	assert_eq(again.scene_queue, ["intro"] as Array[String], "the intro waits until it is shown")
	again.start_scene("intro")
	assert_eq(Progress.from_dict(again.to_dict(), data).queued_scene(data), "", "and is not shown again")
	# An old save with Angrboda earned but without her level (a version 1 save) gets her without the scene.
	var v1 := {"version": 1, "silver": 0, "cleared_stage": 4}
	assert_eq(Progress.from_dict(v1, data).scene_queue, ["intro"] as Array[String], "no scene for heroes an old save has")


func test_seen_and_queued_scenes_are_saved() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	progress.cleared_stage = 2
	progress.apply_victory(data, 3)
	var saved: Dictionary = progress.to_dict()
	assert_eq(saved["seen_scenes"], ["intro"], "seen scenes are in the save")
	assert_eq(saved["scene_queue"], ["join_angrboda"], "a scene not shown yet is in the save")
	saved["seen_scenes"] = ["intro", "no_such_scene", 5]
	saved["scene_queue"] = ["join_angrboda", "intro", "join_angrboda", "no_such_scene"]
	var loaded = Progress.from_dict(saved, data)
	assert_eq(loaded.seen_scenes, ["intro"] as Array[String], "unknown scenes are dropped")
	assert_eq(loaded.scene_queue, ["join_angrboda"] as Array[String], "seen, repeated and unknown scenes leave the queue")


func test_reset_forgets_the_seen_scenes() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.mark_all_scenes_seen(data)
	progress.reset(data, 1000)
	assert_eq(progress.seen_scenes, [] as Array[String], "no scenes seen after a reset")
	assert_eq(progress.queued_scene(data), "intro", "the intro is due again")


# --- the scene on screen ------------------------------------------------------------

## A tap while the line is typed shows it whole; the next tap shows the next line. «…» is a line like any other.
func test_tap_shows_the_whole_line_then_the_next() -> void:
	var game_state = await _use_progress(Progress.new_game((await _data())))
	var tree := Engine.get_main_loop() as SceneTree
	var screen := _blank_screen()
	var player = StoryPlayer.play(screen, "boss_after")
	assert_true(game_state.progress.is_scene_seen("boss_after"), "seen as soon as it starts")
	await tree.process_frame
	var text: Label = player.get_node("%DialogText")
	assert_true(player.get_node("%Dialog").visible and not player.get_node("%Page").visible, "a hero's line is a dialog")
	assert_eq(text.text, "Спи, ярл Хальвдан. Теперь — по-настоящему.", "the first line")
	assert_true(not player.is_line_shown(), "the line is being typed")
	assert_true(text.visible_characters >= 0 and text.visible_characters < text.text.length(), "letter by letter")
	_click(player)
	assert_true(player.is_line_shown(), "a tap shows the whole line")
	assert_eq(player.line_index(), 0, "and stays on it")
	_click(player)
	assert_eq(player.line_index(), 1, "the next tap: the next line")
	for i in 2:
		player.tap()
		player.tap()
	assert_true(player.get_node("%Page").visible, "the ravens' lines are a saga page")
	assert_eq(player.get_node("%PageName").text, "Хугин", "Hugin speaks")
	assert_near(player.get_node("%Hugin").modulate.a, 1.0, 0.001, "the raven who speaks is bright")
	assert_near(player.get_node("%Munin").modulate.a, 0.4, 0.001, "the other one is faded")
	for i in 3:
		player.tap()
		player.tap()
	assert_eq(player.get_node("%DialogName").text, "Скади", "Skadi's turn")
	assert_eq(player.get_node("%DialogText").text, "…", "her silence is a line")
	var finished := [false]
	player.finished.connect(func(): finished[0] = true)
	for i in 3:
		player.tap()
		player.tap()
	assert_true(player.is_on_end_card(), "the scene ends with the card")
	assert_true(player.get_node("%EndCard").visible, "on paper")
	assert_eq(player.get_node("%EndText").text, "Сага продолжится. Глава 2 — Ётунхейм", "the card's text")
	assert_true(not player.get_node("%SkipButton").visible, "the card has no «Пропустить»")
	assert_true(not finished[0], "the card waits for a tap")
	player.tap()
	assert_true(finished[0], "a tap closes the card and the scene")
	screen.queue_free()
	_restore()


## The caption stands under the name at every line, on a saga page and in a dialog, smaller and paler than the name.
func test_the_caption_is_under_the_name_at_every_line() -> void:
	await _use_progress(Progress.new_game((await _data())))
	var tree := Engine.get_main_loop() as SceneTree
	var screen := _blank_screen()
	var player = StoryPlayer.play(screen, "intro")
	await tree.process_frame
	var expected := ["ворон Одина · Память", "ворон Одина · Память", "ворон Одина · Мысль", "ворон Одина · Память",
			"ворон Одина · Мысль", "ворон Одина · Мысль", "ворон Одина · Память", "щитоносец дружины", "берсерк дружины",
			"скальд дружины", "скальд дружины", "берсерк дружины"]
	for i in expected.size():
		var on_page: bool = player.get_node("%Page").visible
		var prefix := "%Page" if on_page else "%Dialog"
		var name: Label = player.get_node(prefix + "Name")
		var caption: Label = player.get_node(prefix + "Caption")
		assert_eq(caption.text, expected[i], "line %d: the caption" % (i + 1))
		await tree.process_frame
		assert_true(caption.get_global_rect().position.y >= name.get_global_rect().end.y - 0.5, "line %d: under the name" % (i + 1))
		assert_true(caption.get_theme_font_size("font_size") < name.get_theme_font_size("font_size"), "smaller than the name")
		var paler: Color = caption.get_theme_color("font_color")
		assert_true(paler.s < name.get_theme_color("font_color").s, "paler than the name")
		player.tap()
		player.tap()
	screen.queue_free()
	_restore()


## While a line is typed there is no «продолжить» mark; once it is whole, the mark (in the text's colour, at the bottom
## right of the text) fades in and out once every continue_mark_blink_seconds. On a page, in a dialog, on the end card.
func test_the_continue_mark_blinks_once_the_line_is_shown() -> void:
	var data = await _data()
	await _use_progress(Progress.new_game(data))
	var tree := Engine.get_main_loop() as SceneTree
	var blink := float(data.visual["story"]["continue_mark_blink_seconds"])
	assert_near(blink, 1.0, 0.3, "about once a second")
	var screen := _blank_screen()
	var player = StoryPlayer.play(screen, "boss_after")
	await tree.process_frame
	for view in ["Dialog", "Page", "End"]:
		while (view == "Page" and not player.get_node("%Page").visible) or (view == "End" and not player.is_on_end_card()):
			player.tap()
			player.tap()
		var mark: Control = player.continue_mark()
		assert_eq(mark, player.get_node("%" + view + "Mark"), "%s: its own mark" % view)
		var text: Label = player.get_node("%" + view + "Text")
		if view != "End":
			assert_true(not player.is_line_shown(), "%s: the line is being typed" % view)
			player._process(0.25)
			assert_eq(mark.modulate.a, 0.0, "%s: no mark while typing" % view)
			player.tap()
		assert_true(player.is_line_shown(), "%s: the line is whole" % view)
		assert_eq(mark.color, text.get_theme_color("font_color"), "%s: in the text's colour" % view)
		player._process(blink / 2.0)
		assert_near(mark.modulate.a, 1.0, 0.001, "%s: fully shown half a blink later" % view)
		player._process(blink / 2.0)
		assert_near(mark.modulate.a, 0.0, 0.001, "%s: and gone again after a whole blink" % view)
		player._process(blink / 4.0)
		assert_near(mark.modulate.a, 0.5, 0.001, "%s: softly, not on and off" % view)
		await tree.process_frame
		var rect := mark.get_global_rect()
		var text_rect := text.get_global_rect()
		assert_true(rect.position.y >= text_rect.end.y - 0.5, "%s: under the text" % view)
		assert_near(rect.end.x, text_rect.end.x, 1.0, "%s: at its right edge" % view)
		assert_true(rect.size.x >= 20.0 and rect.size.x <= 40.0, "%s: small" % view)
		if view != "End":
			player.tap()
			assert_eq(mark.modulate.a, 0.0, "%s: the next line hides it" % view)
	screen.queue_free()
	_restore()


## The speaker's portrait: the hero's portrait from «Герои», a raven's head for a raven in a dialog.
func test_dialog_shows_the_speakers_portrait() -> void:
	await _use_progress(Progress.new_game((await _data())))
	var tree := Engine.get_main_loop() as SceneTree
	var screen := _blank_screen()
	var player = StoryPlayer.play(screen, "boss_before")
	await tree.process_frame
	var picture: TextureRect = player.get_node("%DialogPortrait").find_children("*", "TextureRect", true, false)[0]
	assert_eq(player.get_node("%DialogName").text, "Мунин", "Munin speaks first")
	assert_eq(picture.texture.atlas, Art.raven_picture("munin"), "with his own picture")
	player.tap()
	player.tap()
	await tree.process_frame
	var pictures := player.get_node("%DialogPortrait").find_children("*", "TextureRect", true, false)
	assert_eq(pictures.size(), 1, "one portrait at a time")
	assert_eq(pictures[0].texture.atlas, Art.hero_picture("torvald"), "then Torvald's portrait")
	screen.queue_free()
	_restore()


## M11: Thjazi speaks with his head from his enemy picture (enemies.json → thjazi.portrait), name and caption.
func test_thjazi_speaks_with_his_head() -> void:
	var data = await _data()
	await _use_progress(Progress.new_game(data))
	var tree := Engine.get_main_loop() as SceneTree
	var screen := _blank_screen()
	var player = StoryPlayer.play(screen, "ch2_boss_after")
	player.tap()
	player.tap()
	await tree.process_frame
	assert_eq(player.get_node("%DialogName").text, "Тьяцци", "Thjazi's line second")
	assert_eq(player.get_node("%DialogCaption").text, "великан, отец Скади", "with his caption")
	var picture: TextureRect = player.get_node("%DialogPortrait").find_children("*", "TextureRect", true, false)[0]
	assert_eq(picture.texture.atlas, Art.enemy_picture("thjazi"), "his own picture")
	assert_eq(picture.texture.region, Art.enemy_portrait(data.get_enemy("thjazi")).region, "his head")
	screen.queue_free()
	_restore()


func test_skip_closes_the_whole_scene_at_once() -> void:
	var game_state = await _use_progress(Progress.new_game((await _data())))
	var tree := Engine.get_main_loop() as SceneTree
	var screen := _blank_screen()
	var player = StoryPlayer.play(screen, "intro")
	await tree.process_frame
	var finished := [0]
	player.finished.connect(func(): finished[0] += 1)
	var skip: Button = player.get_node("%SkipButton")
	assert_true(skip.visible and skip.text == "Пропустить", "«Пропустить» is on screen")
	var rect := skip.get_global_rect()
	assert_true(rect.position.x > screen.size.x / 2.0 and rect.position.y < 200.0, "top right")
	assert_true(rect.size.y >= 96.0, "big enough for a finger")
	skip.pressed.emit()
	assert_eq(finished[0], 1, "the scene is over")
	assert_true(player.is_queued_for_deletion(), "and gone, without a question")
	assert_true(game_state.progress.is_scene_seen("intro"), "a skipped scene counts as seen")
	assert_eq(game_state.progress.queued_scene(game_state.data), "", "and is not shown again")
	screen.queue_free()
	_restore()


## Every line fits the screen on a tall and a short phone: the saga page text ends above the bottom edge, the dialog
## panel with its text is inside the screen and below the «Пропустить» button.
func test_every_line_fits_the_phone_screen() -> void:
	var data = await _data()
	await _use_progress(Progress.new_game(data))
	var tree := Engine.get_main_loop() as SceneTree
	for window in [PHONE_SIZE, BASE_SIZE]:
		tree.root.size = window
		for scene_id in data.scene_ids():
			var screen := _blank_screen()
			var player = StoryPlayer.play(screen, scene_id)
			for line in data.get_scene(scene_id)["lines"]:
				player.get_node("%PageText").visible_characters = -1
				player.get_node("%DialogText").visible_characters = -1
				await tree.process_frame
				await tree.process_frame
				var where := "%s %s «%s»" % [window, scene_id, String(line["text"]).left(30)]
				var screen_rect := Rect2(Vector2.ZERO, Vector2(window))
				var shown: Control = player.get_node("%PageText" if line["view"] == "page" else "%DialogPanel")
				var rect := shown.get_global_rect()
				assert_true(screen_rect.encloses(rect), "%s fits the screen (%s)" % [where, rect])
				var mark_rect: Rect2 = player.continue_mark().get_global_rect()
				assert_true(screen_rect.encloses(mark_rect), "%s: the «продолжить» mark too (%s)" % [where, mark_rect])
				if line["view"] == "dialog":
					assert_true(rect.position.y > player.get_node("%SkipButton").get_global_rect().end.y, "%s: below «Пропустить»" % where)
					var text: Label = player.get_node("%DialogText")
					assert_true(text.get_line_count() <= text.get_visible_line_count(), "%s: every row of the text shows" % where)
				else:
					var name_rect: Rect2 = player.get_node("%PageName").get_global_rect()
					assert_true(name_rect.position.y > player.get_node("%Hugin").get_global_rect().end.y - 0.5, "%s: name under the ravens" % where)
				player.tap()
			screen.queue_free()
	_restore()


# --- screens --------------------------------------------------------------------------

## The main screen plays the queued intro over itself, and nothing when no scene is due.
func test_main_screen_plays_the_intro() -> void:
	var data = await _data()
	var game_state = await _use_progress(Progress.new_game(data))
	var tree := Engine.get_main_loop() as SceneTree
	var menu: Control = load(MAIN_MENU_SCENE).instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	var players := menu.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)
	assert_eq(players.size(), 1, "the intro is on the main screen")
	if players.size() == 1:
		assert_eq(players[0].scene_id, "intro", "it is the intro")
		assert_eq(players[0].get_index(), menu.get_child_count() - 1, "on top of everything")
	assert_true(game_state.progress.is_scene_seen("intro"), "seen")
	menu.queue_free()
	await tree.process_frame
	var again: Control = load(MAIN_MENU_SCENE).instantiate()
	tree.root.add_child(again)
	await tree.process_frame
	assert_eq(again.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer).size(), 0,
			"not again next time")
	# The debug panel's «Перейти к этапу» and «Открыть всех героев» play nothing.
	var panel: Control = again.get_node("%DebugPanel")
	panel.open()
	panel.get_node("%UnlockHeroesButton").pressed.emit()
	panel.get_node("%JumpButton").pressed.emit()
	await tree.process_frame
	assert_eq(again.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer).size(), 0,
			"the debug panel starts no scene")
	assert_eq(game_state.progress.scene_queue, [] as Array[String], "and queues none")
	panel.get_node("%UnlockScenesButton").pressed.emit()
	assert_eq(game_state.progress.seen_scene_ids(data), data.scene_ids(), "«Открыть все сцены» marks them all seen")
	again.queue_free()
	_restore()


## A scene left unseen when the game was closed (here: Angrboda's, after the intro) plays on the main screen next.
func test_main_screen_plays_scenes_left_from_a_closed_game_one_after_another() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.cleared_stage = 2
	progress.apply_victory(data, 3)  # the game was closed on the «Новый герой» window
	var game_state = await _use_progress(Progress.from_dict(progress.to_dict(), data))
	assert_eq(game_state.progress.scene_queue, ["intro", "join_angrboda"] as Array[String], "both scenes are still due")
	var tree := Engine.get_main_loop() as SceneTree
	var menu: Control = load(MAIN_MENU_SCENE).instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	var shown := []
	for i in 3:
		var players := menu.find_children("*", "", false, false).filter(
				func(node): return node.get_script() == StoryPlayer and not node.is_queued_for_deletion())
		if players.is_empty():
			break
		shown.append(players[0].scene_id)
		players[0].close()
		await tree.process_frame
		await tree.process_frame
	assert_eq(shown, ["intro", "join_angrboda"], "the intro, then Angrboda's scene, then nothing")
	assert_eq(game_state.progress.scene_queue, [] as Array[String], "nothing is due any more")
	menu.queue_free()
	_restore()


## The first tap on the boss stage plays the scene before the battle over the map.
func test_the_map_plays_the_boss_scene_before_the_first_battle() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	progress.jump_to_stage(data, 10)
	var game_state = await _use_progress(progress)
	var tree := Engine.get_main_loop() as SceneTree
	var map: Control = load(MAP_SCENE).instantiate()
	tree.root.add_child(map)
	await tree.process_frame
	map._stage_buttons[10].pressed.emit()
	var players := map.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)
	assert_eq(players.size(), 1, "a scene over the map")
	if players.size() == 1:
		assert_eq(players[0].scene_id, "boss_before", "the boss's first scene")
	assert_eq(game_state.selected_stage, 10, "the boss battle comes next")
	assert_eq(game_state.progress.scenes_before_battle(data, 10), [] as Array[String], "only the first time")
	map.queue_free()
	_restore()


## M11: an old save that has won chapter 1 opens the map on chapter 2 and gets Jotunheim's scene once; switching to
## chapter 1 and back does not play it again.
func test_the_map_plays_jotunheims_scene_once() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	progress.jump_to_stage(data, 11)
	var game_state = await _use_progress(progress)
	var tree := Engine.get_main_loop() as SceneTree
	var map: Control = load(MAP_SCENE).instantiate()
	tree.root.add_child(map)
	await tree.process_frame
	assert_eq(map.shown_chapter(), 2, "the map opens on chapter 2")
	var players := map.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)
	assert_eq(players.size(), 1, "a scene over the map")
	if players.size() == 1:
		assert_eq(players[0].scene_id, "ch2_intro", "Jotunheim's scene")
		players[0].close()
	await tree.process_frame
	map.show_chapter(1)
	map.show_chapter(2)
	await tree.process_frame
	players = map.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)
	assert_eq(players.size(), 0, "not again")
	map.queue_free()
	_restore()


## M11: the first tap on a stage with carrion eagles plays their scene over the map, then the battle.
func test_the_map_plays_the_eagles_scene_before_their_first_battle() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.mark_all_scenes_seen(data)
	progress.seen_scenes.erase("ch2_eagles")
	var stage_id := 0
	for id in data.chapter_stage_ids(2):
		if data.stage_has_enemy(id, "carrion_eagle"):
			stage_id = id
			break
	progress.jump_to_stage(data, stage_id)
	var game_state = await _use_progress(progress)
	var tree := Engine.get_main_loop() as SceneTree
	var map: Control = load(MAP_SCENE).instantiate()
	tree.root.add_child(map)
	await tree.process_frame
	map._stage_buttons[stage_id].pressed.emit()
	var players := map.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)
	assert_eq(players.size(), 1, "a scene over the map")
	if players.size() == 1:
		assert_eq(players[0].scene_id, "ch2_eagles", "the eagles' scene")
	assert_eq(game_state.selected_stage, stage_id, "the battle with them comes next")
	map.queue_free()
	_restore()


## After the first win on stage 3: «Новый герой», then Angrboda's scene when the window closes.
func test_the_battle_plays_the_heroes_scene_after_the_new_hero_window() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	progress.jump_to_stage(data, 3)
	progress.mark_hint_shown = true
	var game_state = await _use_progress(progress)
	game_state.selected_stage = 3
	game_state.selected_pack = ""
	var tree := Engine.get_main_loop() as SceneTree
	var battle: Control = load(BATTLE_SCENE).instantiate()
	tree.root.add_child(battle)
	await tree.process_frame
	battle.set_process(false)
	battle._finish_stage(true, false)
	assert_true(battle.get_node("%NewHeroOverlay").visible, "«Новый герой» first")
	assert_eq(battle.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer).size(), 0,
			"no scene yet")
	battle.get_node("%NewHeroButton").pressed.emit()
	assert_true(not battle.get_node("%NewHeroOverlay").visible, "the window is closed")
	var players := battle.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)
	assert_eq(players.size(), 1, "then the scene")
	if players.size() == 1:
		assert_eq(players[0].scene_id, "join_angrboda", "Angrboda's scene")
	assert_true(battle.get_node("%ResultOverlay").visible, "over the «Победа!» screen")
	battle.queue_free()
	_restore()


## «Сцены саги»: the seen scenes by title; a tap plays the scene again.
func test_settings_list_the_seen_scenes_and_play_them_again() -> void:
	var data = await _data()
	var progress = Progress.new_game(data)
	progress.start_scene("intro")
	progress.start_scene("boss_before")
	var game_state = await _use_progress(progress)
	var tree := Engine.get_main_loop() as SceneTree
	var screen: Control = load(SETTINGS_SCENE).instantiate()
	tree.root.add_child(screen)
	await tree.process_frame
	assert_eq(screen.get_node("%ScenesButton").text, "Сцены саги", "the item in «Настройки»")
	screen.get_node("%ScenesButton").pressed.emit()
	var buttons: Array = screen.get_node("%SceneList").get_children()
	assert_eq(buttons.map(func(button): return button.text), ["Сон о замолчавших норнах", "Корона мертвеца"],
			"seen scenes by title, in story order")
	assert_true(not screen.get_node("%NoScenesLabel").visible, "no «nothing yet» text")
	buttons[1].pressed.emit()
	var players := screen.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)
	assert_eq(players.size(), 1, "the scene plays again")
	if players.size() == 1:
		assert_eq(players[0].scene_id, "boss_before", "the one tapped")
	assert_eq(game_state.progress.seen_scenes, ["intro", "boss_before"] as Array[String], "nothing else changes")
	screen.queue_free()
	game_state.progress = Progress.new_game(data)
	game_state.progress.scene_queue.clear()
	var empty: Control = load(SETTINGS_SCENE).instantiate()
	tree.root.add_child(empty)
	await tree.process_frame
	empty.open_scenes()
	assert_eq(empty.get_node("%SceneList").get_child_count(), 0, "no scenes seen: an empty list")
	assert_true(empty.get_node("%NoScenesLabel").visible, "with a note")
	empty.queue_free()
	_restore()


# --- helpers ----------------------------------------------------------------------------

func _data():
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	return game_state.data


## Puts `progress` into GameState for the test (restored by _restore) and returns GameState.
func _use_progress(progress) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	if _saved_progress == null:
		_saved_progress = game_state.progress
		_saved_window_size = tree.root.size
	game_state.progress = progress
	return game_state


func _restore() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.get_node("GameState").progress = _saved_progress
	tree.root.size = _saved_window_size
	_saved_progress = null


func _blank_screen() -> Control:
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	return screen


## A tap in the middle of the scene (a mouse press, as a touch arrives).
func _click(player: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = player.size / 2.0
	player._gui_input(event)

