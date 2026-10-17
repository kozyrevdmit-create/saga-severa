## Loads game content (heroes, enemies, stages, beast packs, settlement buildings, balance, visual, saga scenes, hints)
## from JSON files in res://data/.
## All balance numbers live in those files, never in code; visual.json holds the tunable strength of the hit feedback;
## story.json holds the texts of the saga scenes (word for word from docs/STORY_M10.md, M11, M12) and when each scene is shown.
extends RefCounted

const DATA_DIR := "res://data/"

var heroes: Dictionary  ## heroes.json: classes, clans, heroes
var enemies: Dictionary  ## enemies.json
var stages: Dictionary  ## stages.json: chapters (map picture, enemy growth), stages (chapter, point on the map)
var packs: Dictionary  ## packs.json: beast packs on a chapter's map (chapter, enemies, unlock, point on the map)
var buildings: Dictionary  ## buildings.json: the settlement's buildings (M12): when they open, level costs, bonuses, places
var balance: Dictionary  ## balance.json
var visual: Dictionary  ## visual.json: hit flash and shake
var story: Dictionary  ## story.json: saga scenes (lines, when shown), the ravens who speak in them, speakers' captions
var hints: Dictionary  ## hints.json: tips under «Дружина пала» (defeat: [{when, text}], see StageBattle.defeat_hints)


static func load_all() -> RefCounted:
	var data = new()
	data.heroes = load_json("heroes.json")
	data.enemies = load_json("enemies.json")
	data.stages = load_json("stages.json")
	data.packs = load_json("packs.json")
	data.buildings = load_json("buildings.json")
	data.balance = load_json("balance.json")
	data.visual = load_json("visual.json")
	data.story = load_json("story.json")
	data.hints = load_json("hints.json")
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


# --- saga scenes (story.json) --------------------------------------------------

func get_scene(scene_id: String) -> Dictionary:
	for scene in story.get("scenes", []):
		if scene["id"] == scene_id:
			return scene
	push_error("Unknown saga scene: %s" % scene_id)
	return {}


func has_scene(scene_id: String) -> bool:
	return story.get("scenes", []).any(func(scene): return scene["id"] == scene_id)


## Scene ids in story order.
func scene_ids() -> Array[String]:
	var ids: Array[String] = []
	for scene in story.get("scenes", []):
		ids.append(scene["id"])
	return ids


## Scenes shown at the moment `when` (story.json → scenes[].show.when): "new_game", "hero_joined" (subject = hero id),
## "before_first_battle" or "first_victory" (subject = stage id), "chapter_map" (subject = chapter id: the first time
## the chapter's map is shown), "before_battle_with" (subject = enemy id: before the first battle where it fights),
## "settlement" (no subject: the first time the settlement is entered with construction open, M12).
## In story order.
func scene_ids_shown_at(when: String, subject = null) -> Array[String]:
	var ids: Array[String] = []
	for scene in story.get("scenes", []):
		var show: Dictionary = scene["show"]
		if show["when"] != when:
			continue
		if show.has("hero") and show["hero"] != subject:
			continue
		if show.has("enemy") and show["enemy"] != subject:
			continue
		if show.has("stage") and not _is_number(subject, show["stage"]):
			continue
		if show.has("chapter") and not _is_number(subject, show["chapter"]):
			continue
		ids.append(scene["id"])
	return ids


static func _is_number(subject, number) -> bool:
	return (subject is int or subject is float) and int(number) == int(subject)


## The name over a line: a raven or an enemy who speaks (story.json → speakers) or a hero (heroes.json).
func speaker_name(speaker_id: String) -> String:
	var speakers: Dictionary = story.get("speakers", {})
	return speakers[speaker_id]["name"] if speakers.has(speaker_id) else get_hero(speaker_id)["name"]


## The short caption under the name, «кто есть кто» (story.json → captions, word for word from docs/LORE.md, 6а).
func speaker_caption(speaker_id: String) -> String:
	return story.get("captions", {}).get(speaker_id, "")


func is_raven(speaker_id: String) -> bool:
	return story.get("speakers", {}).has(speaker_id) and speaker_enemy(speaker_id) == ""


## The enemy (enemies.json id) whose head is the speaker's portrait (Thjazi in chapter 2), or "".
func speaker_enemy(speaker_id: String) -> String:
	return story.get("speakers", {}).get(speaker_id, {}).get("enemy", "")


