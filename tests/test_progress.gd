## Progress rules: levelling, rewards and replays, hero unlocks, formation, jarl level, offline income, beast packs, saves,
## chapters (M11).
## Expected numbers come from data/*.json.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const Progress := preload("res://scripts/save/progress.gd")

var data = GameData.load_all()


func leveling() -> Dictionary:
	return data.balance["leveling"]


func win_stages(progress, last_stage: int) -> void:
	for stage in range(progress.cleared_stage + 1, last_stage + 1):
		progress.apply_victory(data, stage)


# --- new game, levelling ------------------------------------------------------

func test_new_game_starts_with_the_starting_squad_at_level_one() -> void:
	var progress = Progress.new_game(data)
	assert_eq(progress.silver, int(data.balance["start_silver"]), "start silver")
	assert_eq(progress.cleared_stage, 0, "no stages won")
	assert_eq(progress.hero_levels.keys(), data.starting_hero_ids(), "starting heroes")
	for hero_id in progress.hero_levels:
		assert_eq(progress.level_of(hero_id), 1, "%s level" % hero_id)
	assert_eq(progress.squad_ids(), data.starting_hero_ids(), "starting heroes are in the squad")
	assert_eq(progress.next_stage_id(data), 1, "first battle is stage 1")


func test_level_up_cost_follows_the_formula() -> void:
	for level in [1, 2, 5, 10, 29]:
		var expected := roundi(float(leveling()["cost_base"]) * pow(float(leveling()["cost_growth"]), level - 1))
		assert_eq(data.level_up_cost(level), expected, "cost at level %d" % level)


func test_each_level_adds_stat_growth() -> void:
	var growth := float(leveling()["stat_growth_per_level"])
	assert_near(data.hero_stat_multiplier(1), 1.0, 0.0001, "level 1")
	assert_near(data.hero_stat_multiplier(3) / data.hero_stat_multiplier(2), 1.0 + growth, 0.0001, "each level on top of the previous")


func test_enemy_power_grows_per_stage() -> void:
	var growth := float(data.balance["enemy_power_growth_per_stage"])
	assert_near(data.enemy_power_multiplier(1), 1.0, 0.0001, "stage 1")
	assert_near(data.enemy_power_multiplier(10) / data.enemy_power_multiplier(9), 1.0 + growth, 0.0001, "stage 10 over stage 9")
	assert_eq(data.enemy_power_multiplier(10), pow(1.0 + growth, 9), "chapter 1 exactly as before M11")


## M11 (Dmitriy's choice, 17.10.2026): chapter 2's enemies grow by their own, slower step (stages.json →
## chapters[].enemy_power_growth_per_stage); stage 11 grows from stage 10 by it.
func test_chapter_two_enemies_grow_by_their_own_step() -> void:
	var growth: float = data.enemy_power_growth(2)
	assert_eq(growth, float(data.get_chapter(2)["enemy_power_growth_per_stage"]), "from stages.json")
	assert_true(growth > 0.0 and growth < float(data.balance["enemy_power_growth_per_stage"]), "slower than chapter 1")
	assert_eq(data.enemy_power_growth(1), float(data.balance["enemy_power_growth_per_stage"]), "chapter 1: balance.json")
	assert_near(data.enemy_power_multiplier(11) / data.enemy_power_multiplier(10), 1.0 + growth, 0.0001, "stage 11 over stage 10")
	for stage in range(12, 21):
		assert_near(data.enemy_power_multiplier(stage) / data.enemy_power_multiplier(stage - 1), 1.0 + growth, 0.0001,
				"stage %d over the stage before" % stage)


# --- chapters (M11) -------------------------------------------------------------

## Chapter 2 opens with the first win over the last stage of chapter 1; the map opens on the chapter of the next
## stage to win, on the last chapter once everything is won.
func test_chapter_two_opens_after_the_first_boss() -> void:
	var progress = Progress.new_game(data)
	assert_true(progress.is_chapter_open(data, 1), "chapter 1 is open from the start")
	assert_true(not progress.is_chapter_open(data, 2), "chapter 2 is closed")
	assert_eq(progress.current_chapter(data), 1, "the map opens on chapter 1")
	win_stages(progress, 9)
	assert_true(not progress.is_chapter_open(data, 2), "still closed before the boss")
	assert_true(not progress.is_stage_open(data, 11), "and so is stage 11")
	win_stages(progress, 10)
	assert_true(progress.is_chapter_open(data, 2), "open after the first win on stage 10")
	assert_eq(progress.current_chapter(data), 2, "the map opens on chapter 2")
	assert_eq(progress.next_stage_id(data), 11, "the next battle is stage 11")
	assert_true(progress.is_stage_open(data, 11) and not progress.is_stage_open(data, 12), "stage 11 open, 12 not yet")
	assert_true(progress.is_replay(3), "chapter 1 stays open for replays")
	win_stages(progress, 19)
	assert_true(not progress.is_chapter_open(data, 3), "chapter 3 is closed before Thjazi")
	win_stages(progress, 20)
	assert_true(progress.is_chapter_open(data, 3), "M13: chapter 3 opens with the first win on stage 20")
	assert_eq(progress.current_chapter(data), 3, "the map opens on chapter 3")
	assert_eq(progress.next_stage_id(data), 21, "the next battle is stage 21")
	win_stages(progress, 30)
	assert_eq(progress.current_chapter(data), 3, "everything won: the last chapter")
	assert_eq(progress.next_stage_id(data), 30, "the last stage")


## M13: a save from before M13 that has won chapter 2 has chapter 3 open at once.
func test_an_old_save_with_chapter_two_won_opens_chapter_three() -> void:
	var old := {"version": 2, "silver": 500, "cleared_stage": 20, "hero_levels": {"torvald": 18}}
	var progress = Progress.from_dict(old, data)
	assert_true(progress.is_chapter_open(data, 3), "chapter 3 is open")
	assert_eq(progress.current_chapter(data), 3, "the map opens on it")


