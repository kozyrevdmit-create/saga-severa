## M12: the settlement. Construction opens with chapter 1 won (also for an old save), with starting supplies for exactly
## one level-1 building; supplies come from first wins and beast packs (less from a passed chapter's packs) only while
## construction is open; five buildings with five levels and growing prices; their bonuses: the shrine's HP and the
## forge's attack in the squad's power and in battle, the training yard's cheaper level-ups, the trading pier's battle
## silver (not offline income), Thjazi's barrow's shorter pack wait. «Сбросить прогресс» forgets the settlement.
## The screen: closed construction, captions of the plots, the building's window, building, the saga scene.
## Expected numbers come from data/*.json.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const Progress := preload("res://scripts/save/progress.gd")
const StageBattle := preload("res://scripts/battle/stage_battle.gd")
const StoryPlayer := preload("res://scripts/ui/story_player.gd")
const SETTLEMENT_SCENE := "res://scenes/settlement.tscn"
const PHONE_SIZE := Vector2i(720, 1558)  ## iPhone 14 shape at the project's 720 px width
const BASE_SIZE := Vector2i(720, 1280)  ## project.godot viewport (a shorter phone)
const NOW := 1_800_000_000
const OPEN_BUILDINGS := ["shrine", "training_yard", "pier"]  ## open from the opening of construction

var data = GameData.load_all()
var _saved_progress
var _saved_window_size: Vector2i


func win_stages(progress, last_stage: int) -> void:
	for stage in range(progress.cleared_stage + 1, last_stage + 1):
		progress.apply_victory(data, stage)


func supplies() -> Dictionary:
	return data.balance["supplies"]


# --- data ---------------------------------------------------------------------------

func test_five_buildings_with_five_levels_and_growing_prices() -> void:
	assert_eq(data.building_ids(), ["shrine", "training_yard", "pier", "thjazi_barrow", "forge"] as Array[String], "five buildings")
	assert_eq(data.building_max_level(), 5, "five levels")
	var costs: Array = data.buildings["level_costs"]
	assert_eq(costs.size(), data.building_max_level(), "a price for every level")
	for level in range(1, costs.size()):
		assert_true(int(costs[level]) > int(costs[level - 1]), "level %d costs more than level %d" % [level + 1, level])
	var at_top := {"shrine": 0.10, "training_yard": 0.15, "pier": 0.15, "thjazi_barrow": 0.5, "forge": 0.10}
	for building_id in at_top:
		assert_near(data.building_bonus(building_id, 5), at_top[building_id], 0.0001, "%s at level 5" % building_id)
		assert_near(data.building_bonus(building_id, 1), at_top[building_id] / 5.0, 0.0001, "%s: a fifth per level" % building_id)
	assert_eq(int(data.get_building("thjazi_barrow")["opens_after_chapter"]), 2, "the barrow after chapter 2")
	assert_eq(int(data.get_building("forge")["opens_after_chapter"]), 3, "the forge after chapter 3")
	for building_id in OPEN_BUILDINGS:
		assert_eq(int(data.get_building(building_id)["opens_after_chapter"]), 1, "%s with construction" % building_id)
	# The barrow at level 5: 2 h → 1 h, −12 min a level.
	var progress = Progress.new_game(data)
	assert_eq(progress.pack_respawn_seconds(data), 2 * 3600, "packs come back in 2 h without the barrow")
	progress.building_levels["thjazi_barrow"] = 1
	assert_eq(progress.pack_respawn_seconds(data), 2 * 3600 - 12 * 60, "−12 min at level 1")
	progress.building_levels["thjazi_barrow"] = 5
	assert_eq(progress.pack_respawn_seconds(data), 3600, "1 h at level 5")


# --- construction opens ----------------------------------------------------------

