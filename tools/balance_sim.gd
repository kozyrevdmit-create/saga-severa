## Balance simulation without a screen:
##   godot --headless --path . --script res://tools/balance_sim.gd
##   godot --headless --path . --script res://tools/balance_sim.gd -- --campaigns=40 --runs=200
##   godot --headless --path . --script res://tools/balance_sim.gd -- --level=12
##   godot --headless --path . --script res://tools/balance_sim.gd -- --until=6   (campaigns stop after stage 6, table 1 only)
## 1. Campaign: a player goes through the chapter from a new game. Before every fight they spend all their
##    silver; when they lose a stage they replay the previous one (for the replay reward) and try again.
##    Two players: "разумный" buys the level-up with the best gain in squad power per silver,
##    "неидеальный" spreads silver evenly over all heroes (lowest level first, bench included).
##    Prints replays needed per stage, where players get stuck, and how many level-ups a first win buys.
## 2. Per stage: win rate at level 1 and at the levels the sensible player had when they first won it
##    (with and without ultimates). With --level=N all heroes are at level N instead.
## 3. Average time for each hero's ultimate to charge (auto mode, sensible player's fights).
extends SceneTree

const GameData := preload("res://scripts/data/game_data.gd")
const StageBattle := preload("res://scripts/battle/stage_battle.gd")
const Progress := preload("res://scripts/save/progress.gd")

## Hang guard only, not a game rule: battles always end (enemies never heal, heroes always deal damage).
## A battle still running after this long means a bug, and the simulation stops with an error.
const HANG_GUARD_SECONDS := 3600.0
## A player who needs more replays than this for one stage counts as stuck there.
const STUCK_AFTER_REPLAYS := 40
const POLICIES := {"sensible": "разумный", "uneven": "неидеальный"}

var data
var _hung := false
var _seed := 1
var _charges := {}  ## hero id -> [sum of charge times, count]
var _last_stage := 0  ## campaigns stop after this stage


func _initialize() -> void:
	var runs := 100
	var campaigns := 20
	var forced_level := 0
	var until := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = int(arg.get_slice("=", 1))
		elif arg.begins_with("--campaigns="):
			campaigns = int(arg.get_slice("=", 1))
		elif arg.begins_with("--level="):
			forced_level = int(arg.get_slice("=", 1))
		elif arg.begins_with("--until="):
			until = int(arg.get_slice("=", 1))
	data = GameData.load_all()
	_last_stage = until if until > 0 else data.stage_count()

	# 1. Campaigns.
	var results := {}
	for policy in POLICIES:
		results[policy] = []
		for i in campaigns:
			results[policy].append(_campaign(policy))
			if _hung:
				quit(1)
				return
	print("1. Прохождение главы с нуля (%d прохождений на каждого игрока, ульты — «Авто»)" % campaigns)
	print("Повторы = сколько раз пришлось перепройти предыдущий этап, чтобы взять этот.")
	print("")
	print("Этап | разумный: повторы ср./макс. | уровни | улучшений за 1-ю победу, ср. (мин–макс) | неидеальный: повторы ср./макс. | застряли")
	print("-----+-----------------------------+--------+-------------------------+---------------------------------+---------")
	for stage in range(1, _last_stage + 1):
		var sensible := _stage_summary(results["sensible"], stage)
		var uneven := _stage_summary(results["uneven"], stage)
		print("%4d | %21s | %6s | %23s | %31s | %7s" % [
			stage, _replays_text(sensible), sensible["levels"], sensible["upgrades"],
			_replays_text(uneven), "%d%%" % uneven["stuck_share"]])
	for policy in POLICIES:
		var totals := _totals(results[policy])
		print("Всего (%s): боёв %s, время боёв %s мин, дошли до конца %d%%" % [
			POLICIES[policy], totals["fights"], totals["minutes"], totals["finished_share"]])
	if until > 0:
		quit()
		return

	# 2. Win rates per stage.
	print("")
	print("2. Победы по этапам (%d боёв на ячейку, ульты — «Авто»)" % runs)
	print("Этап | ур.1: побед | уровни разумного игрока | побед | без ульт: побед")
	print("-----+-------------+-------------------------+-------+----------------")
	for stage in range(1, data.stage_count() + 1):
		var squad_base := _squad_for(stage, {}, 1)
		var won_levels := _median_levels(results["sensible"], stage)
		if forced_level > 0:
			won_levels = {}
		var squad_leveled := _squad_for(stage, won_levels, forced_level if forced_level > 0 else 1)
		var base := _win_rate(stage, squad_base, true, runs)
		var leveled := _win_rate(stage, squad_leveled, true, runs)
		var no_ults := _win_rate(stage, squad_leveled, false, runs)
		print("%4d | %10d%% | %23s | %4d%% | %14d%%" % [stage, base, _levels_text(squad_leveled), leveled, no_ults])
		if _hung:
			quit(1)
			return

	# 3. Ultimate charge times. Heroes that never fought in the campaigns (e.g. waiting outside a full squad)
	# are measured by swapping them in for the squad hero of the same class.
	for hero in data.heroes["heroes"]:
		if _charges.has(hero["id"]):
			continue
		for stage in range(1, data.stage_count() + 1):
			var squad := _squad_for(stage + 1, _median_levels(results["sensible"], stage), 1)
			var level: int = squad.map(func(m): return m["level"]).max()
			for member in squad:
				if data.get_hero(member["id"])["class"] == hero["class"]:
					member["id"] = hero["id"]
					member["level"] = level
					break
			for run in maxi(1, runs / 10):
				_fight(stage, squad, true)
	print("")
	print("3. Зарядка ульт (среднее время от нуля до готовности в боях разумного игрока):")
	for hero in data.heroes["heroes"]:
		var entry: Array = _charges.get(hero["id"], [0.0, 0])
		if entry[1] > 0:
			print("  %-9s стоимость %3d: %5.1f с" % [hero["name"], int(hero["ultimate"]["energy_cost"]), entry[0] / entry[1]])
	quit()


