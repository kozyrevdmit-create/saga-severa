## A stage: several waves fought one after another by the same squad. No UI here.
## Heroes keep their HP, energy, timers and effects between waves; only the enemies change.
## Deterministic for a given seed: each wave's battle gets a seed derived from it.
extends RefCounted

const Battle := preload("res://scripts/battle/battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")

var stage_id := 0
var wave_index := 0  ## current wave, 0-based
var wave_count := 0
var battle  ## Battle of the current wave
var finished := false
var victory := false
var auto_ultimates := false:
	set(value):
		auto_ultimates = value
		if battle != null:
			battle.auto_ultimates = value

var _heroes: Array = []
var _waves: Array = []  ## Array of enemy unit arrays, one per wave
var _wave_seeds: Array[int] = []
var _balance: Dictionary
var _events: Array[Dictionary] = []
var _time_accumulator := 0.0
var _time_before_wave := 0.0


func _init(stage: int, hero_units: Array, waves: Array, balance: Dictionary, rng_seed: int) -> void:
	stage_id = stage
	_heroes = hero_units
	_waves = waves
	wave_count = waves.size()
	_balance = balance
	var seeds := RandomNumberGenerator.new()
	seeds.seed = rng_seed
	for i in wave_count:
		_wave_seeds.append(seeds.randi())
	_start_wave(0)


## Builds a stage from game data: heroes at their levels, enemies scaled by the stage's power.
static func from_data(data, stage: int, hero_levels: Dictionary, rng_seed: int) -> RefCounted:
	var hero_units: Array = []
	for hero_id in hero_levels:
		var hero: Dictionary = data.get_hero(hero_id)
		var multiplier: float = data.hero_stat_multiplier(int(hero_levels[hero_id]))
		hero_units.append(BattleUnit.from_hero(hero, data.get_hero_class(hero), multiplier))
	var power: float = data.enemy_power_multiplier(stage)
	var waves: Array = []
	for wave in data.get_stage(stage)["waves"]:
		var enemy_units: Array = []
		for enemy_id in wave:
			enemy_units.append(BattleUnit.from_enemy(data.get_enemy(enemy_id), power))
		waves.append(enemy_units)
	return new(stage, hero_units, waves, data.balance, rng_seed)


## Total battle time over all waves so far.
var time: float:
	get:
		return _time_before_wave + battle.time


## Units of the current wave's battle (heroes first); unit.id is the index here.
var units: Array:
	get:
		return battle.units


func heroes() -> Array:
	return battle.heroes()


func enemies() -> Array:
	return battle.enemies()


func advance(delta: float) -> void:
	_time_accumulator += delta
	while _time_accumulator >= Battle.TICK and not finished:
		_time_accumulator -= Battle.TICK
		step()


func run_to_end(max_seconds: float) -> void:
	while not finished and time < max_seconds:
		step()


func step() -> void:
	if finished:
		return
	battle.step()
	_collect_battle_events()


func can_use_ultimate(unit_id: int) -> bool:
	return not finished and battle.can_use_ultimate(unit_id)


func use_ultimate(unit_id: int) -> bool:
	if finished:
		return false
	var used: bool = battle.use_ultimate(unit_id)
	_collect_battle_events()
	return used


## Battle events plus: {"type": "wave", "index"} when the next wave arrives,
## {"type": "end", "victory"} once for the whole stage.
func take_events() -> Array[Dictionary]:
	var events := _events
	_events = []
	return events


func _start_wave(index: int) -> void:
	if battle != null:
		_time_before_wave += battle.time
	wave_index = index
	battle = Battle.new(_heroes, _waves[index], _balance, _wave_seeds[index])
	battle.auto_ultimates = auto_ultimates
	if index > 0:
		_events.append({"type": "wave", "index": index})


func _collect_battle_events() -> void:
	for event in battle.take_events():
		if event["type"] != "end":
			_events.append(event)
	if not battle.finished:
		return
	if battle.victory and wave_index + 1 < wave_count:
		_start_wave(wave_index + 1)
	else:
		finished = true
		victory = battle.victory
		_events.append({"type": "end", "victory": victory})
