## Auto-battle rules, independent from the screen.
## Deterministic for a given seed: time advances in fixed ticks and all randomness
## goes through the battle's own RandomNumberGenerator.
## The screen (or a test) calls advance()/use_ultimate() and reads take_events().
extends RefCounted

const BattleUnit := preload("res://scripts/battle/battle_unit.gd")

const TICK := 0.05  ## simulation step, seconds

var units: Array = []  ## all BattleUnits; unit.id == index
var time := 0.0
var auto_ultimates := false  ## "Авто": heroes use ultimates as soon as they are ready
var finished := false
var victory := false

var _energy: Dictionary  ## balance.json "energy": max, per_attack, per_heal, per_hit_taken
var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
var _time_accumulator := 0.0


func _init(hero_units: Array, enemy_units: Array, balance: Dictionary, rng_seed: int) -> void:
	_energy = balance["energy"]
	_rng.seed = rng_seed
	for unit in hero_units + enemy_units:
		unit.id = units.size()
		units.append(unit)


## Builds a battle of the given heroes against one wave of enemies straight from game data.
static func from_data(data, hero_ids: Array, enemy_ids: Array, rng_seed: int) -> RefCounted:
	var hero_units: Array = []
	for hero_id in hero_ids:
		var hero: Dictionary = data.get_hero(hero_id)
		hero_units.append(BattleUnit.from_hero(hero, data.get_hero_class(hero)))
	var enemy_units: Array = []
	for enemy_id in enemy_ids:
		enemy_units.append(BattleUnit.from_enemy(data.get_enemy(enemy_id)))
	return new(hero_units, enemy_units, data.balance, rng_seed)


func heroes() -> Array:
	return units.filter(func(u): return u.team == BattleUnit.Team.HEROES)


func enemies() -> Array:
	return units.filter(func(u): return u.team == BattleUnit.Team.ENEMIES)


## Advances the battle by real time (already multiplied by game speed).
func advance(delta: float) -> void:
	_time_accumulator += delta
	while _time_accumulator >= TICK and not finished:
		_time_accumulator -= TICK
		step()


## Runs until the end or until max_seconds of battle time pass (for tests and simulation).
func run_to_end(max_seconds: float) -> void:
	while not finished and time < max_seconds:
		step()


## Events since the last call: damage, heal, death, ultimate, end. Used by the screen for effects.
func take_events() -> Array[Dictionary]:
	var events := _events
	_events = []
	return events


func step() -> void:
	if finished:
		return
	time += TICK
	# Effects wear off for everyone before anyone acts, so a buff or stun lasts
	# the same time no matter where its target stands in the turn order.
	for unit in units:
		if unit.is_alive():
			unit.tick_effects(TICK)
	for unit in units:
		if not unit.is_alive() or unit.is_stunned():
			continue
		unit.attack_timer += TICK * unit.action_speed()
		if unit.attack_timer >= unit.attack_interval:
			unit.attack_timer -= unit.attack_interval
			_perform_action(unit)
			if _check_end():
				return
	if auto_ultimates:
		for unit in units:
			if can_use_ultimate(unit.id):
				use_ultimate(unit.id)
				if finished:
					return


func can_use_ultimate(unit_id: int) -> bool:
	var unit = units[unit_id]
	return not finished and unit.is_alive() and unit.has_ultimate() and unit.energy >= int(_energy["max"])


func use_ultimate(unit_id: int) -> bool:
	if not can_use_ultimate(unit_id):
		return false
	var unit = units[unit_id]
	unit.energy = 0
	_events.append({"type": "ultimate", "unit": unit.id, "name": unit.ultimate["name"]})
	for effect in unit.ultimate["effects"]:
		_apply_effect(unit, effect)
	_check_end()
	return true


func _perform_action(unit) -> void:
	match unit.action:
		"attack_front_row":
			_attack(unit, _pick_front_row_target(unit))
		"attack_lowest_hp":
			_attack(unit, _pick_lowest_hp_target(unit))
		"heal_or_attack":
			# Heals the ally with the lowest HP share if it is below the threshold, otherwise attacks.
			var ally = _pick_most_wounded_ally(unit)
			if ally != null and ally.hp_fraction() < float(unit.action_params["heal_below_hp_fraction"]):
				_heal(unit, ally, roundi(unit.attack_power() * float(unit.action_params["heal_attack_multiplier"])))
				_gain_energy(unit, int(_energy["per_heal"]))
			else:
				_attack(unit, _pick_front_row_target(unit))
		_:
			push_error("Unknown action: %s" % unit.action)