## Dmitriy's save from before M11 (chapter 1 won): chapter 2 is open at once and the map opens on it.
func test_an_old_save_with_chapter_one_won_opens_chapter_two() -> void:
	var old := {"version": 2, "silver": 500, "cleared_stage": 10, "hero_levels": {"torvald": 12}}
	var progress = Progress.from_dict(old, data)
	assert_eq(progress.cleared_stage, 10, "the won stages stay")
	assert_true(progress.is_chapter_open(data, 2), "chapter 2 is open")
	assert_eq(progress.current_chapter(data), 2, "the map opens on it")
	var far := {"version": 2, "cleared_stage": 20}
	assert_eq(Progress.from_dict(far, data).cleared_stage, 20, "a save may hold stages up to 20")


## Chapter 2's packs: the Iron Wood wolves with chapter 2, the troll after stage 13, the scavengers after 16; like any
## pack they fight at the strength of the last stage won and pay its share. Midgard's packs grow with it too.
func test_chapter_two_packs() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 9)
	for pack_id in data.pack_ids(2):
		assert_true(not progress.is_pack_available(data, pack_id, NOW), "%s is not on the map before chapter 2" % pack_id)
	win_stages(progress, 10)
	assert_true(progress.is_pack_available(data, "ironwood_wolves", NOW), "the Iron Wood wolves with chapter 2")
	assert_true(not progress.is_pack_available(data, "troll", NOW), "not the troll yet")
	win_stages(progress, 13)
	assert_true(progress.is_pack_available(data, "troll", NOW), "the troll after stage 13")
	assert_true(not progress.is_pack_available(data, "scavengers", NOW), "not the scavengers yet")
	win_stages(progress, 16)
	assert_true(progress.is_pack_available(data, "scavengers", NOW), "the scavengers after stage 16")
	assert_eq(progress.pack_stage(data, "scavengers"), 16, "at the strength of stage 16")
	var share := float(data.balance["beast_packs"]["reward_share_of_first_win"])
	assert_eq(progress.pack_reward(data, "scavengers")["silver"],
			roundi(float(data.get_stage(16)["reward"]["silver"]) * share * progress.silver_multiplier(data)), "a share of stage 16")
	progress.apply_pack_victory(data, "scavengers", NOW)
	assert_eq(progress.pack_seconds_left(data, "scavengers", NOW), data.pack_respawn_seconds(), "its own timer")
	assert_true(progress.is_pack_available(data, "troll", NOW), "the other packs stay")
	assert_true(progress.is_pack_available(data, "bear", NOW), "Midgard's packs too")


func test_level_up_spends_silver() -> void:
	var progress = Progress.new_game(data)
	var cost: int = data.level_up_cost(1)
	progress.silver = cost + 7
	assert_true(progress.level_up(data, "torvald"), "level-up done")
	assert_eq(progress.level_of("torvald"), 2, "new level")
	assert_eq(progress.silver, 7, "silver spent")


func test_level_up_needs_enough_silver_and_stops_at_max() -> void:
	var progress = Progress.new_game(data)
	progress.silver = data.level_up_cost(1) - 1
	assert_true(not progress.level_up(data, "torvald"), "cannot afford")
	progress.hero_levels["sigrid"] = data.max_level()
	progress.silver = 100000000
	assert_true(not progress.level_up(data, "sigrid"), "no level-up past max")
	assert_true(not progress.level_up(data, "skadi"), "locked hero cannot be levelled")


# --- rewards, replays, unlocks ------------------------------------------------

func test_first_win_pays_full_reward_and_opens_next_stage() -> void:
	var progress = Progress.new_game(data)
	var base: Dictionary = data.get_stage(1)["reward"]
	var paid: Dictionary = progress.apply_victory(data, 1)
	assert_eq(paid["silver"], int(base["silver"]), "full silver at jarl level 1")
	assert_eq(paid["experience"], int(base["experience"]), "full experience")
	assert_true(not paid["replay"], "not a replay")
	assert_eq(progress.cleared_stage, 1, "stage 1 won")
	assert_true(progress.is_stage_open(data, 2), "stage 2 open")
	assert_true(not progress.is_stage_open(data, 3), "stage 3 still locked")


func test_replay_pays_its_share_and_changes_nothing_else() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 2)
	var silver_before: int = progress.silver
	var share := float(data.balance["replay_reward_share"])
	var base: Dictionary = data.get_stage(1)["reward"]
	var paid: Dictionary = progress.apply_victory(data, 1)
	assert_true(paid["replay"], "stage 1 is a replay")
	assert_eq(paid["silver"], roundi(float(base["silver"]) * share * progress.silver_multiplier(data)), "replay silver")
	assert_eq(paid["experience"], roundi(float(base["experience"]) * share), "replay experience")
	assert_eq(progress.silver, silver_before + paid["silver"], "silver added")
	assert_eq(progress.cleared_stage, 2, "progress unchanged")


func test_heroes_join_after_their_stages() -> void:
	var progress = Progress.new_game(data)
	for hero in data.heroes["heroes"]:
		var unlock_stage := int(hero["unlock_after_stage"])
		if unlock_stage == 0 or hero.has("joins_after_scene"):  # Regin joins after his scene (test_regin_joins_after_his_scene)
			continue
		win_stages(progress, unlock_stage - 1)
		assert_true(not progress.hero_levels.has(hero["id"]), "%s locked before stage %d" % [hero["id"], unlock_stage])
		# One hero at 6, the rest at 9: a squad of 3 → 8.0, of 4 → 8.25, of 5 → 8.4; rounded down, always 8.
		progress.hero_levels[progress.hero_levels.keys()[0]] = 6
		for other in progress.hero_levels.keys().slice(1):
			progress.hero_levels[other] = 9
		var paid: Dictionary = progress.apply_victory(data, unlock_stage)
		assert_eq(paid["new_heroes"], [hero["id"]], "%s announced after stage %d" % [hero["id"], unlock_stage])
		assert_eq(progress.level_of(hero["id"]), 8, "%s joins at the squad's average level, rounded down" % hero["id"])
		assert_true(progress.apply_victory(data, unlock_stage)["new_heroes"].is_empty(), "a replay unlocks nobody")


