## Fighter on the battlefield: HP/energy bars above the character's picture, the name below it.
## The battle screen sets the picture size to fit the field (set_art_size); a fighter with art_scale (the boss)
## is that much bigger. Simple tweened animation, no extra drawings: breathing while alive, a lunge towards the
## enemy on every attack (lunge), a bright flash and a small shake when hit (hit), fading out on death; a boss that
## changes form gets its new picture with a flash (change_picture); a boss burrowed into its gold (invulnerable) is darker.
## The hit feedback's colour, strength and timing come from data/visual.json; a fighter hit again soon after
## (hit_min_gap_seconds, real time, so x2 does not double it) does not flash or shake again.
extends Control

const StatBar := preload("res://scripts/ui/stat_bar.gd")
const BattleUnit := preload("res://scripts/battle/battle_unit.gd")
const HIT_FLASH_SHADER := preload("res://assets/shaders/hit_flash.gdshader")

const HP_HEIGHT := 14.0
const ENERGY_HEIGHT := 9.0
const BAR_GAP := 4.0
const BAR_INSET := 0.12  ## bars are this share of the picture narrower on each side (the picture has margins)
const NAME_HEIGHT := 24.0
const NAME_FONT_SIZE := 19
const NAME_MIN_FONT_SIZE := 13
const HP_COLOR := Color("#d8342c")
const ENERGY_COLOR := Color("#f2c230")
const MARK_COLOR := Color("#ffe27a")
const MARK_BORDER := 5.0
const MARK_OUTLINE := 3.0  ## dark edge around the yellow frame: readable on the light paper

const BREATH_SECONDS := 1.3  ## one way; a full breath is twice that
const BREATH_SCALE := Vector2(0.992, 1.025)
const LUNGE_DISTANCE := 0.14  ## share of the picture size
const LUNGE_OUT_SECONDS := 0.08
const LUNGE_BACK_SECONDS := 0.18
const DEATH_SECONDS := 0.6
const DEAD_ALPHA := 0.25
const DEATH_SINK := 0.05  ## share of the picture size the body sinks while fading
const SHADOW_COLOR := Color(0.1, 0.07, 0.03, 0.22)
const BURROWED_TINT := Color(0.5, 0.5, 0.5)  ## a boss burrowed into its gold (Fafnir, invulnerable) is darkened

signal tapped

var art_scale := 1.0
var _is_hero := true
var _alive_shown := true
var _art_size := 0.0  ## picture side before art_scale
var _pose_rest := Vector2.ZERO  ## where the picture holder stands between lunges

var _hp_bar: StatBar
var _energy_bar: StatBar
var _pose: Control  ## moves for the lunge and the death sink
var _art: TextureRect  ## scales for breathing, flashes when hit
var _name: Label
var _mark: Control  ## frame and «ЦЕЛЬ» on the enemy the player marked
var _breath: Tween
var _lunge: Tween
var _flash: Tween
var _shake: Tween
var _visual: Dictionary  ## data/visual.json
var _last_hit_msec := -1  ## real time of the last hit shown (flash and shake)


func _init(unit, picture: Texture2D, picture_scale: float, visual: Dictionary, show_name := true) -> void:
	art_scale = picture_scale
	_visual = visual
	_is_hero = unit.team == BattleUnit.Team.HEROES
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_pose = Control.new()
	_pose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pose)
	_art = TextureRect.new()
	_art.texture = picture
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = HIT_FLASH_SHADER
	material.set_shader_parameter("flash_color", Color.html(visual["hit_flash"]["color"]))
	_art.material = material
	_pose.add_child(_art)

	_hp_bar = StatBar.new(HP_COLOR, HP_HEIGHT)
	add_child(_hp_bar)
	_energy_bar = StatBar.new(ENERGY_COLOR, ENERGY_HEIGHT)
	_energy_bar.visible = unit.has_ultimate()
	add_child(_energy_bar)

	_name = Label.new()
	_name.text = unit.display_name
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_constant_override("outline_size", 6)
	_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.visible = show_name  ## «Показывать имена в бою» (Settings); the space stays, so rows do not move
	add_child(_name)

	_mark = Control.new()
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	_mark.draw.connect(_draw_mark)
	var mark_label := Label.new()
	mark_label.text = "ЦЕЛЬ"
	mark_label.position = Vector2(MARK_BORDER + 6, MARK_BORDER + 2)
	mark_label.add_theme_font_size_override("font_size", 22)
	mark_label.add_theme_color_override("font_color", MARK_COLOR)
	mark_label.add_theme_constant_override("outline_size", 8)
	mark_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_mark.add_child(mark_label)
	add_child(_mark)

	# Enemies can be tapped to mark them as the squad's target.
	if not _is_hero:
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(_on_gui_input)


