## Checks that data/*.json is complete and consistent.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")

const KNOWN_ACTIONS := ["attack_front_row", "attack_lowest_hp", "heal_or_attack", "attack_back_row_weakest"]
const KNOWN_EFFECTS := ["buff_allies", "hits", "damage", "heal_allies"]
const KNOWN_TARGETS := ["front_row_single", "front_row_all", "all_enemies"]
const KNOWN_PASSIVES := ["attack_per_missing_hp", "damage_taken_reduction", "front_row_damage_taken_reduction"]

var data = GameData.load_all()


## M13: Regin is the seventh.
func test_all_seven_heroes_present() -> void:
	var ids := []
	for hero in data.heroes["heroes"]:
		ids.append(hero["id"])
	assert_eq(ids, ["torvald", "sigrid", "eyvind", "angrboda", "skadi", "hrungnir", "regin"], "hero ids")


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


## The power grows from stage to stage within a chapter. M13: the first stage of chapter 3 asks less than the end of
## chapter 2: Regin joins with the chapter, and his armour for the front row is not counted in «Сила» (HP and attack only),
## so the same fight needs less «Сила»; the first stage of a chapter is not compared with the chapter before.
func test_every_stage_has_a_growing_recommended_power() -> void:
	var previous := 0
	for stage in data.stages["stages"]:
		var stage_id := int(stage["id"])
		var power: int = data.recommended_power(stage_id)
		assert_true(power > 0, "stage %s has a recommended power" % stage_id)
		if data.chapter_stage_ids(int(stage["chapter"]))[0] != stage_id:
			assert_true(power >= previous, "stage %s needs at least as much power as the one before" % stage_id)
		previous = power


func test_heroes_have_role_details() -> void:
	for hero in data.heroes["heroes"]:
		var detail: String = hero.get("role_detail", "")
		assert_true(detail.begins_with(data.get_hero_class(hero)["role_short"] + " · "), "%s: «роль · уточнение»" % hero["id"])


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
	assert_eq(regular, ["draugr", "wolf", "draugr_archer", "boar", "bear", "ice_troll", "ironwood_wolf", "carrion_eagle",
			"rune_golem", "cave_spider", "forge_spirit"],
			"regular enemy ids (boar and bear: beast packs, M9; troll, Iron Wood wolf and carrion eagle: chapter 2, M11; golem, spider, forge spirit: chapter 3, M13)")
	assert_eq(bosses, ["draugr_king", "thjazi", "fafnir"], "boss ids")
	var special: Dictionary = data.get_enemy("draugr_king")["special"]
	assert_eq(special["type"], "hit_all", "boss strikes the whole squad")
	assert_true(special["interval"] > 0 and special["attack_multiplier"] > 0, "boss strike numbers positive")


## M11: chapter 2's enemies (LORE.md «Глава 2 — Ётунхейм, подробно», TZ M11 section 3).
func test_chapter_two_enemies() -> void:
	var troll: Dictionary = data.get_enemy("ice_troll")
	var wolf: Dictionary = data.get_enemy("ironwood_wolf")
	var eagle: Dictionary = data.get_enemy("carrion_eagle")
	for enemy in [troll, wolf, eagle]:
		assert_eq(enemy["row"], "front", "%s stands in the enemies' front row" % enemy["id"])
	assert_eq(troll["action"], "attack_front_row", "the troll hits the front row")
	assert_true(troll["hp"] > wolf["hp"] * 2 and troll["hp"] > eagle["hp"] * 2, "the troll has a lot of HP")
	assert_true(troll["attack_interval"] > wolf["attack_interval"] and troll["attack"] > wolf["attack"] * 2,
			"the troll is slow and hits hard")
	var midgard_wolf: Dictionary = data.get_enemy("wolf")
	assert_true(wolf["attack_interval"] <= midgard_wolf["attack_interval"], "the Iron Wood wolf is fast")
	assert_true(wolf["hp"] > midgard_wolf["hp"] and wolf["attack"] > midgard_wolf["attack"], "and stronger than the Midgard wolf")
	assert_eq(eagle["action"], "attack_back_row_weakest", "the carrion eagle goes for the back row")
	assert_true(eagle["hp"] < wolf["hp"] and eagle["attack_interval"] < troll["attack_interval"], "the eagle has little HP and is fast")


