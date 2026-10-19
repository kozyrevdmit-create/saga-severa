## Player progress: silver, experience (jarl level), won stages, unlocked heroes with their levels,
## the squad formation, the time the game was last open (for offline income), when beaten beast packs come back,
## which saga scenes have been seen, the settlement (M12): supplies and the buildings' levels, and which hints of the
## beginner's tutorial (M14, data/tutorial.json) have been shown.
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
var pack_respawn_unix := {}  ## beaten beast pack id -> when it comes back to the map (unix time)
var pack_clock_unix := 0  ## when the pack timers were last checked against the clock (to notice it turned back); 0 = never
var seen_scenes: Array[String] = []  ## saga scenes (story.json ids) that have started: each is shown once per game
var scene_queue: Array[String] = []  ## scenes whose moment has come but that have not started yet (saved, so closing the game does not lose them)
var supplies := 0  ## «Припасы» (wood, stone, iron) for the settlement's buildings
var building_levels := {}  ## built building id -> level (1..max); a building not built yet is not here
var start_supplies_given := false  ## the starting supplies came with the opening of construction (once per game)
var tutorial_shown: Array[String] = []  ## tutorial hints (tutorial.json ids) already shown: each once per game


static func new_game(data) -> RefCounted:
	var progress = new()
	progress.silver = int(data.balance["start_silver"])
	progress._reset_formation(data)
	for hero_id in data.starting_hero_ids():
		progress.hero_levels[hero_id] = 1
		progress.formation_add(data, hero_id)
	progress._queue_scenes(data, "new_game")
	return progress


## Debug panel «Сбросить прогресс»: everything back to a new game (stages, heroes and their levels, squad,
## silver, jarl experience, offline bank, beast pack timers, seen saga scenes: the intro is due again; supplies and
## buildings; the tutorial starts again). The offline clock restarts now, so the time before the reset earns nothing.
func reset(data, now_unix: int) -> void:
	var fresh = new_game(data)
	silver = fresh.silver
	experience = fresh.experience
	cleared_stage = fresh.cleared_stage
	hero_levels = fresh.hero_levels
	formation = fresh.formation
	offline_bank = fresh.offline_bank
	pack_respawn_unix = fresh.pack_respawn_unix
	pack_clock_unix = fresh.pack_clock_unix
	seen_scenes = fresh.seen_scenes
	scene_queue = fresh.scene_queue
	supplies = fresh.supplies
	building_levels = fresh.building_levels
	start_supplies_given = fresh.start_supplies_given
	tutorial_shown = fresh.tutorial_shown
	last_seen_unix = now_unix


## Debug panel «Открыть всех героев»: every locked hero joins like a new hero (at the join level,
## into a free slot if there is one), but without their saga scene. Returns the heroes that joined.
func unlock_all_heroes(data) -> Array[String]:
	var joined: Array[String] = []
	var level := _join_level(data)
	for hero in data.heroes["heroes"]:
		if not hero_levels.has(hero["id"]):
			_join(data, hero["id"], level)
			joined.append(hero["id"])
	return joined


## Debug panel «Перейти к этапу N»: stages before N count as won (without rewards), N is the next battle.
## Heroes earned by those stages join (without their saga scenes); heroes already unlocked stay. Past chapter 1
## construction opens with its starting supplies (once per game); buildings already built stay.
func jump_to_stage(data, stage_id: int) -> void:
	cleared_stage = clampi(stage_id, 1, data.stage_count()) - 1
	var level := _join_level(data)
	for hero_id in earned_hero_ids(data):
		if not hero_levels.has(hero_id):
			_join(data, hero_id, level)
	_open_construction(data)


# --- stages and rewards -------------------------------------------------------

## The first stage not won yet, or the last one once every chapter is done.
func next_stage_id(data) -> int:
	return mini(cleared_stage + 1, data.stage_count())


# --- chapters -------------------------------------------------------------------

## Chapter 1 is open from the start; the next chapter opens with the first win over the previous chapter's boss.
## (A save that has already beaten chapter 1 has chapter 2 open at once.)
func is_chapter_open(data, chapter_id: int) -> bool:
	return is_stage_open(data, data.chapter_stage_ids(chapter_id)[0])


