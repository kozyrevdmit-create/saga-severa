## The glide of «Герои» and «Отряд» after the finger lifts (M9.1, scripts/ui/scroll_glide.gd): it slows down smoothly
## to a stop, a light flick glides less than a screen, a hard one further but within the cap. On the iPhone one
## flick used to fly to the end of the list. The finger-following part is in test_screens.gd.
extends "res://tests/base_test.gd"

const GameData := preload("res://scripts/data/game_data.gd")
const ScrollGlide := preload("res://scripts/ui/scroll_glide.gd")

const SCREEN := 1000.0  ## the list's visible height in these tests
const FRAME := 1.0 / 60.0

var _settings: Dictionary = GameData.load_all().visual["list_scroll"]


func test_settings_are_in_visual_json() -> void:
	for key in ["glide_seconds", "max_speed_screens_per_second", "stop_speed_screens_per_second", "speed_sample_seconds"]:
		assert_true(_settings.has(key) and float(_settings[key]) > 0.0, "visual.json → list_scroll.%s is a positive number" % key)


func test_the_glide_slows_down_to_a_stop() -> void:
	var glide := _flick(2.0)
	var start_speed := glide.velocity
	assert_near(start_speed, 2.0 * SCREEN, 0.01 * SCREEN, "the glide starts at the finger's speed")
	var previous := start_speed
	var travelled := 0.0
	var seconds := 0.0
	while glide.velocity != 0.0 and seconds < 10.0:
		travelled += glide.step(FRAME, SCREEN)
		seconds += FRAME
		if glide.velocity > previous or glide.velocity < 0.0:
			failures.append("the speed only falls: %s after %s" % [glide.velocity, previous])
			break
		previous = glide.velocity
	assert_eq(glide.velocity, 0.0, "the glide stops")
	assert_true(seconds < 3.0, "the glide stops within 3 s (took %.2f s)" % seconds)
	assert_near(travelled, start_speed * float(_settings["glide_seconds"]), 0.05 * SCREEN,
			"a glide covers speed × glide_seconds")


func test_a_light_flick_glides_less_than_a_screen() -> void:
	# A light flick on the iPhone: about one visible height per second.
	var distance := _glide_distance(_flick(1.0))
	assert_true(distance > 0.0, "a light flick still glides a little")
	assert_true(distance <= 1.0 * SCREEN, "a light flick glides at most about a screen (%.2f screens)" % (distance / SCREEN))


func test_a_hard_flick_glides_further_but_within_the_cap() -> void:
	var light := _glide_distance(_flick(1.0))
	var hard := _glide_distance(_flick(20.0))
	var cap := float(_settings["max_speed_screens_per_second"]) * float(_settings["glide_seconds"]) * SCREEN
	assert_true(hard > light, "a hard flick glides further than a light one")
	assert_true(hard <= cap + 1.0, "even a very hard flick glides at most max speed × glide_seconds (%.2f screens)" % (hard / SCREEN))


func test_twice_as_fast_glides_twice_as_far() -> void:
	var one := _glide_distance(_flick(1.0))
	var two := _glide_distance(_flick(2.0))
	assert_near(two / one, 2.0, 0.1, "the glide grows with the flick's speed, not with its square")


func test_no_glide_after_the_finger_stood_still() -> void:
	var glide := ScrollGlide.new(_settings)
	glide.begin(0.0, 0.0)
	for i in 6:
		glide.track((i + 1) * FRAME, (i + 1) * 30.0)
	glide.release(6 * FRAME + float(_settings["speed_sample_seconds"]) + 0.05, SCREEN)
	assert_eq(glide.velocity, 0.0, "a finger that stopped before lifting leaves the list where it is")


func test_only_the_last_moments_of_the_drag_set_the_speed() -> void:
	# A long slow drag ending in a quick flick glides at the flick's speed, not the drag's average.
	var glide := ScrollGlide.new(_settings)
	glide.begin(0.0, 0.0)
	var time := 0.0
	var offset := 0.0
	for i in 60:  # one second at 0.2 screens/s
		time += FRAME
		offset += 0.2 * SCREEN * FRAME
		glide.track(time, offset)
	for i in 6:  # then 0.1 s at 3 screens/s
		time += FRAME
		offset += 3.0 * SCREEN * FRAME
		glide.track(time, offset)
	glide.release(time, SCREEN)
	assert_near(glide.velocity, 3.0 * SCREEN, 0.05 * SCREEN, "the speed of the final flick")


func test_a_new_touch_stops_the_glide() -> void:
	var glide := _flick(2.0)
	glide.step(FRAME, SCREEN)
	glide.begin(1.0, 500.0)
	assert_eq(glide.velocity, 0.0, "touching a gliding list stops it")


# --- helpers -----------------------------------------------------------------

## A finger moving the list at the given speed (screens per second) for 0.1 s at 60 frames a second, then lifting.
func _flick(screens_per_second: float) -> ScrollGlide:
	var glide := ScrollGlide.new(_settings)
	glide.begin(0.0, 0.0)
	for i in 6:
		glide.track((i + 1) * FRAME, (i + 1) * FRAME * screens_per_second * SCREEN)
	glide.release(6 * FRAME, SCREEN)
	return glide


func _glide_distance(glide: ScrollGlide) -> float:
	var travelled := 0.0
	for i in 600:
		travelled += glide.step(FRAME, SCREEN)
	return travelled
