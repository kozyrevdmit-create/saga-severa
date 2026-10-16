## Finger scrolling of a vertical list («Герои», «Отряд»; M9.1). While the finger is down the list moves exactly with
## it; after release it glides on and slows down smoothly (scroll_glide.gd, numbers in data/visual.json → list_scroll).
##
## Replaces the ScrollContainer's own touch drag: its glide took the finger's speed from a single frame and braked
## by a small fixed amount, so the glide grew with the square of the flick and one flick on the iPhone flew to the end.
## As with the built-in drag (M6.2): the drag may start anywhere, even on a button, and once the list moves the
## button's press is cancelled. The mouse wheel still scrolls the built-in way.
extends ScrollContainer

const ScrollGlide := preload("res://scripts/ui/scroll_glide.gd")

var _glide: ScrollGlide
var _clock := 0.0  ## seconds since the list opened, counted by frames
var _finger_down := false
var _scrolling := false  ## the finger moved past the dead zone: the list follows it, buttons under it are cancelled
var _drag_from := 0.0  ## the list's offset when the finger touched it
var _finger_offset := 0.0  ## how far the finger has moved the list since then


func _ready() -> void:
	_glide = ScrollGlide.new(GameState.data.visual["list_scroll"])


func _gui_input(event: InputEvent) -> void:
	# A finger reaches Godot as an emulated mouse (the built-in drag works on touch screens only, so does this one).
	if not DisplayServer.is_touchscreen_available():
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press()
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _finger_down:
		_move(event.relative.y)
		accept_event()


func _process(delta: float) -> void:
	_clock += delta
	if _finger_down or _glide.velocity == 0.0:
		return
	var bar := get_v_scroll_bar()
	var before := bar.value
	bar.value = before + _glide.step(delta, size.y)
	if bar.value == before or _glide.velocity == 0.0:  # stopped, or reached the start or the end of the list
		_glide.stop()
		_end_scroll()


func _press() -> void:
	if _scrolling:
		_end_scroll()  # a touch catches a gliding list
	_finger_down = true
	_finger_offset = 0.0
	_drag_from = get_v_scroll_bar().value
	_glide.begin(_clock, _drag_from)


func _move(finger_dy: float) -> void:
	_finger_offset -= finger_dy
	if not _scrolling:
		if absf(_finger_offset) <= scroll_deadzone:
			return
		_scrolling = true
		_finger_offset = -finger_dy  # like the built-in drag: the list starts from here, without a jump
		propagate_notification(NOTIFICATION_SCROLL_BEGIN)  # cancels the press of the button under the finger
		scroll_started.emit()
	var bar := get_v_scroll_bar()
	bar.value = _drag_from + _finger_offset
	_finger_offset = bar.value - _drag_from  # past the start or end the list stays; turning back moves it at once
	_glide.track(_clock, bar.value)


func _release() -> void:
	_finger_down = false
	if not _scrolling:
		return
	_glide.release(_clock, size.y)
	if _glide.velocity == 0.0:
		_end_scroll()


func _end_scroll() -> void:
	_scrolling = false
	scroll_ended.emit()
	propagate_notification(NOTIFICATION_SCROLL_END)