func get_pack(pack_id: String) -> Dictionary:
	for pack in packs.get("packs", []):
		if pack["id"] == pack_id:
			return pack
	push_error("Unknown beast pack: %s" % pack_id)
	return {}


## Beast pack ids in data order (all chapters, or only `chapter_id`'s).
func pack_ids(chapter_id := 0) -> Array[String]:
	var ids: Array[String] = []
	for pack in packs.get("packs", []):
		if chapter_id == 0 or int(pack["chapter"]) == chapter_id:
			ids.append(pack["id"])
	return ids


## Seconds before a beaten pack comes back (balance.json → beast_packs.respawn_hours).
func pack_respawn_seconds() -> int:
	return roundi(float(balance["beast_packs"]["respawn_hours"]) * 3600.0)


# --- settlement buildings (buildings.json) ---------------------------------------

func get_building(building_id: String) -> Dictionary:
	for building in buildings.get("buildings", []):
		if building["id"] == building_id:
			return building
	push_error("Unknown building: %s" % building_id)
	return {}


## Building ids in data order (the order of the settlement's plots and of the window texts).
func building_ids() -> Array[String]:
	var ids: Array[String] = []
	for building in buildings.get("buildings", []):
		ids.append(building["id"])
	return ids


func building_max_level() -> int:
	return int(buildings["max_level"])


## Supplies to raise a building from `level` to `level + 1` (buildings.json → level_costs, the same for every building).
func building_cost(level: int) -> int:
	return int(buildings["level_costs"][level])


## A building's bonus at `level`: buildings.json → bonus.per_level × level (a share: 0.06 = 6%).
func building_bonus(building_id: String, level: int) -> float:
	return float(get_building(building_id)["bonus"]["per_level"]) * level


func stage_count() -> int:
	return stages.get("stages", []).size()


func get_chapter(chapter_id: int) -> Dictionary:
	for chapter in stages.get("chapters", []):
		if int(chapter["id"]) == chapter_id:
			return chapter
	push_error("Unknown chapter: %d" % chapter_id)
	return {}


## Chapter ids in data order (1, 2, …).
func chapter_ids() -> Array[int]:
	var ids: Array[int] = []
	for chapter in stages.get("chapters", []):
		ids.append(int(chapter["id"]))
	return ids


func chapter_of_stage(stage_id: int) -> int:
	return int(get_stage(stage_id)["chapter"])


## The chapter's stage ids in order. Stage numbers go on from chapter to chapter (chapter 2 is stages 11–20).
func chapter_stage_ids(chapter_id: int) -> Array[int]:
	var ids: Array[int] = []
	for stage in stages.get("stages", []):
		if int(stage["chapter"]) == chapter_id:
			ids.append(int(stage["id"]))
	return ids


## The chapter's last stage: the boss.
func is_boss_stage(stage_id: int) -> bool:
	return chapter_stage_ids(chapter_of_stage(stage_id)).back() == stage_id


## The enemy appears in one of the stage's waves.
func stage_has_enemy(stage_id: int, enemy_id: String) -> bool:
	return get_stage(stage_id)["waves"].any(func(wave): return enemy_id in wave)


func pack_has_enemy(pack_id: String, enemy_id: String) -> bool:
	return enemy_id in get_pack(pack_id)["enemies"]


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


## Enemy HP and attack multiplier on a stage: each stage adds its chapter's growth on top of the previous stage
## (stage 11 grows from stage 10 by chapter 2's growth). A chapter's growth is stages.json → chapters[].enemy_power_growth_per_stage,
## or balance.json → enemy_power_growth_per_stage when the chapter has none (chapter 1).
func enemy_power_multiplier(stage_id: int) -> float:
	var multiplier := 1.0
	for chapter_id in chapter_ids():
		var steps := 0  ## stages of this chapter after stage 1, up to stage_id
		for id in chapter_stage_ids(chapter_id):
			if id > 1 and id <= stage_id:
				steps += 1
		multiplier *= pow(1.0 + enemy_power_growth(chapter_id), steps)
	return multiplier


func enemy_power_growth(chapter_id: int) -> float:
	var chapter: Dictionary = get_chapter(chapter_id)
	return float(chapter["enemy_power_growth_per_stage"] if chapter.has("enemy_power_growth_per_stage") \
			else balance["enemy_power_growth_per_stage"])


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
