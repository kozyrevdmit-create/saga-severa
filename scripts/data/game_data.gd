## Loads game content (heroes, enemies, stages, balance, visual) from JSON files in res://data/.
## All balance numbers live in those files, never in code; visual.json holds the tunable strength of the hit feedback.
extends RefCounted

const DATA_DIR := "res://data/"

var heroes: Dictionary  ## heroes.json: classes, clans, heroes
var enemies: Dictionary  ## enemies.json
var stages: Dictionary  ## stages.json
var balance: Dictionary  ## balance.json
var visual: Dictionary  ## visual.json: hit flash and shake


static func load_all() -> RefCounted:
	var data = new()
	data.heroes = load_json("heroes.json")
	data.enemies = load_json("enemies.json")
	data.stages = load_json("stages.json")
	data.balance = load_json("balance.json")
	data.visual = load_json("visual.json")
	return data


static func load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		push_error("Data file not found: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Data file is not a valid JSON object: %s" % path)
		return {}
	return parsed


func get_hero(hero_id: String) -> Dictionary:
	for hero in heroes.get("heroes", []):
		if hero["id"] == hero_id:
			return hero
	push_error("Unknown hero: %s" % hero_id)
	return {}


func get_hero_class(hero: Dictionary) -> Dictionary:
	return heroes["classes"][hero["class"]]


func get_enemy(enemy_id: String) -> Dictionary:
	for enemy in enemies.get("enemies", []):
		if enemy["id"] == enemy_id:
			return enemy
	push_error("Unknown enemy: %s" % enemy_id)
	return {}


func get_stage(stage_id: int) -> Dictionary:
	for stage in stages.get("stages", []):
		if int(stage["id"]) == stage_id:
			return stage
	push_error("Unknown stage: %d" % stage_id)
	return {}


func stage_count() -> int:
	return stages.get("stages", []).size()


func get_chapter(chapter_id: int) -> Dictionary:
	for chapter in stages.get("chapters", []):
		if int(chapter["id"]) == chapter_id:
			return chapter
	push_error("Unknown chapter: %d" % chapter_id)
	return {}


func max_level() -> int:
	return int(balance["leveling"]["max_level"])


## Silver to raise a hero from `level` to `level + 1`: cost_base × cost_growth^(level − 1).
func level_up_cost(level: int) -> int:
	var leveling: Dictionary = balance["leveling"]
	return roundi(float(leveling["cost_base"]) * pow(float(leveling["cost_growth"]), level - 1))


## HP and attack multiplier at `level`: each level adds stat_growth_per_level on top of the previous one.
func hero_stat_multiplier(level: int) -> float:
	return pow(1.0 + float(balance["leveling"]["stat_growth_per_level"]), level - 1)


## «Сила» of one hero, a whole number: HP × hp_weight + attack × attack_weight (balance.json → squad_power),
## with HP and attack at the hero's level (stat_growth_per_level) and the squad's clan bonuses (synergy_bonuses).
func hero_power(hero_id: String, level: int, synergy: Dictionary) -> int:
	var hero: Dictionary = get_hero(hero_id)
	var weights: Dictionary = balance["squad_power"]
	var multiplier := hero_stat_multiplier(level)
	var hp := float(hero["hp"]) * multiplier * (1.0 + float(synergy["hp"]))
	var attack := float(hero["attack"]) * multiplier * (1.0 + float(synergy["attack"]))
	return roundi(hp * float(weights["hp_weight"]) + attack * float(weights["attack_weight"]))


## «Рекомендуемая сила» of a stage (stages.json → recommended_power, found by tools/balance_sim.gd -- --recommend).
func recommended_power(stage_id: int) -> int:
	return int(get_stage(stage_id)["recommended_power"])


## Enemy HP and attack multiplier on a stage: each stage adds enemy_power_growth_per_stage on top of the previous one.
func enemy_power_multiplier(stage_id: int) -> float:
	return pow(1.0 + float(balance["enemy_power_growth_per_stage"]), stage_id - 1)


func front_slot_count() -> int:
	return int(balance["formation"]["front_slots"])


func slot_count() -> int:
	return front_slot_count() + int(balance["formation"]["back_slots"])


## Heroes that join the squad after winning `stage_id` for the first time (in data order).
func heroes_unlocked_at(stage_id: int) -> Array[String]:
	var ids: Array[String] = []
	for hero in heroes.get("heroes", []):
		if int(hero["unlock_after_stage"]) == stage_id and stage_id > 0:
			ids.append(hero["id"])
	return ids


## All heroes available once stages up to `cleared_stage` are won (in data order).
func unlocked_hero_ids(cleared_stage: int) -> Array[String]:
	var ids: Array[String] = []
	for hero in heroes.get("heroes", []):
		if int(hero["unlock_after_stage"]) <= cleared_stage:
			ids.append(hero["id"])
	return ids


## Clan bonuses for a squad: every clan with at least min_heroes members gives its bonus to the whole squad.
## Returns [{clan_id, name, count, needed, active, stat, bonus, description}] in data order.
func clan_synergies(hero_ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for clan_id in heroes["clans"]:
		var clan: Dictionary = heroes["clans"][clan_id]
		var synergy: Dictionary = clan["synergy"]
		var count := 0
		for hero_id in hero_ids:
			if get_hero(hero_id)["clan"] == clan_id:
				count += 1
		result.append({
			"clan_id": clan_id, "name": clan["name"], "count": count, "needed": int(synergy["min_heroes"]),
			"active": count >= int(synergy["min_heroes"]), "stat": synergy["stat"],
			"bonus": float(synergy["bonus"]), "description": synergy["description"],
		})
	return result


## Total active clan bonus per stat: {"hp": 0.2, "attack": 0.0}.
func synergy_bonuses(hero_ids: Array) -> Dictionary:
	var bonuses := {"hp": 0.0, "attack": 0.0}
	for synergy in clan_synergies(hero_ids):
		if synergy["active"]:
			bonuses[synergy["stat"]] += synergy["bonus"]
	return bonuses


## Heroes available from the very start (in data order).
func starting_hero_ids() -> Array[String]:
	var ids: Array[String] = []
	for hero in heroes.get("heroes", []):
		if int(hero["unlock_after_stage"]) == 0:
			ids.append(hero["id"])
	return ids