## Thjazi (M11): a giant with «Ледяное копьё» on the front row, an eagle from half HP: faster, at the weakest of the
## back row, with «Пике». The numbers are data.
func test_thjazi_has_two_phases() -> void:
	var thjazi: Dictionary = data.get_enemy("thjazi")
	assert_eq(thjazi["name"], "Тьяцци", "the name")
	var spear: Dictionary = thjazi["special"]
	assert_eq([spear["name"], spear["type"], spear["target"]], ["Ледяное копьё", "hit_one", "front_row"], "the ice spear")
	assert_near(float(spear["interval"]), 6.0, 0.001, "every 6 s")
	assert_true(float(spear["attack_multiplier"]) > 1.0, "the spear hits harder than a blow")
	assert_eq(thjazi["phases"].size(), 1, "one change of form")
	var eagle: Dictionary = thjazi["phases"][0]
	assert_near(float(eagle["at_hp_fraction"]), 0.5, 0.001, "at half HP")
	assert_eq(eagle["picture"], "thjazi_eagle", "the eagle's picture")
	assert_true(ResourceLoader.exists("res://assets/art/enemies/thjazi_eagle.png"), "the eagle's picture is in the game")
	assert_eq(eagle["announcement"], "Тьяцци обращается в орла!", "the announcement")
	assert_eq(eagle["action"], "attack_back_row_weakest", "the eagle goes for the back row")
	assert_true(float(eagle["attack_interval_multiplier"]) < 1.0, "and attacks faster")
	var dive: Dictionary = eagle["special"]
	assert_eq([dive["name"], dive["type"], dive["target"]], ["Пике", "hit_one", "back_row_weakest"], "the dive")
	assert_near(float(dive["interval"]), 5.0, 0.001, "every 5 s")
	assert_true(float(dive["attack_multiplier"]) > 1.0, "the dive hits harder than a blow")


## Two chapters of ten stages, the numbers go on (chapter 2 is stages 11–20); each chapter's boss stands alone in the
## last wave of its last stage; a chapter's stages bring only its own enemies (M11: chapter 2 only the troll, the Iron
## Wood wolf and the carrion eagle, and Thjazi).
## M13: chapter 3 «Свартальфхейм», stages 21–30, Fafnir on stage 30.
func test_three_chapters_of_ten_stages_of_three_waves() -> void:
	var known := []
	for enemy in data.enemies["enemies"]:
		known.append(enemy["id"])
	assert_eq(data.chapter_ids(), [1, 2, 3] as Array[int], "three chapters")
	assert_eq(data.get_chapter(2)["name"], "Ётунхейм", "chapter 2")
	assert_eq(data.get_chapter(3)["name"], "Свартальфхейм", "chapter 3")
	assert_eq(data.get_chapter(3)["map"], "map_svartalfheim", "chapter 3's map")
	assert_eq(data.stage_count(), 30, "stage count")
	assert_eq(data.chapter_stage_ids(1), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] as Array[int], "chapter 1: stages 1–10")
	assert_eq(data.chapter_stage_ids(2), [11, 12, 13, 14, 15, 16, 17, 18, 19, 20] as Array[int], "chapter 2: stages 11–20")
	assert_eq(data.chapter_stage_ids(3), [21, 22, 23, 24, 25, 26, 27, 28, 29, 30] as Array[int], "chapter 3: stages 21–30")
	var chapter_enemies := {
		1: ["draugr", "wolf", "draugr_archer", "draugr_king"],
		2: ["ice_troll", "ironwood_wolf", "carrion_eagle", "thjazi"],
		3: ["rune_golem", "cave_spider", "forge_spirit", "fafnir"],
	}
	var bosses := {10: "draugr_king", 20: "thjazi", 30: "fafnir"}
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
				assert_true(enemy_id in chapter_enemies[int(stage["chapter"])], "stage %s: %s belongs to its chapter" % [stage["id"], enemy_id])
				var is_boss_slot: bool = bosses.has(int(stage["id"])) and w == 2
				assert_eq(data.get_enemy(enemy_id).get("boss", false), is_boss_slot, "boss only in stage 10, 20 and 30 wave 3 (stage %s wave %d)" % [stage["id"], w + 1])
			if bosses.has(int(stage["id"])) and w == 2:
				assert_eq(wave, [bosses[int(stage["id"])]], "stage %s: the boss stands alone" % stage["id"])
	for stage_id in range(1, data.stage_count() + 1):
		assert_eq(data.is_boss_stage(stage_id), bosses.has(stage_id), "stage %d: boss stage" % stage_id)


