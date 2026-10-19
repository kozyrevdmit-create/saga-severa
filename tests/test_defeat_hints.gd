## M11.2: tips under «Дружина пала» (data/hints.json → defeat). The eagles' tip comes after every defeat or retreat
## in a battle where an enemy attacking the back row was on the field (a carrion eagle, Thjazi as an eagle),
## and never in other battles. M13: tips about the cave spider, the forge spirit and Fafnir, word for word from the task;
## when several fit, only the first one in the data is shown. M13.1: the forge spirit's tip before the spider's (spirits
## almost always come with spiders; the spider's tip stays for battles with spiders only).
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const StageBattle := preload("res://scripts/battle/stage_battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")
const Progress := preload("res://scripts/save/progress.gd")
const BATTLE_SCENE := "res://scenes/battle.tscn"
const EAGLES_TIP := "Совет: орлы бьют задний ряд. Поставь туда того, кто выдержит удар."  ## word for word from the task
const SPIDER_TIP := "Совет: пауки опутывают героев паутиной. Отметь паука целью — пусть дружина бьёт его первым."
const SPIRIT_TIP := "Совет: дух горна взрывается при смерти и бьёт весь первый ряд. Береги здоровье щитоносцев."
const FAFNIR_TIP := "Совет: яд Фафнира бьёт по всей дружине. Лекарь и «Закалка» Регина спасают в бою со змеем."

var data = GameData.load_all()
var _saved_progress = null


func test_the_eagles_tip_is_in_the_data_word_for_word() -> void:
	var tips: Array = data.hints["defeat"].filter(func(hint): return hint["text"] == EAGLES_TIP)
	assert_eq(tips.size(), 1, "the tip is in hints.json")
	if tips.size() == 1:
		assert_eq(tips[0]["when"], {"enemy_action": "attack_back_row_weakest"}, "for enemies that attack the back row")


## M13: the three tips of chapter 3, word for word from the task, each for its enemy. Fafnir's comes before the spider's
## and the spirit's: on stage 30 his waves follow theirs, and the tip should be about the boss who beat the squad.
## M13.1: the spirit's before the spider's.
func test_the_tips_of_chapter_three_are_in_the_data_word_for_word() -> void:
	var by_text := {}
	for hint in data.hints["defeat"]:
		by_text[hint["text"]] = hint["when"]
	assert_eq(by_text.get(SPIDER_TIP), {"enemy": "cave_spider"}, "the spider's tip")
	assert_eq(by_text.get(SPIRIT_TIP), {"enemy": "forge_spirit"}, "the forge spirit's tip")
	assert_eq(by_text.get(FAFNIR_TIP), {"enemy": "fafnir"}, "Fafnir's tip")
	var texts: Array = data.hints["defeat"].map(func(hint): return hint["text"])
	assert_true(texts.find(FAFNIR_TIP) < texts.find(SPIDER_TIP) and texts.find(FAFNIR_TIP) < texts.find(SPIRIT_TIP),
			"Fafnir's tip first")
	assert_true(texts.find(SPIRIT_TIP) < texts.find(SPIDER_TIP), "the forge spirit's tip before the spider's (M13.1)")


## One tip per battle: the first in the data that fits. A spider and a spirit in one wave — the spirit's tip (M13.1);
## a retreat from a pack of spirits — the spirit's; from a pack of spiders — the spider's; Fafnir reached — his,
## though spiders and spirits were there before.
func test_one_tip_the_first_that_fits() -> void:
	var stage = StageBattle.from_data(data, 24, _squad(1), 1)
	stage.retreat()
	assert_eq(stage.defeat_hint(data.hints["defeat"]), SPIRIT_TIP, "spider and spirit: only the spirit's tip")
	var spiders = StageBattle.from_pack(data, "cave_spiders", 22, _squad(10), 1)
	spiders.retreat()
	assert_eq(spiders.defeat_hint(data.hints["defeat"]), SPIDER_TIP, "the spiders' pack: their tip")
	var spirits = StageBattle.from_pack(data, "forge_spirits", 26, _squad(10), 1)
	spirits.retreat()
	assert_eq(spirits.defeat_hint(data.hints["defeat"]), SPIRIT_TIP, "the spirits' pack: their tip")
	var boss = StageBattle.from_data(data, 30, _squad(1), 1)
	while boss.wave_index < boss.wave_count - 1:
		boss.battle.enemies().map(func(enemy): enemy.hp = 0)
		boss.step()
	boss.retreat()
	assert_eq(boss.defeat_hint(data.hints["defeat"]), FAFNIR_TIP, "Fafnir reached: his tip only")


