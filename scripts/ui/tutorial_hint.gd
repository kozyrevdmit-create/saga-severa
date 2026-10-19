## A hint of the beginner's tutorial (M14, data/tutorial.json) over a screen: the screen is dimmed except the element
## the hint points at (with a light frame around it), a light paper window like the settlement's building window holds
## the text and «Понятно», and a drawn arrow goes from the window to the element (the game's font has no arrow glyph).
## A tap anywhere but «Понятно» does nothing. The window stands under the element if there is room for it there (so it
## does not hide what is above: the defeat's text over «На карту»), else above it; where there is room on neither side
## (the battlefield), at the top of the element (the enemies' back row, empty in the first battle's waves), without
## the arrow.
## Start with TutorialHint.try_show(screen, screen_id, moment, targets): it asks the progress which hints are due
## (Progress.tutorial_hints_due), shows the first one whose target is on the screen and marks it shown at once
## (GameState.show_tutorial_hint); only one hint at a time is on a screen. The element is followed every frame, so the
## hole stays on it while the screen lays itself out.
extends Control

signal closed  ## «Понятно» was pressed

const GROUP := "tutorial_hint"
const DIM := Color(0, 0, 0, 0.62)
const HOLE_PADDING := 10.0
const HOLE_BORDER := Color("#ffe27a")
const HOLE_BORDER_WIDTH := 4.0
const INK := Color("#1a1a1a")
const PAPER := Color(0.937, 0.89, 0.784, 1)
const SIDE_MARGIN := 24.0  ## between the window and the screen's sides
const WINDOW_MAX_WIDTH := 640.0
const GAP := 10.0  ## between the arrow and the window or the hole
const ARROW_LENGTH := 72.0
const INSIDE_GAP := 24.0  ## between the top of a big element and the window over it
const ARROW_WIDTH := 12.0
const ARROW_OUTLINE := 4.0
const ARROW_HEAD := 30.0
const TEXT_FONT_SIZE := 32
const BUTTON_FONT_SIZE := 36
const BUTTON_HEIGHT := 104.0  ## spec: buttons at least 96 px tall

var hint_id := ""
var _text := ""
var _button_text := ""
var _targets: Array = []  ## Controls the hint points at; the hole is around all of them
var _hole := Rect2()
var _arrow := PackedVector2Array()  ## [from (window), to (element)]; empty = no arrow
var _window := PanelContainer.new()
var _label := Label.new()
var _button := Button.new()
var _frames := 0
var _closed := false


## The first hint due on `screen_id` at `moment` whose target is on the screen, put over `screen` (as its last child);
## null if none is due or a hint is already on the screen. `targets` turns a target key (tutorial.json → hints[].target)
## into the Controls to point at ([] = not on the screen now: the hint waits). `facts` go to Progress.tutorial_hints_due.
static func try_show(screen: Control, screen_id: String, moment: String, targets: Callable, facts := {}) -> Control:
	if is_on(screen):
		return null
	var game_state = screen.get_node("/root/GameState")
	if not facts.has("now"):
		facts["now"] = game_state.now()
	for id in game_state.progress.tutorial_hints_due(game_state.data, screen_id, moment, facts):
		var hint: Dictionary = game_state.data.get_tutorial_hint(id)
		var controls: Array = targets.call(hint["target"]).filter(
				func(control): return is_instance_valid(control) and control.is_visible_in_tree())
		if controls.is_empty():
			continue
		game_state.show_tutorial_hint(id)
		var overlay = new()
		overlay.hint_id = id
		overlay._text = hint["text"]
		overlay._button_text = game_state.data.tutorial_text("got_it")
		overlay._targets = controls
		screen.add_child(overlay)
		return overlay
	return null


## A tutorial hint is on this screen now.
static func is_on(screen: Node) -> bool:
	return screen.get_children().any(func(child): return child.is_in_group(GROUP) and not child.is_queued_for_deletion())


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0  # until the hole has found its element (the screen lays itself out in its first frames)
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = INK
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	_window.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	_window.add_child(box)
	_label.text = _text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 1
	_label.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	_label.add_theme_color_override("font_color", INK)
	box.add_child(_label)
	_button.text = _button_text
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size.y = BUTTON_HEIGHT
	_button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	_button.pressed.connect(close)
	box.add_child(_button)
	add_child(_window)
	_place()


