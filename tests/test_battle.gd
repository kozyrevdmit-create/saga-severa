## Battle rules from the spec (section 5.2) and the six ultimates, checked without a screen.
## Expected numbers are taken from data/*.json, so the tests survive balance changes.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const Battle := preload("res://scripts/battle/battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")

const HEROES := BattleUnit.Team.HEROES
const ENEMIES := BattleUnit.Team.ENEMIES
const NO_ULTIMATE_EFFECTS := {"name": "test", "energy_cost": 100, "effects": []}

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


func test_each_hero_has_own_ultimate_cost() -> void:
	var sigrid = hero_from_data("sigrid")
	var battle = make_battle([sigrid], [make_dummy()])
	var cost := int(data.get_hero("sigrid")["ultimate"]["energy_cost"])
	sigrid.energy = cost - 1
	assert_true(not battle.can_use_ultimate(sigrid.id), "not ready one point short of her own cost")
	sigrid.energy = cost
	assert_true(battle.can_use_ultimate(sigrid.id), "ready at her own cost")
	sigrid.energy = 0
	battle.run_to_end(60.0)
	assert_eq(sigrid.energy, cost, "energy is capped at the hero's cost")


func test_ultimate_ready_only_at_its_energy_cost() -> void:
	var hero = make_unit(HEROES, "front", 1000, 10, 1.0)
	hero.ultimate = NO_ULTIMATE_EFFECTS
	var battle = make_battle([hero], [make_dummy()])
	hero.energy = hero.ultimate_cost() - 1
	assert_true(not battle.can_use_ultimate(hero.id), "not ready below max")
	assert_true(not battle.use_ultimate(hero.id), "cannot use below max")
	hero.energy = hero.ultimate_cost()
	assert_true(battle.can_use_ultimate(hero.id), "ready at max")
	assert_true(battle.use_ultimate(hero.id), "used at max")
	assert_eq(hero.energy, 0, "energy spent")
	assert_eq(events_of(battle.take_events(), "ultimate").size(), 1, "ultimate event")


func test_auto_mode_uses_ready_ultimate() -> void:
	var hero = make_unit(HEROES, "front", 1000, 10, 100.0)
	hero.ultimate = NO_ULTIMATE_EFFECTS
	var battle = make_battle([hero], [make_dummy()])
	hero.energy = hero.ultimate_cost()
	battle.step()
	assert_eq(hero.energy, hero.ultimate_cost(), "manual mode waits for a tap")
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


func test_enemies_prefer_shieldbearer_by_weight() -> void:
	var tank = hero_from_data("torvald")
	var berserker = hero_from_data("sigrid")
	for hero in [tank, berserker]:
		hero.max_hp = 10000000
		hero.hp = hero.max_hp
		hero.attack_interval = 1000.0
	var enemies := []
	for i in 3:
		enemies.append(make_unit(ENEMIES, "front", 100000, 1, 0.1))
	var battle = make_battle([tank, berserker], enemies)
	battle.run_to_end(100.0)
	var hits := events_of(battle.take_events(), "damage")
	var on_tank := hits.filter(func(e): return e["target"] == tank.id).size()
	var weights: Dictionary = data.balance["target_weights"]
	var tank_weight := float(weights["by_class"].get("shieldbearer", weights["default"]))
	var other_weight := float(weights["by_class"].get("berserker", weights["default"]))
	assert_true(hits.size() > 2000, "enough hits to measure")
	assert_near(float(on_tank) / hits.size(), tank_weight / (tank_weight + other_weight), 0.03, "share of hits on the shieldbearer")
	assert_true(on_tank < hits.size(), "the berserker is still hit sometimes")


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
	torvald.row = "back"  # the enemy hits only the ally, who has no passive of their own
	var ally = make_unit(HEROES, "front", 100000, 1, 1000.0)
	var enemy = make_unit(ENEMIES, "front", 100000, 100, 1.0)
	var battle = make_battle([torvald, ally], [enemy])
	torvald.energy = torvald.ultimate_cost()
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
	eyvind.energy = eyvind.ultimate_cost()
	battle.use_ultimate(eyvind.id)
	var effect := ultimate_effect("eyvind")
	assert_near(ally.attack_power(), 50 * float(effect["multiplier"]), 0.001, "ally attack boosted")
	assert_near(eyvind.attack_power(), eyvind.base_attack * float(effect["multiplier"]), 0.001, "skald boosted too")
	battle.run_to_end(float(effect["duration"]) + 0.1)
	assert_near(ally.attack_power(), 50.0, 0.001, "song ends after its duration")


