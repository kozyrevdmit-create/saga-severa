## Balance simulation without a screen:
##   godot --headless --path . --script res://tools/balance_sim.gd
##   godot --headless --path . --script res://tools/balance_sim.gd -- --campaigns=40 --runs=200
##   godot --headless --path . --script res://tools/balance_sim.gd -- --level=12
##   godot --headless --path . --script res://tools/balance_sim.gd -- --until=6   (campaigns stop after stage 6, table 1 only)
##   godot --headless --path . --script res://tools/balance_sim.gd -- --sensitivity   (table 5 only, variants run in parallel)
##   godot --headless --path . --script res://tools/balance_sim.gd -- --heroes=0.9 --rewards=1.1   (changed numbers)
##   godot --headless --path . --script res://tools/balance_sim.gd -- --join=weakest   (another new_hero.join_level rule)
## 1. Campaign: a player goes through the chapter from a new game. Before every fight they spend all their
##    silver; when they lose a stage they replay the previous one (for the replay reward) and try again.
##    Two players: "разумный" buys, one level-up at a time, the one that raises the chance to win the stage
##    they are trying to beat the most per silver (measured by test fights, see _best_upgrade);
##    "неидеальный" spreads silver evenly over all heroes (lowest level first, bench included).
##    With --old-bot a third player is added: the sensible player of M4 (best gain in total HP × damage per silver).
##    Prints replays needed per stage, where players get stuck, how many level-ups a first win buys,
##    each player's hero levels at the first win and who falls first in the won fights.
## 2. Per stage: win rate at level 1 and at the levels the sensible player had when they first won it
##    (with and without ultimates). With --level=N all heroes are at level N instead.
## 3. Average time for each hero's ultimate to charge (auto mode, sensible player's fights).
## 4. Offline income for a full absence on every stage, in first wins of the current stage.
## 5. (--sensitivity) The campaign again with all heroes' HP and attack and all stage silver rewards at −10% and +10%.
extends SceneTree

const GameData := preload("res://scripts/data/game_data.gd")
const StageBattle := preload("res://scripts/battle/stage_battle.gd")
const Progress := preload("res://scripts/save/progress.gd")

const POLICY_NAMES := {"sensible": "разумный", "uneven": "неидеальный", "power": "старый разумный (M4)"}

var data
var _variant_failed := false  ## a sensitivity variant failed
## A battle can stall: a lone völva against the boss heals herself about as fast as he hits her and rarely attacks
## (found in M5.1, about 1 in 2000–4000 test fights). A battle still running after
## balance.json → balance_check.stall_after_seconds of battle time counts as a defeat and is reported as stalled.
var _stall_seconds := 0.0
var _stalled := {"campaign": 0, "check": 0}  ## stalled battles: the players' fights / test fights and tables 2–3
var _seed := 1
var _charges := {}  ## hero id -> [sum of charge times, count]
## Who falls in the players' won fights: policy -> {won, nobody, first: {hero id: n}, tank: {survived, last, earlier}}.
## "last": every shieldbearer that fell, fell after every other hero that fell.
var _deaths := {}
var _last_stage := 0  ## campaigns stop after this stage
var _policies: Array = ["sensible", "uneven"]
var _score_fights := 12  ## test fights per squad when the sensible player picks a level-up
var _score_cache := {}  ## "stage|hero:level,..." -> score; test fights use fixed seeds, so a score never changes