func test_construction_opens_with_chapter_one_won_with_supplies_for_one_building() -> void:
	var progress = Progress.new_game(data)
	assert_true(not progress.is_construction_open(data), "closed in a new game")
	win_stages(progress, 9)
	assert_true(not progress.is_construction_open(data), "closed before the boss of chapter 1")
	assert_eq(progress.supplies, 0, "no supplies before construction")
	for building_id in data.building_ids():
		assert_true(not progress.can_build(data, building_id), "%s can not be built yet" % building_id)
	var reward: Dictionary = progress.apply_victory(data, 10)
	assert_true(progress.is_construction_open(data), "open after the first win over the Draugr king")
	assert_eq(int(reward["supplies"]), 0, "the boss's win brings the starting supplies, not a first-win share")
	assert_eq(progress.supplies, data.building_cost(0), "exactly enough for one building of level 1")
	assert_true(progress.build(data, "shrine"), "one building can be built at once")
	assert_eq(progress.supplies, 0, "and that is all")
	assert_true(not progress.build(data, "pier"), "not a second one")
	progress.apply_victory(data, 10)
	assert_eq(progress.supplies, 0, "a replay of the boss does not bring the starting supplies again")
	for building_id in OPEN_BUILDINGS:
		assert_true(progress.is_building_open(data, building_id), "%s is open" % building_id)
	assert_true(not progress.is_building_open(data, "thjazi_barrow"), "the barrow is closed during chapter 2")
	assert_true(not progress.is_building_open(data, "forge"), "the forge is closed")
	win_stages(progress, 20)
	assert_true(progress.is_building_open(data, "thjazi_barrow"), "the barrow opens after chapter 2")
	assert_true(not progress.is_building_open(data, "forge"), "the forge waits for chapter 3")


## A save from before M12: one that has won chapter 1 gets construction and the starting supplies at once, the barrow
## open if chapter 2 is won too; one that has not gets nothing yet. The starting supplies come only once.
func test_an_old_save_opens_construction_with_starting_supplies() -> void:
	var old: Dictionary = Progress.new_game(data).to_dict()
	for key in ["supplies", "building_levels", "start_supplies_given"]:
		old.erase(key)
	old["cleared_stage"] = 5
	var early = Progress.from_dict(old, data)
	assert_true(not early.is_construction_open(data), "chapter 1 not won: closed")
	assert_eq(early.supplies, 0, "no supplies")
	old["cleared_stage"] = 12
	var middle = Progress.from_dict(old, data)
	assert_true(middle.is_construction_open(data), "chapter 1 won: open")
	assert_eq(middle.supplies, data.building_cost(0), "with the starting supplies")
	assert_true(not middle.is_building_open(data, "thjazi_barrow"), "the barrow still closed")
	old["cleared_stage"] = 20
	var done = Progress.from_dict(old, data)
	assert_true(done.is_building_open(data, "thjazi_barrow"), "chapter 2 won: the barrow open")
	assert_eq(done.supplies, data.building_cost(0), "the same starting supplies")
	var again = Progress.from_dict(done.to_dict(), data)
	assert_eq(again.supplies, data.building_cost(0), "loading again does not add them again")


func test_supplies_and_buildings_are_saved() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	progress.supplies = 1234
	progress.build(data, "pier")
	progress.build(data, "pier")
	var loaded = Progress.from_dict(progress.to_dict(), data)
	assert_eq(loaded.supplies, progress.supplies, "supplies")
	assert_eq(loaded.building_levels, {"pier": 2}, "the pier's level")
	assert_true(loaded.start_supplies_given, "the starting supplies were given")
	var broken: Dictionary = progress.to_dict()
	broken["building_levels"] = {"pier": 99, "shrine": -3, "castle": 2}
	broken["supplies"] = -5
	var fixed = Progress.from_dict(broken, data)
	assert_eq(fixed.building_levels, {"pier": data.building_max_level()}, "broken levels fall back to safe ones")
	assert_eq(fixed.supplies, 0, "no negative supplies")


func test_reset_forgets_the_settlement() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	progress.build(data, "shrine")
	progress.supplies = 500
	progress.reset(data, NOW)
	assert_eq(progress.supplies, 0, "no supplies")
	assert_eq(progress.building_levels, {}, "no buildings")
	assert_true(not progress.start_supplies_given, "the starting supplies come again with construction")
	win_stages(progress, 10)
	assert_eq(progress.supplies, data.building_cost(0), "they do")


func test_the_debug_jump_opens_construction() -> void:
	var progress = Progress.new_game(data)
	progress.jump_to_stage(data, 11)
	assert_true(progress.is_construction_open(data), "open after the jump past chapter 1")
	assert_eq(progress.supplies, data.building_cost(0), "with the starting supplies")
	progress.jump_to_stage(data, 15)
	assert_eq(progress.supplies, data.building_cost(0), "only once")


# --- where supplies come from ---------------------------------------------------------