func test_fury_strikes_three_times() -> void:
	var sigrid = hero_from_data("sigrid")
	var battle = make_battle([sigrid], [make_dummy()])
	sigrid.energy = sigrid.ultimate_cost()
	battle.use_ultimate(sigrid.id)
	var effect := ultimate_effect("sigrid")
	var hits := events_of(battle.take_events(), "damage")
	assert_eq(hits.size(), int(effect["count"]), "number of strikes")
	for hit in hits:
		assert_eq(hit["amount"], roundi(sigrid.attack_power() * float(effect["attack_multiplier"])), "strike damage")
		assert_eq(hit["kind"], "ultimate", "strike marked as ultimate")


func test_shieldbearers_take_less_damage() -> void:
	for hero_id in ["torvald", "hrungnir"]:
		var passive: Dictionary = data.get_hero(hero_id)["passive"]
		assert_eq(passive["type"], "damage_taken_reduction", "%s has the tank passive" % hero_id)
		var tank = hero_from_data(hero_id)
		var enemy = make_unit(ENEMIES, "front", 100000, 100, 1.0)
		var battle = make_battle([tank], [enemy])
		battle.run_to_end(1.5)  # one enemy hit
		var hits := events_of(battle.take_events(), "damage").filter(func(e): return e["source"] == enemy.id)
		assert_eq(hits.size(), 1, "one enemy hit on %s" % hero_id)
		assert_eq(hits[0]["amount"], roundi(100 * float(passive["damage_taken_multiplier"])), "%s takes less damage" % hero_id)


func test_tank_passive_stacks_with_shield_wall() -> void:
	var torvald = hero_from_data("torvald")
	var enemy = make_unit(ENEMIES, "front", 100000, 100, 1.0)
	var battle = make_battle([torvald], [enemy])
	torvald.energy = torvald.ultimate_cost()
	battle.use_ultimate(torvald.id)
	var wall := float(ultimate_effect("torvald")["multiplier"])
	var passive := float(data.get_hero("torvald")["passive"]["damage_taken_multiplier"])
	assert_near(torvald.damage_taken_multiplier(), wall * passive, 0.0001, "wall and passive multiply")


func test_other_classes_take_full_damage() -> void:
	for hero_id in ["sigrid", "eyvind", "angrboda", "skadi"]:
		assert_near(hero_from_data(hero_id).damage_taken_multiplier(), 1.0, 0.0001, "%s has no damage reduction" % hero_id)


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
	skadi.energy = skadi.ultimate_cost()
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
	hrungnir.energy = hrungnir.ultimate_cost()
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
	angrboda.energy = angrboda.ultimate_cost()
	battle.use_ultimate(angrboda.id)
	var share := float(ultimate_effect("angrboda")["max_hp_fraction"])
	assert_eq(ally.hp, 100 + roundi(ally.max_hp * share), "ally healed")
	assert_eq(angrboda.hp, 100 + roundi(angrboda.max_hp * share), "völva healed herself")


# --- target mark (tap on an enemy) --------------------------------------------

func test_mark_toggles_on_a_living_enemy_only() -> void:
	var hero = make_unit(HEROES, "front", 100000, 1, 1000.0)
	var enemy_a = make_dummy()
	var enemy_b = make_dummy()
	var battle = make_battle([hero], [enemy_a, enemy_b])
	assert_eq(battle.marked_target_id, -1, "no mark at the start")
	assert_true(not battle.toggle_mark(hero.id), "a hero cannot be marked")
	assert_true(battle.toggle_mark(enemy_a.id), "enemy marked")
	assert_eq(battle.marked_target_id, enemy_a.id, "mark on the tapped enemy")
	assert_true(battle.toggle_mark(enemy_b.id), "mark moved")
	assert_eq(battle.marked_target_id, enemy_b.id, "only one mark at a time")
	assert_true(battle.toggle_mark(enemy_b.id), "second tap")
	assert_eq(battle.marked_target_id, -1, "second tap on the marked enemy removes the mark")
	var marks := events_of(battle.take_events(), "mark").map(func(e): return e["unit"])
	assert_eq(marks, [enemy_a.id, enemy_b.id, -1], "mark events")
	enemy_a.hp = 0
	assert_true(not battle.toggle_mark(enemy_a.id), "a dead enemy cannot be marked")
	assert_true(not battle.toggle_mark(99), "unknown unit")


func test_melee_heroes_hit_the_marked_front_enemy() -> void:
	var heroes := []
	for hero_id in ["torvald", "sigrid", "eyvind"]:
		var hero = hero_from_data(hero_id)
		hero.max_hp = 10000000
		hero.hp = hero.max_hp
		heroes.append(hero)
	var enemies := [make_dummy(), make_dummy(), make_dummy()]
	var battle = make_battle(heroes, enemies)
	battle.toggle_mark(enemies[1].id)
	battle.run_to_end(20.0)
	var hero_hits := events_of(battle.take_events(), "damage").filter(func(e): return not e["target_is_hero"])
	assert_true(hero_hits.size() > 30, "enough hits")
	for hit in hero_hits:
		assert_eq(hit["target"], enemies[1].id, "every hero attack goes to the marked enemy")