## Every tip has a text and one known condition about something that exists in the game.
func test_every_tip_has_a_text_and_a_known_condition() -> void:
	var enemy_ids := []
	var actions := []
	for enemy in data.enemies["enemies"]:
		enemy_ids.append(enemy["id"])
		actions.append(enemy["action"])
		for phase in enemy.get("phases", []):
			actions.append(phase["action"])
	assert_true(not data.hints["defeat"].is_empty(), "there are tips")
	for hint in data.hints["defeat"]:
		assert_true(str(hint["text"]).strip_edges() != "", "a tip has a text")
		var when: Dictionary = hint["when"]
		assert_eq(when.size(), 1, "one condition: %s" % str(when))
		if when.has("enemy_action"):
			assert_true(when["enemy_action"] in actions, "an enemy attacks this way: %s" % when["enemy_action"])
		elif when.has("enemy"):
			assert_true(when["enemy"] in enemy_ids, "a known enemy: %s" % when["enemy"])
		else:
			failures.append("unknown condition: %s" % str(when))


func test_a_defeat_with_a_carrion_eagle_brings_the_tip() -> void:
	var stage = StageBattle.from_data(data, 12, _squad(1), 1)
	stage.auto_ultimates = true
	stage.run_to_end(600.0)
	assert_true(stage.finished and not stage.victory, "level 1 loses stage 12")
	assert_eq(stage.defeat_hint(data.hints["defeat"]), EAGLES_TIP, "the eagles' tip")


func test_a_retreat_from_stage_twenty_brings_the_tip() -> void:
	var stage = StageBattle.from_data(data, 20, _squad(17), 1)
	stage.run_to_end(2.0)
	assert_true(stage.retreat(), "retreated in the first wave (a carrion eagle)")
	assert_eq(stage.defeat_hint(data.hints["defeat"]), EAGLES_TIP, "the eagles' tip after a retreat too")


func test_a_retreat_from_the_eagles_pack_brings_the_tip() -> void:
	var eagle_packs: Array = data.packs["packs"].filter(func(pack): return "carrion_eagle" in pack["enemies"])
	assert_true(not eagle_packs.is_empty(), "a pack of eagles")
	for pack in eagle_packs:
		var stage = StageBattle.from_pack(data, pack["id"], 15, _squad(10), 1)
		stage.retreat()
		assert_eq(stage.defeat_hint(data.hints["defeat"]), EAGLES_TIP, "the eagles' tip for «%s»" % pack["name"])


## Other battles: no eagle on the field (stage 1, the Draugr king's stage 10, stage 11 of chapter 2, a wolf pack).
func test_no_tip_in_battles_without_eagles() -> void:
	for stage_id in [10, 11]:
		var stage = StageBattle.from_data(data, stage_id, _squad(1), 1)
		stage.auto_ultimates = true
		stage.run_to_end(600.0)
		assert_true(stage.finished and not stage.victory, "level 1 loses stage %d" % stage_id)
		assert_eq(stage.defeat_hint(data.hints["defeat"]), "", "no tip on stage %d" % stage_id)
	var first = StageBattle.from_data(data, 1, _squad(1), 1)
	first.retreat()
	assert_eq(first.defeat_hint(data.hints["defeat"]), "", "no tip on stage 1")
	var wolves = StageBattle.from_pack(data, "ironwood_wolves", 15, _squad(10), 1)
	wolves.retreat()
	assert_eq(wolves.defeat_hint(data.hints["defeat"]), "", "no tip for the Ironwood wolves")


