## Battle rules from the spec (section 5.2) and the six ultimates, checked without a screen.
## Expected numbers are taken from data/*.json, so the tests survive balance changes.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const Battle := preload("res://scripts/battle/battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")

const HEROES := BattleUnit.Team.HEROES
const ENEMIES := BattleUnit.Team.ENEMIES
const NO_ULTIMATE_EFFECTS := {"name": "test", "effects": []}

var data = GameData.load_all()


# --- helpers -----------------------------------------------------------------

func make_unit(team: BattleUnit.Team, row: String, hp: int, attack: float, interval: float):
	var unit = BattleUnit.new()
	unit.team = team
	unit.row = row
	unit.max_hp = hp
	unit.hp = hp
	unit.base_attack = attack
	unit.attack_interval = interval
	return unit


## A sturdy enemy that barely fights back: lets a hero act without dying.
func make_dummy(row := "front", hp := 100000):
	return make_unit(ENEMIES, row, hp, 1, 1000.0)


func hero_from_data(hero_id: String):
	var hero: Dictionary = data.get_hero(hero_id)
	return BattleUnit.from_hero(hero, data.get_hero_class(hero))


func make_battle(hero_units: Array, enemy_units: Array, rng_seed := 1):
	return Battle.new(hero_units, enemy_units, data.balance, rng_seed)


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e["type"] == type)


func max_energy() -> int:
	return int(data.balance["energy"]["max"])


func ultimate_effect(hero_id: String) -> Dictionary:
	return data.get_hero(hero_id)["ultimate"]["effects"][0]


# --- whole battle ------------------------------------------------------------

func test_same_seed_gives_same_battle() -> void:
	var stage: Dictionary = data.get_stage(1)
	var results := []
	for i in 2:
		var battle = Battle.from_data(data, data.starting_hero_ids(), stage["waves"][0], 12345)
		battle.auto_ultimates = true
		battle.run_to_end(600.0)
		results.append({"events": battle.take_events(), "time": battle.time, "victory": battle.victory})
	assert_true(not results[0]["events"].is_empty(), "battle produced events")
	assert_eq(results[1], results[0], "two runs with the same seed")


func test_fixed_squad_battle_finishes() -> void:
	for auto in [false, true]:
		var battle = Battle.from_data(data, data.starting_hero_ids(), data.get_stage(1)["waves"][0], 7)
		battle.auto_ultimates = auto
		battle.run_to_end(600.0)
		assert_true(battle.finished, "battle with auto=%s finished" % auto)
		print("        stage 1 wave 1, auto=%s: %s in %.1f s" % [auto, "victory" if battle.victory else "defeat", battle.time])
		assert_eq(events_of(battle.take_events(), "end").size(), 1, "one end event with auto=%s" % auto)


func test_victory_and_defeat() -> void:
	var win = make_battle([make_unit(HEROES, "front", 1000, 100, 1.0)], [make_unit(ENEMIES, "front", 150, 1, 1.0)])
	win.run_to_end(60.0)
	assert_true(win.finished and win.victory, "strong hero wins")
	var lose = make_battle([make_unit(HEROES, "front", 150, 1, 1.0)], [make_unit(ENEMIES, "front", 1000, 100, 1.0)])
	lose.run_to_end(60.0)
	assert_true(lose.finished and not lose.victory, "weak hero loses")


# --- energy and ultimates ----------------------------------------------------

func test_energy_for_attack_and_for_hit_taken() -> void:
	var hero = make_unit(HEROES, "front", 1000, 10, 1.0)
	hero.ultimate = NO_ULTIMATE_EFFECTS
	var enemy = make_unit(ENEMIES, "front", 100000, 1, 1.0)
	var battle = make_battle([hero], [enemy])
	battle.run_to_end(1.5)  # exactly one attack each
	var energy: Dictionary = data.balance["energy"]
	assert_eq(hero.energy, int(energy["per_attack"]) + int(energy["per_hit_taken"]), "energy after one attack and one hit")