func _attack(unit, target) -> void:
	if target == null:
		return
	_deal_damage(unit, target, 1.0, false)
	_gain_energy(unit, int(_energy["per_attack"]))


func _apply_effect(unit, effect: Dictionary) -> void:
	match effect["type"]:
		"buff_allies":
			for ally in _alive(_allies_of(unit)):
				ally.add_buff(effect["stat"], float(effect["multiplier"]), float(effect["duration"]), unit.id)
		"hits":
			for i in int(effect["count"]):
				var target = _pick_effect_targets(unit, effect["target"])
				if target.is_empty():
					break
				_deal_damage(unit, target[0], float(effect["attack_multiplier"]), true)
		"damage":
			for target in _pick_effect_targets(unit, effect["target"]):
				_deal_damage(unit, target, float(effect["attack_multiplier"]), true)
				if effect.has("status") and target.is_alive():
					target.apply_status(effect["status"])
		"heal_allies":
			for ally in _alive(_allies_of(unit)):
				_heal(unit, ally, roundi(ally.max_hp * float(effect["max_hp_fraction"])))
		_:
			push_error("Unknown ultimate effect: %s" % effect["type"])


func _pick_effect_targets(unit, target_kind: String) -> Array:
	var opponents := _alive(_opponents_of(unit))
	match target_kind:
		"front_row_single":
			var target = _pick_front_row_target(unit)
			return [] if target == null else [target]
		"front_row_all":
			return _front_row_or_rest(opponents)
		"all_enemies":
			return opponents
	push_error("Unknown effect target: %s" % target_kind)
	return []


func _deal_damage(source, target, multiplier: float, is_ultimate: bool) -> void:
	var amount := maxi(1, roundi(source.attack_power() * multiplier * target.damage_taken_multiplier()))
	target.hp = maxi(0, target.hp - amount)
	_events.append({"type": "damage", "source": source.id, "target": target.id, "amount": amount, "ultimate": is_ultimate})
	if target.is_alive():
		_gain_energy(target, int(_energy["per_hit_taken"]))
	else:
		_events.append({"type": "death", "unit": target.id})


func _heal(source, target, amount: int) -> void:
	var healed := mini(amount, target.max_hp - target.hp)
	if healed <= 0:
		return
	target.hp += healed
	_events.append({"type": "heal", "source": source.id, "target": target.id, "amount": healed})


func _gain_energy(unit, amount: int) -> void:
	if unit.has_ultimate():
		unit.energy = mini(int(_energy["max"]), unit.energy + amount)


## Everyone hits the opposing front row first; the back row only when the front row has fallen.
func _pick_front_row_target(unit):
	var candidates := _front_row_or_rest(_alive(_opponents_of(unit)))
	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _pick_lowest_hp_target(unit):
	var best = null
	for target in _alive(_opponents_of(unit)):
		if best == null or target.hp < best.hp:
			best = target
	return best


func _pick_most_wounded_ally(unit):
	var best = null
	for ally in _alive(_allies_of(unit)):
		if best == null or ally.hp_fraction() < best.hp_fraction():
			best = ally
	return best


func _front_row_or_rest(alive_units: Array) -> Array:
	var front := alive_units.filter(func(u): return u.row == "front")
	return front if not front.is_empty() else alive_units


func _allies_of(unit) -> Array:
	return units.filter(func(u): return u.team == unit.team)


func _opponents_of(unit) -> Array:
	return units.filter(func(u): return u.team != unit.team)


func _alive(list: Array) -> Array:
	return list.filter(func(u): return u.is_alive())


func _check_end() -> bool:
	if finished:
		return true
	var heroes_alive := not _alive(heroes()).is_empty()
	var enemies_alive := not _alive(enemies()).is_empty()
	if heroes_alive and enemies_alive:
		return false
	finished = true
	victory = heroes_alive
	_events.append({"type": "end", "victory": victory})
	return true
