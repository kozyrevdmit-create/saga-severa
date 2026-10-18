## Auto-battle rules, independent from the screen.
## Deterministic for a given seed: time advances in fixed ticks and all randomness
## goes through the battle's own RandomNumberGenerator.
## The screen (or a test) calls advance()/use_ultimate() and reads take_events().
extends RefCounted

const BattleUnit := preload("res://scripts/battle/battle_unit.gd")

const TICK := 0.05  ## simulation step, seconds
const EPSILON := 0.0001  ## timers summed from TICKs reach whole seconds within this

var units: Array = []  ## all BattleUnits; unit.id == index
var time := 0.0
var auto_ultimates := false  ## "Авто": heroes use ultimates as soon as they are ready
var finished := false
var victory := false
var marked_target_id := -1  ## enemy the player marked (tap): heroes that can reach it hit it first; -1 = none

var _energy: Dictionary  ## balance.json "energy": per_attack, per_heal, per_hit_taken
var _target_weights: Dictionary  ## balance.json "target_weights": by_class, default
var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
var _time_accumulator := 0.0


func _init(hero_units: Array, enemy_units: Array, balance: Dictionary, rng_seed: int) -> void:
	_energy = balance["energy"]
	_target_weights = balance["target_weights"]
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


## The player taps an enemy: it becomes the marked target; tapping the marked enemy again removes the mark.
## Only a living enemy can be marked. Returns true when the mark changed. Adds {"type": "mark", "unit"} (-1 = none).
func toggle_mark(unit_id: int) -> bool:
	if finished or unit_id < 0 or unit_id >= units.size():
		return false
	var unit = units[unit_id]
	if unit.team != BattleUnit.Team.ENEMIES or not unit.is_alive():
		return false
	_set_mark(-1 if marked_target_id == unit_id else unit_id)
	return true


func _set_mark(unit_id: int) -> void:
	marked_target_id = unit_id
	_events.append({"type": "mark", "unit": unit_id})


## Events since the last call: damage, heal, death, mark, ultimate, special, phase, immune, end. Used by the screen for effects.
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
		if unit.is_alive() and unit.is_poisoned():
			_tick_poison(unit)
			if _check_end():
				return
	for unit in units:
		if not unit.is_alive():
			continue
		if unit.is_invulnerable():
			_tick_invulnerable(unit)
			if _check_end():
				return
			continue
		# A stunned unit and a hero caught in a web do not act; their timers wait.
		if unit.is_stunned() or unit.is_webbed():
			continue
		unit.attack_timer += TICK * unit.action_speed()
		if unit.attack_timer >= unit.attack_interval:
			unit.attack_timer -= unit.attack_interval
			_perform_action(unit)
			if _check_end():
				return
		if unit.has_special():
			# A periodic ability on its own timer (the boss's blow at the whole squad).
			unit.special_timer += TICK * unit.action_speed()
			if unit.special_timer >= float(unit.special["interval"]):
				unit.special_timer -= float(unit.special["interval"])
				_perform_special(unit, unit.special)
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
	return not finished and unit.is_alive() and unit.has_ultimate() and unit.energy >= unit.ultimate_cost()


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
		"attack_back_row_weakest":
			_attack(unit, _pick_back_row_weakest_target(unit))
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


## A unit with a first strike (the boar's charge) makes its first attack attack_multiplier times stronger:
## a "special" event with the strike's name, then the damage of kind "special".
func _attack(unit, target) -> void:
	if target == null:
		return
	if unit.has_first_strike():
		unit.first_strike_used = true
		_events.append({"type": "special", "unit": unit.id, "name": unit.first_strike["name"]})
		_deal_damage(unit, target, float(unit.first_strike["attack_multiplier"]), "special")
	else:
		_deal_damage(unit, target, 1.0, "attack")
	_gain_energy(unit, int(_energy["per_attack"]))