func _ready() -> void:
	# Fighters do not breathe in step.
	get_tree().create_timer(randf() * BREATH_SECONDS * 2.0).timeout.connect(_start_breathing)


## Picture side for a normal fighter (the boss gets art_scale times it). Lays out the bars, picture and name.
func set_art_size(art_size: float) -> void:
	_art_size = art_size
	var side := art_size * art_scale
	var bars_height := bars_height()
	size = Vector2(side, bars_height + side + NAME_HEIGHT)
	var inset := side * BAR_INSET
	_hp_bar.position = Vector2(inset, 0)
	_hp_bar.size = Vector2(side - 2 * inset, HP_HEIGHT)
	_energy_bar.position = Vector2(inset, HP_HEIGHT + BAR_GAP)
	_energy_bar.size = Vector2(side - 2 * inset, ENERGY_HEIGHT)
	_pose_rest = Vector2(0, bars_height)
	if _lunge == null or not _lunge.is_running():
		_pose.position = _pose_rest + (Vector2(0, DEATH_SINK * side) if not _alive_shown else Vector2.ZERO)
	_pose.size = Vector2(side, side)
	_art.size = Vector2(side, side)
	_art.pivot_offset = Vector2(side / 2.0, side)  # breathe from the feet
	_mark.position = _pose_rest
	_mark.size = Vector2(side, side)
	_mark.queue_redraw()
	_name.position = Vector2(0, bars_height + side)
	_name.size = Vector2(side, NAME_HEIGHT)
	_name.add_theme_font_size_override("font_size", _fitting_font_size(_name.text, side))
	queue_redraw()


## Height of the bars above the picture (the same for heroes and enemies, so rows line up).
static func bars_height() -> float:
	return HP_HEIGHT + BAR_GAP + ENERGY_HEIGHT + BAR_GAP


## Total height of a normal fighter whose picture is art_size.
static func height_for(art_size: float) -> float:
	return bars_height() + art_size + NAME_HEIGHT


## Largest picture side whose fighter fits into the given height.
static func art_size_for(height: float) -> float:
	return height - bars_height() - NAME_HEIGHT


## battle_over: the fight has ended (a win, a defeat, «Отступить») — a boss that was burrowed into his gold at that
## moment gets his own colour back too (M13.1: darker only for the seconds he cannot be hit).
func refresh(unit, marked := false, battle_over := false) -> void:
	_mark.visible = marked and unit.is_alive()
	_pose.modulate = BURROWED_TINT if unit.is_invulnerable() and not battle_over else Color.WHITE
	_hp_bar.value = unit.hp_fraction()
	if unit.has_ultimate():
		_energy_bar.value = float(unit.energy) / unit.ultimate_cost()
	if _alive_shown and not unit.is_alive():
		_alive_shown = false
		_die()


