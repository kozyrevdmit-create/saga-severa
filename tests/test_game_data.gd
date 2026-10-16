## Checks that data/*.json is complete and consistent.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")

const KNOWN_ACTIONS := ["attack_front_row", "attack_lowest_hp", "heal_or_attack"]
const KNOWN_EFFECTS := ["buff_allies", "hits", "damage", "heal_allies"]
const KNOWN_TARGETS := ["front_row_single", "front_row_all", "all_enemies"]
const KNOWN_PASSIVES := ["attack_per_missing_hp", "damage_taken_reduction"]

var data = GameData.load_all()


func test_all_six_heroes_present() -> void:
	var ids := []
	for hero in data.heroes["heroes"]:
		ids.append(hero["id"])
	assert_eq(ids, ["torvald", "sigrid", "eyvind", "angrboda", "skadi", "hrungnir"], "hero ids")


func test_heroes_have_valid_fields() -> void:
	for hero in data.heroes["heroes"]:
		var who: String = hero["id"]
		for field in ["name", "class", "clan", "hp", "attack", "attack_interval", "unlock_after_stage", "ultimate"]:
			assert_true(hero.has(field), "%s has %s" % [who, field])
		assert_true(data.heroes["classes"].has(hero["class"]), "%s class exists" % who)
		assert_true(data.heroes["clans"].has(hero["clan"]), "%s clan exists" % who)
		assert_true(hero["hp"] > 0 and hero["attack"] > 0 and hero["attack_interval"] > 0, "%s stats positive" % who)
		assert_true(hero["ultimate"].get("energy_cost", 0) > 0, "%s ultimate has an energy cost" % who)
		var effects: Array = hero["ultimate"]["effects"]
		assert_true(not effects.is_empty(), "%s ultimate has effects" % who)
		for effect in effects:
			assert_true(effect["type"] in KNOWN_EFFECTS, "%s effect type %s known" % [who, effect["type"]])
			if effect.has("target"):
				assert_true(effect["target"] in KNOWN_TARGETS, "%s effect target %s known" % [who, effect["target"]])
		if hero.has("passive"):
			assert_true(hero["passive"]["type"] in KNOWN_PASSIVES, "%s passive type known" % who)
			assert_true(not str(hero["passive"].get("description", "")).is_empty(), "%s passive has a description" % who)


func test_classes_have_valid_fields() -> void:
	for class_id in data.heroes["classes"]:
		var hero_class: Dictionary = data.heroes["classes"][class_id]
		assert_true(hero_class["row"] in ["front", "back"], "%s row" % class_id)
		assert_true(hero_class["action"] in KNOWN_ACTIONS, "%s action" % class_id)
		assert_true(Color.html_is_valid(hero_class["color"]), "%s color" % class_id)


func test_shieldbearers_have_the_tank_passive() -> void:
	for hero in data.heroes["heroes"]:
		if hero["class"] == "shieldbearer":
			var multiplier := float(hero.get("passive", {}).get("damage_taken_multiplier", 1.0))
			assert_true(hero["passive"]["type"] == "damage_taken_reduction" and multiplier > 0.0 and multiplier < 1.0,
					"%s takes less damage" % hero["id"])


func test_starting_heroes_and_unlocks() -> void:
	assert_eq(data.starting_hero_ids(), ["torvald", "sigrid", "eyvind"], "starting heroes")
	assert_eq(int(data.get_hero("angrboda")["unlock_after_stage"]), 3, "Angrboda unlock (M6: the healer comes first)")
	assert_eq(int(data.get_hero("skadi")["unlock_after_stage"]), 6, "Skadi unlock")
	assert_eq(int(data.get_hero("hrungnir")["unlock_after_stage"]), 9, "Hrungnir unlock")


func test_three_enemy_types_and_the_boss() -> void:
	var regular := []
	var bosses := []
	for enemy in data.enemies["enemies"]:
		(bosses if enemy.get("boss", false) else regular).append(enemy["id"])
		assert_true(enemy["row"] in ["front", "back"], "%s row" % enemy["id"])
		assert_true(enemy["action"] in KNOWN_ACTIONS, "%s action" % enemy["id"])
		assert_true(enemy["hp"] > 0 and enemy["attack"] > 0 and enemy["attack_interval"] > 0, "%s stats positive" % enemy["id"])
		assert_true(Color.html_is_valid(enemy["color"]), "%s color" % enemy["id"])
	assert_eq(regular, ["draugr", "wolf", "draugr_archer"], "regular enemy ids")
	assert_eq(bosses, ["draugr_king"], "boss ids")
	var special: Dictionary = data.get_enemy("draugr_king")["special"]
	assert_eq(special["type"], "hit_all", "boss strikes the whole squad")
	assert_true(special["interval"] > 0 and special["attack_multiplier"] > 0, "boss strike numbers positive")


