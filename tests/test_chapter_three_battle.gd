## M13, chapter 3 «Свартальфхейм» in battle, checked without a screen: Regin's «Кузнечная броня» and «Закалка», the cave
## spider's web, the forge spirit's blast on death, Fafnir's poisonous breath, his burrowing into the gold at half HP
## (invulnerable, the coins) and his second phase. Expected numbers come from data/*.json.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const Battle := preload("res://scripts/battle/battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")
const HeroCard := preload("res://scripts/ui/hero_card.gd")

const HEROES := BattleUnit.Team.HEROES
const ENEMIES := BattleUnit.Team.ENEMIES

var data = GameData.load_all()


# --- helpers -----------------------------------------------------------------

func make_unit(team: BattleUnit.Team, row: String, hp: int, attack: float, interval: float):
	var unit = BattleUnit.new()
	unit.team = team
	unit.row = row
	unit.max_hp = hp
	unit.hp = hp
	unit.base_attack = attack
	unit.attack_interval = interval
	return unit


## A hero that never attacks and never dies (unless told otherwise).
func make_target(row: String, hp := 10000000):
	return make_unit(HEROES, row, hp, 1, 1000.0)


func hero_from_data(hero_id: String):
	var hero: Dictionary = data.get_hero(hero_id)
	return BattleUnit.from_hero(hero, data.get_hero_class(hero))


func enemy_from_data(enemy_id: String):
	return BattleUnit.from_enemy(data.get_enemy(enemy_id))


func make_battle(hero_units: Array, enemy_units: Array, rng_seed := 1):
	return Battle.new(hero_units, enemy_units, data.balance, rng_seed)


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e["type"] == type)


## The damage one blow of 100 attack deals to `target` in this battle.
func blow_of_100(battle, target) -> int:
	var hitter = make_unit(ENEMIES, "front", 1000, 100, 1000.0)
	hitter.id = battle.units.size()
	battle.units.append(hitter)
	var before: int = target.hp
	battle._deal_damage(hitter, target, 1.0, "attack")
	battle.units.erase(hitter)
	var dealt: int = before - target.hp
	target.hp = before
	return dealt


# --- Regin -------------------------------------------------------------------

## A smith, «Поддержка» on the formation screen and «Поддержка · броня» on «Герои», of Svartalfheim, back row by default;
## his ultimate charges in 7–8 s from his own blows (the M3 rule for everyone but Sigrid and Skadi).
func test_regin_is_a_smith_of_svartalfheim() -> void:
	var regin: Dictionary = data.get_hero("regin")
	var smith: Dictionary = data.get_hero_class(regin)
	assert_eq([regin["name"], smith["name"], smith["role_short"], regin["role_detail"]],
			["Регин", "Кузнец", "Поддержка", "Поддержка · броня"], "name, class and role")
	assert_eq(smith["row"], "back", "stands in the second row by default")
	assert_eq(data.heroes["clans"][regin["clan"]]["name"], "Свартальфхейм", "the clan")
	assert_eq(regin["ultimate"]["name"], "Закалка", "the ultimate")
	assert_true(not str(regin["ultimate"]["description"]).is_empty() and not str(regin["passive"]["description"]).is_empty(),
			"the ultimate and the passive are described for «Герои»")
	var energy_per_second := float(data.balance["energy"]["per_attack"]) / float(regin["attack_interval"])
	var charge := float(regin["ultimate"]["energy_cost"]) / energy_per_second
	assert_true(charge >= 7.0 and charge <= 8.0, "«Закалка» charges in 7–8 s (got %.1f s)" % charge)