func _initialize() -> void:
	var runs := 100
	var campaigns := 20
	var forced_level := 0
	var until := 0
	var hero_scale := 1.0
	var reward_scale := 1.0
	var sensitivity := false
	var summary_path := ""
	var join_rule := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = int(arg.get_slice("=", 1))
		elif arg.begins_with("--campaigns="):
			campaigns = int(arg.get_slice("=", 1))
		elif arg.begins_with("--level="):
			forced_level = int(arg.get_slice("=", 1))
		elif arg.begins_with("--until="):
			until = int(arg.get_slice("=", 1))
		elif arg.begins_with("--score-fights="):
			_score_fights = maxi(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--heroes="):
			hero_scale = float(arg.get_slice("=", 1))
		elif arg.begins_with("--rewards="):
			reward_scale = float(arg.get_slice("=", 1))
		elif arg == "--sensitivity":
			sensitivity = true
		elif arg.begins_with("--summary="):
			summary_path = arg.get_slice("=", 1)
		elif arg == "--old-bot":
			_policies.append("power")
		elif arg.begins_with("--join="):
			join_rule = arg.get_slice("=", 1)
	_load_data(hero_scale, reward_scale)
	if join_rule != "":
		data.balance["new_hero"]["join_level"] = join_rule
	_last_stage = until if until > 0 else data.stage_count()
	_stall_seconds = float(data.balance["balance_check"]["stall_after_seconds"])

	if sensitivity:
		_print_sensitivity(campaigns)
		quit(1 if _variant_failed else 0)
		return
	if summary_path != "":
		_write_summary(campaigns, summary_path)
		quit()
		return

	# 1. Campaigns.
	var results := _run_campaigns(campaigns)
	if hero_scale != 1.0 or reward_scale != 1.0:
		print("Изменённые цифры: HP и атака героев ×%.2f, серебро за этапы ×%.2f" % [hero_scale, reward_scale])
	print("Новый герой приходит по правилу new_hero.join_level = %s" % data.balance["new_hero"]["join_level"])
	print("1. Прохождение главы с нуля (%d прохождений на каждого игрока, ульты — «Авто»)" % campaigns)
	print("Повторы = сколько раз пришлось перепройти предыдущий этап, чтобы взять этот.")
	print("")
	print("Улучшения = сколько улучшений одного героя (среднего по уровню в отряде) покупает первая победа.")
	var header := "Этап"
	for policy in _policies:
		header += " | %s: повторы ср./макс., застряли, улучшения" % POLICY_NAMES[policy]
	print(header)
	for stage in range(1, _last_stage + 1):
		var line := "%4d" % stage
		for policy in _policies:
			var summary := _stage_summary(results[policy], stage)
			line += " | %10s, %3d%%, %11s" % [_replays_text(summary), summary["stuck_share"], summary["upgrades"]]
		print(line)
	for policy in _policies:
		var totals := _totals(results[policy])
		print("Всего (%s): боёв %s, время боёв %s мин, дошли до конца %d%%" % [
			POLICY_NAMES[policy], totals["fights"], totals["minutes"], totals["finished_share"]])

	print("")
	print("Уровни героев при первой победе (медиана по прохождениям; «—» — героя ещё нет):")
	var hero_ids: Array = data.heroes["heroes"].map(func(hero): return hero["id"])
	var names_line := "Этап"
	for policy in _policies:
		names_line += " | %-23s" % POLICY_NAMES[policy]
	print(names_line)
	print("     | " + " | ".join(_policies.map(func(_p): return " ".join(hero_ids.map(func(id): return "%3s" % data.get_hero(id)["name"].substr(0, 3))))))
	for stage in range(1, _last_stage + 1):
		var line := "%4d" % stage
		for policy in _policies:
			var levels := _median_levels(results[policy], stage)
			line += " | " + " ".join(hero_ids.map(func(id): return "%3s" % (str(levels[id]) if levels.has(id) else "—")))
		print(line)
	_print_deaths()
	if until > 0:
		_print_stalled()
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
				_fight(stage, squad, true, "check")
	print("")
	print("3. Зарядка ульт (среднее время от нуля до готовности в боях разумного игрока):")
	for hero in data.heroes["heroes"]:
		var entry: Array = _charges.get(hero["id"], [0.0, 0])
		if entry[1] > 0:
			print("  %-9s стоимость %3d: %5.1f с" % [hero["name"], int(hero["ultimate"]["energy_cost"]), entry[0] / entry[1]])

	# 4. Offline income.
	print("")
	var max_hours := float(data.balance["offline_income"]["max_hours"])
	print("4. Оффлайн-доход за %d ч отсутствия (ярл 1-го уровня; с ярлом доход и награды растут одинаково)" % int(max_hours))
	print("Пройдено этапов | текущий этап | доход | первых побед текущего этапа")
	var offline_progress = Progress.new_game(data)
	for stage in range(1, data.stage_count() + 1):
		offline_progress.apply_victory(data, stage)
		offline_progress.experience = 0
		var cap: int = offline_progress.offline_income_cap(data)
		var current: int = offline_progress.next_stage_id(data)
		print("%15d | %12d | %5d | %.1f" % [stage, current, cap, float(cap) / float(data.get_stage(current)["reward"]["silver"])])
	_print_stalled()
	quit()


func _load_data(hero_scale: float, reward_scale: float) -> void:
	data = GameData.load_all()
	for hero in data.heroes["heroes"]:
		hero["hp"] = float(hero["hp"]) * hero_scale
		hero["attack"] = float(hero["attack"]) * hero_scale
	for stage in data.stages["stages"]:
		stage["reward"]["silver"] = roundi(float(stage["reward"]["silver"]) * reward_scale)
	_score_cache.clear()


func _run_campaigns(campaigns: int) -> Dictionary:
	var results := {}
	for policy in _policies:
		results[policy] = []
		for i in campaigns:
			results[policy].append(_campaign(policy))
	return results


# --- sensitivity --------------------------------------------------------------

## Each variant runs as a separate copy of this tool (in parallel, --summary=...), then the results are joined.
func _print_sensitivity(campaigns: int) -> void:
	var jobs := []
	var check: Dictionary = data.balance["balance_check"]
	var variants: Array = check["variants"]
	var too_many := float(check["max_average_replays_per_stage"])
	for i in variants.size():
		var path := ProjectSettings.globalize_path("user://balance_sim_variant_%d.json" % i)
		DirAccess.remove_absolute(path)
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/balance_sim.gd", "--",
			"--campaigns=%d" % campaigns, "--until=%d" % _last_stage, "--score-fights=%d" % _score_fights,
			"--heroes=%s" % variants[i]["heroes"], "--rewards=%s" % variants[i]["rewards"], "--summary=%s" % path]
		if "power" in _policies:
			args.append("--old-bot")
		args.append("--join=%s" % data.balance["new_hero"]["join_level"])
		jobs.append({"pid": OS.create_process(OS.get_executable_path(), args), "path": path})
	var per_variant := []
	for job in jobs:
		while OS.is_process_running(job["pid"]):
			OS.delay_msec(500)
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(job["path"])) if FileAccess.file_exists(job["path"]) else null
		if not parsed is Dictionary:
			push_error("A sensitivity variant failed: no results in %s" % job["path"])
			_variant_failed = true
			return
		per_variant.append(parsed)
		DirAccess.remove_absolute(job["path"])
	print("5. Устойчивость баланса (%d прохождений на игрока и вариант): повторы в среднем по этапам" % campaigns)
	print("Меняются HP и атака всех героев или серебро за все этапы. «!» — %s+ повторов на этапе или кто-то застрял;" % _number(too_many))
	print("«!» у суммы — глава проходится совсем без повторов. Пороги и варианты — data/balance.json → balance_check.")
	for policy in _policies:
		print("")
		print("Игрок: %s" % POLICY_NAMES[policy])
		print("Этап | " + " | ".join(variants.map(func(v): return "%12s" % v["name"])))
		for stage in range(1, _last_stage + 1):
			var cells := []
			for results in per_variant:
				var average: float = results[policy]["replays"][stage - 1]
				var mark := "!" if average >= too_many or results[policy]["stuck"][stage - 1] > 0 else " "
				cells.append("%11.1f%s" % [average, mark])
			print("%4d | " % stage + " | ".join(cells))
		var replays_line := []
		var fights_line := []
		for results in per_variant:
			var total := 0.0
			for value in results[policy]["replays"]:
				total += value
			replays_line.append("%11.1f%s" % [total, "!" if total <= 0.0 else " "])
			fights_line.append("%12s" % ("%s / %s мин" % [results[policy]["fights"], results[policy]["minutes"]]))
		print("Всего повторов | " + " | ".join(replays_line))
		print("Боёв / минут   | " + " | ".join(fights_line))
	print("")
	for i in variants.size():
		print("%s: %s" % [variants[i]["name"], _stalled_text(per_variant[i]["stalled"])])


