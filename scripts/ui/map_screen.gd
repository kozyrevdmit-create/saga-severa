## Chapter map: the chapter's painted map (stages.json → chapters[].map) fills the screen height, the sides that do
## not fit are cut off. The map opens on the current chapter (the one with the next stage to win); the arrows in the
## top bar switch to the previous or the next chapter («‹ Глава 2 · Ётунхейм ›»), an arrow to a chapter not open yet
## is dimmed and does not react. Stage numbers go on from chapter to chapter (chapter 2 is stages 11–20). The stages stand on the trail from the bottom up (stages.json → stages[].map_point: x, y as
## shares of the picture, the side of the caption). Won stages are marked and can be replayed, the next stage is
## highlighted, later ones are locked; the last stage shows the boss. Each caption shows the stage's
## «Рекомендуемая сила», in red while the squad is weaker than that; the squad's «Сила» is in the top bar.
## Beast packs (packs.json) stand off the trail: a beast's portrait while the pack can be fought, «через 1:24» while
## a beaten pack is away (it comes back by itself, the screen follows the clock), dimmed until it is unlocked.
## The top bar and the «Назад» button lie on a see-through paper strip so they read over the picture.
## The first tap on the boss stage (not won yet) plays the saga scene before the battle (story.json →
## before_first_battle), once per game; so does the first tap on a stage or a pack where the carrion eagles fight
## (before_battle_with); the battle starts right after them. The first time a chapter's map is shown, its scene
## plays over it (chapter_map: Jotunheim's, also for a save that had won chapter 1 before chapter 2 came out).
## M13: at the end of Svartalfheim's scene («ch3_intro») Regin joins: the «Новый герой» window, then the map again
## (the squad's power may have grown).
## M13.1 (playtest): on every phone the boss's crown is seen whole, every caption stays off its circle (and the crown),
## and the chapter's camp at the bottom of the picture (stages.json → chapters[].map_camp_bottom, the lowest point of
## the camp as a share of the picture's height) stays above the «Назад» button. Where the screen is too short for
## that with the map at the full screen height, the map is made a little smaller and shifted (_layout); what is left
## of the screen under the paper bars is paper.
extends Control

const Art := preload("res://scripts/ui/art.gd")
const StoryPlayer := preload("res://scripts/ui/story_player.gd")
const NewHeroWindow := preload("res://scripts/ui/new_hero_window.gd")

const BATTLE_SCENE := "res://scenes/battle.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

const STAGE_SIZE := 84.0  ## stage circle at the map's own scale (≈ 1 screen pixel per map pixel on an iPhone)
const BOSS_SIZE := 100.0
const PACK_SIZE := 96.0
const CAPTION_GAP := 14.0  ## between a caption and its circle, so that the pulsing circle never touches the caption
const MAP_EDGE_GAP := 8.0  ## between the paper bars and what must be seen whole (the crown, captions, the camp)
const MIN_MARKER_SCALE := 0.75  ## markers shrink with the map on a short screen, but stay readable
const MIN_TAP_HEIGHT := 96.0  ## spec: buttons at least 96 px tall on the screen, whatever the markers' scale
const MAX_MARKER_SCALE := 1.1
const CAPTION_FONT_SIZE := 20
const NUMBER_FONT_SIZE := 38
const CURRENT_PULSE_SCALE := 1.08
const CURRENT_PULSE_SECONDS := 0.7

const INK := Color("#1a1a1a")
const PAPER := Color("#efe3c8")
const CAPTION_PAPER := Color(0.937, 0.89, 0.784, 0.9)
const CLEARED_COLOR := Color("#3f6a96")  ## the map's cold blue
const CURRENT_COLOR := Color("#b5442c")  ## the map's rust red
const CURRENT_BORDER := Color("#ffe27a")
const LOCKED_COLOR := Color(0.102, 0.102, 0.102, 0.85)
const BOSS_LOCKED_COLOR := Color("#4a1a14")
const TOO_WEAK_COLOR := Color("#c81e1e")  ## a red that reads on the paper caption
const CROWN_COLOR := Color("#e8c547")
const ARROW_SIZE := 96.0  ## spec: buttons at least 96 px
const ARROW_LOCKED_ALPHA := 0.3


