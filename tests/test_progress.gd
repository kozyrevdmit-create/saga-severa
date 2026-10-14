## Progress rules: levelling, rewards and replays, hero unlocks, formation, jarl level, offline income, saves.
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
		if unlock_stage == 0:
			continue
		win_stages(progress, unlock_stage - 1)
		assert_true(not progress.hero_levels.has(hero["id"]), "%s locked before stage %d" % [hero["id"], unlock_stage])
		progress.hero_levels[progress.hero_levels.keys()[0]] = 7
		for other in progress.hero_levels.keys().slice(1):
			progress.hero_levels[other] = 9
		var paid: Dictionary = progress.apply_victory(data, unlock_stage)
		assert_eq(paid["new_heroes"], [hero["id"]], "%s announced after stage %d" % [hero["id"], unlock_stage])
		assert_eq(progress.level_of(hero["id"]), 7, "%s joins at the weakest hero's level" % hero["id"])
		assert_true(progress.apply_victory(data, unlock_stage)["new_heroes"].is_empty(), "a replay unlocks nobody")


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
	assert_true(progress.offline_bank > 0, "something in the offline bank before the reset")
	progress.reset(data, 2000000)
	var expected: Dictionary = Progress.new_game(data).to_dict()
	expected["last_seen_unix"] = 2000000
	assert_eq(progress.to_dict(), expected, "same as a new game, offline clock restarted at the reset")
	assert_eq(progress.collect_offline_income(data, 2000000 + 8 * 3600), 0, "no offline income until the first win again")


func test_unlock_all_heroes_joins_the_locked_ones_at_the_weakest_level() -> void:
	var progress = Progress.new_game(data)
	win_stages(progress, 3)
	progress.hero_levels["torvald"] = 5
	var locked: Array = data.heroes["heroes"].map(func(h): return h["id"]).filter(func(id): return not progress.hero_levels.has(id))
	var joined: Array[String] = progress.unlock_all_heroes(data)
	assert_eq(Array(joined), locked, "the locked heroes joined, in data order")
	assert_eq(progress.hero_levels.size(), data.heroes["heroes"].size(), "every hero unlocked")
	for hero_id in joined:
		assert_eq(progress.level_of(hero_id), 1, "%s joins at the weakest level" % hero_id)
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
	var restored = Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())), data)
	assert_eq(restored.to_dict(), progress.to_dict(), "same progress after JSON round trip")


func test_version_one_save_is_migrated() -> void:
	# An M3 save: no formation, no unlocked heroes, no last-seen time.
	var restored = Progress.from_dict({
		"version": 1, "silver": 500, "experience": 300, "cleared_stage": 8,
		"hero_levels": {"torvald": 9, "sigrid": 8, "eyvind": 7},
	}, data)
	assert_eq(restored.silver, 500, "silver kept")
	assert_eq(restored.level_of("torvald"), 9, "levels kept")
	assert_eq(restored.hero_levels.keys(), data.unlocked_hero_ids(8), "heroes earned by stage 8 unlocked")
	assert_eq(restored.level_of("skadi"), 7, "a hero earned before the update joins at the weakest saved level")
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
	assert_eq(restored.level_of("sigrid"), restored.level_of("torvald"), "broken level: joins at the weakest valid saved level")
	assert_true(not restored.hero_levels.has("unknown_hero"), "unknown hero ignored")
	assert_eq(restored.squad_ids(), ["torvald"], "duplicates and unknown heroes dropped from the formation")


func test_empty_saved_formation_is_refilled() -> void:
	var restored = Progress.from_dict({"version": Progress.VERSION, "cleared_stage": 0, "formation": ["", "", "", "", ""]}, data)
	assert_eq(restored.squad_ids(), data.starting_hero_ids(), "squad rebuilt")


func test_non_number_version_starts_new_game() -> void:
	for broken_version in [{}, [], "1", null]:
		var restored = Progress.from_dict({"version": broken_version, "silver": 999}, data)
		assert_eq(restored.to_dict(), Progress.new_game(data).to_dict(), "version %s gives a new game" % str(broken_version))
