## Settlement (M12): the settlement's picture stands under the top strip and fills the height below it, like a chapter
## map, but never so large that the middle buildings.json → picture_visible_width of it does not fit the screen width
## (the plots lie near the picture's sides; on a tall phone the picture's foot hides under the bottom strip instead).
## On its five plots stand the buildings (data/buildings.json → label: the caption's point, art: where the
## building's picture stands and how wide, as shares of the picture): a building that is built shows its picture and
## «Капище · ур. 2», an empty plot «Капище · построить», a closed one a pale «Курган Тьяцци · после главы 2».
## A tap on a caption or a building opens its window: name, one line of description, level N/5, the bonus now and at
## the next level, the price in supplies and «Построить» / «Улучшить» (not active without the supplies; at the top
## level «Наибольший уровень»). Building is instant.
## Construction opens after chapter 1 (Progress.is_construction_open); until then the screen shows only the picture,
## the offline income and «Стройка откроется после главы 1». The first visit with construction open plays the saga
## scene «Зерно нового мира» (story.json → settlement), once per game.
## The offline income (spec 5.1) stays on a paper strip at the bottom, with «Забрать» while the bank holds silver.
extends Control

const Art := preload("res://scripts/ui/art.gd")
const StoryPlayer := preload("res://scripts/ui/story_player.gd")
const BattleScreen := preload("res://scripts/ui/battle_screen.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

const CAPTION_FONT_SIZE := 26
const MIN_TAP_HEIGHT := 96.0  ## spec: buttons at least 96 px tall on the screen
const MIN_MARKER_SCALE := 0.75  ## captions shrink with the picture on a short screen, but stay readable
const MAX_MARKER_SCALE := 1.1
const CAPTION_MARGIN := 6.0  ## a caption keeps this far from the screen's side
const CLOSED_ALPHA := 0.7  ## a closed plot's caption is pale

const INK := Color("#1a1a1a")
const CAPTION_PAPER := Color(0.937, 0.89, 0.784, 0.9)

var _picture_size := Vector2.ONE  ## the settlement picture's own size
var _picture_origin := Vector2.ZERO  ## where the picture's corner is on the screen
var _picture_shown := Vector2.ONE  ## the picture's size on the screen
var _marker_scale := 1.0
var _buildings := {}  ## building id -> {picture: Button (the building's picture), caption: Button, label: Label}
var _window_building := ""  ## the building in the open window; "" = no window


func _ready() -> void:
	var data = GameState.data
	%Picture.texture = Art.settlement_picture(data.buildings["picture"])
	_picture_size = %Picture.texture.get_size()
	if GameState.progress.is_construction_open(data):
		for building_id in data.building_ids():
			_add_building(building_id)
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%ClaimButton.pressed.connect(_on_claim_pressed)
	%BuildButton.pressed.connect(_on_build_pressed)
	%CloseButton.pressed.connect(close_window)
	%Window.gui_input.connect(_on_window_input)
	%Board.resized.connect(_layout)
	%TopBar.resized.connect(_layout)
	GameState.offline_bank_changed.connect(_refresh)
	_refresh()
	_layout()
	var scene_id: String = GameState.progress.scene_on_settlement(data)
	if scene_id != "":
		StoryPlayer.play(self, scene_id)


func _refresh() -> void:
	var data = GameState.data
	var progress = GameState.progress
	if progress.is_construction_open(data):
		%Counters.text = "Припасы: %d · Серебро: %d" % [progress.supplies, progress.silver]
	else:
		%Counters.text = "Стройка откроется после главы 1"
	if progress.cleared_stage == 0:
		%Income.text = "Поселение начнёт приносить серебро после первого пройденного этапа."
	else:
		var cap: int = progress.offline_income_cap(data)
		%Income.text = "Пока тебя нет в игре, поселение приносит %s серебра в минуту — до %d за %d ч." % [
			_format_rate(float(cap) / progress.offline_max_minutes(data)), cap,
			int(float(data.balance["offline_income"]["max_hours"]))]
	%ClaimButton.visible = progress.offline_bank > 0
	%ClaimButton.text = "Забрать %d серебра" % progress.offline_bank
	for building_id in _buildings:
		_refresh_building(building_id)
	if _window_building != "":
		_refresh_window()
	_layout()  # a caption's text (and width) may have changed


func _on_claim_pressed() -> void:
	GameState.claim_offline_income()
	_refresh()


# --- buildings ------------------------------------------------------------------

func _add_building(building_id: String) -> void:
	var picture := Button.new()
	_make_see_through(picture)
	var art := TextureRect.new()
	art.texture = Art.settlement_picture(building_id)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.add_child(art)
	picture.pressed.connect(open_window.bind(building_id))
	%Board.add_child(picture)

	var caption := Button.new()
	_make_see_through(caption)
	var paper := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CAPTION_PAPER
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = INK
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	paper.add_theme_stylebox_override("panel", style)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.add_theme_font_size_override("font_size", CAPTION_FONT_SIZE)
	label.add_theme_color_override("font_color", INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(label)
	caption.add_child(paper)
	caption.pressed.connect(open_window.bind(building_id))
	%Board.add_child(caption)
	_buildings[building_id] = {"picture": picture, "caption": caption, "paper": paper, "label": label}


## Captions go over every picture: a building's picture never hides another one's caption.
func _sort_captions_on_top() -> void:
	for entry in _buildings.values():
		%Board.move_child(entry["caption"], -1)


func _make_see_through(button: Button) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())


## The caption and the picture of one plot by the building's state.
func _refresh_building(building_id: String) -> void:
	var data = GameState.data
	var progress = GameState.progress
	var entry: Dictionary = _buildings[building_id]
	entry["label"].text = caption_text(data, progress, building_id)
	entry["caption"].modulate.a = 1.0 if progress.is_building_open(data, building_id) else CLOSED_ALPHA
	entry["picture"].visible = progress.building_level(building_id) > 0


## «Капище · ур. 2», «Капище · построить», «Курган Тьяцци · после главы 2».
static func caption_text(data, progress, building_id: String) -> String:
	var building: Dictionary = data.get_building(building_id)
	if not progress.is_building_open(data, building_id):
		return "%s · после главы %d" % [building["name"], int(building["opens_after_chapter"])]
	var level: int = progress.building_level(building_id)
	return "%s · ур. %d" % [building["name"], level] if level > 0 else "%s · построить" % building["name"]


# --- the building's window ----------------------------------------------------

func open_window(building_id: String) -> void:
	_window_building = building_id
	_refresh_window()
	%Window.visible = true


func close_window() -> void:
	_window_building = ""
	%Window.visible = false


## A tap on the dark area around the window closes it.
func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		close_window()


func _on_build_pressed() -> void:
	if GameState.progress.build(GameState.data, _window_building):
		GameState.save()
	_refresh()


func _refresh_window() -> void:
	var data = GameState.data
	var progress = GameState.progress
	var building_id := _window_building
	var building: Dictionary = data.get_building(building_id)
	var level: int = progress.building_level(building_id)
	var max_level: int = data.building_max_level()
	var open: bool = progress.is_building_open(data, building_id)
	var top: bool = level >= max_level
	%BuildingName.text = building["name"]
	%BuildingDescription.text = building["description"]
	%BuildingLevel.text = "Уровень %d/%d" % [level, max_level]
	%BonusNow.text = "Сейчас: %s" % bonus_text(data, building_id, level) if level > 0 else "Сейчас: не построено"
	%BonusNext.visible = not top
	%BonusNext.text = "На %d-м уровне: %s" % [level + 1, bonus_text(data, building_id, level + 1)]
	%Cost.visible = open and not top
	if %Cost.visible:
		%Cost.text = "Цена: %d припасов · у тебя %d" % [progress.building_cost(data, building_id), progress.supplies]
	if not open:
		%BuildButton.text = "Откроется после главы %d" % int(building["opens_after_chapter"])
	elif top:
		%BuildButton.text = "Наибольший уровень"
	else:
		%BuildButton.text = "Построить" if level == 0 else "Улучшить"
	%BuildButton.disabled = not progress.can_build(data, building_id)


## What the building gives at `level` (≥ 1): «+4% HP всей дружине», «стаи возвращаются через 1 ч 36 мин».
static func bonus_text(data, building_id: String, level: int) -> String:
	var bonus: float = data.building_bonus(building_id, level)
	var percent := roundi(bonus * 100.0)
	match data.get_building(building_id)["bonus"]["kind"]:
		"squad_hp":
			return "+%d%% HP всей дружине" % percent
		"squad_attack":
			return "+%d%% атаки всей дружине" % percent
		"level_up_discount":
			return "прокачка героев дешевле на %d%%" % percent
		"battle_silver":
			return "+%d%% серебра за бои" % percent
		"pack_respawn":
			return "стаи возвращаются через %s" % BattleScreen.hours_text(roundi(data.pack_respawn_seconds() * (1.0 - bonus)))
	push_error("Unknown building bonus: %s" % building_id)
	return ""


# --- layout -------------------------------------------------------------------

## The picture's top is at the top strip's bottom; it fills the height below, unless its middle
## picture_visible_width would not fit the width then; it always fills the width.
func _layout() -> void:
	var area: Vector2 = %Board.size
	var top: float = %TopBar.size.y
	var visible_width := float(GameState.data.buildings["picture_visible_width"])
	var picture_scale := maxf(minf((area.y - top) / _picture_size.y, area.x / (_picture_size.x * visible_width)),
			area.x / _picture_size.x)
	_picture_shown = _picture_size * picture_scale
	_picture_origin = Vector2((area.x - _picture_shown.x) / 2.0, top)
	%Picture.position = _picture_origin
	%Picture.size = _picture_shown
	_marker_scale = clampf(picture_scale, MIN_MARKER_SCALE, MAX_MARKER_SCALE)
	var data = GameState.data
	# Lower buildings are drawn over higher ones (nearer to the viewer).
	var ids: Array = _buildings.keys()
	ids.sort_custom(func(a, b): return float(data.get_building(a)["art"]["y"]) < float(data.get_building(b)["art"]["y"]))
	for building_id in ids:
		var building: Dictionary = data.get_building(building_id)
		var entry: Dictionary = _buildings[building_id]
		var art: Dictionary = building["art"]
		var side := float(art["width"]) * _picture_shown.x
		var picture: Button = entry["picture"]
		picture.size = Vector2(side, side)
		picture.position = point_on_screen(art) - picture.size / 2.0
		%Board.move_child(picture, -1)
		_place_caption(entry, building["label"])
	_sort_captions_on_top()


## The caption's centre on its point, moved in from the screen's sides if it would stick out there; the tap area is at
## least MIN_TAP_HEIGHT tall on the screen.
func _place_caption(entry: Dictionary, point: Dictionary) -> void:
	var caption: Button = entry["caption"]
	var paper: Control = entry["paper"]
	paper.reset_size()
	var tap := Vector2(paper.size.x, maxf(paper.size.y, MIN_TAP_HEIGHT / _marker_scale))
	paper.position = Vector2(0, (tap.y - paper.size.y) / 2.0)
	caption.size = tap
	caption.scale = Vector2.ONE * _marker_scale
	caption.position = point_on_screen(point) - tap * _marker_scale / 2.0
	caption.position.x = clampf(caption.position.x, CAPTION_MARGIN, %Board.size.x - tap.x * _marker_scale - CAPTION_MARGIN)


## Where a point of the settlement picture (x, y as shares) is on the screen now.
func point_on_screen(point: Dictionary) -> Vector2:
	return _picture_origin + Vector2(float(point["x"]), float(point["y"])) * _picture_shown


func _format_rate(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