func test_first_wins_bring_supplies_only_while_construction_is_open() -> void:
	var progress = Progress.new_game(data)
	var before: Dictionary = progress.apply_victory(data, 1)
	assert_eq(int(before["supplies"]), 0, "chapter 1: no supplies")
	win_stages(progress, 10)
	var start: int = progress.supplies
	var first: Dictionary = progress.apply_victory(data, 11)
	assert_eq(int(first["supplies"]), int(supplies()["first_victory"]), "a first win in chapter 2")
	assert_eq(progress.supplies, start + int(supplies()["first_victory"]), "added")
	var replay: Dictionary = progress.apply_victory(data, 11)
	assert_eq(int(replay["supplies"]), 0, "a replay brings none")
	assert_eq(progress.supplies, start + int(supplies()["first_victory"]), "nothing added")


func test_packs_bring_supplies_less_from_a_passed_chapter() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 3)
	assert_eq(int(progress.apply_pack_victory(data, "wolves", NOW)["supplies"]), 0, "before construction: none")
	assert_eq(progress.supplies, 0, "nothing added")
	win_stages(progress, 12)
	var start: int = progress.supplies
	var jotunheim: Dictionary = progress.apply_pack_victory(data, "ironwood_wolves", NOW)
	assert_eq(int(jotunheim["supplies"]), int(supplies()["pack_victory"]), "a pack of the current chapter")
	var midgard: Dictionary = progress.apply_pack_victory(data, "boars", NOW)
	assert_eq(int(midgard["supplies"]), int(supplies()["pack_victory_once_the_next_chapter_is_open"]), "a pack of chapter 1, passed")
	assert_true(int(supplies()["pack_victory_once_the_next_chapter_is_open"]) < int(supplies()["pack_victory"]), "less")
	assert_eq(progress.supplies, start + int(jotunheim["supplies"]) + int(midgard["supplies"]), "both added")


func test_supplies_do_not_change_the_silver() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	var paid: Dictionary = progress.apply_victory(data, 13)
	var base := float(data.get_stage(13)["reward"]["silver"])
	assert_eq(int(paid["silver"]), roundi(base * progress.silver_multiplier(data)), "the stage's silver as before (no pier)")


# --- prices and building ---------------------------------------------------------------

func test_prices_grow_with_the_level_up_to_the_top() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 10)
	progress.supplies = 100000
	var paid := 0
	for level in range(1, data.building_max_level() + 1):
		var cost: int = progress.building_cost(data, "shrine")
		assert_eq(cost, int(data.buildings["level_costs"][level - 1]), "level %d's price" % level)
		assert_true(progress.build(data, "shrine"), "level %d built" % level)
		paid += cost
		assert_eq(progress.building_level("shrine"), level, "level %d" % level)
	assert_eq(progress.supplies, 100000 - paid, "every level paid")
	assert_true(progress.is_building_max_level(data, "shrine"), "the top level")
	assert_true(not progress.can_build(data, "shrine"), "no higher")
	assert_true(not progress.build(data, "shrine"), "building does nothing")
	progress.supplies = progress.building_cost(data, "pier") - 1
	assert_true(not progress.can_build(data, "pier"), "not without enough supplies")
	assert_true(not progress.build(data, "thjazi_barrow"), "a closed building can not be built")
	assert_eq(progress.building_level("thjazi_barrow"), 0, "still nothing")


# --- bonuses ------------------------------------------------------------------------------

## The shrine's HP and the forge's attack count in every hero's power and the squad's «Сила» (and «+N силы»), added to
## the clan bonuses. The recommended power of stages stays as it is.
func test_shrine_and_forge_raise_the_squad_power() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	var recommended: int = data.recommended_power(13)
	var before: int = progress.squad_power(data)
	progress.building_levels["shrine"] = 3
	var with_shrine: int = progress.squad_power(data)
	assert_true(with_shrine > before, "the shrine adds power (%d → %d)" % [before, with_shrine])
	for hero_id in progress.squad_ids():
		var bonuses: Dictionary = data.synergy_bonuses(progress.squad_ids())
		bonuses["hp"] += 0.06
		assert_eq(progress.hero_power(data, hero_id), data.hero_power(hero_id, progress.level_of(hero_id), bonuses),
				"%s: +6%% HP added to the clan bonus" % hero_id)
	progress.building_levels["forge"] = 2
	assert_true(progress.squad_power(data) > with_shrine, "the forge adds power too")
	var bench: Array = progress.hero_levels.keys().filter(func(id): return not progress.is_in_formation(id))
	for hero_id in bench:
		var bonuses := {"hp": 0.06, "attack": 0.04}
		assert_eq(progress.hero_power(data, hero_id), data.hero_power(hero_id, progress.level_of(hero_id), bonuses),
				"%s on the bench gets the settlement's bonuses too" % hero_id)
	var hero_id: String = progress.squad_ids()[0]
	assert_eq(progress.level_up_power_gain(data, hero_id), progress.hero_power(data, hero_id, 1) - progress.hero_power(data, hero_id),
			"«+N силы» with the bonuses")
	assert_eq(data.recommended_power(13), recommended, "the recommended power does not change")


