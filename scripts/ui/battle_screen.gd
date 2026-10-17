## Battle screen: shows the stage battle (scripts/battle) and passes taps to it.
## The squad from the formation fights the stage picked on the chapter map; a win pays the reward
## (less for a replay) and may bring a new hero; «Отступить» ends the battle as a defeat.
## A beast pack picked on the map (GameState.selected_pack) is one wave at the strength of the last stage won;
## a win pays the pack reward and sends the pack away for a while, a defeat or a retreat leaves it on the map.
## Tapping an enemy marks it as the target (tap again to remove the mark). The player's first battle shows a hint
## about it, once per game (Progress.mark_hint_shown), until the first mark or for balance.json → mark_hint.seconds.
## Progress is saved after every stage.
## Saga scenes: a hero's scene right after their «Новый герой» window is closed; the boss's last scene after «Победа!»
## (on the way to the map). Both are queued by the first win (Progress.apply_victory).
extends Control

const StageBattle := preload("res://scripts/battle/stage_battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")
const FighterView := preload("res://scripts/ui/fighter_view.gd")
const HeroCard := preload("res://scripts/ui/hero_card.gd")
const Art := preload("res://scripts/ui/art.gd")
const HeroesScreen := preload("res://scripts/ui/heroes_screen.gd")
const StoryPlayer := preload("res://scripts/ui/story_player.gd")

const MAP_SCENE := "res://scenes/map.tscn"

## Top of each battlefield row, as a share of the field height (top to bottom).
const ROW_TOP := {"enemy_back": 0.03, "enemy_front": 0.27, "hero_front": 0.53, "hero_back": 0.77}
const ROW_GAP := 24.0
const MAX_ART_SIZE := 190.0  ## picture side of a normal fighter on a tall phone screen
const ROW_PADDING := 6.0  ## free space between a row's fighters and the next row
const MAX_ROW_SIZE := 3  ## most fighters in one row (enemy front row; the hero back row)

const DAMAGE_TO_ENEMY_COLOR := Color.WHITE
const DAMAGE_TO_HERO_COLOR := Color("#ff6b6b")
const ULTIMATE_COLOR := Color("#ffd84a")
const SPECIAL_COLOR := Color("#ff9a3c")
const HEAL_COLOR := Color("#6bff8a")
const POPUP_STACK_STEP := 36.0
const NEW_HERO_PORTRAIT_SIZE := 260.0
const MARK_HINT_TEXT := "Нажми на врага, чтобы отряд бил его первым"

var _battle
var _stage_id := 1
var _pack_id := ""  ## the beast pack being fought; "" = a stage
var _speed := 1
var _views := {}  ## unit id -> FighterView (enemy ids are reused by every wave)
var _popups_this_frame := {}  ## unit id -> popups already shown this frame (stacked, not overlapped)
var _cards := {}  ## unit id -> HeroCard
var _new_heroes: Array[String] = []  ## heroes still to announce after a win
var _announced_hero := ""  ## the hero in the «Новый герой» window
var _mark_hint: PanelContainer  ## null unless the hint is on screen


func _ready() -> void:
	var data = GameState.data
	var progress = GameState.progress
	if GameState.selected_pack != "" and progress.is_pack_available(data, GameState.selected_pack, GameState.now()):
		_pack_id = GameState.selected_pack
		_battle = StageBattle.from_pack(data, _pack_id, progress.pack_stage(), progress.squad(data), randi())
	else:
		_stage_id = GameState.selected_stage if progress.is_stage_open(data, GameState.selected_stage) else progress.next_stage_id(data)
		_battle = StageBattle.from_data(data, _stage_id, progress.squad(data), randi())
	var active: Array[String] = []
	for synergy in data.clan_synergies(progress.squad_ids()):
		if synergy["active"]:
			active.append("%s: %s" % [synergy["name"], synergy["description"]])
	%SynergyLabel.text = " · ".join(PackedStringArray(active))
	%SynergyLabel.visible = not active.is_empty()

	for hero in _battle.heroes():
		_add_view(hero)
		var card := HeroCard.new(hero)
		card.pressed.connect(_on_card_pressed.bind(hero.id))
		%Cards.add_child(card)
		_cards[hero.id] = card
	_show_wave()

	%AutoButton.toggled.connect(_on_auto_toggled)
	%SpeedButton.pressed.connect(_on_speed_pressed)
	%RetreatButton.pressed.connect(_battle.retreat)
	%MenuButton.pressed.connect(_on_to_map_pressed)
	%NewHeroButton.pressed.connect(_on_new_hero_closed)
	%Field.resized.connect(_layout_fighters)
	if not progress.mark_hint_shown:
		_show_mark_hint()
	_refresh()