## «Кузнечная броня»: while Regin lives, every front-row hero takes 10% less; the back row and the enemies take full damage.
func test_forge_armour_guards_the_front_row_while_regin_lives() -> void:
	var passive: Dictionary = data.get_hero("regin")["passive"]
	assert_near(float(passive["damage_taken_multiplier"]), 0.9, 0.0001, "−10%")
	var regin = hero_from_data("regin")
	var front = make_target("front")
	var back = make_target("back")
	var enemy = make_target("front")
	enemy.team = ENEMIES
	var battle = make_battle([front, back, regin], [enemy])
	assert_eq(blow_of_100(battle, front), 90, "the front row takes 10% less")
	assert_eq(blow_of_100(battle, back), 100, "the back row takes full damage")
	assert_eq(blow_of_100(battle, regin), 100, "Regin in the back row too")
	regin.row = "front"
	assert_eq(blow_of_100(battle, regin), 90, "Regin in the front row is guarded too")
	regin.row = "back"
	regin.hp = 0
	assert_eq(blow_of_100(battle, front), 100, "nothing once Regin has fallen")


## The armour multiplies with the shieldbearer passive and «Стена щитов»: 100 × 0.7 × 0.9 × 0.6.
func test_forge_armour_multiplies_with_the_tank_passive_and_the_shield_wall() -> void:
	var regin = hero_from_data("regin")
	var torvald = hero_from_data("torvald")
	var enemy = make_target("front")
	enemy.team = ENEMIES
	var battle = make_battle([torvald, regin], [enemy])
	var tank := float(data.get_hero("torvald")["passive"]["damage_taken_multiplier"])
	var armour := float(data.get_hero("regin")["passive"]["damage_taken_multiplier"])
	assert_eq(blow_of_100(battle, torvald), roundi(100 * tank * armour), "tank passive × armour")
	torvald.energy = torvald.ultimate_cost()
	battle.use_ultimate(torvald.id)
	var wall := float(data.get_hero("torvald")["ultimate"]["effects"][0]["multiplier"])
	assert_eq(blow_of_100(battle, torvald), roundi(100 * tank * armour * wall), "× the shield wall")
	assert_near(battle.damage_taken_multiplier(torvald), tank * armour * wall, 0.0001, "the multipliers multiply")


## «Закалка»: for 5 s the front row (the heroes standing there when it is used) takes half damage; with the armour and
## the tank passive it multiplies; the back row gets nothing; the hero cards show the anvil while it lasts.
func test_temper_halves_the_front_rows_damage_for_five_seconds() -> void:
	var effect: Dictionary = data.get_hero("regin")["ultimate"]["effects"][0]
	assert_eq([effect["type"], effect["row"], effect["stat"]], ["buff_allies", "front", "damage_taken"], "a front-row buff")
	assert_near(float(effect["multiplier"]), 0.5, 0.0001, "half damage")
	assert_near(float(effect["duration"]), 5.0, 0.0001, "for 5 s")
	var regin = hero_from_data("regin")
	var torvald = hero_from_data("torvald")
	var back = make_target("back")
	var enemy = make_target("front")
	enemy.team = ENEMIES
	var battle = make_battle([torvald, back, regin], [enemy])
	regin.energy = regin.ultimate_cost()
	assert_true(battle.use_ultimate(regin.id), "used")
	var tank := float(data.get_hero("torvald")["passive"]["damage_taken_multiplier"])
	var armour := float(data.get_hero("regin")["passive"]["damage_taken_multiplier"])
	assert_eq(blow_of_100(battle, torvald), roundi(100 * tank * armour * 0.5), "tank × armour × «Закалка»")
	assert_eq(blow_of_100(battle, back), 100, "the back row gets nothing")
	assert_eq(blow_of_100(battle, regin), 100, "nor Regin in the back row")
	assert_eq(HeroCard.badges_of(torvald), ["temper"] as Array[String], "the anvil on the front-row card")
	assert_eq(HeroCard.badges_of(back), [] as Array[String], "none on the back row")
	battle.run_to_end(4.9)
	assert_true(torvald.has_badge("temper"), "still on at 4.9 s")
	battle.run_to_end(5.1)
	assert_true(not torvald.has_badge("temper"), "over after 5 s")
	assert_eq(blow_of_100(battle, torvald), roundi(100 * tank * armour), "back to tank × armour")


# --- cave spider ---------------------------------------------------------------