func test_leveling_and_growth_present() -> void:
	var leveling: Dictionary = data.balance["leveling"]
	assert_true(leveling["max_level"] > 1, "max level")
	assert_true(leveling["cost_base"] > 0 and leveling["cost_growth"] >= 1.0, "level cost")
	assert_true(leveling["stat_growth_per_level"] > 0, "stat growth")
	assert_true(data.balance["enemy_power_growth_per_stage"] >= 0, "enemy growth")
	assert_true(data.enemy_power_growth(2) > 0, "chapter 2 has its own enemy growth")
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


## Svartalfheim (M13) has one hero so far: its bonus is not set yet (it comes with other dwarves, LORE.md «Регин»).
func test_clan_synergies_present() -> void:
	for clan_id in data.heroes["clans"]:
		var synergy: Dictionary = data.heroes["clans"][clan_id]["synergy"]
		assert_true(synergy["min_heroes"] > 1, "%s needs several heroes" % clan_id)
		assert_true(synergy["stat"] in ["hp", "attack"], "%s bonus stat" % clan_id)
		if clan_id == "svartalfheim":
			var members: Array = data.heroes["heroes"].filter(func(hero): return hero["clan"] == clan_id)
			assert_true(members.size() < int(synergy["min_heroes"]), "Svartalfheim's bonus cannot be active yet")
		else:
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
		assert_true(stage >= 0 and stage <= data.stage_count(), "%s unlocks on an existing stage" % hero["id"])


## M8: the hit feedback is short (~0.15 s) and a fighter does not flash again before the last flash is over.
func test_hit_feedback_is_short_and_spaced() -> void:
	var visual: Dictionary = GameData.load_all().visual
	var flash: Dictionary = visual["hit_flash"]
	var flash_seconds := float(flash["hold_seconds"]) + float(flash["fade_seconds"])
	assert_near(flash_seconds, 0.15, 0.05, "the flash lasts about 0.15 s")
	assert_true(float(flash["strength"]) > 0.0 and float(flash["strength"]) <= 1.0, "flash strength is a share")
	assert_true(Color.html_is_valid(flash["color"]), "flash colour")
	assert_true(float(visual["hit_shake"]["distance"]) <= 0.05, "a light shake: at most 5% of the picture")
	assert_near(float(visual["hit_shake"]["seconds"]), 0.15, 0.05, "the shake is short")
	assert_true(float(visual["hit_min_gap_seconds"]) > maxf(flash_seconds, float(visual["hit_shake"]["seconds"])),
			"the next flash of one fighter waits until the last one is over")


# --- chapter map and beast packs (M9) -------------------------------------------

func test_every_stage_has_a_point_on_the_map_from_the_bottom_up() -> void:
	for chapter_id in data.chapter_ids():
		var chapter: Dictionary = data.get_chapter(chapter_id)
		assert_true(ResourceLoader.exists("res://assets/art/maps/%s.png" % chapter.get("map", "")), "chapter %d has a map picture" % chapter_id)
	var previous_y := 1.0
	for stage in data.stages["stages"]:
		if int(stage["id"]) == data.chapter_stage_ids(int(stage["chapter"]))[0]:
			previous_y = 1.0  # a new chapter's map: from the bottom again
		var point: Dictionary = stage["map_point"]
		var where := "stage %d" % int(stage["id"])
		assert_true(point["x"] > 0.0 and point["x"] < 1.0 and point["y"] > 0.0 and point["y"] < 1.0, "%s: point inside the map" % where)
		assert_true(point["label"] in ["left", "right"], "%s: caption side" % where)
		assert_true(float(point["y"]) < previous_y, "%s: higher on the map than the stage before" % where)
		previous_y = float(point["y"])


