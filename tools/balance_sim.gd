## Balance simulation without a screen:
##   godot --headless --path . --script res://tools/balance_sim.gd
##   godot --headless --path . --script res://tools/balance_sim.gd -- --runs=200
##   godot --headless --path . --script res://tools/balance_sim.gd -- --level=12
## For every stage: win rate and average battle time
##   - at level 1 (no levelling),
##   - at the level the squad can afford by then from first-win rewards (silver spent evenly),
##   - at that level without ultimates.
## With --level=N all heroes are at level N instead.
## Then: average time for each hero's ultimate to charge (auto mode).
extends SceneTree

const GameData := preload("res://scripts/data/game_data.gd")
const StageBattle := preload("res://scripts/battle/stage_battle.gd")
const Progress := preload("res://scripts/save/progress.gd")

const MAX_BATTLE_SECONDS := 900.0  ## safety cap for the simulation only; longer counts as a loss
## Squads for measuring ultimate charge times: the starting trio, plus 5-hero squads for the others.
const CHARGE_SQUADS := [
	["torvald", "sigrid", "eyvind"],
	["torvald", "sigrid", "eyvind", "skadi", "angrboda"],
	["hrungnir", "sigrid", "eyvind", "skadi", "angrboda"],
]

var data


func _initialize() -> void:
	var runs := 100
	var forced_level := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = int(arg.get_slice("=", 1))
		elif arg.begins_with("--level="):
			forced_level = int(arg.get_slice("=", 1))
	data = GameData.load_all()

	print("Симуляция баланса: %d боёв на каждую строку, ульты — режим «Авто»" % runs)
	print("")
	print("Этап | Ур.1: побед | время | Ур.П | Ур.П: побед | время | Ур.П без ульт: побед")
	print("-----+-------------+-------+------+-------------+-------+--------------------")
	var economy = Progress.new_game(data)
	var expected_levels := {}  ## stage -> squad levels at that stage
	for stage in range(1, data.stage_count() + 1):
		_spend_silver_evenly(economy)
		var levels: Dictionary = economy.hero_levels.duplicate()
		if forced_level > 0:
			for hero_id in levels:
				levels[hero_id] = forced_level
		expected_levels[stage] = levels
		var base := _simulate(stage, _levels_of(levels.keys(), 1), true, runs)
		var leveled := _simulate(stage, levels, true, runs)
		var no_ults := _simulate(stage, levels, false, runs)
		print("%4d | %10d%% | %4.0f с | %4s | %10d%% | %4.0f с | %18d%%" % [
			stage, base["win_rate"], base["avg_time"], _levels_text(levels),
			leveled["win_rate"], leveled["avg_time"], no_ults["win_rate"]])
		economy.apply_victory(data, stage)
	print("")
	print("Ур.П — уровни героев, которые можно купить к этапу за серебро с первых побед (поровну на всех).")

	print("")
	print("Зарядка ульт (среднее время от нуля до готовности, этапы 1–%d, уровни Ур.П):" % data.stage_count())
	var charge_sums := {}
	var charge_counts := {}
	for i in CHARGE_SQUADS.size():
		for stage in range(1, data.stage_count() + 1):
			var level: int = expected_levels[stage].values().min()
			var result := _simulate(stage, _levels_of(CHARGE_SQUADS[i], level), true, maxi(1, runs / 5))
			for hero_id in result["charges"]:
				# The starting trio is measured in its own squad, the other heroes in the 5-hero squads.
				if (i == 0) == (hero_id in CHARGE_SQUADS[0]):
					charge_sums[hero_id] = charge_sums.get(hero_id, 0.0) + result["charges"][hero_id][0]
					charge_counts[hero_id] = charge_counts.get(hero_id, 0) + result["charges"][hero_id][1]
	for hero in data.heroes["heroes"]:
		var hero_id: String = hero["id"]
		if charge_counts.get(hero_id, 0) > 0:
			print("  %-9s стоимость %3d: %5.1f с" % [hero["name"], int(hero["ultimate"]["energy_cost"]),
				charge_sums[hero_id] / charge_counts[hero_id]])
	quit()


## Spends silver on the lowest-level hero while it is affordable (keeps the squad even).
func _spend_silver_evenly(progress) -> void:
	while true:
		var lowest := ""
		for hero_id in progress.hero_levels:
			if lowest == "" or progress.level_of(hero_id) < progress.level_of(lowest):
				lowest = hero_id
		if not progress.level_up(data, lowest):
			return


func _simulate(stage: int, levels: Dictionary, auto: bool, runs: int) -> Dictionary:
	var wins := 0
	var total_time := 0.0
	var charges := {}  ## hero id -> [sum of charge times, count]
	for run in runs:
		var battle = StageBattle.from_data(data, stage, levels, run * 7919 + stage)
		battle.auto_ultimates = auto
		var charge_started := {}  ## hero id -> time its energy was last at zero
		for hero in battle.heroes():
			charge_started[hero.def_id] = 0.0
		while not battle.finished and battle.time < MAX_BATTLE_SECONDS:
			battle.step()
			for event in battle.take_events():
				if event["type"] == "ultimate":
					var hero_id: String = battle.units[event["unit"]].def_id
					var entry: Array = charges.get(hero_id, [0.0, 0])
					entry[0] += battle.time - charge_started[hero_id]
					entry[1] += 1
					charges[hero_id] = entry
					charge_started[hero_id] = battle.time
		if battle.finished and battle.victory:
			wins += 1
		total_time += battle.time
	return {"win_rate": roundi(100.0 * wins / runs), "avg_time": total_time / runs, "charges": charges}


func _levels_of(hero_ids: Array, level: int) -> Dictionary:
	var levels := {}
	for hero_id in hero_ids:
		levels[hero_id] = level
	return levels


func _levels_text(levels: Dictionary) -> String:
	var values := levels.values()
	var low: int = values.min()
	var high: int = values.max()
	return str(low) if low == high else "%d–%d" % [low, high]
