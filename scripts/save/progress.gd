## Player progress: silver, experience (jarl level), won stages, unlocked heroes with their levels,
## the squad formation and the time the game was last open (for offline income).
## Rules only; reading and writing the save file lives in save_storage.gd.
extends RefCounted

const VERSION := 2  ## save format version; version 1 (M3) is migrated on load
const EMPTY := ""  ## free formation slot

var silver := 0
var experience := 0
var cleared_stage := 0  ## highest stage won, 0 = none yet
var hero_levels := {}  ## unlocked hero id -> level, in unlock order
var formation: Array[String] = []  ## one hero id or EMPTY per slot; front slots first
var last_seen_unix := 0  ## when the game was last open; 0 = never
var offline_bank := 0  ## offline income collected on return, waiting for «Забрать»


static func new_game(data) -> RefCounted:
	var progress = new()
	progress.silver = int(data.balance["start_silver"])
	progress._reset_formation(data)
	for hero_id in data.starting_hero_ids():
		progress.hero_levels[hero_id] = 1
		progress.formation_add(data, hero_id)
	return progress


## Debug panel «Сбросить прогресс»: everything back to a new game (stages, heroes and their levels, squad,
## silver, jarl experience, offline bank). The offline clock restarts now, so the time before the reset earns nothing.
func reset(data, now_unix: int) -> void:
	var fresh = new_game(data)
	silver = fresh.silver
	experience = fresh.experience
	cleared_stage = fresh.cleared_stage
	hero_levels = fresh.hero_levels
	formation = fresh.formation
	offline_bank = fresh.offline_bank
	last_seen_unix = now_unix


## Debug panel «Открыть всех героев»: every locked hero joins like a new hero (at the join level,
## into a free slot if there is one). Returns the heroes that joined.
func unlock_all_heroes(data) -> Array[String]:
	var joined: Array[String] = []
	var level := _join_level(data)
	for hero in data.heroes["heroes"]:
		if not hero_levels.has(hero["id"]):
			_join(data, hero["id"], level)
			joined.append(hero["id"])
	return joined


## Debug panel «Перейти к этапу N»: stages before N count as won (without rewards), N is the next battle.
## Heroes earned by those stages join; heroes already unlocked stay.
func jump_to_stage(data, stage_id: int) -> void:
	cleared_stage = clampi(stage_id, 1, data.stage_count()) - 1
	var level := _join_level(data)
	for hero_id in data.unlocked_hero_ids(cleared_stage):
		if not hero_levels.has(hero_id):
			_join(data, hero_id, level)


# --- stages and rewards -------------------------------------------------------

## The first stage not won yet, or the last one once the chapter is done.
func next_stage_id(data) -> int:
	return mini(cleared_stage + 1, data.stage_count())


## Won stages can be replayed; the next one can be fought; later ones are locked.
func is_stage_open(data, stage_id: int) -> bool:
	return stage_id >= 1 and stage_id <= next_stage_id(data)


func is_replay(stage_id: int) -> bool:
	return stage_id <= cleared_stage


## Pays the reward (a replay pays replay_reward_share of it; the jarl bonus adds silver),
## marks the stage won and unlocks heroes (at the join level, see _join_level).
## Returns {silver, experience, replay, new_heroes}.
func apply_victory(data, stage_id: int) -> Dictionary:
	var replay := is_replay(stage_id)
	var base: Dictionary = data.get_stage(stage_id)["reward"]
	var share := float(data.balance["replay_reward_share"]) if replay else 1.0
	var silver_gain := roundi(float(base["silver"]) * share * silver_multiplier(data))
	var experience_gain := roundi(float(base["experience"]) * share)
	silver += silver_gain
	experience += experience_gain
	var new_heroes: Array[String] = []
	if not replay:
		cleared_stage = maxi(cleared_stage, stage_id)
		var level := _join_level(data)
		for hero_id in data.heroes_unlocked_at(stage_id):
			if not hero_levels.has(hero_id):
				_join(data, hero_id, level)
				new_heroes.append(hero_id)
	return {"silver": silver_gain, "experience": experience_gain, "replay": replay, "new_heroes": new_heroes}