## M13: Regin's stage is 20, but he joins at the end of his scene «ch3_intro» (heroes.json → joins_after_scene), not with
## the win: like a new hero (squad average level, a free slot or the bench), once. A scene counts as seen as soon as it
## starts, so a game closed during it has him on the next start (earned_hero_ids).
func test_regin_joins_after_his_scene() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 19)
	for hero_id in progress.hero_levels:
		progress.hero_levels[hero_id] = 12
	var paid: Dictionary = progress.apply_victory(data, 20)
	assert_true(not "regin" in paid["new_heroes"], "not announced with the win over stage 20")
	assert_true(not progress.hero_levels.has("regin"), "not here yet")
	assert_true(not "regin" in progress.earned_hero_ids(data), "not earned before his scene")
	assert_eq(progress.join_heroes_after_scene(data, "ch2_boss_after"), [] as Array[String], "another scene brings nobody")
	progress.start_scene("ch3_intro")
	assert_true("regin" in progress.earned_hero_ids(data), "earned once his scene has started")
	assert_eq(progress.join_heroes_after_scene(data, "ch3_intro"), ["regin"] as Array[String], "joins at its end")
	assert_eq(progress.level_of("regin"), 12, "at the squad's average level")
	assert_true(not progress.is_in_formation("regin"), "the squad is full: «Не в отряде»")
	assert_eq(progress.join_heroes_after_scene(data, "ch3_intro"), [] as Array[String], "only once")
	var early = Progress.new_game(data)
	win_stages(early, 10)
	early.start_scene("ch3_intro")
	assert_eq(early.join_heroes_after_scene(data, "ch3_intro"), [] as Array[String], "not before stage 20 is won")


func test_join_level_is_the_squad_average_rounded_down() -> void:
	assert_eq(data.balance["new_hero"]["join_level"], "squad_average", "rule in balance.json")
	var progress = Progress.new_game(data)
	win_stages(progress, 2)
	progress.hero_levels["torvald"] = 10
	progress.hero_levels["sigrid"] = 7
	progress.hero_levels["eyvind"] = 1
	progress.apply_victory(data, 3)
	assert_eq(progress.level_of("angrboda"), 6, "(10 + 7 + 1) / 3 = 6")
	progress.hero_levels["angrboda"] = 5
	win_stages(progress, 5)
	progress.apply_victory(data, 6)
	assert_eq(progress.level_of("skadi"), 5, "(10 + 7 + 1 + 5) / 4 = 5.75 → 5")


func test_a_hero_on_the_bench_does_not_pull_newcomers_down() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 2)
	progress.hero_levels["torvald"] = 8
	progress.hero_levels["sigrid"] = 6
	progress.hero_levels["eyvind"] = 1
	progress.formation_remove("eyvind")
	progress.apply_victory(data, 3)
	assert_eq(progress.level_of("angrboda"), 7, "only the squad counts: (8 + 6) / 2")


func test_weakest_rule_from_balance_json() -> void:
	var weakest_data = GameData.load_all()
	weakest_data.balance["new_hero"]["join_level"] = "weakest"
	var progress = Progress.new_game(weakest_data)
	for stage in range(1, 3):
		progress.apply_victory(weakest_data, stage)
	progress.hero_levels["torvald"] = 8
	progress.hero_levels["sigrid"] = 6
	progress.hero_levels["eyvind"] = 2
	progress.formation_remove("eyvind")
	progress.apply_victory(weakest_data, 3)
	assert_eq(progress.level_of("angrboda"), 2, "the weakest unlocked hero, bench included")


func test_new_heroes_take_free_slots_and_wait_when_full() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 9)
	# 2 front + 3 back slots: Hrungnir (a front-row class) finds no free slot after the first five heroes.
	assert_eq(progress.squad_ids().size(), data.slot_count(), "squad full")
	assert_true(progress.is_in_formation("skadi") and progress.is_in_formation("angrboda"), "Skadi and Angrboda joined the squad")
	assert_true(not progress.is_in_formation("hrungnir"), "Hrungnir waits outside the squad")


# --- formation ----------------------------------------------------------------

func test_formation_uses_default_row_first() -> void:
	var progress = Progress.new_game(data)
	var squad: Array = progress.squad(data)
	var rows := {}
	for member in squad:
		rows[member["id"]] = member["row"]
	assert_eq(rows, {"torvald": "front", "sigrid": "front", "eyvind": "back"}, "default rows")


func test_formation_falls_back_to_the_other_row() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 9)
	progress.formation_remove("eyvind")
	assert_true(progress.formation_add(data, "hrungnir"), "Hrungnir added")
	var hrungnir: Dictionary = progress.squad(data).filter(func(m): return m["id"] == "hrungnir")[0]
	assert_eq(hrungnir["row"], "back", "front row full, so the back row")


func test_formation_remove_and_add_back() -> void:
	var progress = Progress.new_game(data)
	assert_true(progress.formation_remove("sigrid"), "removed")
	assert_true(not progress.is_in_formation("sigrid"), "not in squad")
	assert_true(progress.formation_add(data, "sigrid"), "added back")
	assert_true(not progress.formation_add(data, "sigrid"), "no duplicates")
	assert_true(not progress.formation_add(data, "skadi"), "locked hero cannot join")