# --- campaign ---------------------------------------------------------------

func _campaign(policy: String) -> Dictionary:
	var progress = Progress.new_game(data)
	var stages := []
	var fights := 0
	var battle_time := 0.0
	for stage in range(1, _last_stage + 1):
		var replays := 0
		var record := {"stage": stage, "stuck": false}
		while true:
			_spend(progress, policy)
			var fight := _fight(stage, progress.squad(data), policy == "sensible")
			fights += 1
			battle_time += fight["time"]
			if fight["victory"]:
				record["levels"] = progress.hero_levels.duplicate()
				var middle_level := _middle_squad_level(progress)
				# Count with the silver actually paid (jarl bonus included), at the levels before the reward.
				var paid: Dictionary = progress.apply_victory(data, stage)
				record["upgrades"] = _upgrades_bought_by(middle_level, int(paid["silver"]))
				break
			if replays >= STUCK_AFTER_REPLAYS:
				record["stuck"] = true
				break
			replays += 1
			if stage > 1:
				_spend(progress, policy)
				var replay := _fight(stage - 1, progress.squad(data), policy == "sensible")
				fights += 1
				battle_time += replay["time"]
				if replay["victory"]:
					progress.apply_victory(data, stage - 1)
		record["replays"] = replays
		stages.append(record)
		if record["stuck"]:
			break
	return {"stages": stages, "fights": fights, "battle_time": battle_time}


## Spends silver before a fight.
func _spend(progress, policy: String) -> void:
	while true:
		var hero_id := _best_upgrade(progress) if policy == "sensible" else _lowest_level_hero(progress)
		if hero_id == "" or not progress.level_up(data, hero_id):
			return


## The affordable squad level-up with the largest gain in squad power (total HP × total damage per second) per silver.
func _best_upgrade(progress) -> String:
	var best := ""
	var best_ratio := 0.0
	var base_power := _squad_power(progress, "")
	for hero_id in progress.squad_ids():
		if not progress.can_level_up(data, hero_id):
			continue
		var gain := _squad_power(progress, hero_id) - base_power
		var ratio: float = gain / progress.level_up_cost(data, hero_id)
		if best == "" or ratio > best_ratio:
			best = hero_id
			best_ratio = ratio
	return best


func _squad_power(progress, upgraded_hero: String) -> float:
	var synergy: Dictionary = data.synergy_bonuses(progress.squad_ids())
	var total_hp := 0.0
	var total_dps := 0.0
	for hero_id in progress.squad_ids():
		var hero: Dictionary = data.get_hero(hero_id)
		var level: int = progress.level_of(hero_id) + (1 if hero_id == upgraded_hero else 0)
		var multiplier: float = data.hero_stat_multiplier(level)
		total_hp += float(hero["hp"]) * multiplier * (1.0 + synergy["hp"])
		total_dps += float(hero["attack"]) * multiplier * (1.0 + synergy["attack"]) / float(hero["attack_interval"])
	return total_hp * total_dps


func _lowest_level_hero(progress) -> String:
	var lowest := ""
	for hero_id in progress.hero_levels:
		if lowest == "" or progress.level_of(hero_id) < progress.level_of(lowest):
			lowest = hero_id
	return lowest


func _middle_squad_level(progress) -> int:
	var levels: Array = progress.squad_ids().map(func(hero_id): return progress.level_of(hero_id))
	levels.sort()
	return levels[levels.size() / 2]


## How many level-ups in a row, starting at `level`, this much silver buys.
func _upgrades_bought_by(level: int, silver: int) -> int:
	var count := 0
	while level < data.max_level() and silver >= data.level_up_cost(level):
		silver -= data.level_up_cost(level)
		level += 1
		count += 1
	return count