func test_ultimate_ready_only_at_max_energy() -> void:
	var hero = make_unit(HEROES, "front", 1000, 10, 1.0)
	hero.ultimate = NO_ULTIMATE_EFFECTS
	var battle = make_battle([hero], [make_dummy()])
	hero.energy = max_energy() - 1
	assert_true(not battle.can_use_ultimate(hero.id), "not ready below max")
	assert_true(not battle.use_ultimate(hero.id), "cannot use below max")
	hero.energy = max_energy()
	assert_true(battle.can_use_ultimate(hero.id), "ready at max")
	assert_true(battle.use_ultimate(hero.id), "used at max")
	assert_eq(hero.energy, 0, "energy spent")
	assert_eq(events_of(battle.take_events(), "ultimate").size(), 1, "ultimate event")


func test_auto_mode_uses_ready_ultimate() -> void:
	var hero = make_unit(HEROES, "front", 1000, 10, 100.0)
	hero.ultimate = NO_ULTIMATE_EFFECTS
	var battle = make_battle([hero], [make_dummy()])
	hero.energy = max_energy()
	battle.step()
	assert_eq(hero.energy, max_energy(), "manual mode waits for a tap")
	battle.auto_ultimates = true
	battle.step()
	assert_eq(hero.energy, 0, "auto mode used the ultimate")


# --- targeting ----------------------------------------------------------------

func test_enemies_hit_front_row_first() -> void:
	var tank = make_unit(HEROES, "front", 100000, 1, 1000.0)
	var back = make_unit(HEROES, "back", 1000, 1, 1000.0)
	var enemies := []
	for i in 3:
		enemies.append(make_unit(ENEMIES, "front", 100000, 10, 0.5))
	var battle = make_battle([tank, back], enemies)
	battle.run_to_end(10.0)
	assert_true(tank.hp < tank.max_hp, "front row took damage")
	assert_eq(back.hp, back.max_hp, "back row untouched while front row stands")


func test_back_row_is_hit_when_front_row_falls() -> void:
	var front = make_unit(HEROES, "front", 10, 1, 1000.0)
	var back = make_unit(HEROES, "back", 100000, 1, 1000.0)
	var battle = make_battle([front, back], [make_unit(ENEMIES, "front", 100000, 20, 0.5)])
	battle.run_to_end(5.0)
	assert_true(not front.is_alive(), "front row fell")
	assert_true(back.hp < back.max_hp, "back row is hit next")


func test_melee_hits_enemy_front_row_first() -> void:
	var hero = make_unit(HEROES, "front", 100000, 10, 0.5)
	var enemy_front = make_dummy("front")
	var enemy_back = make_dummy("back", 1000)
	var battle = make_battle([hero], [enemy_front, enemy_back])
	battle.run_to_end(5.0)
	assert_true(enemy_front.hp < enemy_front.max_hp, "front enemy hit")
	assert_eq(enemy_back.hp, enemy_back.max_hp, "back enemy untouched")


func test_archer_hits_lowest_hp_enemy() -> void:
	var archer = hero_from_data("skadi")
	var strong = make_dummy("front", 5000)
	var weak = make_dummy("back", 3000)
	var battle = make_battle([archer], [strong, weak])
	battle.run_to_end(archer.attack_interval + 0.1)  # one shot
	assert_eq(strong.hp, strong.max_hp, "healthier enemy untouched")
	assert_eq(weak.hp, weak.max_hp - roundi(archer.attack_power()), "weakest enemy shot")