## Quick step towards the enemy side and back (heroes stand below and face right, enemies above and face left).
func lunge() -> void:
	if not _alive_shown:
		return
	if _lunge != null:
		_lunge.kill()
	var direction := Vector2(0.35, -1.0) if _is_hero else Vector2(-0.35, 1.0)
	var target := _pose_rest + direction.normalized() * LUNGE_DISTANCE * _art_size
	_pose.position = _pose_rest
	_lunge = create_tween()
	_lunge.tween_property(_pose, "position", target, LUNGE_OUT_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_lunge.tween_property(_pose, "position", _pose_rest, LUNGE_BACK_SECONDS).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


## The fighter was hit: a bright flash and a small sideways shake, unless the last hit was shown just now
## (several fighters hitting one target at x2 would turn into flicker). Returns whether it was shown.
func hit() -> bool:
	var now := Time.get_ticks_msec()
	if _last_hit_msec >= 0 and now - _last_hit_msec < float(_visual["hit_min_gap_seconds"]) * 1000.0:
		return false
	_last_hit_msec = now
	_flash_picture()
	if _alive_shown:
		_shake_picture()
	return true


## A boss changes form (Thjazi turns into an eagle): the new picture with a flash, even right after a hit.
func change_picture(picture: Texture2D) -> void:
	_art.texture = picture
	_last_hit_msec = Time.get_ticks_msec()
	_flash_picture()


## Full strength for hold_seconds, then fades out in fade_seconds.
func _flash_picture() -> void:
	var settings: Dictionary = _visual["hit_flash"]
	if _flash != null:
		_flash.kill()
	_art.material.set_shader_parameter("flash", float(settings["strength"]))
	_flash = create_tween()
	_flash.tween_interval(float(settings["hold_seconds"]))
	_flash.tween_property(_art.material, "shader_parameter/flash", 0.0, float(settings["fade_seconds"])).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Right, left, a little right and back to rest; distance is a share of the picture size.
func _shake_picture() -> void:
	var settings: Dictionary = _visual["hit_shake"]
	var distance := float(settings["distance"]) * _art_size * art_scale
	var step := float(settings["seconds"]) / 4.0
	if _shake != null:
		_shake.kill()
	_art.position = Vector2.ZERO
	_shake = create_tween()
	for offset in [distance, -distance, distance / 2.0, 0.0]:
		_shake.tween_property(_art, "position:x", offset, step).set_trans(Tween.TRANS_SINE)


## Point over the upper body where floating numbers start (in parent coordinates).
func popup_origin() -> Vector2:
	return position + Vector2(size.x / 2.0, bars_height() + _art_size * art_scale * 0.3)


## Ground shadow under the feet (drawn below the picture).
func _draw() -> void:
	var side := _art_size * art_scale
	if side <= 0.0:
		return
	draw_set_transform(Vector2(side / 2.0, bars_height() + side * 0.95), 0.0, Vector2(1.0, 0.2))
	draw_circle(Vector2.ZERO, side * 0.34, SHADOW_COLOR)


func _draw_mark() -> void:
	var rect := Rect2(Vector2.ZERO, _mark.size).grow(-MARK_BORDER / 2.0)
	_mark.draw_rect(rect, Color.BLACK, false, MARK_BORDER + 2 * MARK_OUTLINE)
	_mark.draw_rect(rect, MARK_COLOR, false, MARK_BORDER)


func _start_breathing() -> void:
	if not _alive_shown or not is_inside_tree():
		return
	_breath = create_tween().set_loops()
	_breath.tween_property(_art, "scale", BREATH_SCALE, BREATH_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breath.tween_property(_art, "scale", Vector2.ONE, BREATH_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _die() -> void:
	if _breath != null:
		_breath.kill()
	if _lunge != null:
		_lunge.kill()
	if _shake != null:
		_shake.kill()
	_art.position = Vector2.ZERO
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", DEAD_ALPHA, DEATH_SECONDS).set_ease(Tween.EASE_IN)
	tween.tween_property(_art, "scale", Vector2.ONE, DEATH_SECONDS)
	tween.tween_property(_pose, "position", _pose_rest + Vector2(0, DEATH_SINK * _art_size * art_scale), DEATH_SECONDS)


## Touches arrive as mouse events too (touch-to-mouse emulation is on by default).
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tapped.emit()
		accept_event()


## One line, shrunk to fit: the web build does not wrap at hyphens and would split a word.
func _fitting_font_size(text_value: String, width: float) -> int:
	var font := _name.get_theme_font("font")
	var font_size := NAME_FONT_SIZE
	while font_size > NAME_MIN_FONT_SIZE and font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	return font_size