## «Паутина» every special.interval s: one front-row hero (by the target weights) cannot attack and gains no energy for
## special.duration s, then fights on. The event names the hero (the screen writes «Паутина» over him).
func test_the_spider_webs_a_front_row_hero() -> void:
	var web: Dictionary = data.get_enemy("cave_spider")["special"]
	assert_eq([web["name"], web["type"], web["target"]], ["Паутина", "web", "front_row"], "the web")
	assert_near(float(web["duration"]), 2.0, 0.0001, "2 s")
	var hero = make_unit(HEROES, "front", 10000000, 1, 0.5)
	var back = make_unit(HEROES, "back", 10000000, 1, 0.5)
	hero.ultimate = {"energy_cost": 1000, "name": "test", "effects": []}
	var spider = enemy_from_data("cave_spider")
	spider.base_attack = 0.0001
	var battle = make_battle([hero, back], [spider])
	var interval := float(web["interval"])
	battle.run_to_end(interval - 0.1)
	assert_true(not hero.is_webbed(), "not before the interval")
	var energy_before: int = hero.energy
	battle.take_events()
	battle.run_to_end(interval + 0.01)
	var webs := events_of(battle.take_events(), "special")
	assert_eq(webs.size(), 1, "one web")
	assert_eq(webs[0]["name"], "Паутина", "named from enemies.json")
	assert_eq(webs[0]["target"], hero.id, "at the front-row hero")
	assert_true(hero.is_webbed(), "caught")
	assert_eq(HeroCard.badges_of(hero), ["web"] as Array[String], "the web on his card")
	energy_before = hero.energy
	battle.run_to_end(interval + float(web["duration"]) - 0.1)
	var events: Array = battle.take_events()
	assert_eq(events_of(events, "damage").filter(func(e): return e["source"] == hero.id).size(), 0, "no attacks while webbed")
	assert_true(events_of(events, "damage").any(func(e): return e["source"] == back.id), "the back row fights on")
	assert_eq(hero.energy, energy_before, "no energy while webbed, not even from hits taken")
	battle.run_to_end(interval + float(web["duration"]) + 0.6)
	assert_true(not hero.is_webbed(), "free after 2 s")
	assert_true(events_of(battle.take_events(), "damage").any(func(e): return e["source"] == hero.id), "and attacks again")
	assert_true(hero.energy > energy_before, "and gains energy again")


## With the front row fallen the web catches anyone left.
func test_the_spider_webs_the_back_row_once_the_front_row_has_fallen() -> void:
	var fallen = make_target("front")
	fallen.hp = 0
	var back = make_target("back")
	var spider = enemy_from_data("cave_spider")
	spider.base_attack = 0.0001
	var battle = make_battle([fallen, back], [spider])
	battle.run_to_end(float(data.get_enemy("cave_spider")["special"]["interval"]) + 0.01)
	assert_true(back.is_webbed(), "the back-row hero is caught")


# --- forge spirit ----------------------------------------------------------------

## «Взрыв»: dying, the spirit hits every front-row hero for attack × death_blast.attack_multiplier, reduced by the tank
## passive and the armour; the back row is untouched.
func test_the_forge_spirit_blows_up_at_the_front_row() -> void:
	var blast: Dictionary = data.get_enemy("forge_spirit")["death_blast"]
	assert_eq(blast["name"], "Взрыв", "named")
	var torvald = hero_from_data("torvald")
	var front = make_target("front")
	var back = make_target("back")
	var regin = hero_from_data("regin")
	var spirit = enemy_from_data("forge_spirit")
	var battle = make_battle([torvald, front, back, regin], [spirit])
	battle.take_events()
	spirit.hp = 1
	battle._deal_damage(front, spirit, 1.0, "attack")
	var events: Array = battle.take_events()
	assert_eq(events_of(events, "death").size(), 1, "the spirit died")
	var specials := events_of(events, "special")
	assert_eq(specials.size(), 1, "one blast")
	assert_eq([specials[0]["name"], specials[0]["unit"]], ["Взрыв", spirit.id], "«Взрыв» over the spirit")
	var hits := events_of(events, "damage").filter(func(e): return e["source"] == spirit.id)
	var by_target := {}
	for hit in hits:
		by_target[hit["target"]] = hit["amount"]
	var full: float = spirit.base_attack * float(blast["attack_multiplier"])
	var tank := float(data.get_hero("torvald")["passive"]["damage_taken_multiplier"])
	var armour := float(data.get_hero("regin")["passive"]["damage_taken_multiplier"])
	assert_eq(by_target.keys().size(), 2, "two front-row heroes hit")
	assert_eq(by_target.get(front.id), roundi(full * armour), "the front row, less by the armour")
	assert_eq(by_target.get(torvald.id), roundi(full * tank * armour), "the shieldbearer less again")
	assert_true(not by_target.has(back.id) and not by_target.has(regin.id), "the back row untouched")