func _process(delta: float) -> void:
	_popups_this_frame.clear()
	_battle.advance(delta * _speed)
	for event in _battle.take_events():
		_show_event(event)
	_refresh()


func _on_card_pressed(unit_id: int) -> void:
	_battle.use_ultimate(unit_id)


func _on_auto_toggled(enabled: bool) -> void:
	_battle.auto_ultimates = enabled
	%AutoButton.text = "Авто: вкл" if enabled else "Авто: выкл"


func _on_speed_pressed() -> void:
	_speed = 2 if _speed == 1 else 1
	%SpeedButton.text = "x%d" % _speed


func _refresh() -> void:
	%RetreatButton.disabled = _battle.finished
	for unit in _battle.units:
		_views[unit.id].refresh(unit, unit.id == _battle.marked_target_id)
		if _cards.has(unit.id):
			_cards[unit.id].refresh(unit, _battle.can_use_ultimate(unit.id))


func _add_view(unit) -> void:
	var view: FighterView
	var visual: Dictionary = GameState.data.visual
	var show_name: bool = GameState.settings.show_names_in_battle
	if unit.team == BattleUnit.Team.HEROES:
		view = FighterView.new(unit, Art.hero_picture(unit.def_id), 1.0, visual, show_name)
	else:
		var enemy: Dictionary = GameState.data.get_enemy(unit.def_id)
		view = FighterView.new(unit, Art.enemy_picture(unit.def_id), float(enemy["art_scale"]), visual, show_name)
		view.tapped.connect(_battle.toggle_mark.bind(unit.id))
	%Field.add_child(view)
	_views[unit.id] = view


## Replaces the enemy views with the current wave's enemies.
func _show_wave() -> void:
	for unit_id in _views.keys():
		if not _cards.has(unit_id):
			_views[unit_id].queue_free()
			_views.erase(unit_id)
	for enemy in _battle.enemies():
		_add_view(enemy)
	if _pack_id != "":
		%StageLabel.text = GameState.data.get_pack(_pack_id)["name"]
	else:
		%StageLabel.text = "Этап %d · Волна %d/%d" % [_stage_id, _battle.wave_index + 1, _battle.wave_count]
	if _pack_id == "" and GameState.progress.is_replay(_stage_id):
		%StageLabel.text += " · повтор"
	_layout_fighters()


## Pictures as big as the field allows: a normal fighter fits between its row's top and the next row,
## and a full row fits across. A bigger fighter (the boss) stands on the same ground line and grows upwards.
func _layout_fighters() -> void:
	var field_size: Vector2 = %Field.size
	var tops: Array = ROW_TOP.values()
	tops.sort()
	tops.append(1.0)
	var row_height := INF
	for i in tops.size() - 1:
		row_height = minf(row_height, (tops[i + 1] - tops[i]) * field_size.y - ROW_PADDING)
	var art_size := minf(FighterView.art_size_for(row_height), (field_size.x - (MAX_ROW_SIZE - 1) * ROW_GAP) / MAX_ROW_SIZE)
	art_size = minf(art_size, MAX_ART_SIZE)
	for view in _views.values():
		view.set_art_size(art_size)
	var rows := {}
	for unit in _battle.units:
		var key: String = ("hero_" if unit.team == BattleUnit.Team.HEROES else "enemy_") + unit.row
		if not rows.has(key):
			rows[key] = []
		rows[key].append(_views[unit.id])
	for key in rows:
		var views: Array = rows[key]
		var total_width := (views.size() - 1) * ROW_GAP
		for view in views:
			total_width += view.size.x
		var x := (field_size.x - total_width) / 2.0
		var ground: float = field_size.y * ROW_TOP[key] + FighterView.height_for(art_size)
		for view in views:
			view.position = Vector2(x, ground - view.size.y)
			x += view.size.x + ROW_GAP