func test_shrine_and_forge_work_in_battle() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	var plain = StageBattle.from_data(data, 13, progress.squad(data), 1)
	progress.building_levels["shrine"] = 5
	progress.building_levels["forge"] = 5
	var built = StageBattle.from_data(data, 13, progress.squad(data), 1)
	var synergy: Dictionary = data.synergy_bonuses(progress.squad_ids())
	for i in plain.heroes().size():
		var a = plain.heroes()[i]
		var b = built.heroes()[i]
		assert_near(float(b.max_hp) / a.max_hp, (1.0 + synergy["hp"] + 0.1) / (1.0 + synergy["hp"]), 0.01, "%s: +10%% HP" % a.def_id)
		assert_near(b.base_attack / a.base_attack, (1.0 + synergy["attack"] + 0.1) / (1.0 + synergy["attack"]), 0.01, "%s: +10%% attack" % a.def_id)
	var pack = StageBattle.from_pack(data, "ironwood_wolves", 12, progress.squad(data), 1)
	assert_eq(pack.heroes()[0].max_hp, built.heroes()[0].max_hp, "against a pack too")


func test_training_yard_makes_level_ups_cheaper() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	var hero_id: String = progress.squad_ids()[0]
	var full: int = data.level_up_cost(progress.level_of(hero_id))
	assert_eq(progress.level_up_cost(data, hero_id), full, "full price without the yard")
	progress.building_levels["training_yard"] = 5
	var cheaper: int = progress.level_up_cost(data, hero_id)
	assert_eq(cheaper, roundi(full * 0.85), "15% cheaper at level 5")
	progress.silver = cheaper
	assert_true(progress.level_up(data, hero_id), "the cheaper price is enough")
	assert_eq(progress.silver, 0, "and that is what is paid")


func test_pier_adds_battle_silver_but_not_offline_income() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	progress.last_seen_unix = NOW - 3600
	var offline_before: int = progress.offline_income(data, NOW)
	var cap_before: int = progress.offline_income_cap(data)
	progress.building_levels["pier"] = 5
	assert_eq(progress.offline_income(data, NOW), offline_before, "offline income is the same")
	assert_eq(progress.offline_income_cap(data), cap_before, "so is its cap")
	var stage: Dictionary = progress.apply_victory(data, 12)
	var share := float(data.balance["replay_reward_share"])
	assert_eq(int(stage["silver"]), roundi(float(data.get_stage(12)["reward"]["silver"]) * share * progress.silver_multiplier(data) * 1.15),
			"+15% for a stage (a replay here)")
	var pack: Dictionary = progress.pack_reward(data, "ironwood_wolves")
	var packs: Dictionary = data.balance["beast_packs"]
	assert_eq(int(pack["silver"]), roundi(float(data.get_stage(12)["reward"]["silver"]) * float(packs["reward_share_of_first_win"])
			* progress.silver_multiplier(data) * 1.15), "+15% for a pack")
	assert_eq(int(pack["experience"]), roundi(float(data.get_stage(12)["reward"]["experience"]) * float(packs["reward_share_of_first_win"])),
			"experience as it was")


func test_thjazis_barrow_brings_packs_back_sooner() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 20)
	progress.apply_pack_victory(data, "wolves", NOW)
	assert_eq(progress.pack_seconds_left(data, "wolves", NOW), 2 * 3600, "2 h without the barrow")
	progress.building_levels["thjazi_barrow"] = 5
	progress.apply_pack_victory(data, "boars", NOW)
	assert_eq(progress.pack_seconds_left(data, "boars", NOW), 3600, "1 h with the barrow at level 5")
	assert_eq(progress.pack_seconds_left(data, "wolves", NOW), 3600, "a pack already away waits no longer than that either")
	assert_true(progress.is_pack_available(data, "boars", NOW + 3600), "back after an hour")


# --- the screen ------------------------------------------------------------------------------