# --- hero levels --------------------------------------------------------------

## A new hero joins at the join level, so they are useful at once and a single reward does not buy them
## a pile of cheap low levels. Heroes joining together all get the level counted before the first of them joined.
func _join(data, hero_id: String, level: int) -> void:
	hero_levels[hero_id] = level
	formation_add(data, hero_id)


## The level a new hero joins at, by balance.json → new_hero.join_level:
## "squad_average" — the average level of the heroes in the squad, rounded down (a hero left on the bench
## does not pull newcomers down); "weakest" — the level of the weakest unlocked hero (the rule before M5.1).
## Heroes in `ignored` do not count (heroes of an old save that have no saved level yet).
func _join_level(data, ignored: Array[String] = []) -> int:
	var rule: String = data.balance["new_hero"]["join_level"]
	var counted: Array = hero_levels.keys().filter(func(id): return not id in ignored)
	match rule:
		"squad_average":
			var in_squad: Array = counted.filter(func(id): return is_in_formation(id))
			if not in_squad.is_empty():
				counted = in_squad
			if counted.is_empty():
				return 1
			var total := 0
			for hero_id in counted:
				total += level_of(hero_id)
			return maxi(1, total / counted.size())
		"weakest":
			return maxi(1, counted.map(func(id): return level_of(id)).min() if not counted.is_empty() else 1)
	push_error("Unknown balance.json → new_hero.join_level: %s" % rule)
	return 1


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


# --- formation ----------------------------------------------------------------

func slot_row(data, slot: int) -> String:
	return "front" if slot < data.front_slot_count() else "back"


func is_in_formation(hero_id: String) -> bool:
	return hero_id in formation


func squad_ids() -> Array[String]:
	var ids: Array[String] = []
	for hero_id in formation:
		if hero_id != EMPTY:
			ids.append(hero_id)
	return ids


## The squad for a battle: [{id, level, row}] in slot order.
func squad(data) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in formation.size():
		if formation[slot] != EMPTY:
			result.append({"id": formation[slot], "level": level_of(formation[slot]), "row": slot_row(data, slot)})
	return result


## Puts a hero into the next free slot: its class's default row first, then the other row.
func formation_add(data, hero_id: String) -> bool:
	if not hero_levels.has(hero_id) or is_in_formation(hero_id):
		return false
	var default_row: String = data.get_hero_class(data.get_hero(hero_id))["row"]
	for row in [default_row, "back" if default_row == "front" else "front"]:
		for slot in formation.size():
			if formation[slot] == EMPTY and slot_row(data, slot) == row:
				formation[slot] = hero_id
				return true
	return false


## Takes a hero out of the squad. The last hero stays: a battle needs at least one.
func formation_remove(hero_id: String) -> bool:
	if not is_in_formation(hero_id) or squad_ids().size() <= 1:
		return false
	formation[formation.find(hero_id)] = EMPTY
	return true


func _reset_formation(data) -> void:
	formation.clear()
	for slot in data.slot_count():
		formation.append(EMPTY)


# --- jarl (account level) -----------------------------------------------------

## Level N needs exp_per_level × N experience to reach level N + 1.
func jarl_level(data) -> int:
	return _jarl_state(data)[0]


## [experience gathered inside the current level, experience needed for the next level].
func jarl_level_progress(data) -> Array[int]:
	var state := _jarl_state(data)
	return [state[1], state[2]]


## Silver multiplier from the jarl level: +silver_bonus_per_level for every level above 1.
func silver_multiplier(data) -> float:
	return 1.0 + float(data.balance["jarl"]["silver_bonus_per_level"]) * (jarl_level(data) - 1)


func _jarl_state(data) -> Array[int]:
	var step := int(data.balance["jarl"]["exp_per_level"])
	var level := 1
	var left := experience
	while left >= step * level:
		left -= step * level
		level += 1
	return [level, left, step * level]


# --- offline income -----------------------------------------------------------