func test_last_hero_cannot_leave() -> void:
	var progress = Progress.new_game(data)
	progress.formation_remove("torvald")
	progress.formation_remove("sigrid")
	assert_true(not progress.formation_remove("eyvind"), "last hero stays")
	assert_eq(progress.squad_ids(), ["eyvind"], "one hero left")


func test_full_formation_rejects_more() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 9)
	assert_true(not progress.formation_add(data, "hrungnir"), "no free slot")


# --- jarl ---------------------------------------------------------------------

func test_jarl_level_needs_step_times_level() -> void:
	var step := int(data.balance["jarl"]["exp_per_level"])
	var progress = Progress.new_game(data)
	var cases := [[0, 1], [step - 1, 1], [step, 2], [step + 2 * step - 1, 2], [step + 2 * step, 3], [step * (1 + 2 + 3), 4]]
	for case in cases:
		progress.experience = case[0]
		assert_eq(progress.jarl_level(data), case[1], "jarl level at %d experience" % case[0])
	progress.experience = step + 5
	assert_eq(progress.jarl_level_progress(data), [5, 2 * step], "progress inside level 2")


func test_jarl_level_raises_silver() -> void:
	var bonus := float(data.balance["jarl"]["silver_bonus_per_level"])
	var progress = Progress.new_game(data)
	progress.experience = int(data.balance["jarl"]["exp_per_level"])  # level 2
	assert_near(progress.silver_multiplier(data), 1.0 + bonus, 0.0001, "level 2 bonus")
	var base: Dictionary = data.get_stage(1)["reward"]
	assert_eq(progress.apply_victory(data, 1)["silver"], roundi(float(base["silver"]) * (1.0 + bonus)), "battle silver with the bonus")


# --- offline income -----------------------------------------------------------

func expected_offline_cap(progress) -> int:
	var first_win: float = data.get_stage(progress.next_stage_id(data))["reward"]["silver"]
	return roundi(float(data.balance["offline_income"]["full_time_in_first_wins"]) * first_win * progress.silver_multiplier(data))


func test_full_absence_pays_set_number_of_first_wins_of_current_stage() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 3)
	progress.experience = 0
	progress.last_seen_unix = 1000000
	var cap := expected_offline_cap(progress)
	var max_hours := float(data.balance["offline_income"]["max_hours"])
	assert_eq(progress.offline_income_cap(data), cap, "cap from stage 4 first-win silver")
	assert_eq(progress.offline_income(data, 1000000 + int(max_hours * 3600)), cap, "full absence")
	assert_eq(progress.offline_income(data, 1000000 + 100 * 3600), cap, "capped")
	var max_minutes := int(max_hours * 60)
	assert_eq(progress.offline_income(data, 1000000 + 30 * 60), cap * 30 / max_minutes, "30 minutes away")
	assert_eq(progress.offline_income(data, 1000000 + 30 * 60 + 59), cap * 30 / max_minutes, "whole minutes only")
	assert_eq(progress.offline_income(data, 1000000 - 3600), 0, "clock moved back")


## M11: on stages 11–20 the income follows the current stage of chapter 2 the same way.
## M11.1: the rule is general — with a third chapter in the data, Jotunheim's packs pay the smaller share as soon as
## chapter 3 opens (its first stage can be fought), the full share before.
func test_packs_of_any_passed_chapter_pay_the_smaller_share() -> void:
	var three = GameData.load_all()
	three.stages["chapters"].append({"id": 3, "name": "Свартальфхейм", "map": "map_jotunheim"})
	three.stages["stages"].append({"id": 21, "chapter": 3, "recommended_power": 1, "map_point": {"x": 0.5, "y": 0.5, "label": "left"},
			"reward": {"silver": 5000, "experience": 500}, "waves": [["ice_troll"]]})
	var share := float(three.balance["beast_packs"]["reward_share_of_first_win"])
	var past_share := float(three.balance["beast_packs"]["reward_share_once_the_next_chapter_is_open"])
	var progress = Progress.new_game(three)
	progress.cleared_stage = 19
	assert_eq(progress.pack_reward(three, "troll")["silver"],
			roundi(float(three.get_stage(19)["reward"]["silver"]) * share * progress.silver_multiplier(three)), "chapter 2 is current: full share")
	progress.cleared_stage = 20
	assert_true(progress.is_chapter_open(three, 3), "chapter 3 opens after stage 20")
	assert_eq(progress.pack_reward(three, "troll")["silver"],
			roundi(float(three.get_stage(20)["reward"]["silver"]) * past_share * progress.silver_multiplier(three)), "chapter 2 is passed: smaller share")
	assert_eq(progress.pack_reward(three, "wolves")["silver"],
			roundi(float(three.get_stage(10)["reward"]["silver"]) * past_share * progress.silver_multiplier(three)), "and so is chapter 1")


func test_offline_income_on_chapter_two() -> void:
	var progress = Progress.new_game(data)
	for stage in range(10, 20):
		win_stages(progress, stage)
		var current: int = progress.next_stage_id(data)
		assert_eq(current, stage + 1, "after stage %d the current stage is %d" % [stage, stage + 1])
		assert_eq(progress.offline_income_cap(data), expected_offline_cap(progress), "stage %d: 2.5 first wins of stage %d" % [stage, current])
		assert_true(progress.offline_income_cap(data) > roundi(2.0 * float(data.get_stage(current)["reward"]["silver"])),
				"stage %d: more than two first wins of stage %d" % [stage, current])


func test_offline_income_follows_the_current_stage_up_to_the_last() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, data.stage_count())
	progress.experience = 0
	var last_win: float = data.get_stage(data.stage_count())["reward"]["silver"]
	assert_eq(progress.offline_income_cap(data),
		roundi(float(data.balance["offline_income"]["full_time_in_first_wins"]) * last_win), "chapter done: last stage reward")