func test_before_chapter_one_the_screen_shows_only_the_income_and_when_construction_opens() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 5)
	var screen = await _open(progress, PHONE_SIZE)
	assert_eq(screen.get_node("%Counters").text, "Стройка откроется после главы 1", "the line about construction")
	assert_eq(screen._buildings.size(), 0, "no plots to build on")
	assert_true(screen.get_node("%Income").text.contains("серебра в минуту"), "the offline income is there")
	assert_eq(_players(screen).size(), 0, "no saga scene yet")
	_close(screen)


func test_the_plots_show_their_buildings_and_fit_the_screen() -> void:
	for window in [PHONE_SIZE, BASE_SIZE]:
		var progress = Progress.new_game(data)
		win_stages(progress, 12)
		progress.mark_all_scenes_seen(data)
		progress.building_levels["shrine"] = 2
		var screen = await _open(progress, window)
		var texts := {}
		for building_id in screen._buildings:
			texts[building_id] = screen._buildings[building_id]["label"].text
		assert_eq(texts, {"shrine": "Капище · ур. 2", "training_yard": "Учебный двор · построить",
			"pier": "Торговая пристань · построить", "thjazi_barrow": "Курган Тьяцци · после главы 2",
			"forge": "Кузня · после главы 3"}, "%s: the five captions" % window)
		assert_true(screen._buildings["shrine"]["picture"].visible, "the shrine's picture stands on its plot")
		assert_true(not screen._buildings["pier"]["picture"].visible, "an empty plot shows no building")
		assert_true(screen._buildings["thjazi_barrow"]["caption"].modulate.a < 1.0, "a closed plot's caption is pale")
		var screen_rect: Rect2 = screen.get_viewport_rect()
		var free_area := Rect2(0, screen.get_node("%TopBar").get_global_rect().end.y, screen_rect.size.x,
				screen.get_node("%BottomBar").get_global_rect().position.y - screen.get_node("%TopBar").get_global_rect().end.y)
		var captions := []
		for building_id in screen._buildings:
			var caption: Button = screen._buildings[building_id]["caption"]
			var rect: Rect2 = caption.get_global_rect()
			assert_true(rect.size.y >= 96.0 - 0.01, "%s: %s can be tapped, at least 96 px tall" % [window, building_id])
			var paper: Rect2 = screen._buildings[building_id]["paper"].get_global_rect()
			assert_true(free_area.encloses(paper), "%s: %s's caption is on the screen between the bars (%s)" % [window, building_id, paper])
			for other in captions:
				assert_true(not other[1].intersects(paper), "%s: %s and %s overlap" % [window, other[0], building_id])
			captions.append([building_id, paper])
			var picture: Rect2 = screen._buildings[building_id]["picture"].get_global_rect()
			assert_true(picture.get_center().y > free_area.position.y and picture.get_center().y < free_area.end.y,
					"%s: %s's building stands between the bars" % [window, building_id])
		_close(screen)


func test_the_window_builds_and_improves() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 12)
	progress.mark_all_scenes_seen(data)
	var screen = await _open(progress, PHONE_SIZE)
	await _tap(screen._buildings["shrine"]["caption"])
	assert_true(screen.get_node("%Window").visible, "a tap on the caption opens the window")
	assert_eq(screen.get_node("%BuildingName").text, "Капище", "its name")
	assert_eq(screen.get_node("%BuildingLevel").text, "Уровень 0/5", "level 0 of 5")
	assert_eq(screen.get_node("%BonusNow").text, "Сейчас: не построено", "nothing yet")
	assert_eq(screen.get_node("%BonusNext").text, "На 1-м уровне: +2% HP всей дружине", "the next level's bonus")
	assert_eq(screen.get_node("%BuildButton").text, "Построить", "«Построить»")
	assert_true(not screen.get_node("%BuildButton").disabled, "the starting supplies are enough")
	await _tap(screen.get_node("%BuildButton"))
	assert_eq(progress.building_level("shrine"), 1, "built")
	assert_eq(screen._buildings["shrine"]["label"].text, "Капище · ур. 1", "the caption follows")
	assert_true(screen._buildings["shrine"]["picture"].visible, "the building stands on its plot")
	assert_eq(screen.get_node("%BonusNow").text, "Сейчас: +2% HP всей дружине", "the bonus now")
	assert_eq(screen.get_node("%BuildButton").text, "Улучшить", "«Улучшить» next")
	assert_true(screen.get_node("%BuildButton").disabled, "not active without the supplies")
	progress.supplies = 100000
	screen.open_window("shrine")
	for level in range(2, data.building_max_level() + 1):
		await _tap(screen.get_node("%BuildButton"))
	assert_eq(progress.building_level("shrine"), data.building_max_level(), "up to the top")
	assert_eq(screen.get_node("%BuildButton").text, "Наибольший уровень", "«Наибольший уровень»")
	assert_true(screen.get_node("%BuildButton").disabled, "and nothing to press")
	assert_true(not screen.get_node("%BonusNext").visible, "no next level")
	await _tap(screen.get_node("%CloseButton"))
	assert_true(not screen.get_node("%Window").visible, "«Закрыть» closes the window")
	screen.open_window("thjazi_barrow")
	assert_eq(screen.get_node("%BuildButton").text, "Откроется после главы 2", "a closed building says when it opens")
	assert_true(screen.get_node("%BuildButton").disabled, "and can not be built")
	_close(screen)