func _show_event(event: Dictionary) -> void:
	match event["type"]:
		"damage":
			_animate(event["source"], "lunge")
			_animate(event["target"], "hit")
			var color := DAMAGE_TO_HERO_COLOR if event["target_is_hero"] else DAMAGE_TO_ENEMY_COLOR
			var font_size := 32
			match event["kind"]:
				"ultimate":
					color = ULTIMATE_COLOR
					font_size = 40
				"special":
					color = SPECIAL_COLOR
					font_size = 40
			_popup(event["target"], str(event["amount"]), color, font_size)
		"heal":
			_popup(event["target"], "+%d" % event["amount"], HEAL_COLOR, 32)
		"ultimate":
			_animate(event["unit"], "lunge")
			_popup(event["unit"], event["name"], ULTIMATE_COLOR, 30, 1.4)
		"special":
			_animate(event["unit"], "lunge")
			_popup(event["unit"], event["name"], SPECIAL_COLOR, 30, 1.4)
		"mark":
			if event["unit"] >= 0:
				_hide_mark_hint()
		"wave":
			_show_wave()
			_banner("Волна %d" % (event["index"] + 1))
		"end":
			_finish_stage(event["victory"], event.get("retreat", false))


## Calls the fighter view's animation ("lunge" or "hit") if the fighter is on screen.
func _animate(unit_id: int, animation: String) -> void:
	if _views.has(unit_id):
		_views[unit_id].call(animation)


## Floating text that rises above a fighter and fades out.
func _popup(unit_id: int, text_value: String, color: Color, font_size: int, duration := 0.9) -> void:
	if not _views.has(unit_id):
		return
	var label := _make_floating_label(text_value, color, font_size)
	var origin: Vector2 = _views[unit_id].popup_origin()
	var stacked: int = _popups_this_frame.get(unit_id, 0)
	_popups_this_frame[unit_id] = stacked + 1
	origin.y -= stacked * POPUP_STACK_STEP  # e.g. three Fury strikes in one frame
	origin.x += randf_range(-16.0, 16.0)  # cosmetic jitter for hits in consecutive frames
	label.position = origin - label.size / 2.0
	_float_away(label, duration)


## Large text in the middle of the battlefield (e.g. "Волна 2").
func _banner(text_value: String) -> void:
	var label := _make_floating_label(text_value, Color.WHITE, 56)
	label.position = %Field.size / 2.0 - label.size / 2.0
	_float_away(label, 1.6)