## «Закалка» cuts the blast too; a blast with the front row fallen hits the rest (like every enemy blow).
func test_the_blast_is_cut_by_temper_and_reaches_the_back_row_without_a_front_row() -> void:
	var regin = hero_from_data("regin")
	var front = make_target("front")
	var spirit = enemy_from_data("forge_spirit")
	var battle = make_battle([front, regin], [spirit])
	regin.energy = regin.ultimate_cost()
	battle.use_ultimate(regin.id)
	battle.take_events()
	spirit.hp = 1
	battle._deal_damage(front, spirit, 1.0, "attack")
	var full: float = spirit.base_attack * float(data.get_enemy("forge_spirit")["death_blast"]["attack_multiplier"])
	var armour := float(data.get_hero("regin")["passive"]["damage_taken_multiplier"])
	var hits := events_of(battle.take_events(), "damage").filter(func(e): return e["source"] == spirit.id)
	assert_eq(hits.size(), 1, "the front-row hero")
	assert_eq(hits[0]["amount"], roundi(full * armour * 0.5), "armour × «Закалка»")
	var fallen = make_target("front")
	fallen.hp = 0
	var back = make_target("back")
	var other = enemy_from_data("forge_spirit")
	battle = make_battle([fallen, back], [other])
	battle.take_events()
	other.hp = 1
	battle._deal_damage(back, other, 1.0, "attack")
	hits = events_of(battle.take_events(), "damage").filter(func(e): return e["source"] == other.id)
	assert_eq(hits.map(func(e): return e["target"]), [back.id], "the back row once the front row has fallen")


## «Ярость» stops when Sigrid falls in it: her first blow kills a forge spirit, its blast kills her, the other enemy
## gets no more blows.
func test_a_series_of_blows_stops_when_the_blast_kills_the_hero() -> void:
	var sigrid = hero_from_data("sigrid")
	sigrid.hp = 1
	var spirit = enemy_from_data("forge_spirit")
	spirit.hp = 1
	var other = make_target("front")
	other.team = ENEMIES
	var battle = make_battle([sigrid], [spirit, other])
	assert_true(battle.toggle_mark(spirit.id), "the spirit is marked: the first blow goes to it")
	sigrid.energy = sigrid.ultimate_cost()
	battle.use_ultimate(sigrid.id)
	assert_true(not spirit.is_alive() and not sigrid.is_alive(), "the spirit and Sigrid fell")
	assert_eq(other.hp, other.max_hp, "no blows after her death")


# --- Fafnir --------------------------------------------------------------------