## The chapter the map opens on: the one with the next stage to win (the last chapter once everything is won).
func current_chapter(data) -> int:
	return data.chapter_of_stage(next_stage_id(data))


## Won stages can be replayed; the next one can be fought; later ones are locked.
func is_stage_open(data, stage_id: int) -> bool:
	return stage_id >= 1 and stage_id <= next_stage_id(data)


func is_replay(stage_id: int) -> bool:
	return stage_id <= cleared_stage


## Pays the reward (a replay pays replay_reward_share of it; the jarl bonus and the trading pier add silver),
## marks the stage won and unlocks heroes (at the join level, see _join_level). A first win queues the saga scenes
## of the heroes who joined and of the stage's first victory, and brings balance.json → supplies.first_victory
## while construction is open (the win over chapter 1's boss opens it and brings the starting supplies instead).
## Returns {silver, experience, supplies, replay, new_heroes}.
func apply_victory(data, stage_id: int) -> Dictionary:
	var replay := is_replay(stage_id)
	var base: Dictionary = data.get_stage(stage_id)["reward"]
	var share := float(data.balance["replay_reward_share"]) if replay else 1.0
	var silver_gain := roundi(float(base["silver"]) * share * silver_multiplier(data) * battle_silver_multiplier(data))
	var experience_gain := roundi(float(base["experience"]) * share)
	var supplies_gain := 0 if replay or not is_construction_open(data) else int(data.balance["supplies"]["first_victory"])
	silver += silver_gain
	experience += experience_gain
	supplies += supplies_gain
	var new_heroes: Array[String] = []
	if not replay:
		cleared_stage = maxi(cleared_stage, stage_id)
		var level := _join_level(data)
		for hero_id in data.heroes_unlocked_at(stage_id):
			if not hero_levels.has(hero_id):
				_join(data, hero_id, level)
				new_heroes.append(hero_id)
				_queue_scenes(data, "hero_joined", hero_id)
		_queue_scenes(data, "first_victory", stage_id)
		_open_construction(data)
	return {"silver": silver_gain, "experience": experience_gain, "supplies": supplies_gain, "replay": replay,
		"new_heroes": new_heroes}


## Heroes earned by the won stages: each hero's stage (unlock_after_stage) is won, and a hero who joins after a saga
## scene (Regin after «ch3_intro») has also had that scene start (a scene counts as seen as soon as it starts, so if
## the game is closed during it, he is there on the next start).
func earned_hero_ids(data) -> Array[String]:
	var ids: Array[String] = []
	for hero_id in data.unlocked_hero_ids(cleared_stage):
		var scene_id: String = data.get_hero(hero_id).get("joins_after_scene", "")
		if scene_id == "" or is_scene_seen(scene_id):
			ids.append(hero_id)
	return ids


## The saga scene `scene_id` has ended: the heroes who join at its end (GameData.heroes_joining_after_scene) join like
## new heroes (at the join level, into a free slot or onto the bench) once their stage is won. Returns those who joined
## now, for the «Новый герой» window (nobody when the scene is watched again from «Сцены саги»: they are already here).
func join_heroes_after_scene(data, scene_id: String) -> Array[String]:
	var joined: Array[String] = []
	var level := _join_level(data)
	for hero_id in data.heroes_joining_after_scene(scene_id):
		if not hero_levels.has(hero_id) and hero_id in earned_hero_ids(data):
			_join(data, hero_id, level)
			joined.append(hero_id)
	return joined


# --- saga scenes (data/story.json) ----------------------------------------------

## Queues the scenes shown at `when` (for this hero or stage, see GameData.scene_ids_shown_at) that have not been
## seen or queued yet. A screen plays a queued scene at its place: the intro on the main screen, a hero's scene
## after the «Новый герой» window, the boss's last scene after «Победа!». One left when the game was closed is
## played on the main screen next time.
func _queue_scenes(data, when: String, subject = null) -> void:
	for scene_id in data.scene_ids_shown_at(when, subject):
		if not scene_id in seen_scenes and not scene_id in scene_queue:
			scene_queue.append(scene_id)