func test_no_offline_income_before_first_win_or_first_visit() -> void:
	var progress = Progress.new_game(data)
	progress.last_seen_unix = 1000000
	assert_eq(progress.offline_income(data, 1000000 + 3600), 0, "no stage won yet")
	win_stages(progress, 1)
	progress.last_seen_unix = 0
	assert_eq(progress.offline_income(data, 1000000 + 3600), 0, "never seen before")


func test_offline_income_gets_jarl_bonus() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 2)
	progress.experience = int(data.balance["jarl"]["exp_per_level"])  # level 2
	progress.last_seen_unix = 1000000
	assert_true(progress.silver_multiplier(data) > 1.0, "jarl bonus active")
	assert_eq(progress.offline_income_cap(data), expected_offline_cap(progress), "with the bonus")


func test_return_banks_offline_income_and_restarts_the_clock() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 2)
	progress.experience = 0
	progress.last_seen_unix = 1000000
	var expected: int = progress.offline_income(data, 1000000 + 3600)
	assert_eq(progress.collect_offline_income(data, 1000000 + 3600), expected, "income for the hour away")
	assert_eq(progress.offline_bank, expected, "banked, not yet in silver")
	assert_eq(progress.last_seen_unix, 1000000 + 3600, "clock restarted")
	assert_eq(progress.collect_offline_income(data, 1000000 + 3600), 0, "coming back again at once adds nothing")


func test_each_absence_is_capped_separately_and_claim_moves_bank_to_silver() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 2)
	progress.experience = 0
	var silver_before: int = progress.silver
	progress.last_seen_unix = 1000000
	var cap: int = progress.offline_income(data, 1000000 + 100 * 3600)
	progress.collect_offline_income(data, 1000000 + 100 * 3600)
	progress.collect_offline_income(data, 1000000 + 200 * 3600)
	assert_eq(progress.offline_bank, 2 * cap, "two long absences, each up to the cap")
	assert_eq(progress.claim_offline_bank(), 2 * cap, "claimed amount")
	assert_eq(progress.silver, silver_before + 2 * cap, "added to silver")
	assert_eq(progress.offline_bank, 0, "bank emptied")


func test_reset_returns_everything_to_a_new_game() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 9)
	progress.silver = 5000
	progress.hero_levels["sigrid"] = 12
	progress.formation_remove("eyvind")
	progress.last_seen_unix = 1000000
	progress.collect_offline_income(data, 1000000 + 3600)
	progress.apply_pack_victory(data, "wolves", 1000000)
	assert_true(progress.offline_bank > 0, "something in the offline bank before the reset")
	progress.reset(data, 2000000)
	var expected: Dictionary = Progress.new_game(data).to_dict()
	expected["last_seen_unix"] = 2000000
	assert_eq(progress.to_dict(), expected, "same as a new game, offline clock restarted at the reset")
	assert_eq(progress.collect_offline_income(data, 2000000 + 8 * 3600), 0, "no offline income until the first win again")


func test_unlock_all_heroes_joins_the_locked_ones_at_the_squad_average() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 3)
	progress.hero_levels["torvald"] = 9
	progress.hero_levels["sigrid"] = 6
	progress.hero_levels["eyvind"] = 4
	progress.hero_levels["angrboda"] = 4
	var locked: Array = data.heroes["heroes"].map(func(h): return h["id"]).filter(func(id): return not progress.hero_levels.has(id))
	var joined: Array[String] = progress.unlock_all_heroes(data)
	assert_eq(Array(joined), locked, "the locked heroes joined, in data order")
	assert_eq(progress.hero_levels.size(), data.heroes["heroes"].size(), "every hero unlocked")
	for hero_id in joined:
		assert_eq(progress.level_of(hero_id), 5, "%s joins at the squad average counted before the first newcomer: 23 / 4 → 5" % hero_id)
	assert_eq(progress.squad_ids().size(), data.slot_count(), "free slots filled")
	assert_true(progress.unlock_all_heroes(data).is_empty(), "nothing left to unlock")


func test_jump_to_stage_marks_earlier_stages_won_without_rewards() -> void:
	var progress = Progress.new_game(data)
	progress.jump_to_stage(data, 7)
	assert_eq(progress.cleared_stage, 6, "stages 1–6 won")
	assert_eq(progress.next_stage_id(data), 7, "stage 7 is the next battle")
	assert_eq(progress.silver, int(data.balance["start_silver"]), "no rewards paid")
	assert_eq(progress.experience, 0, "no experience")
	assert_eq(progress.hero_levels.keys(), data.unlocked_hero_ids(6), "heroes of stages 1–6 joined")
	progress.jump_to_stage(data, 2)
	assert_eq(progress.next_stage_id(data), 2, "can jump back")
	assert_eq(progress.hero_levels.keys(), data.unlocked_hero_ids(6), "unlocked heroes stay")
	progress.jump_to_stage(data, 999)
	assert_eq(progress.next_stage_id(data), data.stage_count(), "clamped to the last stage")


# --- saves --------------------------------------------------------------------

func test_progress_survives_dict_round_trip() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 6)
	progress.silver = 1234
	progress.hero_levels["eyvind"] = 7
	progress.formation_remove("sigrid")
	progress.last_seen_unix = 1790000000
	progress.offline_bank = 321
	progress.apply_pack_victory(data, "boars", 1790000000)
	var restored = Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())), data)
	assert_eq(restored.to_dict(), progress.to_dict(), "same progress after JSON round trip")


func test_heroes_opened_beyond_won_stages_survive_a_reload() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 1)
	progress.unlock_all_heroes(data)
	progress.hero_levels["hrungnir"] = 4
	var restored = Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())), data)
	assert_eq(restored.to_dict(), progress.to_dict(), "debug-opened heroes, their levels and slots kept")
	progress.jump_to_stage(data, 10)
	progress.jump_to_stage(data, 2)
	restored = Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())), data)
	assert_eq(restored.hero_levels.keys(), progress.hero_levels.keys(), "heroes kept after jumping back")


