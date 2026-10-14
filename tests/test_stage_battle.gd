## A stage of several waves, hero levels, enemy growth per stage and the boss.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const StageBattle := preload("res://scripts/battle/stage_battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")

const HEROES := BattleUnit.Team.HEROES
const ENEMIES := BattleUnit.Team.ENEMIES

var data = GameData.load_all()


func make_unit(team: BattleUnit.Team, row: String, hp: int, attack: float, interval: float):
	var unit = BattleUnit.new()
	unit.team = team
	unit.row = row
	unit.max_hp = hp
	unit.hp = hp
	unit.base_attack = attack
	unit.attack_interval = interval
	return unit


func starting_levels(level: int) -> Dictionary:
	var levels := {}
	for hero_id in data.starting_hero_ids():
		levels[hero_id] = level
	return levels


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e["type"] == type)


func test_hero_level_scales_hp_and_attack() -> void:
	var stage = StageBattle.from_data(data, 1, {"torvald": 5}, 1)
	var torvald = stage.heroes()[0]
	var hero: Dictionary = data.get_hero("torvald")
	var multiplier: float = data.hero_stat_multiplier(5)
	assert_eq(torvald.max_hp, roundi(hero["hp"] * multiplier), "HP at level 5")
	assert_near(torvald.base_attack, hero["attack"] * multiplier, 0.001, "attack at level 5")


func test_enemies_grow_with_stage() -> void:
	var stage = StageBattle.from_data(data, 4, starting_levels(1), 1)
	var power: float = data.enemy_power_multiplier(4)
	for enemy in stage.enemies():
		var definition: Dictionary = data.get_enemy(enemy.def_id)
		assert_eq(enemy.max_hp, roundi(definition["hp"] * power), "%s HP on stage 4" % enemy.def_id)
		assert_near(enemy.base_attack, definition["attack"] * power, 0.001, "%s attack on stage 4" % enemy.def_id)


func test_stage_is_won_only_after_all_waves() -> void:
	var hero = make_unit(HEROES, "front", 100000, 1000, 0.5)
	var waves := []
	for i in 3:
		waves.append([make_unit(ENEMIES, "front", 500, 1, 1.0)])
	var stage = StageBattle.new(1, [hero], waves, data.balance, 1)
	var events := []
	var waves_seen := [stage.wave_index]
	while not stage.finished and stage.time < 60.0:
		stage.step()
		events.append_array(stage.take_events())
		if waves_seen.back() != stage.wave_index:
			waves_seen.append(stage.wave_index)
	assert_true(stage.finished and stage.victory, "stage won")
	assert_eq(waves_seen, [0, 1, 2], "waves in order")
	assert_eq(events_of(events, "wave").map(func(e): return e["index"]), [1, 2], "wave events")
	assert_eq(events_of(events, "end").size(), 1, "one end event for the whole stage")


func test_heroes_keep_hp_and_energy_between_waves() -> void:
	var hero = make_unit(HEROES, "front", 1000, 100, 1.0)
	hero.ultimate = {"name": "test", "energy_cost": 1000, "effects": []}
	var first_wave := [make_unit(ENEMIES, "front", 150, 30, 0.5)]
	var second_wave := [make_unit(ENEMIES, "front", 100000, 1, 1000.0)]
	var stage = StageBattle.new(1, [hero], [first_wave, second_wave], data.balance, 1)
	while stage.wave_index == 0 and not stage.finished:
		stage.step()
	assert_true(hero.hp < hero.max_hp, "hero was hurt in wave 1")
	assert_true(hero.energy > 0, "hero gained energy in wave 1")
	var hp_after_first: int = hero.hp
	var energy_after_first: int = hero.energy
	assert_eq(stage.heroes()[0], hero, "same hero object in wave 2")
	assert_eq(stage.heroes()[0].hp, hp_after_first, "HP carried over")
	assert_eq(stage.heroes()[0].energy, energy_after_first, "energy carried over")


func test_defeat_in_a_wave_ends_the_stage() -> void:
	var hero = make_unit(HEROES, "front", 50, 1, 1000.0)
	var waves := [[make_unit(ENEMIES, "front", 100000, 100, 0.5)], [make_unit(ENEMIES, "front", 10, 1, 1.0)]]
	var stage = StageBattle.new(1, [hero], waves, data.balance, 1)
	stage.run_to_end(60.0)
	assert_true(stage.finished and not stage.victory, "stage lost")
	assert_eq(stage.wave_index, 0, "never reached wave 2")


func test_same_seed_gives_same_stage() -> void:
	var results := []
	for i in 2:
		var stage = StageBattle.from_data(data, 3, starting_levels(4), 4242)
		stage.auto_ultimates = true
		stage.run_to_end(600.0)
		results.append({"events": stage.take_events(), "time": stage.time, "victory": stage.victory})
	assert_eq(results[1], results[0], "two runs with the same seed")


func test_boss_strikes_the_whole_squad_periodically() -> void:
	var boss_data: Dictionary = data.get_enemy("draugr_king")
	var special: Dictionary = boss_data["special"]
	var boss = BattleUnit.from_enemy(boss_data)
	boss.max_hp = 10000000
	boss.hp = boss.max_hp
	boss.attack_interval = 1000.0  # only the special strikes in this test
	var heroes := []
	for row in ["front", "back", "back"]:
		var hero = make_unit(HEROES, row, 10000000, 1, 1000.0)
		heroes.append(hero)
	var stage = StageBattle.new(10, heroes, [[boss]], data.balance, 1)
	var interval := float(special["interval"])
	stage.run_to_end(interval * 3 + 0.1)
	var events := stage.take_events()
	assert_eq(events_of(events, "special").size(), 3, "one strike per interval")
	var hits := events_of(events, "damage").filter(func(e): return e["kind"] == "special")
	assert_eq(hits.size(), 3 * heroes.size(), "every hero hit by every strike")
	for hit in hits:
		assert_eq(hit["amount"], roundi(boss.base_attack * float(special["attack_multiplier"])), "strike damage")
		assert_true(hit["target_is_hero"], "strike hits heroes")


func test_stage_ten_ends_with_the_boss() -> void:
	var stage = StageBattle.from_data(data, 10, starting_levels(1), 1)
	assert_eq(stage.wave_count, 3, "three waves")
	var last_wave: Array = data.get_stage(10)["waves"][2]
	assert_eq(last_wave, ["draugr_king"], "third wave is the boss alone")