## «Ядовитое дыхание» every 8 s at the whole squad (× attack_multiplier), then poison: 3 blows, one a second, at every
## hero (the poison card badge while it lasts); the armour cuts the poison of the front row; poison gives no energy.
func test_fafnirs_breath_hits_everyone_and_poisons() -> void:
	var fafnir_data: Dictionary = data.get_enemy("fafnir")
	var breath: Dictionary = fafnir_data["special"]
	assert_eq([breath["name"], breath["type"]], ["Ядовитое дыхание", "hit_all"], "the breath")
	assert_near(float(breath["interval"]), 8.0, 0.0001, "every 8 s")
	var poison: Dictionary = breath["poison"]
	assert_eq(int(poison["ticks"]), 3, "poison for 3 s: 3 blows")
	assert_near(float(poison["interval"]), 1.0, 0.0001, "one a second")
	var regin = hero_from_data("regin")
	regin.max_hp = 10000000
	regin.hp = regin.max_hp
	regin.attack_interval = 1000.0  # no blows of his own: his energy may only come from hits
	var front = make_target("front")
	var back = make_target("back")
	var fafnir = enemy_from_data("fafnir")
	fafnir.attack_interval = 1000.0  # only the breath
	var battle = make_battle([front, back, regin], [fafnir])
	battle.run_to_end(8.01)
	var events: Array = battle.take_events()
	assert_eq(events_of(events, "special").map(func(e): return e["name"]), ["Ядовитое дыхание"], "the breath at 8 s")
	var breath_hits := events_of(events, "damage").filter(func(e): return e["kind"] == "special")
	assert_eq(breath_hits.size(), 3, "every hero")
	var full: float = fafnir.base_attack * float(breath["attack_multiplier"])
	var armour := float(data.get_hero("regin")["passive"]["damage_taken_multiplier"])
	assert_eq(breath_hits.filter(func(e): return e["target"] == back.id)[0]["amount"], roundi(full), "the back row: full")
	assert_eq(breath_hits.filter(func(e): return e["target"] == front.id)[0]["amount"], roundi(full * armour), "the front row: less")
	for hero in [front, back, regin]:
		assert_true(hero.is_poisoned(), "poisoned")
		assert_true("poison" in HeroCard.badges_of(hero), "the poison badge on the card")
	var regin_energy: int = regin.energy
	var ticks := []
	while battle.time < 11.3:
		battle.step()
		for event in battle.take_events():
			if event["type"] == "damage" and event["kind"] == "poison":
				ticks.append([event["target"], event["amount"], battle.time])
	assert_eq(ticks.size(), 9, "3 blows at each of 3 heroes")
	var per_tick: float = fafnir.base_attack * float(poison["attack_multiplier"])
	for tick in ticks:
		var expected := roundi(per_tick * (armour if tick[0] == front.id else 1.0))
		assert_eq(tick[1], expected, "a poison blow, less for the front row")
	var times := ticks.filter(func(t): return t[0] == back.id).map(func(t): return t[2])
	for i in 3:
		assert_near(times[i], 8.0 + i + 1, 0.06, "poison blow %d a second after the last" % (i + 1))
	assert_true(not back.is_poisoned(), "the poison is over after 3 s")
	assert_eq(regin.energy, regin_energy, "poison gives no energy")