## Boss icon: a crown over the last stage.
class CrownIcon extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var crown := PackedVector2Array([
			Vector2(0, h), Vector2(0, h * 0.3), Vector2(w * 0.25, h * 0.6), Vector2(w * 0.5, 0),
			Vector2(w * 0.75, h * 0.6), Vector2(w, h * 0.3), Vector2(w, h)])
		draw_colored_polygon(crown, CROWN_COLOR)
		crown.append(crown[0])
		draw_polyline(crown, INK, 3.0, true)


## «‹» / «›» in the top bar, drawn (the game's font has no arrows). Dimmed while the chapter it leads to is closed.
class ChapterArrow extends Button:
	var points_left := true

	func _init(left: bool) -> void:
		points_left = left
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(ARROW_SIZE, ARROW_SIZE)
		for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state_name, StyleBoxEmpty.new())

	func _draw() -> void:
		var c := size / 2.0
		var w := size.x * 0.16
		var h := size.y * 0.26
		var tip := c + Vector2(-w if points_left else w, 0)
		var back := c + Vector2(w if points_left else -w, 0)
		var chevron := PackedVector2Array([Vector2(back.x, c.y - h), tip, Vector2(back.x, c.y + h)])
		draw_polyline(chevron, Color(INK, ARROW_LOCKED_ALPHA if disabled else 1.0), 9.0, true)


var _chapter := 0  ## the chapter on the map now
var _map_size := Vector2.ONE  ## the map picture's own size
var _markers: Array[Dictionary] = []  ## {button, token, caption, side, point (shares of the picture)[, crown]}
var _stage_buttons := {}  ## stage id -> Button
var _pack_markers := {}  ## pack id -> its marker plus {status: Label, state: "ready" / "away" / "locked"}
var _map_origin := Vector2.ZERO  ## where the map picture's corner is on the screen
var _map_shown := Vector2.ONE  ## the map picture's size on the screen
var _marker_scale := 1.0
var _camp_bottom := 1.0  ## the chapter's camp reaches down to this share of the picture's height
var _clock := Timer.new()
var _previous_arrow := ChapterArrow.new(true)
var _next_arrow := ChapterArrow.new(false)
var _story: Control  ## the saga scene on screen, if any
var _new_hero_window: Control  ## «Новый герой» after a chapter's scene, if on screen