## The first queued scene shown at `when` (for this hero or stage), or any queued scene when `when` is "";
## "" if there is none.
func queued_scene(data, when := "", subject = null) -> String:
	var wanted: Array[String] = data.scene_ids_shown_at(when, subject) if when != "" else scene_queue
	for scene_id in scene_queue:
		if scene_id in wanted:
			return scene_id
	return ""


## The scenes shown before the battle on a stage (pack_id "") or with a beast pack, in order, each once per game
## (not again after a defeat or a retreat): the boss's first scene, only while the stage has not been won; the scene
## of an enemy's first battle (the carrion eagles), on a stage or a pack where that enemy fights.
func scenes_before_battle(data, stage_id: int, pack_id := "") -> Array[String]:
	var ids: Array[String] = []
	if pack_id == "" and not is_replay(stage_id):
		ids.append_array(data.scene_ids_shown_at("before_first_battle", stage_id))
	for enemy in data.enemies["enemies"]:
		var fights: bool = data.pack_has_enemy(pack_id, enemy["id"]) if pack_id != "" else data.stage_has_enemy(stage_id, enemy["id"])
		if fights:
			ids.append_array(data.scene_ids_shown_at("before_battle_with", enemy["id"]))
	return ids.filter(func(scene_id): return not scene_id in seen_scenes)


## The scene shown the first time the settlement is entered with construction open (story.json → settlement), or ""
## (also once it has been seen, and while construction is closed).
func scene_on_settlement(data) -> String:
	if not is_construction_open(data):
		return ""
	for scene_id in data.scene_ids_shown_at("settlement"):
		if not scene_id in seen_scenes:
			return scene_id
	return ""


## The scene shown the first time the chapter's map is shown (Jotunheim's), or "" (also once it has been seen).
func scene_on_chapter_map(data, chapter_id: int) -> String:
	for scene_id in data.scene_ids_shown_at("chapter_map", chapter_id):
		if not scene_id in seen_scenes:
			return scene_id
	return ""


## A scene counts as seen as soon as it starts (also when it is skipped).
func start_scene(scene_id: String) -> void:
	if not scene_id in seen_scenes:
		seen_scenes.append(scene_id)
	scene_queue.erase(scene_id)


func is_scene_seen(scene_id: String) -> bool:
	return scene_id in seen_scenes


## Seen scenes in story order (the «Сцены саги» list in «Настройки»).
func seen_scene_ids(data) -> Array[String]:
	var ids: Array[String] = []
	for scene_id in data.scene_ids():
		if scene_id in seen_scenes:
			ids.append(scene_id)
	return ids


## Debug panel «Открыть все сцены»: every scene counts as seen (and none is played), so all can be watched
## from «Сцены саги».
func mark_all_scenes_seen(data) -> void:
	for scene_id in data.scene_ids():
		start_scene(scene_id)


# --- the beginner's tutorial (data/tutorial.json, M14) -----------------------------

## The tutorial hints due on `screen` at `moment` (tutorial.json → hints[].screen / moment) that have not been shown and
## whose conditions (hints[].if) hold, in data order. The screen shows the first one whose target is on it, only one at a
## time; the others wait for their next moment. Moments: "open" (the screen is opened and nothing else is over it:
## a saga scene, a window), "start" (a battle starts), "ultimate_ready" (a hero's ultimate is charged), "defeat".
## Conditions: stages_won N (at least N stages won), hint_shown_before (that hint was shown before this screen was
## opened: facts.shown_before, so «the next battle after hint 3»), pack_available (a beast pack of the current chapter can
## be fought now: facts.now), construction_open, scene_seen (that saga scene has started), defeat_tip (the defeat has a
## tip of hints.json: facts.defeat_tip).
func tutorial_hints_due(data, screen: String, moment: String, facts := {}) -> Array[String]:
	var due: Array[String] = []
	for hint in data.tutorial["hints"]:
		if hint["screen"] == screen and hint["moment"] == moment and not hint["id"] in tutorial_shown \
				and _tutorial_conditions_met(data, hint.get("if", {}), facts):
			due.append(hint["id"])
	return due