## "hit_all": the whole opposing side (Гнев конунга); with "poison" every target that survives is poisoned too
## (Fafnir's «Ядовитое дыхание»: poison.ticks blows of poison.attack_multiplier × attack, one every poison.interval s).
## "hit_one": one target picked like the unit's attack of that kind (special.target: "front_row" — by the target weights,
## «Ледяное копьё»; "back_row_weakest" — as the carrion eagle, «Пике»; "random" — any living opponent, Fafnir's «Монеты»).
## "web": the cave spider's «Паутина» — one target picked like "hit_one" (special.target) cannot act and gains no energy
## for special.duration seconds; no damage. Its event carries the target: the screen writes «Паутина» over the hero.
func _perform_special(unit, special: Dictionary) -> void:
	match special["type"]:
		"hit_all":
			_events.append({"type": "special", "unit": unit.id, "name": special["name"]})
			for target in _alive(_opponents_of(unit)):
				_deal_damage(unit, target, float(special["attack_multiplier"]), "special")
				if special.has("poison") and target.is_alive():
					var poison: Dictionary = special["poison"]
					target.apply_poison(unit.id, unit.attack_power() * float(poison["attack_multiplier"]),
							float(poison["interval"]), int(poison["ticks"]))
		"hit_one":
			var target = _pick_special_target(unit, special["target"])
			if target == null:
				return
			_events.append({"type": "special", "unit": unit.id, "name": special["name"]})
			_deal_damage(unit, target, float(special["attack_multiplier"]), "special")
		"web":
			var target = _pick_special_target(unit, special["target"])
			if target == null:
				return
			_events.append({"type": "special", "unit": unit.id, "name": special["name"], "target": target.id})
			target.apply_status({"kind": "web", "duration": float(special["duration"])})
		_:
			push_error("Unknown special ability: %s" % special["type"])


func _pick_special_target(unit, target_kind: String):
	match target_kind:
		"front_row":
			return _pick_front_row_target(unit)
		"back_row_weakest":
			return _pick_back_row_weakest_target(unit)
		"random":
			var opponents := _alive(_opponents_of(unit))
			return null if opponents.is_empty() else opponents[_rng.randi_range(0, opponents.size() - 1)]
	push_error("Unknown special target: %s" % target_kind)
	return null


## A poisoned unit takes its poison's blow every poison.interval seconds until the blows run out. Reduced like any damage
## (shieldbearers, «Кузнечная броня», «Закалка», «Стена щитов»); poison does not give energy (it is not a hit).
func _tick_poison(unit) -> void:
	var poison: Dictionary = unit.poison
	poison["timer"] += TICK
	if poison["timer"] < float(poison["interval"]) - EPSILON:
		return
	poison["timer"] -= float(poison["interval"])
	poison["ticks_left"] -= 1
	if poison["ticks_left"] <= 0:
		unit.poison = {}
	var amount := maxi(1, roundi(float(poison["amount"]) * damage_taken_multiplier(unit)))
	_take_damage(int(poison["source"]), unit, amount, "poison", false)


## Fafnir burrowed into his gold: the coins hit (invulnerable_special) on their own timer, stuns and slows do not stop
## them; when the time is over he comes out ({"type": "invulnerable_end", "unit"}), and his special ability starts
## on a fresh timer (enter_phase reset it).
func _tick_invulnerable(unit) -> void:
	var coins: Dictionary = unit.invulnerable_special
	unit.invulnerable_timer += TICK
	if unit.invulnerable_timer >= float(coins["interval"]) - EPSILON:
		unit.invulnerable_timer -= float(coins["interval"])
		_perform_special(unit, coins)
	unit.invulnerable_remaining -= TICK
	if unit.invulnerable_remaining <= EPSILON:
		unit.invulnerable_remaining = 0.0
		_events.append({"type": "invulnerable_end", "unit": unit.id})


func _apply_effect(unit, effect: Dictionary) -> void:
	match effect["type"]:
		"buff_allies":
			# "row": only the allies standing in that row when the ultimate is used (Regin's «Закалка»: the front row).
			for ally in _alive(_allies_of(unit)):
				if not effect.has("row") or ally.row == effect["row"]:
					ally.add_buff(effect["stat"], float(effect["multiplier"]), float(effect["duration"]), unit.id,
							effect.get("badge", ""))
		"hits":
			for i in int(effect["count"]):
				var target = _pick_effect_targets(unit, effect["target"])
				if target.is_empty():
					break
				_deal_damage(unit, target[0], float(effect["attack_multiplier"]), "ultimate")
		"damage":
			for target in _pick_effect_targets(unit, effect["target"]):
				_deal_damage(unit, target, float(effect["attack_multiplier"]), "ultimate")
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


## kind: "attack", "ultimate" or "special" (the screen styles the numbers by it).
## A boss burrowed into its gold takes nothing: {"type": "immune", "unit"} instead (the screen writes «Неуязвим»).
func _deal_damage(source, target, multiplier: float, kind: String) -> void:
	if target.is_invulnerable():
		_events.append({"type": "immune", "unit": target.id, "source": source.id})
		return
	var amount := maxi(1, roundi(source.attack_power() * multiplier * damage_taken_multiplier(target)))
	_take_damage(source.id, target, amount, kind, true)


