## Levelling for silver, stage rewards and progress (spec 4 and 5.3). Expected numbers come from data/*.json.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const Progress := preload("res://scripts/save/progress.gd")

var data = GameData.load_all()


func leveling() -> Dictionary:
	return data.balance["leveling"]


func test_new_game_starts_with_the_starting_squad_at_level_one() -> void:
	var progress = Progress.new_game(data)
	assert_eq(progress.silver, int(data.balance["start_silver"]), "start silver")
	assert_eq(progress.cleared_stage, 0, "no stages won")
	assert_eq(progress.hero_levels.keys(), data.starting_hero_ids(), "starting squad")
	for hero_id in progress.hero_levels:
		assert_eq(progress.level_of(hero_id), 1, "%s level" % hero_id)
	assert_eq(progress.next_stage_id(data), 1, "first battle is stage 1")


func test_level_up_cost_follows_the_spec_formula() -> void:
	# Spec 5.3: cost = 100 × 1.15^(level − 1); the numbers themselves live in balance.json.
	for level in [1, 2, 5, 10, 29]:
		var expected := roundi(float(leveling()["cost_base"]) * pow(float(leveling()["cost_growth"]), level - 1))
		assert_eq(data.level_up_cost(level), expected, "cost at level %d" % level)
	assert_eq(data.level_up_cost(1), int(leveling()["cost_base"]), "first level-up costs the base price")


func test_each_level_adds_stat_growth() -> void:
	var growth := float(leveling()["stat_growth_per_level"])
	assert_near(data.hero_stat_multiplier(1), 1.0, 0.0001, "level 1")
	assert_near(data.hero_stat_multiplier(2), 1.0 + growth, 0.0001, "level 2")
	assert_near(data.hero_stat_multiplier(3) / data.hero_stat_multiplier(2), 1.0 + growth, 0.0001, "each level on top of the previous")


func test_enemy_power_grows_per_stage() -> void:
	var growth := float(data.balance["enemy_power_growth_per_stage"])
	assert_near(data.enemy_power_multiplier(1), 1.0, 0.0001, "stage 1")
	assert_near(data.enemy_power_multiplier(2), 1.0 + growth, 0.0001, "stage 2")
	assert_near(data.enemy_power_multiplier(10) / data.enemy_power_multiplier(9), 1.0 + growth, 0.0001, "stage 10 over stage 9")


func test_level_up_spends_silver() -> void:
	var progress = Progress.new_game(data)
	var cost: int = data.level_up_cost(1)
	progress.silver = cost + 7
	assert_true(progress.level_up(data, "torvald"), "level-up done")
	assert_eq(progress.level_of("torvald"), 2, "new level")
	assert_eq(progress.silver, 7, "silver spent")


func test_level_up_needs_enough_silver() -> void:
	var progress = Progress.new_game(data)
	progress.silver = data.level_up_cost(1) - 1
	assert_true(not progress.can_level_up(data, "torvald"), "cannot afford")
	assert_true(not progress.level_up(data, "torvald"), "level-up refused")
	assert_eq(progress.level_of("torvald"), 1, "level unchanged")
	assert_eq(progress.silver, data.level_up_cost(1) - 1, "silver unchanged")


func test_level_is_capped_at_max() -> void:
	var progress = Progress.new_game(data)
	progress.hero_levels["sigrid"] = data.max_level()
	progress.silver = 100000000
	assert_true(progress.is_max_level(data, "sigrid"), "at max level")
	assert_true(not progress.level_up(data, "sigrid"), "no level-up past max")
	assert_eq(progress.level_of("sigrid"), data.max_level(), "level stays at max")


func test_unknown_hero_cannot_be_levelled() -> void:
	var progress = Progress.new_game(data)
	progress.silver = 100000
	assert_true(not progress.level_up(data, "skadi"), "hero not in the squad yet")


func test_victory_pays_reward_and_opens_next_stage() -> void:
	var progress = Progress.new_game(data)
	var reward: Dictionary = data.get_stage(1)["reward"]
	var paid: Dictionary = progress.apply_victory(data, 1)
	assert_eq(paid, reward, "returned reward")
	assert_eq(progress.silver, int(data.balance["start_silver"]) + int(reward["silver"]), "silver added")
	assert_eq(progress.experience, int(reward["experience"]), "experience added")
	assert_eq(progress.cleared_stage, 1, "stage 1 won")
	assert_eq(progress.next_stage_id(data), 2, "next battle is stage 2")


func test_after_the_last_stage_the_battle_stays_on_it() -> void:
	var progress = Progress.new_game(data)
	for stage in range(1, data.stage_count() + 1):
		progress.apply_victory(data, stage)
	assert_eq(progress.cleared_stage, data.stage_count(), "chapter done")
	assert_eq(progress.next_stage_id(data), data.stage_count(), "replays the last stage")
	progress.apply_victory(data, 3)
	assert_eq(progress.cleared_stage, data.stage_count(), "replaying never lowers progress")


func test_progress_survives_dict_round_trip() -> void:
	var progress = Progress.new_game(data)
	progress.silver = 1234
	progress.experience = 56
	progress.cleared_stage = 4
	progress.hero_levels["eyvind"] = 7
	var restored = Progress.from_dict(JSON.parse_string(JSON.stringify(progress.to_dict())), data)
	assert_eq(restored.to_dict(), progress.to_dict(), "same progress after JSON round trip")


func test_broken_values_fall_back_to_safe_ones() -> void:
	var restored = Progress.from_dict({
		"version": Progress.VERSION,
		"silver": "a lot",
		"experience": -5,
		"cleared_stage": 999,
		"hero_levels": {"torvald": 999, "sigrid": "x", "unknown_hero": 5},
	}, data)
	assert_eq(restored.silver, int(data.balance["start_silver"]), "non-number silver ignored")
	assert_eq(restored.experience, 0, "negative experience clamped")
	assert_eq(restored.cleared_stage, data.stage_count(), "cleared stage clamped")
	assert_eq(restored.level_of("torvald"), data.max_level(), "level clamped to max")
	assert_eq(restored.level_of("sigrid"), 1, "broken level falls back to 1")
	assert_true(not restored.hero_levels.has("unknown_hero"), "unknown hero ignored")