## A sensitivity variant: campaigns only, the per-stage averages written as JSON for _print_sensitivity.
func _write_summary(campaigns: int, path: String) -> void:
	var results := _run_campaigns(campaigns)
	var summary := {}
	for policy in _policies:
		var replays := []
		var stuck := []
		for stage in range(1, _last_stage + 1):
			var stage_summary := _stage_summary(results[policy], stage)
			replays.append(_average(stage_summary["replays"]))
			stuck.append(stage_summary["stuck_share"])
		var totals := _totals(results[policy])
		summary[policy] = {"replays": replays, "stuck": stuck, "fights": totals["fights"], "minutes": totals["minutes"]}
	summary["stalled"] = _stalled
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(summary))
	file.close()


## Printed last, so the fights of tables 2 and 3 are counted too.
func _print_stalled() -> void:
	var text := _stalled_text(_stalled)
	print("")
	print(text.left(1).to_upper() + text.substr(1))


## «!» when a campaign fight stalled: a real player would be stuck in that battle.
func _stalled_text(stalled: Dictionary) -> String:
	return "затянувшихся боёв (дольше %d мин, засчитаны поражением) — в прохождениях %d%s, в пробных боях бота и таблицах 2–3 %d" % [
		roundi(_stall_seconds / 60.0), int(stalled["campaign"]), " !" if int(stalled["campaign"]) > 0 else "", int(stalled["check"])]


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
			_spend(progress, policy, stage)
			var fight := _fight(stage, progress.squad(data), policy == "sensible", "campaign", policy)
			fights += 1
			battle_time += fight["time"]
			if fight["victory"]:
				record["levels"] = progress.hero_levels.duplicate()
				var middle_level := _middle_squad_level(progress)
				# Count with the silver actually paid (jarl bonus included), at the levels before the reward.
				var paid: Dictionary = progress.apply_victory(data, stage)
				record["upgrades"] = _upgrades_bought_by(middle_level, int(paid["silver"]))
				break
			if replays >= int(data.balance["balance_check"]["stuck_after_replays"]):
				record["stuck"] = true
				break
			replays += 1
			if stage > 1:
				_spend(progress, policy, stage)
				var replay := _fight(stage - 1, progress.squad(data), policy == "sensible", "campaign", policy)
				fights += 1
				battle_time += replay["time"]
				if replay["victory"]:
					progress.apply_victory(data, stage - 1)
		record["replays"] = replays
		stages.append(record)
		if record["stuck"]:
			break
	return {"stages": stages, "fights": fights, "battle_time": battle_time}