## The share of damage the unit takes: its own buffs and passive (BattleUnit.damage_taken_multiplier) times the passive
## of every living ally that guards the front row (Regin's «Кузнечная броня», heroes.json passive
## "front_row_damage_taken_reduction") while the unit stands in the front row. Multipliers multiply.
func damage_taken_multiplier(unit) -> float:
	var multiplier: float = unit.damage_taken_multiplier()
	if unit.row == "front":
		for ally in _alive(_allies_of(unit)):
			if ally.passive.get("type", "") == "front_row_damage_taken_reduction":
				multiplier *= float(ally.passive["damage_taken_multiplier"])
	return multiplier


## kind: "attack", "ultimate", "special" or "poison". A unit that dies with a death blast (the forge spirit) blows up.
func _take_damage(source_id: int, target, amount: int, kind: String, gives_energy: bool) -> void:
	target.hp = maxi(0, target.hp - amount)
	_events.append({
		"type": "damage", "source": source_id, "target": target.id, "amount": amount,
		"kind": kind, "target_is_hero": target.team == BattleUnit.Team.HEROES,
	})
	if target.is_alive():
		if gives_energy:
			_gain_energy(target, int(_energy["per_hit_taken"]))
		_enter_due_phases(target)
	else:
		target.poison = {}
		_events.append({"type": "death", "unit": target.id})
		if target.id == marked_target_id:
			_set_mark(-1)
		if not target.death_blast.is_empty():
			_blow_up(target)


## The forge spirit's «Взрыв»: dying, it hits the opposing front row (everyone left when the front row has fallen)
## for death_blast.attack_multiplier × its attack, reduced like any damage.
func _blow_up(unit) -> void:
	_events.append({"type": "special", "unit": unit.id, "name": unit.death_blast["name"]})
	for target in _front_row_or_rest(_alive(_opponents_of(unit))):
		_deal_damage(unit, target, float(unit.death_blast["attack_multiplier"]), "special")


## A boss whose HP has dropped to a phase's share enters it: {"type": "phase", "unit", "phase"} (1 = the first change,
## the screen shows the phase's picture and announcement from enemies.json). HP is not restored. A blow that drops HP
## past two shares at once enters both, in order.
func _enter_due_phases(unit) -> void:
	var next: Dictionary = unit.due_phase()
	while not next.is_empty():
		unit.enter_phase(next)
		_events.append({"type": "phase", "unit": unit.id, "phase": unit.phase})
		next = unit.due_phase()


func _heal(source, target, amount: int) -> void:
	var healed := mini(amount, target.max_hp - target.hp)
	if healed <= 0:
		return
	target.hp += healed
	_events.append({"type": "heal", "source": source.id, "target": target.id, "amount": healed})


## A hero caught in a web gains no energy.
func _gain_energy(unit, amount: int) -> void:
	if unit.has_ultimate() and not unit.is_webbed():
		unit.energy = mini(unit.ultimate_cost(), unit.energy + amount)


## Everyone hits the opposing front row first; the back row only when the front row has fallen.
## The target is random, weighted by class (a shieldbearer draws more hits, but not all of them).
func _pick_front_row_target(unit):
	var candidates := _front_row_or_rest(_alive(_opponents_of(unit)))
	if candidates.is_empty():
		return null
	var marked = _marked_among(unit, candidates)
	if marked != null:
		return marked
	var weights := PackedFloat32Array()
	for candidate in candidates:
		weights.append(_target_weight(candidate))
	return candidates[_rng.rand_weighted(weights)]


## The carrion eagle (and Thjazi as an eagle) goes for the back row: the hero there with the lowest share of HP,
## a random one of them on a tie. With nobody left in the back row it hits the front row like everyone else.
func _pick_back_row_weakest_target(unit):
	var back := _alive(_opponents_of(unit)).filter(func(u): return u.row == "back")
	if back.is_empty():
		return _pick_front_row_target(unit)
	var lowest: float = back.map(func(u): return u.hp_fraction()).min()
	var weakest := back.filter(func(u): return u.hp_fraction() == lowest)
	return weakest[_rng.randi_range(0, weakest.size() - 1)]


func _target_weight(target) -> float:
	return float(_target_weights["by_class"].get(target.class_id, _target_weights["default"]))


func _pick_lowest_hp_target(unit):
	var candidates := _alive(_opponents_of(unit))
	var marked = _marked_among(unit, candidates)
	if marked != null:
		return marked
	var best = null
	for target in candidates:
		if best == null or target.hp < best.hp:
			best = target
	return best


## The marked enemy when a hero can reach it (it is among the targets the hero's action may pick), else null.
## Enemies never follow the mark.
func _marked_among(unit, candidates: Array):
	if unit.team != BattleUnit.Team.HEROES or marked_target_id < 0:
		return null
	var marked = units[marked_target_id]
	return marked if marked in candidates else null


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