## Silver for a full absence (max_hours): full_time_in_first_wins × the first-win silver of the current stage
## (the next one to win, or the last one once the chapter is done), with the jarl bonus. 0 before the first win.
func offline_income_cap(data) -> int:
	if cleared_stage == 0:
		return 0
	var offline: Dictionary = data.balance["offline_income"]
	var first_win_silver := float(data.get_stage(next_stage_id(data))["reward"]["silver"])
	return roundi(float(offline["full_time_in_first_wins"]) * first_win_silver * silver_multiplier(data))


func offline_max_minutes(data) -> int:
	return int(float(data.balance["offline_income"]["max_hours"]) * 60.0)


## Silver earned since the game was last open: the cap spread evenly over max_hours, whole minutes only.
func offline_income(data, now_unix: int) -> int:
	if last_seen_unix <= 0:
		return 0
	var max_minutes := offline_max_minutes(data)
	var minutes := clampi((now_unix - last_seen_unix) / 60, 0, max_minutes)
	return offline_income_cap(data) * minutes / max_minutes


## Called when the game starts or comes back from the background: puts the income for the time away
## into the bank (saved, so it cannot be lost) and starts counting from now. Returns the amount added.
func collect_offline_income(data, now_unix: int) -> int:
	var gained := offline_income(data, now_unix)
	offline_bank += gained
	last_seen_unix = now_unix
	return gained


## «Забрать»: moves the bank into silver. Returns the amount.
func claim_offline_bank() -> int:
	var amount := offline_bank
	silver += amount
	offline_bank = 0
	return amount


# --- saving -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"silver": silver,
		"experience": experience,
		"cleared_stage": cleared_stage,
		"hero_levels": hero_levels.duplicate(),
		"formation": formation.duplicate(),
		"last_seen_unix": last_seen_unix,
		"offline_bank": offline_bank,
	}


## Restores saved progress (also from a version 1 save). Missing or broken values fall back to safe ones.
static func from_dict(saved: Dictionary, data) -> RefCounted:
	var progress = new_game(data)
	var version := _to_int(saved.get("version"), -1)
	if version != VERSION and version != 1:
		push_warning("Unknown save version %s, starting a new game" % str(saved.get("version")))
		return progress
	progress.silver = maxi(0, _to_int(saved.get("silver"), progress.silver))
	progress.experience = maxi(0, _to_int(saved.get("experience"), 0))
	progress.cleared_stage = clampi(_to_int(saved.get("cleared_stage"), 0), 0, data.stage_count())
	progress.last_seen_unix = maxi(0, _to_int(saved.get("last_seen_unix"), 0))
	progress.offline_bank = maxi(0, _to_int(saved.get("offline_bank"), 0))

	# Every hero earned by the won stages is unlocked, so a version 1 save gets the heroes it has earned;
	# a hero without a saved level joins like a new hero (at the join level counted over the heroes with a saved
	# level, once the formation is restored). Heroes saved with a level beyond that (opened by the debug panel,
	# or kept after jumping back to an earlier stage) stay unlocked.
	var levels = saved.get("hero_levels")
	var earned: Array[String] = data.unlocked_hero_ids(progress.cleared_stage)
	progress.hero_levels.clear()
	var missing: Array[String] = []
	for hero in data.heroes["heroes"]:
		var hero_id: String = hero["id"]
		var level := _to_int(levels.get(hero_id), 0) if levels is Dictionary else 0
		if level <= 0 and not hero_id in earned:
			continue
		if level <= 0:
			missing.append(hero_id)
		progress.hero_levels[hero_id] = clampi(level, 1, data.max_level())

	progress._reset_formation(data)
	var saved_formation = saved.get("formation")
	if saved_formation is Array and saved_formation.size() == data.slot_count():
		for slot in saved_formation.size():
			var hero_id = saved_formation[slot]
			if hero_id is String and progress.hero_levels.has(hero_id) and not progress.is_in_formation(hero_id):
				progress.formation[slot] = hero_id
	if progress.squad_ids().is_empty():
		for hero_id in progress.hero_levels:
			progress.formation_add(data, hero_id)
	var join_level: int = progress._join_level(data, missing)
	for hero_id in missing:
		progress.hero_levels[hero_id] = join_level
	return progress


static func _to_int(value, fallback: int) -> int:
	return int(value) if (value is int or value is float) else fallback