func _tutorial_conditions_met(data, conditions: Dictionary, facts: Dictionary) -> bool:
	for key in conditions:
		var wanted = conditions[key]
		var met := false
		match key:
			"stages_won":
				met = cleared_stage >= int(wanted)
			"hint_shown_before":
				met = wanted in facts.get("shown_before", [])
			"pack_available":
				var now_unix: int = facts.get("now", 0)
				var available: bool = data.pack_ids(current_chapter(data)).any(
						func(pack_id): return is_pack_available(data, pack_id, now_unix))
				met = available == bool(wanted)
			"construction_open":
				met = is_construction_open(data) == bool(wanted)
			"scene_seen":
				met = is_scene_seen(wanted)
			"defeat_tip":
				met = bool(facts.get("defeat_tip", false)) == bool(wanted)
			_:
				push_error("Unknown tutorial.json condition: %s" % key)
		if not met:
			return false
	return true


## The hint is on the screen: it counts as shown at once (also if the game is closed while it is open).
func show_tutorial_hint(hint_id: String) -> void:
	if not hint_id in tutorial_shown:
		tutorial_shown.append(hint_id)


func is_tutorial_hint_shown(hint_id: String) -> bool:
	return hint_id in tutorial_shown


## Debug panel «Сбросить обучение»: every hint is due again; the progress stays as it is.
func reset_tutorial() -> void:
	tutorial_shown.clear()


## Every hint counts as shown: no tutorial (a save that had passed stage 1 before M14; tests of other screens).
func finish_tutorial(data) -> void:
	for hint_id in data.tutorial_hint_ids():
		show_tutorial_hint(hint_id)


## A save from before M14 (no tutorial flags in it). Once it has won tutorial.json → old_saves.tutorial_off_once_stages_won
## stages, the tutorial is off: every hint counts as shown, except the hints of old_saves.kept_while_construction_open
## (the settlement's) while construction is open (the settlement has not been opened since the update: it explains the
## buildings there once). The old target mark hint (mark_hint_shown, M6.1) is the tutorial's hint
## old_saves.mark_hint_shown_counts_as: shown there, shown here.
func _migrate_tutorial(data, mark_hint_was_shown: bool) -> void:
	var old_saves: Dictionary = data.tutorial["old_saves"]
	if cleared_stage >= int(old_saves["tutorial_off_once_stages_won"]):
		var kept: Array = old_saves["kept_while_construction_open"] if is_construction_open(data) else []
		for hint_id in data.tutorial_hint_ids():
			if not hint_id in kept:
				show_tutorial_hint(hint_id)
	if mark_hint_was_shown:
		show_tutorial_hint(old_saves["mark_hint_shown_counts_as"])


# --- beast packs ----------------------------------------------------------------

## A beast pack fights at the strength of the last stage won in ITS chapter and pays a share of that stage's first-win
## reward (M11.1): Midgard's packs at most at stage 10, Jotunheim's at stages 11–20. Before the first win in its chapter
## a pack is as strong as the chapter's first stage (stage 1, stage 11).
func pack_stage(data, pack_id: String) -> int:
	var stages: Array[int] = data.chapter_stage_ids(int(data.get_pack(pack_id)["chapter"]))
	return clampi(cleared_stage, stages[0], stages.back())


func is_pack_unlocked(data, pack_id: String) -> bool:
	return cleared_stage >= int(data.get_pack(pack_id)["unlock_after_stage"])


## Seconds until a beaten pack comes back; 0 = it is on the map. Counted by the clock, so the time while the game
## is closed counts too. Never more than the respawn time (pack_respawn_seconds), even if the device clock was turned
## back (a level of Thjazi's barrow cuts the saved times themselves, see build).
func pack_seconds_left(data, pack_id: String, now_unix: int) -> int:
	if not pack_respawn_unix.has(pack_id):
		return 0
	return clampi(int(pack_respawn_unix[pack_id]) - now_unix, 0, pack_respawn_seconds(data))


## Seconds before a beaten pack comes back: balance.json → beast_packs.respawn_hours, shorter by Thjazi's barrow
## (M12: −10% per level, 2 h → 1 h at level 5; buildings.json).
func pack_respawn_seconds(data) -> int:
	return roundi(data.pack_respawn_seconds() * (1.0 - building_bonus_total(data, "pack_respawn")))