func _process(_delta: float) -> void:
	_place()
	_frames += 1
	if _frames >= 2:
		modulate.a = 1.0


## «Понятно»: the hint closes (the screen goes on: a paused battle runs again).
func close() -> void:
	if _closed:
		return
	_closed = true
	closed.emit()
	queue_free()


func press_button() -> void:
	_button.pressed.emit()


func text() -> String:
	return _label.text


## The hole around the element, in this overlay's coordinates (= the screen's).
func hole() -> Rect2:
	return _hole


func window_rect() -> Rect2:
	return _window.get_rect()


func has_arrow() -> bool:
	return not _arrow.is_empty()


func _place() -> void:
	var area := Rect2(Vector2.ZERO, size)
	var found := false
	var rect := Rect2()
	for control in _targets:
		if not is_instance_valid(control):
			continue
		var own: Rect2 = get_global_transform().affine_inverse() * control.get_global_rect()
		rect = own if not found else rect.merge(own)
		found = true
	if found:
		_hole = rect.grow(HOLE_PADDING).intersection(area)
	var width := minf(WINDOW_MAX_WIDTH, size.x - 2.0 * SIDE_MARGIN)
	_window.custom_minimum_size.x = width
	_window.size = Vector2(width, 0)
	_window.reset_size()
	var height := _window.size.y
	var needed := height + ARROW_LENGTH + 2.0 * GAP
	var above := _hole.position.y
	var below := size.y - _hole.end.y
	var x := (size.x - width) / 2.0
	var y := 0.0
	_arrow = PackedVector2Array()
	var target_x := _hole.get_center().x
	var arrow_x := clampf(target_x, x + 48.0, x + width - 48.0)
	if below >= needed:
		y = _hole.end.y + GAP + ARROW_LENGTH
		_arrow = PackedVector2Array([Vector2(arrow_x, y - 2.0), Vector2(target_x, _hole.end.y + GAP)])
	elif above >= needed:
		y = _hole.position.y - GAP - ARROW_LENGTH - height
		_arrow = PackedVector2Array([Vector2(arrow_x, y + height + 2.0), Vector2(target_x, _hole.position.y - GAP)])
	else:
		y = clampf(_hole.position.y + INSIDE_GAP, 0.0, maxf(0.0, size.y - height))
	_window.position = Vector2(x, y)
	queue_redraw()


func _draw() -> void:
	var cut := _hole
	draw_rect(Rect2(0, 0, size.x, cut.position.y), DIM)
	draw_rect(Rect2(0, cut.end.y, size.x, size.y - cut.end.y), DIM)
	draw_rect(Rect2(0, cut.position.y, cut.position.x, cut.size.y), DIM)
	draw_rect(Rect2(cut.end.x, cut.position.y, size.x - cut.end.x, cut.size.y), DIM)
	draw_rect(cut, HOLE_BORDER, false, HOLE_BORDER_WIDTH)
	if _arrow.is_empty():
		return
	var from := _arrow[0]
	var to := _arrow[1]
	var direction := (to - from).normalized()
	var across := Vector2(-direction.y, direction.x)
	var neck := to - direction * ARROW_HEAD
	var head := PackedVector2Array([to, neck + across * ARROW_HEAD * 0.75, neck - across * ARROW_HEAD * 0.75])
	draw_line(from, neck, INK, ARROW_WIDTH + 2.0 * ARROW_OUTLINE)
	draw_colored_polygon(head, INK)
	draw_line(from, neck, HOLE_BORDER, ARROW_WIDTH)
	var inner := PackedVector2Array([
		to - direction * ARROW_OUTLINE * 1.6,
		neck + across * (ARROW_HEAD * 0.75 - ARROW_OUTLINE * 1.6) + direction * ARROW_OUTLINE * 0.6,
		neck - across * (ARROW_HEAD * 0.75 - ARROW_OUTLINE * 1.6) + direction * ARROW_OUTLINE * 0.6])
	draw_colored_polygon(inner, HOLE_BORDER)
