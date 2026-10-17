## A saga scene (data/story.json) over the current screen. Lines appear letter by letter
## (visual.json → story.letters_per_second); a tap anywhere shows the whole line while it is still being typed,
## otherwise the next line. A line has one of two looks:
## «страница саги» — the whole screen is old paper (the battlefield's paper shader), both ravens on top (Hugin left,
##   Munin right; the one who speaks is bright, the other faded to story.quiet_raven_alpha), under them the speaker's
##   name and the text;
## «диалог» — a panel at the bottom with the speaker's portrait (a hero's from «Герои», a raven's head), name and text;
##   behind it the screen the scene started on, dimmed.
## «Пропустить» closes the whole scene at once. A scene with an end card (story.json → end_card) ends with the card on
## paper; a tap closes it. Start a scene with StoryPlayer.play(screen, scene_id): it counts as seen as soon as it starts.
extends Control

signal finished  ## the scene is over: watched to the end or skipped

const SCENE := "res://scenes/story.tscn"
const Art := preload("res://scripts/ui/art.gd")
const HeroesScreen := preload("res://scripts/ui/heroes_screen.gd")

const PORTRAIT_SIZE := 180.0

var scene_id := ""
var _lines: Array = []
var _end_card := ""
var _index := -1  ## the line on screen
var _on_end_card := false
var _typing: Label  ## the label whose text is being typed
var _letters := 0.0  ## letters of the line shown so far
var _letters_per_second := 1.0
var _quiet_alpha := 1.0
var _closed := false


## Puts the scene over `screen` (on top of everything on it) and marks it seen.
static func play(screen: Node, id: String) -> Control:
	var player: Control = load(SCENE).instantiate()
	player.scene_id = id
	screen.get_node("/root/GameState").start_scene(id)
	screen.add_child(player)
	return player


func _ready() -> void:
	var data = GameState.data
	var settings: Dictionary = data.visual["story"]
	_letters_per_second = float(settings["letters_per_second"])
	_quiet_alpha = float(settings["quiet_raven_alpha"])
	%Hugin.texture = Art.raven_picture("hugin")
	%Munin.texture = Art.raven_picture("munin")
	var scene: Dictionary = data.get_scene(scene_id)
	_lines = scene.get("lines", [])
	_end_card = scene.get("end_card", "")
	%SkipButton.pressed.connect(close)
	_next()


func _process(delta: float) -> void:
	if _typing == null or is_line_shown():
		return
	_letters += delta * _letters_per_second
	if _letters >= _typing.get_total_character_count():
		_typing.visible_characters = -1
	else:
		_typing.visible_characters = int(_letters)


## Touches arrive as mouse events too (touch-to-mouse emulation is on by default).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		tap()


## A tap anywhere: the whole line if it is still being typed, otherwise the next line (or the end card, or the end).
func tap() -> void:
	if not is_line_shown():
		_typing.visible_characters = -1
	else:
		_next()


func is_line_shown() -> bool:
	return _typing == null or _typing.visible_characters < 0


## «Пропустить», or the end: the scene closes at once.
func close() -> void:
	if _closed:
		return
	_closed = true
	finished.emit()
	queue_free()


func line_index() -> int:
	return _index


func is_on_end_card() -> bool:
	return _on_end_card


func _next() -> void:
	if _on_end_card:
		close()
		return
	_index += 1
	if _index < _lines.size():
		_show_line(_lines[_index])
	elif _end_card != "":
		_show_end_card()
	else:
		close()


func _show_line(line: Dictionary) -> void:
	var data = GameState.data
	var speaker: String = line["speaker"]
	var on_page: bool = line["view"] == "page"
	%Page.visible = on_page
	%Dialog.visible = not on_page
	%Dim.visible = not on_page
	if on_page:
		%Hugin.modulate.a = 1.0 if speaker == "hugin" else _quiet_alpha
		%Munin.modulate.a = 1.0 if speaker == "munin" else _quiet_alpha
		%PageName.text = data.speaker_name(speaker)
		%PageText.text = line["text"]
		_type(%PageText)
	else:
		for old in %DialogPortrait.get_children():
			%DialogPortrait.remove_child(old)
			old.queue_free()
		var texture: Texture2D
		if data.is_raven(speaker):
			texture = Art.raven_portrait(speaker, data.story["speakers"][speaker])
		else:
			texture = Art.hero_portrait(data.get_hero(speaker))
		%DialogPortrait.add_child(HeroesScreen.make_portrait_frame(texture, PORTRAIT_SIZE))
		%DialogName.text = data.speaker_name(speaker)
		%DialogText.text = line["text"]
		_type(%DialogText)


func _type(label: Label) -> void:
	_typing = label
	_letters = 0.0
	label.visible_characters = 0


func _show_end_card() -> void:
	_on_end_card = true
	_typing = null
	%Page.visible = false
	%Dialog.visible = false
	%Dim.visible = false
	%SkipButton.visible = false
	%EndText.text = _end_card
	%EndCard.visible = true
