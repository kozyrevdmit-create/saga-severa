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


## A squad in the heroes' default rows: [{id, level, row}].
func squad_at(level: int, hero_ids: Array = data.starting_hero_ids()) -> Array:
	return hero_ids.map(func(hero_id): return {
		"id": hero_id, "level": level, "row": data.get_hero_class(data.get_hero(hero_id))["row"]})


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e["type"] == type)


func test_hero_level_scales_hp_and_attack() -> void:
	var stage = StageBattle.from_data(data, 1, squad_at(5, ["torvald"]), 1)
	var torvald = stage.heroes()[0]
	var hero: Dictionary = data.get_hero("torvald")
	var multiplier: float = data.hero_stat_multiplier(5)
	assert_eq(torvald.max_hp, roundi(hero["hp"] * multiplier), "HP at level 5")
	assert_near(torvald.base_attack, hero["attack"] * multiplier, 0.001, "attack at level 5")


func test_enemies_grow_with_stage() -> void:
	var stage = StageBattle.from_data(data, 4, squad_at(1), 1)
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


func test_retreat_ends_the_stage_as_a_defeat() -> void:
	var stage = StageBattle.from_data(data, 10, squad_at(1), 1)
	stage.auto_ultimates = true
	stage.run_to_end(3.0)
	assert_true(not stage.finished, "the battle is still going")
	stage.take_events()
	assert_true(stage.retreat(), "retreated")
	assert_true(stage.finished and not stage.victory, "stage lost")
	assert_eq(stage.take_events(), [{"type": "end", "victory": false, "retreat": true}], "one end event, marked as a retreat")
	var time_at_retreat: float = stage.time
	stage.advance(5.0)
	assert_eq(stage.time, time_at_retreat, "nothing happens after the retreat")
	assert_true(not stage.can_use_ultimate(0) and not stage.use_ultimate(0), "no ultimates after the retreat")
	assert_true(not stage.retreat(), "a finished stage cannot retreat again")
	assert_true(stage.take_events().is_empty(), "no second end event")


func test_same_seed_gives_same_stage() -> void:
	var results := []
	for i in 2:
		var stage = StageBattle.from_data(data, 3, squad_at(4), 4242)
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
	var stage = StageBattle.from_data(data, 10, squad_at(1), 1)
	assert_eq(stage.wave_count, 3, "three waves")
	var last_wave: Array = data.get_stage(10)["waves"][2]
	assert_eq(last_wave, ["draugr_king"], "third wave is the boss alone")


func synergy_bonus(clan_id: String) -> float:
	return float(data.heroes["clans"][clan_id]["synergy"]["bonus"])


func test_three_midgard_heroes_get_more_hp() -> void:
	var stage = StageBattle.from_data(data, 1, squad_at(1), 1)
	var bonus := synergy_bonus("midgard")
	for hero in stage.heroes():
		var definition: Dictionary = data.get_hero(hero.def_id)
		assert_eq(hero.max_hp, roundi(definition["hp"] * (1.0 + bonus)), "%s HP with the Midgard bonus" % hero.def_id)
		assert_near(hero.base_attack, definition["attack"], 0.001, "%s attack unchanged" % hero.def_id)


func test_three_jotunheim_heroes_get_more_attack() -> void:
	var stage = StageBattle.from_data(data, 1, squad_at(1, ["hrungnir", "skadi", "angrboda"]), 1)
	var bonus := synergy_bonus("jotunheim")
	for hero in stage.heroes():
		var definition: Dictionary = data.get_hero(hero.def_id)
		assert_near(hero.base_attack, definition["attack"] * (1.0 + bonus), 0.001, "%s attack with the Jotunheim bonus" % hero.def_id)
		assert_eq(hero.max_hp, int(definition["hp"]), "%s HP unchanged" % hero.def_id)


func test_no_clan_bonus_below_three() -> void:
	var stage = StageBattle.from_data(data, 1, squad_at(1, ["torvald", "sigrid", "skadi", "angrboda"]), 1)
	for hero in stage.heroes():
		var definition: Dictionary = data.get_hero(hero.def_id)
		assert_eq(hero.max_hp, int(definition["hp"]), "%s HP without a bonus" % hero.def_id)
		assert_near(hero.base_attack, definition["attack"], 0.001, "%s attack without a bonus" % hero.def_id)


func test_formation_row_is_used_in_battle() -> void:
	var squad := [{"id": "torvald", "level": 1, "row": "front"}, {"id": "sigrid", "level": 1, "row": "back"}]
	var stage = StageBattle.from_data(data, 1, squad, 1)
	var rows := {}
	for hero in stage.heroes():
		rows[hero.def_id] = hero.row
	assert_eq(rows, {"torvald": "front", "sigrid": "back"}, "rows from the formation")


func test_energy_carries_into_the_boss_wave() -> void:
	var stage = StageBattle.from_data(data, 10, squad_at(25), 3)
	stage.auto_ultimates = false
	while stage.wave_index < 2 and not stage.finished:
		stage.step()
	assert_true(not stage.finished, "reached the boss wave")
	var total_energy := 0
	for hero in stage.heroes():
		total_energy += hero.energy
	assert_true(total_energy > 0, "energy from earlier waves is kept")


func test_progress_shares_count_every_wave() -> void:
	var hero = make_unit(HEROES, "front", 1000, 1000, 0.5)
	var waves := [[make_unit(ENEMIES, "front", 500, 1, 1.0)], [make_unit(ENEMIES, "front", 1500, 1, 1.0)]]
	var stage = StageBattle.new(1, [hero], waves, data.balance, 1)
	assert_near(stage.enemy_hp_share_taken(), 0.0, 0.0001, "nothing taken at the start")
	assert_near(stage.hero_hp_share_left(), 1.0, 0.0001, "full HP at the start")
	waves[0][0].hp = 0
	waves[1][0].hp = 1000
	hero.hp = 250
	assert_near(stage.enemy_hp_share_taken(), 0.5, 0.0001, "1000 of 2000 enemy HP over both waves")
	assert_near(stage.hero_hp_share_left(), 0.25, 0.0001, "a quarter of the squad's HP left")