func test_save_from_before_the_m6_unlock_order() -> void:
	# Before M6 Skadi came after stage 3 and Angrboda after 6: a save with stage 4 won has Skadi, not Angrboda.
	var restored = Progress.from_dict({
		"version": Progress.VERSION, "silver": 0, "experience": 0, "cleared_stage": 4,
		"hero_levels": {"torvald": 6, "sigrid": 6, "eyvind": 6, "skadi": 4},
		"formation": ["torvald", "sigrid", "eyvind", "skadi", ""],
	}, data)
	assert_eq(restored.level_of("skadi"), 4, "Skadi kept with her level")
	assert_eq(restored.level_of("angrboda"), 5, "Angrboda joins at the squad average: (6 + 6 + 6 + 4) / 4 → 5")
	assert_true(restored.is_in_formation("angrboda"), "and takes the free slot")


func test_version_one_save_is_migrated() -> void:
	# An M3 save: no formation, no unlocked heroes, no last-seen time.
	var restored = Progress.from_dict({
		"version": 1, "silver": 500, "experience": 300, "cleared_stage": 8,
		"hero_levels": {"torvald": 9, "sigrid": 8, "eyvind": 7},
	}, data)
	assert_eq(restored.silver, 500, "silver kept")
	assert_eq(restored.level_of("torvald"), 9, "levels kept")
	assert_eq(restored.hero_levels.keys(), data.unlocked_hero_ids(8), "heroes earned by stage 8 unlocked")
	assert_eq(restored.level_of("skadi"), 8, "a hero earned before the update joins at the squad average of the saved levels")
	assert_eq(restored.level_of("angrboda"), 8, "every such hero gets the same level")
	assert_eq(restored.squad_ids().size(), 5, "squad filled")
	assert_eq(restored.last_seen_unix, 0, "no offline income for the gap before the update")


func test_broken_values_fall_back_to_safe_ones() -> void:
	var restored = Progress.from_dict({
		"version": Progress.VERSION, "silver": "a lot", "experience": -5, "cleared_stage": 999,
		"hero_levels": {"torvald": 999, "sigrid": "x", "unknown_hero": 5},
		"formation": ["torvald", "torvald", "unknown_hero", 7, ""],
	}, data)
	assert_eq(restored.silver, int(data.balance["start_silver"]), "non-number silver ignored")
	assert_eq(restored.experience, 0, "negative experience clamped")
	assert_eq(restored.cleared_stage, data.stage_count(), "cleared stage clamped")
	assert_eq(restored.level_of("torvald"), data.max_level(), "level clamped to max")
	assert_eq(restored.level_of("sigrid"), restored.level_of("torvald"), "broken level: joins like a new hero (the squad is Torvald alone)")
	assert_true(not restored.hero_levels.has("unknown_hero"), "unknown hero ignored")
	assert_eq(restored.formation[0], "torvald", "saved slot kept")
	assert_eq(restored.formation.count("torvald"), 1, "duplicates dropped from the formation")
	assert_true(not restored.is_in_formation("unknown_hero"), "unknown heroes dropped from the formation")
	# Heroes without a saved level join like new heroes, into the free slots (M6).
	assert_eq(restored.squad_ids().size(), data.slot_count(), "free slots taken by the heroes that joined")


func test_empty_saved_formation_is_refilled() -> void:
	var restored = Progress.from_dict({"version": Progress.VERSION, "cleared_stage": 0, "formation": ["", "", "", "", ""]}, data)
	assert_eq(restored.squad_ids(), data.starting_hero_ids(), "squad rebuilt")


func test_non_number_version_starts_new_game() -> void:
	for broken_version in [{}, [], "1", null]:
		var restored = Progress.from_dict({"version": broken_version, "silver": 999}, data)
		assert_eq(restored.to_dict(), Progress.new_game(data).to_dict(), "version %s gives a new game" % str(broken_version))


# --- squad power («Сила») -----------------------------------------------------

func test_hero_power_formula_from_balance_json() -> void:
	var weights: Dictionary = data.balance["squad_power"]
	var hero: Dictionary = data.get_hero("torvald")
	var no_bonus := {"hp": 0.0, "attack": 0.0}
	var expected := float(hero["hp"]) * float(weights["hp_weight"]) + float(hero["attack"]) * float(weights["attack_weight"])
	assert_eq(data.hero_power("torvald", 1, no_bonus), roundi(expected), "level 1: HP × hp_weight + attack × attack_weight")
	var multiplier: float = data.hero_stat_multiplier(5)
	assert_eq(data.hero_power("torvald", 5, no_bonus), roundi(expected * multiplier), "HP and attack grow with the level")
	var with_hp_bonus := float(hero["hp"]) * 1.2 * float(weights["hp_weight"]) + float(hero["attack"]) * float(weights["attack_weight"])
	assert_eq(data.hero_power("torvald", 1, {"hp": 0.2, "attack": 0.0}), roundi(with_hp_bonus), "clan bonus counts")


func test_squad_power_is_the_sum_over_the_squad_with_clan_bonuses() -> void:
	var progress = Progress.new_game(data)
	var synergy: Dictionary = data.synergy_bonuses(progress.squad_ids())
	assert_true(synergy["hp"] > 0.0, "three Midgard heroes: the HP bonus is on")
	var total := 0
	for hero_id in progress.squad_ids():
		total += data.hero_power(hero_id, progress.level_of(hero_id), synergy)
	assert_eq(progress.squad_power(data), total, "sum of the squad heroes")
	progress.hero_levels["sigrid"] = 4
	assert_true(progress.squad_power(data) > total, "a level-up raises the power")