func test_the_barrows_window_tells_the_packs_wait() -> void:
	var screen_script = load("res://scripts/ui/settlement_screen.gd")
	assert_eq(screen_script.bonus_text(data, "thjazi_barrow", 1), "стаи возвращаются через 1 ч 48 мин", "level 1")
	assert_eq(screen_script.bonus_text(data, "thjazi_barrow", 5), "стаи возвращаются через 1 ч", "level 5")
	assert_eq(screen_script.bonus_text(data, "training_yard", 5), "прокачка героев дешевле на 15%", "the yard")
	assert_eq(screen_script.bonus_text(data, "pier", 2), "+6% серебра за бои", "the pier")
	assert_eq(screen_script.bonus_text(data, "forge", 5), "+10% атаки всей дружине", "the forge")


## «Зерно нового мира» plays on the first visit with construction open (also for an old save), once.
func test_the_settlement_scene_plays_once_with_construction_open() -> void:
	var progress = Progress.new_game(data)
	progress.mark_all_scenes_seen(data)
	progress.seen_scenes.erase("settlement_intro")
	win_stages(progress, 9)
	var closed = await _open(progress, PHONE_SIZE)
	assert_eq(_players(closed).size(), 0, "not while construction is closed")
	_close(closed)
	win_stages(progress, 10)
	var screen = await _open(progress, PHONE_SIZE)
	var players := _players(screen)
	assert_eq(players.size(), 1, "the scene over the settlement")
	if players.size() == 1:
		assert_eq(players[0].scene_id, "settlement_intro", "«Зерно нового мира»")
		players[0].close()
	_close(screen)
	var again = await _open(progress, PHONE_SIZE)
	assert_eq(_players(again).size(), 0, "not again")
	_close(again)


func test_the_main_screen_shows_supplies_once_construction_is_open() -> void:
	var progress = Progress.new_game(data)
	progress.mark_all_scenes_seen(data)
	win_stages(progress, 9)
	var tree := Engine.get_main_loop() as SceneTree
	_use(progress, PHONE_SIZE)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	assert_true(not menu.get_node("%SuppliesLabel").visible, "no supplies before construction")
	menu.queue_free()
	win_stages(progress, 10)
	menu = load("res://scenes/main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	assert_true(menu.get_node("%SuppliesLabel").visible, "supplies next to the silver")
	assert_eq(menu.get_node("%SuppliesLabel").text, "Припасы: %d" % data.building_cost(0), "the starting supplies")
	menu.queue_free()
	_restore()


func test_debug_adds_supplies() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = _use(Progress.new_game(data), PHONE_SIZE)
	game_state.debug_add_supplies()
	assert_eq(game_state.progress.supplies, int(data.balance["debug_panel"]["add_supplies"]), "+N припасов")
	await tree.process_frame
	_restore()


# --- helpers ----------------------------------------------------------------------------------

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
	tree.root.get_node("GameState").progress = _saved_progress
	tree.root.size = _saved_window_size
	_saved_progress = null


func _open(progress, window: Vector2i) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	_use(progress, window)
	var screen: Control = load(SETTLEMENT_SCENE).instantiate()
	tree.root.add_child(screen)
	for i in 3:
		await tree.process_frame
	return screen


func _close(screen: Control) -> void:
	screen.queue_free()
	_restore()


func _players(screen: Node) -> Array:
	return screen.find_children("*", "", false, false).filter(func(node): return node.get_script() == StoryPlayer)


## A tap: a press and a release over the middle of the control.
func _tap(control: Control) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var center: Vector2 = control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = center
		event.global_position = center
		tree.root.push_input(event)
		await tree.process_frame
