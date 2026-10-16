## One fighter in a battle (hero or enemy): stats and temporary effects. No UI here.
extends RefCounted

enum Team { HEROES, ENEMIES }

var id := -1  ## index in Battle.units
var team: Team
var def_id := ""  ## hero/enemy id from data
var class_id := ""  ## hero class from data; empty for enemies
var display_name := ""
var row := "front"  ## "front" or "back"
var color := Color.WHITE

var max_hp := 1
var hp := 1
var base_attack := 0.0
var attack_interval := 1.0
var attack_timer := 0.0

var action := "attack_front_row"
var action_params: Dictionary = {}  ## extra numbers for the action (e.g. völva heal threshold)
var ultimate: Dictionary = {}  ## empty for enemies
var passive: Dictionary = {}
var special: Dictionary = {}  ## periodic ability (boss), empty for most units
var special_timer := 0.0
var first_strike: Dictionary = {}  ## the first attack hits harder (the boar's charge), empty for most units
var first_strike_used := false
var energy := 0

var buffs: Array[Dictionary] = []  ## {stat, multiplier, remaining, source}
var stun_remaining := 0.0
var slow_amount := 0.0
var slow_remaining := 0.0


## The multipliers come from the hero's level and the squad's clan bonuses (see StageBattle.from_data).
static func from_hero(hero: Dictionary, hero_class: Dictionary, hp_multiplier := 1.0, attack_multiplier := 1.0) -> RefCounted:
	var unit = new()
	unit.team = Team.HEROES
	unit.def_id = hero["id"]
	unit.class_id = hero["class"]
	unit.display_name = hero["name"]
	unit.row = hero_class["row"]
	unit.color = Color.html(hero_class["color"])
	unit.max_hp = roundi(float(hero["hp"]) * hp_multiplier)
	unit.hp = unit.max_hp
	unit.base_attack = float(hero["attack"]) * attack_multiplier
	unit.attack_interval = float(hero["attack_interval"])
	unit.action = hero_class["action"]
	unit.action_params = hero_class
	unit.ultimate = hero.get("ultimate", {})
	unit.passive = hero.get("passive", {})
	return unit


## power_multiplier comes from the stage (see GameData.enemy_power_multiplier).
static func from_enemy(enemy: Dictionary, power_multiplier := 1.0) -> RefCounted:
	var unit = new()
	unit.team = Team.ENEMIES
	unit.def_id = enemy["id"]
	unit.display_name = enemy["name"]
	unit.row = enemy["row"]
	unit.color = Color.html(enemy["color"])
	unit.max_hp = roundi(float(enemy["hp"]) * power_multiplier)
	unit.hp = unit.max_hp
	unit.base_attack = float(enemy["attack"]) * power_multiplier
	unit.attack_interval = float(enemy["attack_interval"])
	unit.action = enemy["action"]
	unit.special = enemy.get("special", {})
	unit.first_strike = enemy.get("first_strike", {})
	return unit


func is_alive() -> bool:
	return hp > 0


func hp_fraction() -> float:
	return float(hp) / float(max_hp)


func has_ultimate() -> bool:
	return not ultimate.is_empty()


## Energy needed to use the ultimate (heroes.json ultimate.energy_cost, per hero).
func ultimate_cost() -> int:
	return int(ultimate["energy_cost"])


## The first attack is still the strong one (enemies.json first_strike).
func has_first_strike() -> bool:
	return not first_strike.is_empty() and not first_strike_used


func has_special() -> bool:
	return not special.is_empty()


func is_stunned() -> bool:
	return stun_remaining > 0.0


func attack_power() -> float:
	var power := base_attack * _buff_multiplier("attack")
	if passive.get("type", "") == "attack_per_missing_hp":
		power *= 1.0 + float(passive["attack_bonus_per_missing_hp"]) * (1.0 - hp_fraction())
	return power


## Buffs (Shield Wall) times the shieldbearer passive (heroes.json passive.damage_taken_multiplier).
func damage_taken_multiplier() -> float:
	var multiplier := _buff_multiplier("damage_taken")
	if passive.get("type", "") == "damage_taken_reduction":
		multiplier *= float(passive["damage_taken_multiplier"])
	return multiplier


## A newer buff of the same stat from the same source refreshes the old one instead of stacking.
func add_buff(stat: String, multiplier: float, duration: float, source_id: int) -> void:
	for buff in buffs:
		if buff["stat"] == stat and buff["source"] == source_id:
			buff["multiplier"] = multiplier
			buff["remaining"] = duration
			return
	buffs.append({"stat": stat, "multiplier": multiplier, "remaining": duration, "source": source_id})


func apply_status(status: Dictionary) -> void:
	match status["kind"]:
		"stun":
			stun_remaining = maxf(stun_remaining, float(status["duration"]))
		"slow":
			slow_amount = float(status["amount"])
			slow_remaining = maxf(slow_remaining, float(status["duration"]))
		_:
			push_error("Unknown status kind: %s" % status["kind"])


## Counts down buffs and statuses by dt seconds.
func tick_effects(dt: float) -> void:
	for i in range(buffs.size() - 1, -1, -1):
		buffs[i]["remaining"] -= dt
		if buffs[i]["remaining"] <= 0.0:
			buffs.remove_at(i)
	stun_remaining = maxf(0.0, stun_remaining - dt)
	slow_remaining = maxf(0.0, slow_remaining - dt)
	if slow_remaining == 0.0:
		slow_amount = 0.0


## How fast the attack timer runs: 1.0 normally, less when slowed.
func action_speed() -> float:
	return 1.0 - slow_amount


func _buff_multiplier(stat: String) -> float:
	var result := 1.0
	for buff in buffs:
		if buff["stat"] == stat:
			result *= float(buff["multiplier"])
	return result