func test_bench_hero_does_not_count_and_level_up_gain_matches() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 9)
	assert_true(not progress.is_in_formation("hrungnir"), "Hrungnir waits on the bench")
	var before: int = progress.squad_power(data)
	progress.hero_levels["hrungnir"] = 20
	assert_eq(progress.squad_power(data), before, "the bench does not add to the squad's power")
	assert_eq(progress.hero_power(data, "hrungnir"), data.hero_power("hrungnir", 20, data.synergy_bonuses([])), "bench hero: no clan bonus")
	for hero_id in progress.squad_ids():
		var gain: int = progress.level_up_power_gain(data, hero_id)
		var power_before: int = progress.squad_power(data)
		progress.hero_levels[hero_id] += 1
		assert_eq(progress.squad_power(data) - power_before, gain, "«+N силы» of %s is what the squad gains" % hero_id)
		assert_true(gain > 0, "%s gains power" % hero_id)


# --- the map's red numbers (M6.1; the target mark hint became the tutorial's hint, M14: test_tutorial.gd) ---

func test_recommended_power_is_red_only_while_the_squad_is_weaker() -> void:
	var progress = Progress.new_game(data)
	var stage: int = data.stage_count()
	assert_true(progress.is_below_recommended(data, stage), "a new squad is weaker than the boss stage asks")
	assert_true(not progress.is_below_recommended(data, 1), "a new squad is strong enough for stage 1")
	while progress.squad_power(data) < data.recommended_power(stage):
		for hero_id in progress.squad_ids():
			progress.hero_levels[hero_id] += 1
	assert_true(not progress.is_below_recommended(data, stage), "at or above the recommended power: not red")


# --- beast packs (M9) ------------------------------------------------------------

const NOW := 1800000000


func test_packs_unlock_after_their_stage() -> void:
	var progress = Progress.new_game(data)
	for pack_id in data.pack_ids():
		var unlock := int(data.get_pack(pack_id)["unlock_after_stage"])
		progress.cleared_stage = maxi(0, unlock - 1)
		if unlock > 0:
			assert_true(not progress.is_pack_available(data, pack_id, NOW), "%s is locked before stage %d" % [pack_id, unlock])
		progress.cleared_stage = unlock
		assert_true(progress.is_pack_available(data, pack_id, NOW), "%s is on the map after stage %d" % [pack_id, unlock])


func test_pack_strength_and_reward_follow_the_last_stage_won() -> void:
	var progress = Progress.new_game(data)
	var share := float(data.balance["beast_packs"]["reward_share_of_first_win"])
	assert_eq(progress.pack_stage(data, "wolves"), 1, "before the first win the packs are as strong as stage 1")
	assert_eq(progress.pack_reward(data, "wolves")["silver"], roundi(float(data.get_stage(1)["reward"]["silver"]) * share), "and pay a share of stage 1")
	win_stages(progress, 6)
	assert_eq(progress.pack_stage(data, "wolves"), 6, "after stage 6: stage 6 strength")
	var reward: Dictionary = data.get_stage(6)["reward"]
	var expected := {
		"silver": roundi(float(reward["silver"]) * share * progress.silver_multiplier(data)),
		"experience": roundi(float(reward["experience"]) * share),
		"supplies": 0,  # construction opens after chapter 1 (M12)
	}
	assert_eq(progress.pack_reward(data, "wolves"), expected, "a share of stage 6's first win, silver with the jarl bonus")
	assert_true(progress.silver_multiplier(data) > 1.0, "the jarl bonus is really in play here")


## M11.1 (Dmitriy, 17.10.2026): a pack follows the last stage won in ITS chapter. Midgard's packs stop at stage 10
## (their strength and reward do not grow in chapter 2) and, once chapter 2 is open, pay the smaller share
## (beast_packs.reward_share_once_the_next_chapter_is_open); Jotunheim's follow stages 11–20 and, before the first win
## in chapter 2, are as strong as stage 11.
func test_packs_follow_the_last_stage_won_in_their_own_chapter() -> void:
	var share := float(data.balance["beast_packs"]["reward_share_of_first_win"])
	var progress = Progress.new_game(data)
	win_stages(progress, 10)
	for pack_id in data.pack_ids(1):
		assert_eq(progress.pack_stage(data, pack_id), 10, "%s: stage 10 after chapter 1" % pack_id)
	assert_eq(progress.pack_stage(data, "ironwood_wolves"), 11, "Jotunheim's wolves before the first win there: stage 11")
	win_stages(progress, 15)
	var past_share := float(data.balance["beast_packs"]["reward_share_once_the_next_chapter_is_open"])
	assert_true(past_share < share, "the chapter behind pays a smaller share")
	for pack_id in data.pack_ids(1):
		assert_eq(progress.pack_stage(data, pack_id), 10, "%s: still stage 10 in chapter 2" % pack_id)
		var midgard: Dictionary = data.get_stage(10)["reward"]
		assert_eq(progress.pack_reward(data, pack_id), {
			"silver": roundi(float(midgard["silver"]) * past_share * progress.silver_multiplier(data)),
			"experience": roundi(float(midgard["experience"]) * past_share),
			"supplies": int(data.balance["supplies"]["pack_victory_once_the_next_chapter_is_open"])},
			"%s pays the smaller share of stage 10" % pack_id)
	for pack_id in data.pack_ids(2):
		assert_eq(progress.pack_stage(data, pack_id), 15, "%s: stage 15" % pack_id)
	var jotunheim := roundi(float(data.get_stage(15)["reward"]["silver"]) * share * progress.silver_multiplier(data))
	assert_eq(progress.pack_reward(data, "troll")["silver"], jotunheim, "the troll pays a share of stage 15")
	var before: int = progress.silver
	progress.apply_pack_victory(data, "bear", NOW)
	assert_eq(progress.silver - before,
			roundi(float(data.get_stage(10)["reward"]["silver"]) * past_share * progress.silver_multiplier(data)), "the bear pays as at stage 10")
	win_stages(progress, 19)
	assert_eq(progress.pack_stage(data, "scavengers"), 19, "Jotunheim's packs follow stages 11–20")
	assert_eq(progress.pack_reward(data, "scavengers")["silver"],
			roundi(float(data.get_stage(19)["reward"]["silver"]) * share * progress.silver_multiplier(data)),
			"the full share while chapter 2 is the current one")
	win_stages(progress, 25)
	assert_eq(progress.pack_stage(data, "scavengers"), 20, "M13: Jotunheim's packs stop at stage 20")
	assert_eq(progress.pack_reward(data, "scavengers")["silver"],
			roundi(float(data.get_stage(20)["reward"]["silver"]) * past_share * progress.silver_multiplier(data)),
			"and pay the smaller share once chapter 3 is open")
	assert_eq(progress.pack_stage(data, "cave_spiders"), 25, "Svartalfheim's packs follow stages 21–30")
	win_stages(progress, 30)
	assert_eq(progress.pack_stage(data, "forge_spirits"), 30, "up to stage 30")
	assert_eq(progress.pack_reward(data, "forge_spirits")["silver"],
			roundi(float(data.get_stage(30)["reward"]["silver"]) * share * progress.silver_multiplier(data)),
			"the last chapter's packs keep the full share after its boss")
	var midgard_only = Progress.new_game(data)
	win_stages(midgard_only, 9)
	assert_eq(midgard_only.pack_reward(data, "bear")["silver"],
			roundi(float(data.get_stage(9)["reward"]["silver"]) * share * midgard_only.silver_multiplier(data)),
			"before chapter 2 opens Midgard's packs pay the full share")
	assert_eq(progress.pack_stage(data, "boars"), 10, "Midgard's stay at stage 10")