func _fight(stage: int, squad: Array, record_charges: bool) -> Dictionary:
	_seed += 1
	var battle = StageBattle.from_data(data, stage, squad, _seed * 7919)
	battle.auto_ultimates = true
	var charge_started := {}
	for hero in battle.heroes():
		charge_started[hero.def_id] = 0.0
	while not battle.finished:
		if battle.time > HANG_GUARD_SECONDS:
			push_error("Stage %d did not end after %d s of battle time: a bug in the battle rules" % [stage, HANG_GUARD_SECONDS])
			_hung = true
			break
		battle.step()
		for event in battle.take_events():
			if record_charges and event["type"] == "ultimate":
				var hero_id: String = battle.units[event["unit"]].def_id
				var entry: Array = _charges.get(hero_id, [0.0, 0])
				entry[0] += battle.time - charge_started[hero_id]
				entry[1] += 1
				_charges[hero_id] = entry
				charge_started[hero_id] = battle.time
	return {"victory": battle.victory, "time": battle.time}


# --- reports ----------------------------------------------------------------

func _stage_summary(campaigns: Array, stage: int) -> Dictionary:
	var replays := []
	var stuck := 0
	var reached := 0
	var upgrades := []
	for campaign in campaigns:
		for record in campaign["stages"]:
			if record["stage"] == stage:
				reached += 1
				if record["stuck"]:
					stuck += 1
				else:
					replays.append(record["replays"])
					upgrades.append(record["upgrades"])
	var levels := _median_levels(campaigns, stage)
	return {
		"replays": replays, "stuck_share": roundi(100.0 * stuck / maxi(1, campaigns.size())),
		"reached": reached, "levels": _levels_text_of(levels),
		"upgrades": "%.1f (%d–%d)" % [_average(upgrades), upgrades.min(), upgrades.max()] if not upgrades.is_empty() else "—",
	}


func _average(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxi(1, values.size())


func _replays_text(summary: Dictionary) -> String:
	var replays: Array = summary["replays"]
	if replays.is_empty():
		return "—"
	var total := 0
	for value in replays:
		total += value
	return "%.1f / %d" % [float(total) / replays.size(), replays.max()]


func _totals(campaigns: Array) -> Dictionary:
	var fights := 0
	var seconds := 0.0
	var finished := 0
	for campaign in campaigns:
		fights += campaign["fights"]
		seconds += campaign["battle_time"]
		var last: Dictionary = campaign["stages"].back()
		if last["stage"] == _last_stage and not last["stuck"]:
			finished += 1
	return {
		"fights": "%.0f" % (float(fights) / campaigns.size()),
		"minutes": "%.0f" % (seconds / campaigns.size() / 60.0),
		"finished_share": roundi(100.0 * finished / campaigns.size()),
	}


## Hero levels the sensible player most often had when first winning the stage (median per hero).
func _median_levels(campaigns: Array, stage: int) -> Dictionary:
	var per_hero := {}
	for campaign in campaigns:
		for record in campaign["stages"]:
			if record["stage"] == stage and not record["stuck"]:
				for hero_id in record["levels"]:
					per_hero.get_or_add(hero_id, []).append(record["levels"][hero_id])
	var result := {}
	for hero_id in per_hero:
		var values: Array = per_hero[hero_id]
		values.sort()
		result[hero_id] = values[values.size() / 2]
	return result


## The default squad of the heroes unlocked before `stage`, at the given levels (or default_level).
func _squad_for(stage: int, levels: Dictionary, default_level: int) -> Array:
	var progress = Progress.new_game(data)
	for won in range(1, stage):
		progress.apply_victory(data, won)
	for hero_id in progress.hero_levels:
		progress.hero_levels[hero_id] = int(levels.get(hero_id, default_level))
	return progress.squad(data)


func _win_rate(stage: int, squad: Array, auto: bool, runs: int) -> int:
	var wins := 0
	for run in runs:
		var battle = StageBattle.from_data(data, stage, squad, run * 7919 + stage)
		battle.auto_ultimates = auto
		while not battle.finished:
			if battle.time > HANG_GUARD_SECONDS:
				push_error("Stage %d did not end after %d s of battle time: a bug in the battle rules" % [stage, HANG_GUARD_SECONDS])
				_hung = true
				return 0
			battle.step()
		if battle.victory:
			wins += 1
	return roundi(100.0 * wins / runs)


func _levels_text(squad: Array) -> String:
	var levels := {}
	for member in squad:
		levels[member["id"]] = member["level"]
	return _levels_text_of(levels)


func _levels_text_of(levels: Dictionary) -> String:
	if levels.is_empty():
		return "—"
	var values := levels.values()
	var low: int = values.min()
	var high: int = values.max()
	return str(low) if low == high else "%d–%d" % [low, high]