## The pack is on the map and can be fought: unlocked and not waiting to come back.
func is_pack_available(data, pack_id: String, now_unix: int) -> bool:
	return is_pack_unlocked(data, pack_id) and pack_seconds_left(data, pack_id, now_unix) == 0


## The reward for beating a pack: balance.json → beast_packs.reward_share_of_first_win of the first-win reward
## of pack_stage(data, pack_id), silver with the jarl bonus and the trading pier; while construction is open also
## balance.json → supplies.pack_victory (M12). Returns {silver, experience, supplies}.
## The packs of a chapter already passed (the player has opened the next chapter) pay less:
## beast_packs.reward_share_once_the_next_chapter_is_open; the packs of the current chapter pay the full share (M11.1;
## the rule holds for any chapter: Midgard's packs in chapter 2, Jotunheim's once a chapter 3 opens). Otherwise the
## easy packs of the chapters behind would take away most replays of the current chapter. The same holds for
## supplies: supplies.pack_victory_once_the_next_chapter_is_open.
func pack_reward(data, pack_id: String) -> Dictionary:
	var packs: Dictionary = data.balance["beast_packs"]
	var share := float(packs["reward_share_of_first_win"])
	var supplies_key := "pack_victory"
	var next_chapter := int(data.get_pack(pack_id)["chapter"]) + 1
	if next_chapter in data.chapter_ids() and is_chapter_open(data, next_chapter):
		share = float(packs["reward_share_once_the_next_chapter_is_open"])
		supplies_key = "pack_victory_once_the_next_chapter_is_open"
	var base: Dictionary = data.get_stage(pack_stage(data, pack_id))["reward"]
	return {
		"silver": roundi(float(base["silver"]) * share * silver_multiplier(data) * battle_silver_multiplier(data)),
		"experience": roundi(float(base["experience"]) * share),
		"supplies": int(data.balance["supplies"][supplies_key]) if is_construction_open(data) else 0,
	}


## Pays the pack reward and sends the pack away for pack_respawn_seconds.
## A defeat or a retreat changes nothing: the pack stays on the map. Returns {silver, experience, supplies}.
func apply_pack_victory(data, pack_id: String, now_unix: int) -> Dictionary:
	var reward := pack_reward(data, pack_id)
	silver += int(reward["silver"])
	experience += int(reward["experience"])
	supplies += int(reward["supplies"])
	update_pack_timers(data, now_unix)
	pack_respawn_unix[pack_id] = now_unix + pack_respawn_seconds(data)
	return reward


## Keeps the saved pack times honest when the device clock jumps back: every saved time moves back by as much as
## the clock went back since the last check, so the real wait stays the respawn time; a pack never waits longer than
## the respawn time from now; a pack that has come back is forgotten (turning the clock back does not send it away
## again). Called when the game starts or comes back, while the map is open, when a pack is beaten and when a building
## is built (Thjazi's barrow shortens the respawn time).
func update_pack_timers(data, now_unix: int) -> void:
	var went_back := maxi(0, pack_clock_unix - now_unix)
	pack_clock_unix = now_unix
	var latest: int = now_unix + pack_respawn_seconds(data)
	for pack_id in pack_respawn_unix.keys():
		var at := mini(int(pack_respawn_unix[pack_id]) - went_back, latest)
		if at <= now_unix:
			pack_respawn_unix.erase(pack_id)
		else:
			pack_respawn_unix[pack_id] = at


## Debug panel «Промотать время»: beaten packs come back that much sooner.
func skip_pack_timers(seconds: int) -> void:
	for pack_id in pack_respawn_unix:
		pack_respawn_unix[pack_id] = int(pack_respawn_unix[pack_id]) - seconds


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


## Silver for the hero's next level: GameData.level_up_cost, cheaper by the training yard (M12: −3% per level).
func level_up_cost(data, hero_id: String) -> int:
	return roundi(data.level_up_cost(level_of(hero_id)) * (1.0 - building_bonus_total(data, "level_up_discount")))


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


# --- squad power («Сила») -----------------------------------------------------

## The chapter map shows a stage's recommended power in red while the squad is weaker than it.
func is_below_recommended(data, stage_id: int) -> bool:
	return data.recommended_power(stage_id) > squad_power(data)