## Thjazi alone: as a giant he attacks the front row — no tip; once he has turned into an eagle — the tip.
func test_thjazi_brings_the_tip_only_as_an_eagle() -> void:
	var tank := BattleUnit.new()
	tank.team = BattleUnit.Team.HEROES
	tank.row = "front"
	tank.max_hp = 10000000
	tank.hp = tank.max_hp
	tank.base_attack = 1
	tank.attack_interval = 1000.0
	var thjazi = BattleUnit.from_enemy(data.get_enemy("thjazi"), data.enemy_power_multiplier(20))
	var stage = StageBattle.new(20, [tank], [[thjazi]], data.balance, 1)
	stage.run_to_end(1.0)
	assert_eq(stage.defeat_hint(data.hints["defeat"]), "", "no tip while Thjazi is a giant")
	thjazi.hp = roundi(thjazi.max_hp * float(data.get_enemy("thjazi")["phases"][0]["at_hp_fraction"]))
	stage.battle._deal_damage(tank, thjazi, 0.0, "attack")
	stage.step()
	assert_eq(thjazi.phase, 1, "turned into an eagle")
	stage.retreat()
	assert_eq(stage.defeat_hint(data.hints["defeat"]), EAGLES_TIP, "the tip once he is an eagle")


func test_a_tip_about_one_enemy_by_its_id() -> void:
	var hints := [{"when": {"enemy": "draugr_archer"}, "text": "лучник"}, {"when": {"enemy": "bear"}, "text": "медведь"}]
	var stage = StageBattle.from_data(data, 10, _squad(1), 1)
	assert_eq(stage.defeat_hint(hints), "", "the archer is in the second wave, not reached yet")
	while stage.wave_index == 0:
		stage.battle.enemies().map(func(enemy): enemy.hp = 0)
		stage.step()
	assert_eq(stage.defeat_hint(hints), "лучник", "the archer has been on the field; the bear has not")


## The «Дружина пала» / «Дружина отступила» window shows the tip under the usual text, each time.
func test_the_defeat_window_shows_the_tip_after_every_retreat_from_stage_twenty() -> void:
	for attempt in 2:
		var battle = await _open_battle(20)
		_retreat(battle)
		var text: String = battle.get_node("%ResultHint").text
		assert_true(battle.get_node("%ResultOverlay").visible, "the result window")
		assert_eq(battle.get_node("%ResultTitle").text, "Дружина отступила", "after a retreat")
		assert_true(text.begins_with("Бой засчитан поражением.\nПодсказка: прокачай героев или поменяй расстановку отряда."),
				"the usual text first")
		assert_true(text.contains("\n\n" + EAGLES_TIP + "\n\nЭйвинд: песнь добавила "),
				"then the eagles' tip, then the support heroes' lines (M13.1) (attempt %d)" % (attempt + 1))
		_close(battle)


func test_the_defeat_window_has_no_tip_after_stage_ten() -> void:
	var battle = await _open_battle(10)
	_retreat(battle)
	assert_true(not battle.get_node("%ResultHint").text.contains(EAGLES_TIP), "no eagles' tip at the Draugr king")
	_close(battle)


func _squad(level: int) -> Array:
	return data.starting_hero_ids().map(func(hero_id): return {
		"id": hero_id, "level": level, "row": data.get_hero_class(data.get_hero(hero_id))["row"]})


func _open_battle(stage_id: int) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	var progress = Progress.new_game(game_state.data)
	progress.jump_to_stage(game_state.data, stage_id)
	progress.finish_tutorial(game_state.data)
	if _saved_progress == null:
		_saved_progress = game_state.progress
	game_state.progress = progress
	game_state.selected_stage = stage_id
	game_state.selected_pack = ""
	var battle: Control = load(BATTLE_SCENE).instantiate()
	tree.root.add_child(battle)
	await tree.process_frame
	battle.set_process(false)
	return battle


func _retreat(battle: Control) -> void:
	battle.get_node("%RetreatButton").pressed.emit()
	for event in battle._battle.take_events():
		battle._show_event(event)


func _close(battle: Control) -> void:
	battle.queue_free()
	(Engine.get_main_loop() as SceneTree).root.get_node("GameState").progress = _saved_progress
	_saved_progress = null