func test_three_beast_packs_in_each_chapter() -> void:
	assert_eq(data.pack_ids(1), ["wolves", "boars", "bear"] as Array[String], "Midgard's packs")
	assert_eq(data.pack_ids(2), ["ironwood_wolves", "troll", "scavengers"] as Array[String], "Jotunheim's packs (M11)")
	assert_eq(data.pack_ids(3), ["cave_spiders", "rune_golem", "forge_spirits"] as Array[String], "Svartalfheim's packs (M13)")
	assert_eq(data.pack_ids(), data.pack_ids(1) + data.pack_ids(2) + data.pack_ids(3), "all packs")
	var unlocks: Array = data.packs["packs"].map(func(pack): return int(pack["unlock_after_stage"]))
	assert_eq(unlocks, [0, 3, 6, 10, 13, 16, 20, 23, 26],
			"wolves from the start, boars after 3, the bear after 6; Iron Wood wolves with chapter 2, the troll after 13, the scavengers after 16; spiders with chapter 3, the golem after 23, the spirits after 26")
	assert_eq(data.get_pack("wolves")["enemies"].all(func(id): return id == "wolf"), true, "the wolf pack is wolves")
	assert_eq(data.get_pack("boars")["enemies"].all(func(id): return id == "boar"), true, "the boar pack is boars")
	assert_eq(data.get_pack("bear")["enemies"], ["bear"], "the bear is alone")
	assert_eq(data.get_pack("ironwood_wolves")["enemies"], ["ironwood_wolf", "ironwood_wolf", "ironwood_wolf"], "three Iron Wood wolves")
	assert_eq(data.get_pack("troll")["enemies"][0], "ice_troll", "the troll (maybe with a wolf)")
	assert_true(data.get_pack("troll")["enemies"].slice(1).all(func(id): return id == "ironwood_wolf"), "the troll's only company is a wolf")
	assert_eq(data.get_pack("scavengers")["enemies"], ["carrion_eagle", "carrion_eagle", "carrion_eagle"], "three carrion eagles")
	assert_eq(data.get_pack("ironwood_wolves")["name"], "Волки Железного леса", "names from the TZ")
	assert_eq(data.get_pack("troll")["name"], "Тролль", "names from the TZ")
	assert_eq(data.get_pack("scavengers")["name"], "Падальщики", "names from the TZ")
	assert_eq(data.get_pack("cave_spiders")["enemies"], ["cave_spider", "cave_spider", "cave_spider"], "three cave spiders")
	assert_eq(data.get_pack("rune_golem")["enemies"][0], "rune_golem", "the golem (maybe with a spider)")
	assert_true(data.get_pack("rune_golem")["enemies"].slice(1).all(func(id): return id == "cave_spider"), "the golem's only company is a spider")
	assert_eq(data.get_pack("forge_spirits")["enemies"], ["forge_spirit", "forge_spirit", "forge_spirit"], "three forge spirits")
	assert_eq([data.get_pack("cave_spiders")["name"], data.get_pack("rune_golem")["name"], data.get_pack("forge_spirits")["name"]],
			["Пещерные пауки", "Рунный голем", "Духи горна"], "names from the TZ")
	for pack in data.packs["packs"]:
		var who: String = pack["id"]
		assert_true(not str(pack["name"]).is_empty(), "%s has a name" % who)
		assert_true(pack["enemies"].size() >= 1 and pack["enemies"].size() <= 3, "%s: one wave that fits the enemy front row" % who)
		for enemy_id in pack["enemies"]:
			assert_eq(data.get_enemy(enemy_id)["row"], "front", "%s: %s stands in the front row" % [who, enemy_id])
		assert_true(data.get_enemy(pack["icon"]).has("portrait"), "%s: the icon beast has a portrait" % who)
		var point: Dictionary = pack["map_point"]
		assert_true(point["x"] > 0.0 and point["x"] < 1.0 and point["y"] > 0.0 and point["y"] < 1.0, "%s: point inside the map" % who)
	var packs: Dictionary = data.balance["beast_packs"]
	assert_eq(data.pack_respawn_seconds(), roundi(float(packs["respawn_hours"]) * 3600.0), "respawn time from balance.json")
	assert_true(float(packs["reward_share_of_first_win"]) > 0.0 and float(packs["reward_share_of_first_win"]) < 1.0,
			"a pack pays less than a first win")
	assert_true(float(packs["reward_share_once_the_next_chapter_is_open"]) > 0.0
			and float(packs["reward_share_once_the_next_chapter_is_open"]) < float(packs["reward_share_of_first_win"]),
			"a pack of a passed chapter pays less than one of the current chapter (M11.1)")


func test_boar_and_bear() -> void:
	var boar: Dictionary = data.get_enemy("boar")
	var bear: Dictionary = data.get_enemy("bear")
	var draugr: Dictionary = data.get_enemy("draugr")
	assert_true(boar["attack_interval"] < draugr["attack_interval"], "the boar is fast")
	assert_true(boar["hp"] < draugr["hp"] and boar["hp"] > data.get_enemy("wolf")["hp"], "the boar has medium HP")
	assert_true(float(boar["first_strike"]["attack_multiplier"]) > 1.0, "the boar's first strike (charge) is strong")
	assert_true(bear["hp"] > draugr["hp"] * 2, "the bear has a lot of HP")
	assert_true(bear["attack_interval"] > draugr["attack_interval"], "the bear is slow")
	assert_true(bear["attack"] > draugr["attack"] * 1.5, "the bear hits hard")