func test_ten_stages_of_three_waves() -> void:
	var known := []
	for enemy in data.enemies["enemies"]:
		known.append(enemy["id"])
	assert_eq(data.stage_count(), 10, "stage count")
	for i in data.stage_count():
		var stage: Dictionary = data.stages["stages"][i]
		assert_eq(int(stage["id"]), i + 1, "stage ids in order")
		assert_true(not data.get_chapter(int(stage["chapter"])).is_empty(), "stage %s chapter exists" % stage["id"])
		assert_eq(stage["waves"].size(), 3, "stage %s has 3 waves" % stage["id"])
		assert_true(stage["reward"]["silver"] > 0 and stage["reward"]["experience"] > 0, "stage %s reward" % stage["id"])
		for w in stage["waves"].size():
			var wave: Array = stage["waves"][w]
			assert_true(not wave.is_empty(), "stage %s wave %d not empty" % [stage["id"], w + 1])
			for enemy_id in wave:
				assert_true(enemy_id in known, "stage %s enemy %s known" % [stage["id"], enemy_id])
				var is_boss_slot: bool = int(stage["id"]) == 10 and w == 2
				assert_eq(data.get_enemy(enemy_id).get("boss", false), is_boss_slot, "boss only in stage 10 wave 3 (stage %s wave %d)" % [stage["id"], w + 1])


func test_leveling_and_growth_present() -> void:
	var leveling: Dictionary = data.balance["leveling"]
	assert_true(leveling["max_level"] > 1, "max level")
	assert_true(leveling["cost_base"] > 0 and leveling["cost_growth"] >= 1.0, "level cost")
	assert_true(leveling["stat_growth_per_level"] > 0, "stat growth")
	assert_true(data.balance["enemy_power_growth_per_stage"] >= 0, "enemy growth")
	assert_true(data.balance["start_silver"] >= 0, "start silver")


func test_energy_balance_present() -> void:
	var energy: Dictionary = data.balance["energy"]
	assert_true(energy["per_attack"] > 0, "energy per attack")
	assert_true(energy["per_heal"] >= 0, "energy per heal")
	assert_true(energy["per_hit_taken"] > 0, "energy per hit taken")


func test_target_weights_present() -> void:
	var weights: Dictionary = data.balance["target_weights"]
	assert_true(weights["default"] > 0, "default target weight")
	for class_id in weights["by_class"]:
		assert_true(data.heroes["classes"].has(class_id), "weighted class %s exists" % class_id)
		assert_true(weights["by_class"][class_id] > 0, "weight of %s positive" % class_id)


func test_classes_have_short_roles() -> void:
	for class_id in data.heroes["classes"]:
		assert_true(data.heroes["classes"][class_id]["role_short"] in ["Танк", "Урон", "Лекарь", "Поддержка"], "%s role" % class_id)


func test_clan_synergies_present() -> void:
	for clan_id in data.heroes["clans"]:
		var synergy: Dictionary = data.heroes["clans"][clan_id]["synergy"]
		assert_true(synergy["min_heroes"] > 1, "%s needs several heroes" % clan_id)
		assert_true(synergy["stat"] in ["hp", "attack"], "%s bonus stat" % clan_id)
		assert_true(synergy["bonus"] > 0, "%s bonus positive" % clan_id)


func test_m4_balance_settings_present() -> void:
	var formation: Dictionary = data.balance["formation"]
	assert_eq([int(formation["front_slots"]), int(formation["back_slots"])], [2, 3], "2 front and 3 back slots")
	assert_true(data.balance["replay_reward_share"] > 0 and data.balance["replay_reward_share"] <= 1, "replay share")
	assert_true(data.balance["jarl"]["exp_per_level"] > 0 and data.balance["jarl"]["silver_bonus_per_level"] >= 0, "jarl")
	var offline: Dictionary = data.balance["offline_income"]
	assert_true(offline["full_time_in_first_wins"] > 0 and offline["max_hours"] > 0, "offline income")
	assert_true(offline["last_seen_refresh_seconds"] > 0, "last-seen refresh interval")


func test_debug_panel_settings_present() -> void:
	var debug: Dictionary = data.balance["debug_panel"]
	assert_true(debug["long_press_seconds"] > 0, "hold time for the debug panel")
	assert_true(debug["add_silver"] > 0 and debug["skip_time_hours"] > 0, "debug panel amounts")


func test_balance_check_settings_present() -> void:
	var check: Dictionary = data.balance["balance_check"]
	assert_true(check["max_average_replays_per_stage"] > 0 and check["stuck_after_replays"] > 0, "thresholds")
	assert_true(check["variants"].size() > 1, "several variants")
	for variant in check["variants"]:
		assert_true(variant["name"] is String and variant["heroes"] > 0 and variant["rewards"] > 0, "variant %s" % str(variant))


func test_stage_one_has_no_boss_and_heroes_unlock_on_real_stages() -> void:
	for hero in data.heroes["heroes"]:
		var stage := int(hero["unlock_after_stage"])
		assert_true(stage >= 0 and stage < data.stage_count(), "%s unlocks on an existing stage" % hero["id"])
