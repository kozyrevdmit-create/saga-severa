## Player progress: silver, experience, won stages and hero levels.
## Rules only; reading and writing the save file lives in save_storage.gd.
extends RefCounted

const VERSION := 1  ## save format version

var silver := 0
var experience := 0
var cleared_stage := 0  ## highest stage won, 0 = none yet
var hero_levels := {}  ## hero id -> level, in squad order


static func new_game(data) -> RefCounted:
	var progress = new()
	progress.silver = int(data.balance["start_silver"])
	for hero_id in data.starting_hero_ids():
		progress.hero_levels[hero_id] = 1
	return progress


## Stage for «В бой»: the first one not won yet, or the last one once the chapter is done.
func next_stage_id(data) -> int:
	return mini(cleared_stage + 1, data.stage_count())


func level_of(hero_id: String) -> int:
	return int(hero_levels.get(hero_id, 1))


func level_up_cost(data, hero_id: String) -> int:
	return data.level_up_cost(level_of(hero_id))


func is_max_level(data, hero_id: String) -> bool:
	return level_of(hero_id) >= data.max_level()


func can_level_up(data, hero_id: String) -> bool:
	return hero_levels.has(hero_id) and not is_max_level(data, hero_id) and silver >= level_up_cost(data, hero_id)


func level_up(data, hero_id: String) -> bool:
	if not can_level_up(data, hero_id):
		return false
	silver -= level_up_cost(data, hero_id)
	hero_levels[hero_id] = level_of(hero_id) + 1
	return true


## Adds the stage reward and marks the stage won. Returns the reward: {silver, experience}.
func apply_victory(data, stage_id: int) -> Dictionary:
	var reward: Dictionary = data.get_stage(stage_id)["reward"]
	silver += int(reward["silver"])
	experience += int(reward["experience"])
	cleared_stage = maxi(cleared_stage, stage_id)
	return reward


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"silver": silver,
		"experience": experience,
		"cleared_stage": cleared_stage,
		"hero_levels": hero_levels.duplicate(),
	}


## Restores saved progress. Missing or broken values fall back to a new game's values.
static func from_dict(saved: Dictionary, data) -> RefCounted:
	var progress = new_game(data)
	if _to_int(saved.get("version"), -1) != VERSION:
		push_warning("Unknown save version %s, starting a new game" % str(saved.get("version")))
		return progress
	progress.silver = maxi(0, _to_int(saved.get("silver"), progress.silver))
	progress.experience = maxi(0, _to_int(saved.get("experience"), 0))
	progress.cleared_stage = clampi(_to_int(saved.get("cleared_stage"), 0), 0, data.stage_count())
	var levels = saved.get("hero_levels")
	if levels is Dictionary:
		for hero_id in progress.hero_levels:
			progress.hero_levels[hero_id] = clampi(_to_int(levels.get(hero_id), 1), 1, data.max_level())
	return progress


static func _to_int(value, fallback: int) -> int:
	return int(value) if (value is int or value is float) else fallback