func _make_floating_label(text_value: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Field.add_child(label)
	label.reset_size()
	return label


func _float_away(label: Label, duration: float) -> void:
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 80.0, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


## Shown once per game; the flag is saved at once, so leaving the battle early does not bring it back.
## Real seconds: the hint stays as long at x2.
func _show_mark_hint() -> void:
	GameState.progress.mark_hint_shown = true
	GameState.save()
	_mark_hint = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_color = FighterView.MARK_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	_mark_hint.add_theme_stylebox_override("panel", style)
	_mark_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var label := Label.new()
	label.text = MARK_HINT_TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", FighterView.MARK_COLOR)
	_mark_hint.add_child(label)
	%Field.add_child(_mark_hint)
	get_tree().create_timer(float(GameState.data.balance["mark_hint"]["seconds"])).timeout.connect(_hide_mark_hint)


func _hide_mark_hint() -> void:
	if _mark_hint != null:
		_mark_hint.queue_free()
		_mark_hint = null


## A retreat counts as a defeat; only the title and the hint's first line differ.
func _finish_stage(victory: bool, retreat: bool) -> void:
	_hide_mark_hint()
	var progress = GameState.progress
	if victory and _pack_id != "":
		var pack_reward: Dictionary = progress.apply_pack_victory(GameState.data, _pack_id, GameState.now())
		%ResultTitle.text = "Победа!"
		%ResultHint.text = "+%d серебра · +%d опыта\nСтая вернётся через %s" % [
			int(pack_reward["silver"]), int(pack_reward["experience"]), _hours_text(GameState.data.pack_respawn_seconds())]
	elif victory:
		var reward: Dictionary = progress.apply_victory(GameState.data, _stage_id)
		%ResultTitle.text = "Победа!"
		%ResultHint.text = "+%d серебра · +%d опыта" % [int(reward["silver"]), int(reward["experience"])]
		if reward["replay"]:
			%ResultHint.text += "\nПовтор: %d%% награды" % roundi(float(GameState.data.balance["replay_reward_share"]) * 100)
		_new_heroes = reward["new_heroes"]
	else:
		%ResultTitle.text = "Дружина отступила" if retreat else "Дружина пала"
		%ResultHint.text = "Подсказка: прокачай героев или поменяй расстановку отряда."
		if retreat:
			%ResultHint.text = "Бой засчитан поражением.\n" + %ResultHint.text
	GameState.save()
	%ResultOverlay.visible = true
	_show_next_new_hero()


## «2 ч», «1 ч 30 мин», «45 мин».
static func _hours_text(seconds: int) -> String:
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	if hours > 0 and minutes > 0:
		return "%d ч %d мин" % [hours, minutes]
	return "%d ч" % hours if hours > 0 else "%d мин" % minutes


## «На карту»: the boss's last scene first, after the first win over him.
func _on_to_map_pressed() -> void:
	var progress = GameState.progress
	var scene_id: String = "" if _pack_id != "" else progress.queued_scene(GameState.data, "first_victory", _stage_id)
	if scene_id != "":
		StoryPlayer.play(self, scene_id).finished.connect(_go_to_map, CONNECT_DEFERRED)
	else:
		_go_to_map()


func _go_to_map() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


## «Отлично!»: the window closes, the hero's saga scene plays (if it has not been seen), then the next new hero.
func _on_new_hero_closed() -> void:
	%NewHeroOverlay.visible = false
	var scene_id: String = GameState.progress.queued_scene(GameState.data, "hero_joined", _announced_hero)
	if scene_id != "":
		StoryPlayer.play(self, scene_id).finished.connect(_show_next_new_hero, CONNECT_DEFERRED)
	else:
		_show_next_new_hero()


## «Новый герой присоединился к дружине» for each hero this win unlocked, one after another.
func _show_next_new_hero() -> void:
	if _new_heroes.is_empty():
		%NewHeroOverlay.visible = false
		_announced_hero = ""
		return
	var data = GameState.data
	var hero_id: String = _new_heroes.pop_front()
	_announced_hero = hero_id
	var hero: Dictionary = data.get_hero(hero_id)
	var hero_class: Dictionary = data.get_hero_class(hero)
	for old in %NewHeroPortrait.get_children():
		old.queue_free()
	%NewHeroPortrait.add_child(HeroesScreen.make_portrait(hero, NEW_HERO_PORTRAIT_SIZE))
	%NewHeroName.text = hero["name"]
	var where := "Уже в отряде." if GameState.progress.is_in_formation(hero_id) else "Поставь в отряд на экране «Отряд»."
	%NewHeroInfo.text = "%s · %s · род %s\nУльта: %s\n%s" % [
		hero_class["name"], hero_class["role_short"], data.heroes["clans"][hero["clan"]]["name"],
		hero["ultimate"]["name"], where]
	%NewHeroOverlay.visible = true