func test_volva_heals_wounded_ally() -> void:
	var volva = hero_from_data("angrboda")
	var ally = make_unit(HEROES, "front", 1000, 1, 1000.0)
	var threshold := float(volva.action_params["heal_below_hp_fraction"])
	ally.hp = int(ally.max_hp * threshold) - 1
	var hp_before: int = ally.hp
	var enemy = make_dummy()
	var battle = make_battle([ally, volva], [enemy])
	battle.run_to_end(volva.attack_interval + 0.1)  # one action
	var heal := roundi(volva.attack_power() * float(volva.action_params["heal_attack_multiplier"]))
	assert_eq(ally.hp, hp_before + heal, "ally healed")
	assert_eq(enemy.hp, enemy.max_hp, "no attack while healing")
	assert_eq(volva.energy, int(data.balance["energy"]["per_heal"]), "energy for healing comes from per_heal")


func test_volva_heal_energy_is_configured_separately() -> void:
	var balance: Dictionary = data.balance.duplicate(true)
	balance["energy"]["per_heal"] = 3
	var volva = hero_from_data("angrboda")
	var ally = make_unit(HEROES, "front", 1000, 1, 1000.0)
	ally.hp = 1
	var battle = Battle.new([ally, volva], [make_dummy()], balance, 1)
	battle.run_to_end(volva.attack_interval + 0.1)
	assert_eq(volva.energy, 3, "heal energy follows balance.json, not per_attack")


func test_volva_attacks_when_nobody_is_wounded() -> void:
	var volva = hero_from_data("angrboda")
	var ally = make_unit(HEROES, "front", 1000, 1, 1000.0)
	var enemy = make_dummy()
	var battle = make_battle([ally, volva], [enemy])
	battle.run_to_end(volva.attack_interval + 0.1)
	assert_eq(enemy.hp, enemy.max_hp - roundi(volva.attack_power()), "enemy attacked")


# --- the six ultimates and the berserker passive -----------------------------

func test_shield_wall_reduces_damage_taken() -> void:
	var torvald = hero_from_data("torvald")
	var ally = make_unit(HEROES, "front", 100000, 1, 1000.0)
	var enemy = make_unit(ENEMIES, "front", 100000, 100, 1.0)
	var battle = make_battle([torvald, ally], [enemy])
	torvald.energy = max_energy()
	battle.use_ultimate(torvald.id)
	battle.run_to_end(1.5)  # one enemy hit during the wall
	var hits := events_of(battle.take_events(), "damage").filter(func(e): return e["source"] == enemy.id)
	var effect := ultimate_effect("torvald")
	assert_eq(hits.size(), 1, "one enemy hit")
	assert_eq(hits[0]["amount"], roundi(100 * float(effect["multiplier"])), "damage reduced")
	battle.run_to_end(float(effect["duration"]) + 0.1)
	assert_near(ally.damage_taken_multiplier(), 1.0, 0.0001, "wall ends after its duration")


func test_battle_song_boosts_squad_attack() -> void:
	var eyvind = hero_from_data("eyvind")
	var ally = make_unit(HEROES, "front", 100000, 50, 1000.0)
	var battle = make_battle([eyvind, ally], [make_dummy()])
	eyvind.energy = max_energy()
	battle.use_ultimate(eyvind.id)
	var effect := ultimate_effect("eyvind")
	assert_near(ally.attack_power(), 50 * float(effect["multiplier"]), 0.001, "ally attack boosted")
	assert_near(eyvind.attack_power(), eyvind.base_attack * float(effect["multiplier"]), 0.001, "skald boosted too")
	battle.run_to_end(float(effect["duration"]) + 0.1)
	assert_near(ally.attack_power(), 50.0, 0.001, "song ends after its duration")


func test_fury_strikes_three_times() -> void:
	var sigrid = hero_from_data("sigrid")
	var battle = make_battle([sigrid], [make_dummy()])
	sigrid.energy = max_energy()
	battle.use_ultimate(sigrid.id)
	var effect := ultimate_effect("sigrid")
	var hits := events_of(battle.take_events(), "damage")
	assert_eq(hits.size(), int(effect["count"]), "number of strikes")
	for hit in hits:
		assert_eq(hit["amount"], roundi(sigrid.attack_power() * float(effect["attack_multiplier"])), "strike damage")
		assert_true(hit["ultimate"], "strike marked as ultimate")