## Spends silver before a fight; `goal` is the stage the player is trying to beat.
func _spend(progress, policy: String, goal: int) -> void:
	while true:
		var hero_id := ""
		match policy:
			"sensible":
				hero_id = _best_upgrade(progress, goal)
			"power":
				hero_id = _best_power_upgrade(progress)
			_:
				hero_id = _lowest_level_hero(progress)
		if hero_id == "" or not progress.level_up(data, hero_id):
			return


## The sensible player: the affordable squad level-up that raises the chance to beat `goal` the most per silver.
## The chance is measured by test fights with fixed seeds (the same for every option, so only the level-up
## makes the difference). A fight scores 1 + the squad's HP left on a win and the share of the stage's enemy HP
## taken on a loss: this tells "almost won" from "far off" when a few test fights all end the same way.
func _best_upgrade(progress, goal: int) -> String:
	var squad: Array = progress.squad(data)
	var base := _squad_score(goal, squad)
	var best := ""
	var best_ratio := 0.0
	for member in squad:
		var hero_id: String = member["id"]
		if not progress.can_level_up(data, hero_id):
			continue
		member["level"] += 1
		var ratio: float = (_squad_score(goal, squad) - base) / progress.level_up_cost(data, hero_id)
		member["level"] -= 1
		if best == "" or ratio > best_ratio:
			best = hero_id
			best_ratio = ratio
	return best


func _squad_score(stage: int, squad: Array) -> float:
	var key := "%d|%s" % [stage, ",".join(squad.map(func(m): return "%s:%d:%s" % [m["id"], m["level"], m["row"]]))]
	if _score_cache.has(key):
		return _score_cache[key]
	var total := 0.0
	for i in _score_fights:
		var battle = StageBattle.from_data(data, stage, squad, 104729 * (i + 1) + stage)
		battle.auto_ultimates = true
		_run(battle)
		total += (1.0 + battle.hero_hp_share_left()) if battle.victory else battle.enemy_hp_share_taken()
	var score := total / _score_fights
	_score_cache[key] = score
	return score


## The sensible player of M4: the affordable squad level-up with the largest gain in squad power
## (total HP × total damage per second) per silver. Kept to show why it lost to the uneven player.
func _best_power_upgrade(progress) -> String:
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