## At half HP: «Фафнир зарывается в золото!» — 5 s invulnerable (blows show «Неуязвим», no damage, no stun from
## ultimates), the coins hit a random hero (any row) every second, 5 times; no blows and no breath meanwhile; then the
## second phase: blows again and the breath every 6 s. HP is not restored.
func test_fafnir_burrows_into_the_gold_at_half_hp() -> void:
	var fafnir_data: Dictionary = data.get_enemy("fafnir")
	var gold: Dictionary = fafnir_data["phases"][0]
	assert_eq(gold["announcement"], "Фафнир зарывается в золото!", "the announcement")
	assert_near(float(gold["at_hp_fraction"]), 0.5, 0.0001, "at half HP")
	assert_true(not gold.has("picture"), "the same picture")
	var invulnerable: Dictionary = gold["invulnerable"]
	assert_near(float(invulnerable["seconds"]), 5.0, 0.0001, "5 s")
	var coins: Dictionary = invulnerable["special"]
	assert_eq([coins["name"], coins["type"], coins["target"]], ["Монеты", "hit_one", "random"], "the coins")
	assert_near(float(coins["interval"]), 1.0, 0.0001, "every second")
	assert_near(float(gold["special"]["interval"]), 6.0, 0.0001, "phase 2: the breath every 6 s")

	var front = make_target("front")
	var back = make_target("back")
	var hrungnir = hero_from_data("hrungnir")
	hrungnir.attack_interval = 1000.0  # no blows of his own before the test's
	var fafnir = enemy_from_data("fafnir")
	var battle = make_battle([front, back, hrungnir], [fafnir], 3)
	var half := roundi(fafnir.max_hp * float(gold["at_hp_fraction"]))
	fafnir.hp = half + 1
	battle.run_to_end(3.0)  # the breath and blow timers are partway
	battle.take_events()
	var start: float = battle.time
	battle._deal_damage(front, fafnir, 0.0, "attack")  # 1 HP: down to exactly half
	var events: Array = battle.take_events()
	assert_eq(events_of(events, "phase").size(), 1, "the phase event")
	assert_true(fafnir.is_invulnerable(), "invulnerable")
	assert_eq(fafnir.hp, half, "HP stays at half")
	battle._deal_damage(front, fafnir, 100.0, "attack")
	events = battle.take_events()
	assert_eq(events_of(events, "damage").size(), 0, "no damage")
	assert_eq(events_of(events, "immune").map(func(e): return e["unit"]), [fafnir.id], "«Неуязвим»")
	hrungnir.energy = hrungnir.ultimate_cost()
	battle.use_ultimate(hrungnir.id)
	assert_eq(fafnir.hp, half, "the ultimate does not pass either")
	assert_true(not fafnir.is_stunned(), "nor does its stun")
	battle.take_events()
	var coin_hits := []
	var other := []
	var ended := -1.0
	while battle.time - start < 5.2:
		battle.step()
		for event in battle.take_events():
			if event["type"] == "damage" and event["source"] == fafnir.id:
				(coin_hits if event["kind"] == "special" else other).append([event["target"], battle.time - start])
			elif event["type"] == "special":
				assert_eq(event["name"], "Монеты", "only the coins while burrowed")
			elif event["type"] == "invulnerable_end":
				ended = battle.time - start
	assert_eq(coin_hits.size(), 5, "5 coins in 5 s")
	for i in coin_hits.size():
		assert_near(coin_hits[i][1], i + 1.0, 0.06, "coin %d a second after the last" % (i + 1))
	assert_eq(other.filter(func(hit): return hit[1] < ended - 0.01).size(), 0, "no blows and no breath while burrowed")
	assert_near(ended, 5.0, 0.06, "comes out after 5 s")
	assert_true(not fafnir.is_invulnerable(), "can be hit again")
	assert_eq(fafnir.phase, 1, "in phase 2")
	var targets := {}
	for probe_seed in 40:
		var probe_front = make_target("front")
		var probe_back = make_target("back")
		var probe = enemy_from_data("fafnir")
		var probe_battle = make_battle([probe_front, probe_back], [probe], probe_seed)
		probe.hp = half
		probe_battle._enter_due_phases(probe)
		probe_battle.run_to_end(1.01)
		for event in events_of(probe_battle.take_events(), "damage"):
			targets[event["target"]] = true
	assert_eq(targets.size(), 2, "the coins hit any row")
	# Phase 2: blows again, the breath 6 s after coming out, then every 6 s.
	var breaths := []
	var blows := 0
	while battle.time - start < 5.0 + 12.2:
		battle.step()
		for event in battle.take_events():
			if event["type"] == "special":
				breaths.append(battle.time - start)
			elif event["type"] == "damage" and event["source"] == fafnir.id and event["kind"] == "attack":
				blows += 1
	assert_true(blows > 0, "blows again")
	assert_eq(breaths.size(), 2, "two breaths in 12 s")
	assert_near(breaths[0], 11.0, 0.06, "6 s after coming out")
	assert_near(breaths[1], 17.0, 0.06, "then every 6 s")
	fafnir.hp = 1
	battle._deal_damage(front, fafnir, 1.0, "attack")
	assert_true(not fafnir.is_alive(), "and can be killed")
	assert_eq(events_of(battle.take_events(), "phase").size(), 0, "no more phases")