## The squad's «Сила»: the sum of the squad heroes' power (GameData.hero_power) with the squad's clan bonuses
## and the settlement's bonuses (the shrine's HP, the forge's attack).
func squad_power(data) -> int:
	var total := 0
	for hero_id in squad_ids():
		total += hero_power(data, hero_id)
	return total


## A hero's power at their level (plus extra_levels): with the squad's clan bonuses when in the squad, without on the bench;
## the settlement's bonuses count for every hero (they are the whole druzhina's). The bonuses add up (+20% clan HP and
## +4% shrine HP = +24% HP), as in the battle (StageBattle).
func hero_power(data, hero_id: String, extra_levels := 0) -> int:
	var bonuses: Dictionary = data.synergy_bonuses(squad_ids() if is_in_formation(hero_id) else [])
	var settlement := settlement_stat_bonuses(data)
	for stat in settlement:
		bonuses[stat] += settlement[stat]
	return data.hero_power(hero_id, level_of(hero_id) + extra_levels, bonuses)


## «+N силы» on the level-up button: how much the hero's power grows with the next level
## (for a hero in the squad, exactly how much the squad's power grows).
func level_up_power_gain(data, hero_id: String) -> int:
	return hero_power(data, hero_id, 1) - hero_power(data, hero_id)


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


## The squad for a battle: [{id, level, row, bonus}] in slot order; bonus = the settlement's {hp, attack} bonuses
## (settlement_stat_bonuses), the same for every hero.
func squad(data) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bonus := settlement_stat_bonuses(data)
	for slot in formation.size():
		if formation[slot] != EMPTY:
			result.append({"id": formation[slot], "level": level_of(formation[slot]), "row": slot_row(data, slot),
				"bonus": bonus.duplicate()})
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


# --- settlement: supplies and buildings (M12) -------------------------------------

## A chapter is won once its last stage (the boss) has been won. A chapter not in the game yet (chapter 3) is never won.
func is_chapter_won(data, chapter_id: int) -> bool:
	return chapter_id in data.chapter_ids() and cleared_stage >= data.chapter_stage_ids(chapter_id).back()


## Construction opens with the first win over chapter 1's boss (buildings.json → opens_after_chapter): the settlement's
## scene has all six heroes speak, and chapter 1 and its balance stay as they were. Until then the settlement only
## brings offline income, and no supplies are earned.
func is_construction_open(data) -> bool:
	return is_chapter_won(data, int(data.buildings["opens_after_chapter"]))


## A building can be built once construction is open and its chapter is won (Thjazi's barrow after chapter 2,
## the forge after chapter 3).
func is_building_open(data, building_id: String) -> bool:
	return is_construction_open(data) and is_chapter_won(data, int(data.get_building(building_id)["opens_after_chapter"]))


## 0 = not built yet.
func building_level(building_id: String) -> int:
	return int(building_levels.get(building_id, 0))


func is_building_max_level(data, building_id: String) -> bool:
	return building_level(building_id) >= data.building_max_level()


## Supplies for the building's next level (building or improving it).
func building_cost(data, building_id: String) -> int:
	return data.building_cost(building_level(building_id))


func can_build(data, building_id: String) -> bool:
	return is_building_open(data, building_id) and not is_building_max_level(data, building_id) \
			and supplies >= building_cost(data, building_id)


## «Построить» / «Улучшить»: the building gets its next level at once for its cost in supplies.
## A level of Thjazi's barrow shortens the wait of the packs that are away right now: their saved return time is cut
## to `now_unix` + the new respawn time (update_pack_timers), so they really come back that soon.
func build(data, building_id: String, now_unix: int) -> bool:
	if not can_build(data, building_id):
		return false
	supplies -= building_cost(data, building_id)
	building_levels[building_id] = building_level(building_id) + 1
	update_pack_timers(data, now_unix)
	return true


## The sum of the built buildings' bonuses of one kind (buildings.json → bonus.kind): "squad_hp", "squad_attack",
## "level_up_discount", "battle_silver", "pack_respawn"; a share (0.06 = 6%).
func building_bonus_total(data, kind: String) -> float:
	var total := 0.0
	for building_id in building_levels:
		if data.get_building(building_id)["bonus"]["kind"] == kind:
			total += data.building_bonus(building_id, building_level(building_id))
	return total


