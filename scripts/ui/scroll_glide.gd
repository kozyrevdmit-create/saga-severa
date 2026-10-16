## The glide of a finger-scrolled list after release (M9.1): the finger's speed over its last moments, then a smooth
## slow-down to a stop. No nodes and no real time: the caller passes times and the list's visible height, so tests
## can drive it frame by frame.
##
## The speed falls the same share every moment (it never jumps to zero), so the glide after release is
## speed × glide_seconds: twice as fast a flick glides twice as far, not four times as with the ScrollContainer's own
## fixed braking. Settings (data/visual.json → list_scroll), speeds in visible heights of the list per second:
##   glide_seconds — how far a flick glides: distance = release speed × this;
##   max_speed_screens_per_second — the fastest glide, so even a very hard flick glides at most max × glide_seconds;
##   stop_speed_screens_per_second — the glide stops once it is slower than this;
##   speed_sample_seconds — the finger's speed is measured over this last stretch of the drag; a finger that stood still
##     that long before lifting does not start a glide.
extends RefCounted

var velocity := 0.0  ## list pixels per second, + = the list moves on to its end

var _settings: Dictionary
var _samples: Array[Vector2] = []  ## (time, list offset under the finger), oldest first


func _init(settings: Dictionary) -> void:
	_settings = settings


## The finger touched the list: any glide stops.
func begin(time: float, offset: float) -> void:
	velocity = 0.0
	_samples = [Vector2(time, offset)]


## The finger moved the list to offset.
func track(time: float, offset: float) -> void:
	_samples.append(Vector2(time, offset))
	var window := float(_settings["speed_sample_seconds"])
	while _samples.size() > 2 and _samples[1].x <= time - window:
		_samples.pop_front()


## The finger lifted: the glide starts at the finger's recent speed (capped).
func release(time: float, screen_height: float) -> void:
	velocity = 0.0
	var window := float(_settings["speed_sample_seconds"])
	var last: Vector2 = _samples.back()
	if _samples.size() < 2 or time - last.x > window:
		return  # the finger did not move, or stood still before lifting
	var start := maxf(_samples[0].x, time - window)
	if time - start <= 0.0:
		return
	var max_speed := float(_settings["max_speed_screens_per_second"]) * screen_height
	velocity = clampf((last.y - _offset_at(start)) / (time - start), -max_speed, max_speed)
	if absf(velocity) < float(_settings["stop_speed_screens_per_second"]) * screen_height:
		velocity = 0.0


## How far the list moves during the next delta seconds of the glide; the speed slows down meanwhile.
func step(delta: float, screen_height: float) -> float:
	if velocity == 0.0:
		return 0.0
	var tau := float(_settings["glide_seconds"])
	var keep := exp(-delta / tau)
	var moved := velocity * tau * (1.0 - keep)
	velocity *= keep
	if absf(velocity) < float(_settings["stop_speed_screens_per_second"]) * screen_height:
		velocity = 0.0
	return moved


func stop() -> void:
	velocity = 0.0


## Where the finger had moved the list at the given time (between two samples: along the straight line).
func _offset_at(time: float) -> float:
	for i in range(1, _samples.size()):
		if _samples[i].x >= time:
			var a: Vector2 = _samples[i - 1]
			var b: Vector2 = _samples[i]
			return lerpf(a.y, b.y, (time - a.x) / (b.x - a.x)) if b.x > a.x else b.y
	return _samples.back().y