func test_mark_on_back_row_enemy_only_draws_the_archer_while_the_front_stands() -> void:
	var sigrid = hero_from_data("sigrid")
	var skadi = hero_from_data("skadi")
	var front = make_dummy("front", 100000)
	var back = make_dummy("back", 100000)
	var battle = make_battle([sigrid, skadi], [front, back])
	battle.toggle_mark(back.id)
	battle.run_to_end(10.0)
	var hits := events_of(battle.take_events(), "damage")
	var sigrid_targets := hits.filter(func(e): return e["source"] == sigrid.id).map(func(e): return e["target"])
	var skadi_targets := hits.filter(func(e): return e["source"] == skadi.id).map(func(e): return e["target"])
	assert_true(not sigrid_targets.is_empty() and not skadi_targets.is_empty(), "both attacked")
	assert_true(sigrid_targets.all(func(t): return t == front.id), "melee still hits the front row it can reach")
	assert_true(skadi_targets.all(func(t): return t == back.id), "the archer shoots the marked enemy, not the lowest HP one")


func test_volva_still_heals_with_a_mark() -> void:
	var volva = hero_from_data("angrboda")
	var ally = make_unit(HEROES, "front", 1000, 1, 1000.0)
	ally.hp = int(ally.max_hp * float(volva.action_params["heal_below_hp_fraction"])) - 1
	var hp_before: int = ally.hp
	var marked = make_dummy()
	var battle = make_battle([ally, volva], [make_dummy(), marked])
	battle.toggle_mark(marked.id)
	battle.run_to_end(volva.attack_interval + 0.1)  # one action
	assert_true(ally.hp > hp_before, "a wounded ally is healed first")
	assert_eq(marked.hp, marked.max_hp, "no attack on the mark while healing")
	ally.hp = ally.max_hp
	battle.run_to_end(volva.attack_interval * 2 + 0.1)  # the next action
	assert_eq(marked.hp, marked.max_hp - roundi(volva.attack_power()), "with nobody to heal the völva attacks the mark")


func test_fury_strikes_the_marked_enemy() -> void:
	var sigrid = hero_from_data("sigrid")
	var enemies := [make_dummy(), make_dummy(), make_dummy()]
	var battle = make_battle([sigrid], enemies)
	battle.toggle_mark(enemies[2].id)
	sigrid.energy = sigrid.ultimate_cost()
	battle.use_ultimate(sigrid.id)
	var hits := events_of(battle.take_events(), "damage")
	assert_eq(hits.size(), int(ultimate_effect("sigrid")["count"]), "three strikes")
	assert_true(hits.all(func(e): return e["target"] == enemies[2].id), "all on the marked enemy")


func test_mark_clears_when_the_enemy_dies_and_attacks_go_back_to_normal() -> void:
	var hero = make_unit(HEROES, "front", 100000, 100, 0.5)
	var weak = make_dummy("front", 150)
	var strong = make_dummy("front", 100000)
	var battle = make_battle([hero], [strong, weak])
	battle.toggle_mark(weak.id)
	battle.run_to_end(1.1)  # two attacks: the marked enemy falls
	assert_true(not weak.is_alive(), "marked enemy killed first")
	assert_eq(battle.marked_target_id, -1, "mark gone with the enemy")
	var marks := events_of(battle.take_events(), "mark").map(func(e): return e["unit"])
	assert_eq(marks, [weak.id, -1], "mark set, then cleared on death")
	battle.run_to_end(3.0)
	assert_true(strong.hp < strong.max_hp, "the squad moves on to the next enemy")


func test_enemies_ignore_the_mark_and_auto_sets_none() -> void:
	var tank = hero_from_data("torvald")
	var other = make_unit(HEROES, "front", 100000, 1, 1000.0)
	tank.max_hp = 10000000
	tank.hp = tank.max_hp
	var enemy = make_unit(ENEMIES, "front", 10000000, 1, 0.1)
	var battle = make_battle([tank, other], [enemy])
	battle.auto_ultimates = true
	battle.run_to_end(30.0)
	assert_eq(battle.marked_target_id, -1, "«Авто» never marks a target")
	assert_true(events_of(battle.take_events(), "mark").is_empty(), "no mark events")
	battle.toggle_mark(enemy.id)
	battle.run_to_end(60.0)
	var on_other := events_of(battle.take_events(), "damage").filter(func(e): return e["target"] == other.id)
	assert_true(not on_other.is_empty(), "enemies keep picking their own targets")


func test_same_seed_and_taps_give_same_battle() -> void:
	var results := []
	for i in 2:
		var battle = Battle.from_data(data, data.starting_hero_ids(), data.get_stage(1)["waves"][1], 4242)
		battle.run_to_end(2.0)
		battle.toggle_mark(battle.enemies()[1].id)
		battle.run_to_end(600.0)
		results.append({"events": battle.take_events(), "time": battle.time})
	assert_eq(results[1], results[0], "two runs with the same seed and the same tap")