func _ready() -> void:
	var data = GameState.data
	var progress = GameState.progress
	%ChapterRow.add_child(_previous_arrow)
	%ChapterRow.move_child(_previous_arrow, 0)
	%ChapterRow.add_child(_next_arrow)
	_previous_arrow.pressed.connect(func(): show_chapter(_chapter - 1))
	_next_arrow.pressed.connect(func(): show_chapter(_chapter + 1))
	%BackButton.pressed.connect(func(): get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%Board.resized.connect(_layout)
	%TopBar.resized.connect(_layout)
	%BottomBar.resized.connect(_layout)
	_clock.wait_time = 1.0
	_clock.timeout.connect(_refresh_packs)
	add_child(_clock)
	_clock.start()
	show_chapter(progress.current_chapter(data))


## Puts the chapter's map, stages and packs on the board (only an open chapter); its scene plays the first time.
func show_chapter(chapter_id: int) -> void:
	var data = GameState.data
	var progress = GameState.progress
	if not chapter_id in data.chapter_ids() or not progress.is_chapter_open(data, chapter_id):
		return
	_chapter = chapter_id
	%PowerLabel.text = "Сила отряда: %d" % progress.squad_power(data)
	for marker in _markers:
		marker["button"].queue_free()
	_markers.clear()
	_stage_buttons.clear()
	_pack_markers.clear()
	var chapter: Dictionary = data.get_chapter(chapter_id)
	%Title.text = "Глава %d · %s" % [chapter_id, chapter["name"]]
	%MapPicture.texture = Art.map_picture(chapter["map"])
	_map_size = %MapPicture.texture.get_size()
	_camp_bottom = float(chapter["map_camp_bottom"])
	for stage_id in data.chapter_stage_ids(chapter_id):
		_add_stage(stage_id)
	for pack_id in data.pack_ids(chapter_id):
		_add_pack(pack_id)
	_refresh_arrows()
	_layout()
	var scene_id: String = progress.scene_on_chapter_map(data, chapter_id)
	if scene_id != "" and not is_instance_valid(_story):
		_story = StoryPlayer.play(self, scene_id)
		_story.finished.connect(_on_chapter_scene_finished.bind(scene_id), CONNECT_DEFERRED)


## The heroes who join at the end of the chapter's scene (Regin) join now and are announced; the map is laid out again.
func _on_chapter_scene_finished(scene_id: String) -> void:
	var joined: Array[String] = GameState.progress.join_heroes_after_scene(GameState.data, scene_id)
	if joined.is_empty():
		return
	GameState.save()
	_new_hero_window = NewHeroWindow.open(self, joined)
	_new_hero_window.closed.connect(func(): show_chapter(_chapter), CONNECT_DEFERRED)


func shown_chapter() -> int:
	return _chapter


## An arrow is hidden where there is no chapter at all and dimmed (not tappable) where the chapter is not open yet.
func _refresh_arrows() -> void:
	var data = GameState.data
	for arrow in [_previous_arrow, _next_arrow]:
		var target: int = _chapter + (-1 if arrow == _previous_arrow else 1)
		var exists: bool = target in data.chapter_ids()
		arrow.modulate.a = 1.0 if exists else 0.0
		arrow.disabled = not exists or not GameState.progress.is_chapter_open(data, target)
		arrow.queue_redraw()


# --- stages -------------------------------------------------------------------

func _add_stage(stage_id: int) -> void:
	var data = GameState.data
	var progress = GameState.progress
	var is_boss: bool = data.is_boss_stage(stage_id)
	var cleared: bool = progress.is_replay(stage_id)
	var open: bool = progress.is_stage_open(data, stage_id)
	var current := open and not cleared
	var side: float = BOSS_SIZE if is_boss else STAGE_SIZE

	var color := LOCKED_COLOR
	var state := ""
	if cleared:
		color = CLEARED_COLOR
		state = "пройден"
	elif open:
		color = CURRENT_COLOR
		state = "в бой!"
	elif is_boss:
		color = BOSS_LOCKED_COLOR
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(roundi(side / 2.0))
	style.set_border_width_all(6 if current else 3)
	style.border_color = CURRENT_BORDER if current else (PAPER if open else PAPER.darkened(0.45))
	var token := _make_token(Vector2(side, side), style)
	var number := _make_label(str(stage_id), NUMBER_FONT_SIZE, PAPER if open else PAPER.darkened(0.35))
	number.add_theme_constant_override("outline_size", 6)
	number.add_theme_color_override("font_outline_color", INK)
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	token.add_child(number)
	if current:
		_pulse(token)

	var lines: Array[Control] = [_make_label("Этап %d · %s" % [stage_id, state] if state != "" else "Этап %d" % stage_id,
			CAPTION_FONT_SIZE, INK)]
	if is_boss:
		lines.append(_make_label(data.get_enemy(data.get_stage(stage_id)["waves"].back()[0])["name"], CAPTION_FONT_SIZE, INK))
	var power := HBoxContainer.new()
	power.add_theme_constant_override("separation", 0)
	power.alignment = BoxContainer.ALIGNMENT_CENTER
	power.add_child(_make_label("Рек. сила ", CAPTION_FONT_SIZE, INK))
	var weak: bool = progress.is_below_recommended(data, stage_id)
	var power_number := _make_label(str(data.recommended_power(stage_id)), CAPTION_FONT_SIZE, TOO_WEAK_COLOR if weak else INK)
	power_number.name = "RecommendedPower"
	power.add_child(power_number)
	lines.append(power)

	var point: Dictionary = data.get_stage(stage_id)["map_point"]
	var marker := _make_marker(token, _make_caption(lines), point["label"], point)
	var button: Button = marker["button"]
	if is_boss:
		var crown := CrownIcon.new()
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crown.size = Vector2(56, 42)
		crown.position = Vector2((side - crown.size.x) / 2.0, -crown.size.y + 8.0)
		token.add_child(crown)
		token.move_child(crown, 0)
		marker["crown"] = crown
	button.disabled = not open
	button.pressed.connect(_on_stage_pressed.bind(stage_id))
	_stage_buttons[stage_id] = button


func _on_stage_pressed(stage_id: int) -> void:
	GameState.selected_stage = stage_id
	GameState.selected_pack = ""
	_play_then_battle(GameState.progress.scenes_before_battle(GameState.data, stage_id))


## The scenes due before this battle one after another, then the battle.
func _play_then_battle(scene_ids: Array[String]) -> void:
	if scene_ids.is_empty():
		_start_battle()
		return
	var scene_id: String = scene_ids.pop_front()
	_story = StoryPlayer.play(self, scene_id)
	_story.finished.connect(_play_then_battle.bind(scene_ids), CONNECT_DEFERRED)


func _start_battle() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


# --- beast packs --------------------------------------------------------------

func _add_pack(pack_id: String) -> void:
	var data = GameState.data
	var pack: Dictionary = data.get_pack(pack_id)
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	style.border_color = INK
	var token := _make_token(Vector2(PACK_SIZE, PACK_SIZE), style)
	var portrait := TextureRect.new()
	portrait.texture = Art.enemy_portrait(data.get_enemy(pack["icon"]))
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	token.add_child(portrait)

	var name_label := _make_label(pack["name"], CAPTION_FONT_SIZE, INK)
	var status := _make_label("", CAPTION_FONT_SIZE, INK)
	status.name = "Status"
	var marker := _make_marker(token, _make_caption([name_label, status]), "below", pack["map_point"])
	marker["button"].pressed.connect(_on_pack_pressed.bind(pack_id))
	marker["status"] = status
	marker["state"] = ""
	_pack_markers[pack_id] = marker
	_refresh_pack(pack_id)


func _on_pack_pressed(pack_id: String) -> void:
	if not GameState.progress.is_pack_available(GameState.data, pack_id, GameState.now()):
		_refresh_packs()
		return
	GameState.selected_pack = pack_id
	_play_then_battle(GameState.progress.scenes_before_battle(GameState.data, 0, pack_id))


func _refresh_packs() -> void:
	GameState.progress.update_pack_timers(GameState.data, GameState.now())
	for pack_id in _pack_markers:
		_refresh_pack(pack_id)


## Three looks: on the map (portrait, tappable), away («через 1:24» where the pack stood, no portrait),
## locked (dimmed portrait, «после этапа N»).
func _refresh_pack(pack_id: String) -> void:
	var data = GameState.data
	var progress = GameState.progress
	var marker: Dictionary = _pack_markers[pack_id]
	var button: Button = marker["button"]
	var status: Label = marker["status"]
	var seconds_left: int = progress.pack_seconds_left(data, pack_id, GameState.now())
	var state := "ready"
	if not progress.is_pack_unlocked(data, pack_id):
		state = "locked"
		status.text = "после этапа %d" % int(data.get_pack(pack_id)["unlock_after_stage"])
	elif seconds_left > 0:
		state = "away"
		status.text = "через %s" % clock_text(seconds_left)
	else:
		status.text = "в бой!"
	button.disabled = state != "ready"
	marker["token"].modulate = Color(1, 1, 1, 0.55) if state == "locked" else Color.WHITE  # the caption stays readable
	marker["token"].visible = state != "away"
	marker["side"] = "center" if state == "away" else "below"
	marker["state"] = state
	_arrange(marker)
	_place(marker)


## «1:24» — hours and minutes left, rounded up (59 seconds left is «0:01», not «0:00»).
static func clock_text(seconds: int) -> String:
	var minutes := ceili(seconds / 60.0)
	return "%d:%02d" % [minutes / 60, minutes % 60]


# --- markers ------------------------------------------------------------------

func _make_token(token_size: Vector2, style: StyleBoxFlat) -> Panel:
	var token := Panel.new()
	token.add_theme_stylebox_override("panel", style)
	token.size = token_size
	token.pivot_offset = token_size / 2.0
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return token


func _make_caption(lines: Array[Control]) -> PanelContainer:
	var caption := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CAPTION_PAPER
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = INK
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	caption.add_theme_stylebox_override("panel", style)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for line in lines:
		box.add_child(line)
	caption.add_child(box)
	return caption


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A see-through button holding the token and its caption: a tap on either starts the battle.
## side: "left" / "right" — the caption beside the token, "below" — under it, "center" — over the token's place
## (a pack that is away). Returns the marker: {button, token, caption, side, point}.
func _make_marker(token: Panel, caption: PanelContainer, side: String, point: Dictionary) -> Dictionary:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	button.add_child(caption)
	button.add_child(token)
	%Board.add_child(button)
	var marker := {"button": button, "token": token, "caption": caption, "side": side, "point": point}
	_arrange(marker)
	_markers.append(marker)
	return marker


## Lays the token and the caption out inside the marker's button by its side. The button reaches at least
## MIN_TAP_HEIGHT on the screen (at the markers' scale): the parts are centred in a taller tap area when needed.
func _arrange(marker: Dictionary) -> void:
	var token: Control = marker["token"]
	var caption: Control = marker["caption"]
	caption.reset_size()
	var caption_size := caption.size
	var token_size := token.size
	match marker["side"]:
		"left":
			caption.position = Vector2(0, (token_size.y - caption_size.y) / 2.0)
			token.position = Vector2(caption_size.x + CAPTION_GAP, 0)
		"right":
			token.position = Vector2.ZERO
			caption.position = Vector2(token_size.x + CAPTION_GAP, (token_size.y - caption_size.y) / 2.0)
		"below":
			var width := maxf(token_size.x, caption_size.x)
			token.position = Vector2((width - token_size.x) / 2.0, 0)
			caption.position = Vector2((width - caption_size.x) / 2.0, token_size.y + CAPTION_GAP)
		_:
			var box := token_size.max(caption_size)
			token.position = (box - token_size) / 2.0
			caption.position = (box - caption_size) / 2.0
	# The caption may stand above the token's top: shift both so the button starts at 0.
	var top := minf(0.0, caption.position.y)
	caption.position.y -= top
	token.position.y -= top
	var visible_parts := Rect2(caption.position, caption_size)
	if token.visible:
		visible_parts = visible_parts.merge(Rect2(token.position, token_size))
	var pad := maxf(0.0, MIN_TAP_HEIGHT / _marker_scale - visible_parts.size.y) / 2.0
	caption.position.y += pad
	token.position.y += pad
	marker["button"].position = Vector2.ZERO
	marker["button"].size = Vector2(visible_parts.end.x, visible_parts.end.y + 2.0 * pad)


func _pulse(token: Control) -> void:
	var tween := token.create_tween().set_loops()
	tween.tween_property(token, "scale", Vector2.ONE * CURRENT_PULSE_SCALE, CURRENT_PULSE_SECONDS).set_trans(Tween.TRANS_SINE)
	tween.tween_property(token, "scale", Vector2.ONE, CURRENT_PULSE_SECONDS).set_trans(Tween.TRANS_SINE)


## The map fills the screen height (the sides that do not fit are cut off; on a screen wider than the map it fills
## the width instead) — unless then a marker (with the boss's crown) would reach under a paper bar or the camp would
## hide behind «Назад»: then the map is the biggest that keeps all of them between the bars, shifted to fit.
func _layout() -> void:
	var area: Vector2 = %Board.size
	if area.y <= 0.0:
		return
	var fill_scale := maxf(area.y / _map_size.y, area.x / _map_size.x)
	var top: float = %TopBar.get_rect().end.y + MAP_EDGE_GAP
	var bottom: float = %BottomBar.get_rect().position.y - MAP_EDGE_GAP
	var reaches: Array[Vector2] = []
	for marker in _markers:
		_arrange(marker)
		reaches.append(_reach(marker))
	var map_scale := fill_scale
	if not _fits(_origin_range(fill_scale, top, bottom, reaches)):
		var low := fill_scale * 0.25
		var high := fill_scale
		for i in 30:
			var middle := (low + high) / 2.0
			if _fits(_origin_range(middle, top, bottom, reaches)):
				low = middle
			else:
				high = middle
		map_scale = low
	var origin_range := _origin_range(map_scale, top, bottom, reaches)
	_map_shown = _map_size * map_scale
	_map_origin = (area - _map_shown) / 2.0
	_map_origin.y = clampf(_map_origin.y, origin_range.x, maxf(origin_range.x, origin_range.y))
	%MapPicture.position = _map_origin
	%MapPicture.size = _map_shown
	_marker_scale = _marker_scale_for(map_scale)
	for marker in _markers:
		_arrange(marker)
		_place(marker)


func _marker_scale_for(map_scale: float) -> float:
	return clampf(map_scale, MIN_MARKER_SCALE, MAX_MARKER_SCALE)


## Where the map's top edge may be (x: highest, y: lowest) at this scale so that every marker stays between `top`
## and `bottom` and the camp above `bottom`. Empty (x > y) when the map is too big for that.
func _origin_range(map_scale: float, top: float, bottom: float, reaches: Array[Vector2]) -> Vector2:
	var height := _map_size.y * map_scale
	var markers := _marker_scale_for(map_scale)
	var lowest := bottom - _camp_bottom * height
	var highest := -INF
	for i in _markers.size():
		var y := float(_markers[i]["point"]["y"]) * height
		highest = maxf(highest, top - y + reaches[i].x * markers)
		lowest = minf(lowest, bottom - y - reaches[i].y * markers)
	return Vector2(highest, lowest)


func _fits(origin_range: Vector2) -> bool:
	return origin_range.x <= origin_range.y


## How far the marker's drawn parts reach above (x) and below (y) its point, at the markers' own scale: the circle
## at the top of its pulse, the boss's crown, the caption. A pack counts in its biggest look (portrait, caption below)
## so that the map does not jump when the pack comes back.
func _reach(marker: Dictionary) -> Vector2:
	var token: Control = marker["token"]
	var half := token.size.y / 2.0 * CURRENT_PULSE_SCALE
	var above := half
	if marker.has("crown"):
		above = maxf(above, (token.size.y / 2.0 - marker["crown"].position.y) * CURRENT_PULSE_SCALE)
	var below := half
	var caption_height: float = marker["caption"].size.y
	var side: String = "below" if marker.has("status") else marker["side"]
	if side == "below":
		below = maxf(below, token.size.y / 2.0 + CAPTION_GAP + caption_height)
	else:
		above = maxf(above, caption_height / 2.0)
		below = maxf(below, caption_height / 2.0)
	return Vector2(above, below)


## Puts the marker so that its token's centre stands on its point of the picture.
func _place(marker: Dictionary) -> void:
	var button: Button = marker["button"]
	var token: Control = marker["token"]
	var center: Vector2 = token.position + token.size / 2.0
	button.scale = Vector2.ONE * _marker_scale
	button.position = map_point_on_screen(marker["point"]) - center * _marker_scale


## Where a point of the map picture (x, y as shares) is on the screen now.
func map_point_on_screen(point: Dictionary) -> Vector2:
	return _map_origin + Vector2(float(point["x"]), float(point["y"])) * _map_shown