## The shrine's HP and the forge's attack bonus for every hero: {"hp": 0.04, "attack": 0.0}.
func settlement_stat_bonuses(data) -> Dictionary:
	return {"hp": building_bonus_total(data, "squad_hp"), "attack": building_bonus_total(data, "squad_attack")}


## The trading pier: more silver for battles, stages and packs (not for offline income).
func battle_silver_multiplier(data) -> float:
	return 1.0 + building_bonus_total(data, "battle_silver")


## Once construction opens (also for a save that won chapter 1 before M12, and after the debug jump), the player gets
## exactly enough supplies for one building of level 1 (buildings.json → level_costs[0]), once per game.
func _open_construction(data) -> void:
	if is_construction_open(data) and not start_supplies_given:
		supplies += data.building_cost(0)
		start_supplies_given = true


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
		"pack_respawn_unix": pack_respawn_unix.duplicate(),
		"pack_clock_unix": pack_clock_unix,
		"seen_scenes": seen_scenes.duplicate(),
		"scene_queue": scene_queue.duplicate(),
		"supplies": supplies,
		"building_levels": building_levels.duplicate(),
		"start_supplies_given": start_supplies_given,
		"tutorial_shown": tutorial_shown.duplicate(),
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
	# A save from before M12 has no settlement: no supplies or buildings; if it has won chapter 1, construction opens
	# with its starting supplies (at the end, once the stages are restored).
	progress.supplies = maxi(0, _to_int(saved.get("supplies"), 0))
	var levels_saved = saved.get("building_levels")
	if levels_saved is Dictionary:
		for building_id in data.building_ids():
			var saved_level := clampi(_to_int(levels_saved.get(building_id), 0), 0, data.building_max_level())
			if saved_level > 0:
				progress.building_levels[building_id] = saved_level
	var given = saved.get("start_supplies_given")
	progress.start_supplies_given = given is bool and given
	# A save from before M9 has no pack timers: every unlocked pack is on the map.
	var respawns = saved.get("pack_respawn_unix")
	if respawns is Dictionary:
		for pack_id in data.pack_ids():
			var at := _to_int(respawns.get(pack_id), 0)
			if at > 0:
				progress.pack_respawn_unix[pack_id] = at
	progress.pack_clock_unix = maxi(0, _to_int(saved.get("pack_clock_unix"), 0))
	# A save from before M10 has no scene lists: it keeps the intro queued by new_game (shown once, as on a first start);
	# the heroes and stages it already has bring no scenes.
	var seen = saved.get("seen_scenes")
	if seen is Array:
		progress.seen_scenes.clear()
		progress.scene_queue.clear()
		for scene_id in data.scene_ids():
			if scene_id in seen:
				progress.seen_scenes.append(scene_id)
		var queue = saved.get("scene_queue")
		if queue is Array:
			for scene_id in queue:
				if scene_id is String and data.has_scene(scene_id) and not progress.is_scene_seen(scene_id) \
						and not scene_id in progress.scene_queue:
					progress.scene_queue.append(scene_id)

	# Every hero earned by the won stages is unlocked, so a version 1 save gets the heroes it has earned;
	# a hero without a saved level joins like a new hero (at the join level counted over the heroes with a saved
	# level, once the formation is restored). Heroes saved with a level beyond that (opened by the debug panel,
	# or kept after jumping back to an earlier stage) stay unlocked.
	var levels = saved.get("hero_levels")
	var earned: Array[String] = progress.earned_hero_ids(data)
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
		progress.formation_add(data, hero_id)  # like a new hero: into a free slot, if there is one
	progress._open_construction(data)
	var shown = saved.get("tutorial_shown")
	if shown is Array:
		for hint_id in data.tutorial_hint_ids():
			if hint_id in shown:
				progress.show_tutorial_hint(hint_id)
	else:
		var mark_hint_shown = saved.get("mark_hint_shown")  # M6.1–M13.2: the battle hint about the target mark
		progress._migrate_tutorial(data, mark_hint_shown is bool and mark_hint_shown)
	return progress


static func _to_int(value, fallback: int) -> int:
	return int(value) if (value is int or value is float) else fallback