func test_berserker_gets_stronger_when_wounded() -> void:
	var sigrid = hero_from_data("sigrid")
	var bonus := float(data.get_hero("sigrid")["passive"]["attack_bonus_per_missing_hp"])
	assert_near(sigrid.attack_power(), sigrid.base_attack, 0.001, "no bonus at full HP")
	sigrid.hp = sigrid.max_hp / 2
	assert_near(sigrid.attack_power(), sigrid.base_attack * (1.0 + bonus * 0.5), 0.001, "bonus at half HP")


func test_ice_volley_hits_all_enemies_and_slows() -> void:
	var skadi = hero_from_data("skadi")
	var enemies := [make_dummy("front"), make_dummy("front"), make_dummy("back")]
	var battle = make_battle([skadi], enemies)
	skadi.energy = max_energy()
	battle.use_ultimate(skadi.id)
	var effect := ultimate_effect("skadi")
	var damage := roundi(skadi.attack_power() * float(effect["attack_multiplier"]))
	for enemy in enemies:
		assert_eq(enemy.hp, enemy.max_hp - damage, "every enemy hit")
		assert_near(enemy.action_speed(), 1.0 - float(effect["status"]["amount"]), 0.001, "enemy slowed")
	battle.run_to_end(float(effect["status"]["duration"]) + 0.1)
	assert_near(enemies[0].action_speed(), 1.0, 0.001, "slow wears off")


func test_slowed_enemy_attacks_less_often() -> void:
	var hero = make_unit(HEROES, "front", 100000, 1, 1000.0)
	var enemy = make_unit(ENEMIES, "front", 100000, 1, 1.0)
	var battle = make_battle([hero], [enemy])
	enemy.apply_status({"kind": "slow", "amount": 0.5, "duration": 100.0})
	battle.run_to_end(10.1)
	var hits := events_of(battle.take_events(), "damage").size()
	assert_eq(hits, 5, "half speed gives half the attacks")


func test_stone_strike_hits_front_row_and_stuns() -> void:
	var hrungnir = hero_from_data("hrungnir")
	var enemy_front = make_unit(ENEMIES, "front", 100000, 10, 0.5)
	var enemy_back = make_dummy("back")
	var battle = make_battle([hrungnir], [enemy_front, enemy_back])
	hrungnir.energy = max_energy()
	battle.use_ultimate(hrungnir.id)
	var effect := ultimate_effect("hrungnir")
	assert_eq(enemy_front.hp, enemy_front.max_hp - roundi(hrungnir.attack_power() * float(effect["attack_multiplier"])), "front row hit")
	assert_eq(enemy_back.hp, enemy_back.max_hp, "back row untouched")
	battle.take_events()
	battle.run_to_end(float(effect["status"]["duration"]) - 0.1)
	var enemy_hits := events_of(battle.take_events(), "damage").filter(func(e): return e["source"] == enemy_front.id)
	assert_eq(enemy_hits.size(), 0, "stunned enemy does not attack")
	battle.run_to_end(float(effect["status"]["duration"]) + 1.0)
	enemy_hits = events_of(battle.take_events(), "damage").filter(func(e): return e["source"] == enemy_front.id)
	assert_true(enemy_hits.size() > 0, "enemy attacks again after the stun")


func test_healing_restores_share_of_max_hp() -> void:
	var angrboda = hero_from_data("angrboda")
	var ally = make_unit(HEROES, "front", 1000, 1, 1000.0)
	ally.hp = 100
	angrboda.hp = 100
	var battle = make_battle([ally, angrboda], [make_dummy()])
	angrboda.energy = max_energy()
	battle.use_ultimate(angrboda.id)
	var share := float(ultimate_effect("angrboda")["max_hp_fraction"])
	assert_eq(ally.hp, 100 + roundi(ally.max_hp * share), "ally healed")
	assert_eq(angrboda.hp, 100 + roundi(angrboda.max_hp * share), "völva healed herself")
