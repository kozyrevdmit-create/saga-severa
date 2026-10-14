## Battle screen: shows the battle logic (scripts/battle) and passes taps to it.
## M2: the starting squad fights the first wave of stage 1.
extends Control

const GameData := preload("res://scripts/data/game_data.gd")
const Battle := preload("res://scripts/battle/battle.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")
const FighterView := preload("res://scripts/ui/fighter_view.gd")
const HeroCard := preload("res://scripts/ui/hero_card.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const STAGE_ID := 1
const WAVE_INDEX := 0

## Top of each battlefield row, as a share of the field height (top to bottom).
const ROW_TOP := {"enemy_back": 0.03, "enemy_front": 0.27, "hero_front": 0.53, "hero_back": 0.77}
const ROW_GAP := 24.0

const DAMAGE_TO_ENEMY_COLOR := Color.WHITE
const DAMAGE_TO_HERO_COLOR := Color("#ff6b6b")
const ULTIMATE_COLOR := Color("#ffd84a")
const HEAL_COLOR := Color("#6bff8a")
const POPUP_STACK_STEP := 36.0

var _battle
var _max_energy := 1
var _speed := 1
var _views := {}  ## unit id -> FighterView
var _popups_this_frame := {}  ## unit id -> popups already shown this frame (stacked, not overlapped)
var _cards := {}  ## unit id -> HeroCard


func _ready() -> void:
	var data = GameData.load_all()
	var stage: Dictionary = data.get_stage(STAGE_ID)
	_battle = Battle.from_data(data, data.starting_hero_ids(), stage["waves"][WAVE_INDEX], randi())
	_max_energy = int(data.balance["energy"]["max"])
	%StageLabel.text = "Этап %d · Волна %d" % [STAGE_ID, WAVE_INDEX + 1]

	for unit in _battle.units:
		var view := FighterView.new(unit, unit.has_ultimate())
		%Field.add_child(view)
		_views[unit.id] = view
	for hero in _battle.heroes():
		var card := HeroCard.new(hero)
		card.pressed.connect(_on_card_pressed.bind(hero.id))
		%Cards.add_child(card)
		_cards[hero.id] = card

	%AutoButton.toggled.connect(_on_auto_toggled)
	%SpeedButton.pressed.connect(_on_speed_pressed)
	%MenuButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%Field.resized.connect(_layout_fighters)
	_layout_fighters()
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
	for unit in _battle.units:
		_views[unit.id].refresh(unit, _max_energy)
		if _cards.has(unit.id):
			_cards[unit.id].refresh(unit, _max_energy, _battle.can_use_ultimate(unit.id))


func _layout_fighters() -> void:
	var field_size: Vector2 = %Field.size
	var rows := {}
	for unit in _battle.units:
		var key: String = ("hero_" if unit.team == BattleUnit.Team.HEROES else "enemy_") + unit.row
		if not rows.has(key):
			rows[key] = []
		rows[key].append(_views[unit.id])
	for key in rows:
		var views: Array = rows[key]
		var total_width := views.size() * FighterView.WIDTH + (views.size() - 1) * ROW_GAP
		var x := (field_size.x - total_width) / 2.0
		for view in views:
			view.position = Vector2(x, field_size.y * ROW_TOP[key])
			x += FighterView.WIDTH + ROW_GAP


func _show_event(event: Dictionary) -> void:
	match event["type"]:
		"damage":
			var target = _battle.units[event["target"]]
			var color := DAMAGE_TO_HERO_COLOR if target.team == BattleUnit.Team.HEROES else DAMAGE_TO_ENEMY_COLOR
			if event["ultimate"]:
				color = ULTIMATE_COLOR
			_popup(event["target"], str(event["amount"]), color, 40 if event["ultimate"] else 32)
		"heal":
			_popup(event["target"], "+%d" % event["amount"], HEAL_COLOR, 32)
		"ultimate":
			_popup(event["unit"], event["name"], ULTIMATE_COLOR, 30, 1.4)
		"end":
			_show_result(event["victory"])


## Floating text that rises above a fighter and fades out.
func _popup(unit_id: int, text_value: String, color: Color, font_size: int, duration := 0.9) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Field.add_child(label)
	label.reset_size()
	var origin: Vector2 = _views[unit_id].popup_origin()
	var stacked: int = _popups_this_frame.get(unit_id, 0)
	_popups_this_frame[unit_id] = stacked + 1
	origin.y -= stacked * POPUP_STACK_STEP  # e.g. three Fury strikes in one frame
	origin.x += randf_range(-16.0, 16.0)  # cosmetic jitter for hits in consecutive frames
	label.position = origin - label.size / 2.0
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 80.0, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func _show_result(victory: bool) -> void:
	%ResultTitle.text = "Победа!" if victory else "Дружина пала"
	%ResultHint.text = "" if victory else "Подсказка: прокачай героев или поменяй расстановку отряда."
	%ResultHint.visible = not victory
	%ResultOverlay.visible = true