func test_beaten_pack_pays_and_comes_back_after_the_respawn_time() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 4)
	var expected: Dictionary = progress.pack_reward(data, "boars")
	var silver_before: int = progress.silver
	var experience_before: int = progress.experience
	assert_eq(progress.apply_pack_victory(data, "boars", NOW), expected, "the reward is returned")
	assert_eq(progress.silver - silver_before, int(expected["silver"]), "silver paid")
	assert_eq(progress.experience - experience_before, int(expected["experience"]), "experience paid")
	var respawn: int = data.pack_respawn_seconds()
	assert_eq(progress.pack_seconds_left(data, "boars", NOW), respawn, "the pack is away for the respawn time")
	assert_true(not progress.is_pack_available(data, "boars", NOW + respawn - 1), "still away a second before")
	assert_eq(progress.pack_seconds_left(data, "boars", NOW + 3600), respawn - 3600, "time counts by the clock (also while the game is closed)")
	assert_true(progress.is_pack_available(data, "boars", NOW + respawn), "back on the map after the respawn time")
	assert_true(progress.is_pack_available(data, "wolves", NOW), "other packs are not touched")


func test_skip_time_brings_packs_back_sooner() -> void:
	var progress = Progress.new_game(data)
	progress.apply_pack_victory(data, "wolves", NOW)
	var respawn: int = data.pack_respawn_seconds()
	progress.skip_pack_timers(3600)
	assert_eq(progress.pack_seconds_left(data, "wolves", NOW), respawn - 3600, "an hour less to wait")
	progress.skip_pack_timers(respawn)
	assert_true(progress.is_pack_available(data, "wolves", NOW), "back once the skipped time covers the wait")


func test_pack_timer_never_grows_past_the_respawn_time() -> void:
	var progress = Progress.new_game(data)
	progress.apply_pack_victory(data, "wolves", NOW)
	assert_eq(progress.pack_seconds_left(data, "wolves", NOW - 24 * 3600), data.pack_respawn_seconds(),
			"the device clock turned back a day: still at most the respawn time")


func test_turning_the_clock_back_moves_the_saved_pack_time() -> void:
	var progress = Progress.new_game(data)
	var respawn: int = data.pack_respawn_seconds()
	progress.apply_pack_victory(data, "wolves", NOW)
	var back := NOW - 24 * 3600
	progress.update_pack_timers(data, back)
	assert_eq(progress.pack_respawn_unix["wolves"], back + respawn, "the saved time moves back with the clock")
	assert_true(progress.is_pack_available(data, "wolves", back + respawn), "back after the respawn time of real waiting")
	# A small step back: an hour after the win the clock goes back 30 minutes; the pack still comes back
	# after the respawn time of real waiting.
	var won_at := NOW + 7 * 24 * 3600
	progress.apply_pack_victory(data, "boars", won_at)
	progress.update_pack_timers(data, won_at + 3600)
	progress.update_pack_timers(data, won_at + 1800)
	assert_eq(progress.pack_seconds_left(data, "boars", won_at + 1800), respawn - 3600, "an hour of real waiting counts")
	progress.apply_pack_victory(data, "wolves", NOW)
	progress.update_pack_timers(data, NOW + respawn)
	assert_true(not progress.pack_respawn_unix.has("wolves"), "a pack that came back is forgotten")
	assert_true(progress.is_pack_available(data, "wolves", NOW), "turning the clock back does not send it away again")


func test_pack_timers_are_saved_and_old_saves_have_every_pack_on_the_map() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 6)
	progress.apply_pack_victory(data, "bear", NOW)
	var restored = Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())), data)
	assert_eq(restored.pack_seconds_left(data, "bear", NOW), data.pack_respawn_seconds(), "the timer survives a reload")
	var old_save: Dictionary = progress.to_dict()
	old_save.erase("pack_respawn_unix")
	restored = Progress.from_dict(old_save, data)
	for pack_id in data.pack_ids(1):
		assert_true(restored.is_pack_available(data, pack_id, NOW), "a save from before M9: %s is on the map" % pack_id)
	old_save["pack_respawn_unix"] = {"bear": "soon", "nobody": NOW}
	restored = Progress.from_dict(old_save, data)
	assert_eq(restored.pack_respawn_unix, {}, "broken values and unknown packs are dropped")
