## Checks that data/*.json is complete and consistent.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")

const KNOWN_ACTIONS := ["attack_front_row", "attack_lowest_hp", "heal_or_attack"]
const KNOWN_EFFECTS := ["buff_allies", "hits", "damage", "heal_allies"]
const KNOWN_TARGETS := ["front_row_single", "front_row_all", "all_enemies"]

var data = GameData.load_all()


func test_all_six_heroes_present() -> void:
	var ids := []
	for hero in data.heroes["heroes"]:
		ids.append(hero["id"])
	assert_eq(ids, ["torvald", "sigrid", "eyvind", "skadi", "angrboda", "hrungnir"], "hero ids")


func test_heroes_have_valid_fields() -> void:
	for hero in data.heroes["heroes"]:
		var who: String = hero["id"]
		for field in ["name", "class", "clan", "hp", "attack", "attack_interval", "unlock_after_stage", "ultimate"]:
			assert_true(hero.has(field), "%s has %s" % [who, field])
		assert_true(data.heroes["classes"].has(hero["class"]), "%s class exists" % who)
		assert_true(data.heroes["clans"].has(hero["clan"]), "%s clan exists" % who)
		assert_true(hero["hp"] > 0 and hero["attack"] > 0 and hero["attack_interval"] > 0, "%s stats positive" % who)
		var effects: Array = hero["ultimate"]["effects"]
		assert_true(not effects.is_empty(), "%s ultimate has effects" % who)
		for effect in effects:
			assert_true(effect["type"] in KNOWN_EFFECTS, "%s effect type %s known" % [who, effect["type"]])
			if effect.has("target"):
				assert_true(effect["target"] in KNOWN_TARGETS, "%s effect target %s known" % [who, effect["target"]])


func test_classes_have_valid_fields() -> void:
	for class_id in data.heroes["classes"]:
		var hero_class: Dictionary = data.heroes["classes"][class_id]
		assert_true(hero_class["row"] in ["front", "back"], "%s row" % class_id)
		assert_true(hero_class["action"] in KNOWN_ACTIONS, "%s action" % class_id)
		assert_true(Color.html_is_valid(hero_class["color"]), "%s color" % class_id)


func test_starting_heroes_and_unlocks() -> void:
	assert_eq(data.starting_hero_ids(), ["torvald", "sigrid", "eyvind"], "starting heroes")
	assert_eq(int(data.get_hero("skadi")["unlock_after_stage"]), 3, "Skadi unlock")
	assert_eq(int(data.get_hero("angrboda")["unlock_after_stage"]), 6, "Angrboda unlock")
	assert_eq(int(data.get_hero("hrungnir")["unlock_after_stage"]), 9, "Hrungnir unlock")


func test_three_enemy_types() -> void:
	var ids := []
	for enemy in data.enemies["enemies"]:
		ids.append(enemy["id"])
		assert_true(enemy["row"] in ["front", "back"], "%s row" % enemy["id"])
		assert_true(enemy["action"] in KNOWN_ACTIONS, "%s action" % enemy["id"])
		assert_true(enemy["hp"] > 0 and enemy["attack"] > 0 and enemy["attack_interval"] > 0, "%s stats positive" % enemy["id"])
		assert_true(Color.html_is_valid(enemy["color"]), "%s color" % enemy["id"])
	assert_eq(ids, ["draugr", "wolf", "draugr_archer"], "enemy ids")


func test_stage_waves_reference_known_enemies() -> void:
	var known := []
	for enemy in data.enemies["enemies"]:
		known.append(enemy["id"])
	for stage in data.stages["stages"]:
		assert_true(not stage["waves"].is_empty(), "stage %s has waves" % stage["id"])
		for wave in stage["waves"]:
			for enemy_id in wave:
				assert_true(enemy_id in known, "stage %s enemy %s known" % [stage["id"], enemy_id])


func test_energy_balance_present() -> void:
	var energy: Dictionary = data.balance["energy"]
	assert_true(energy["max"] > 0, "energy max")
	assert_true(energy["per_attack"] > 0, "energy per attack")
	assert_true(energy["per_hit_taken"] > 0, "energy per hit taken")