## Runs a test fight (or a table 2 fight) to the end; a stalled one stops as a defeat.
func _run(battle) -> void:
	while not battle.finished:
		if battle.time > _stall_seconds:
			_stalled["check"] += 1
			return
		battle.step()


## `stall_key`: where a stalled fight is counted ("campaign" for the players' fights, "check" for measurements).
## `deaths_policy`: a player's fight whose fallen heroes are counted in _deaths ("" = not counted).
func _fight(stage: int, squad: Array, record_charges: bool, stall_key := "campaign", deaths_policy := "") -> Dictionary:
	_seed += 1
	var battle = StageBattle.from_data(data, stage, squad, _seed * 7919)
	battle.auto_ultimates = true
	var charge_started := {}
	for hero in battle.heroes():
		charge_started[hero.def_id] = 0.0
	var fallen: Array[String] = []  ## heroes in the order they fell
	while not battle.finished:
		if battle.time > _stall_seconds:
			push_warning("Stage %d stalled after %d s of battle time, counted as a defeat" % [stage, _stall_seconds])
			_stalled[stall_key] += 1
			break
		battle.step()
		for event in battle.take_events():
			# Heroes come first in every wave's units, so a hero's id is the same in every wave
			# (an enemy's id may point past the next wave's units).
			if event["type"] == "death" and event["unit"] < squad.size():
				fallen.append(battle.units[event["unit"]].def_id)
			if record_charges and event["type"] == "ultimate":
				var hero_id: String = battle.units[event["unit"]].def_id
				var entry: Array = _charges.get(hero_id, [0.0, 0])
				entry[0] += battle.time - charge_started[hero_id]
				entry[1] += 1
				_charges[hero_id] = entry
				charge_started[hero_id] = battle.time
	if deaths_policy != "" and battle.victory:
		_count_deaths(deaths_policy, squad, fallen)
	return {"victory": battle.victory, "time": battle.time}


func _count_deaths(policy: String, squad: Array, fallen: Array[String]) -> void:
	var stats: Dictionary = _deaths.get_or_add(policy, {"won": 0, "nobody": 0, "first": {}, "tank": {"survived": 0, "last": 0, "earlier": 0}})
	stats["won"] += 1
	if fallen.is_empty():
		stats["nobody"] += 1
	else:
		stats["first"][fallen[0]] = stats["first"].get(fallen[0], 0) + 1
	var tanks: Array = squad.map(func(m): return m["id"]).filter(func(id): return data.get_hero(id)["class"] == "shieldbearer")
	if tanks.is_empty():
		return
	var last_other := -1
	var first_tank := fallen.size()
	for i in fallen.size():
		if fallen[i] in tanks:
			first_tank = mini(first_tank, i)
		else:
			last_other = i
	if first_tank == fallen.size():
		stats["tank"]["survived"] += 1
	elif first_tank > last_other:
		stats["tank"]["last"] += 1
	else:
		stats["tank"]["earlier"] += 1


func _print_deaths() -> void:
	print("")
	print("Кто погибает первым в выигранных боях прохождения (доля побед; щитоносец «в порядке» — выжил или пал последним):")
	for policy in _policies:
		if not _deaths.has(policy):
			continue
		var stats: Dictionary = _deaths[policy]
		var won := float(maxi(1, stats["won"]))
		var parts := ["никто — %d%%" % roundi(100.0 * stats["nobody"] / won)]
		var first: Dictionary = stats["first"]
		var ids := first.keys()
		ids.sort_custom(func(a, b): return first[a] > first[b])
		for hero_id in ids:
			parts.append("%s — %d%%" % [data.get_hero(hero_id)["name"], roundi(100.0 * first[hero_id] / won)])
		var tank: Dictionary = stats["tank"]
		print("  %s (%d побед): первым погибает %s" % [POLICY_NAMES[policy], stats["won"], ", ".join(parts)])
		print("    щитоносец: выжил %d%%, пал последним %d%%, пал раньше других %d%% → в порядке %d%%" % [
			roundi(100.0 * tank["survived"] / won), roundi(100.0 * tank["last"] / won), roundi(100.0 * tank["earlier"] / won),
			roundi(100.0 * (tank["survived"] + tank["last"]) / won)])


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
	return "%.1f / %d" % [_average(replays), replays.max()]


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


## Hero levels the player most often had when first winning the stage (median per hero).
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
		_run(battle)
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


func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)
