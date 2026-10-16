## M7: character art instead of rectangles. Every hero and enemy has a picture of one format, every hero a portrait,
## the boss is drawn bigger, and the battlefield fits the pictures on a phone screen (5 heroes, 4 enemies, the boss).
extends "res://tests/base_test.gd"

const Art := preload("res://scripts/ui/art.gd")
const GameData := preload("res://scripts/data/game_data.gd")
const Progress := preload("res://scripts/save/progress.gd")
const FighterView := preload("res://scripts/ui/fighter_view.gd")
const BATTLE_SCENE := "res://scenes/battle.tscn"
const PHONE_SIZE := Vector2i(720, 1558)  ## iPhone 14 shape at the project's 720 px width
const BASE_SIZE := Vector2i(720, 1280)  ## project.godot viewport (a shorter phone)

var _data = GameData.load_all()


func test_every_character_has_a_square_picture_of_one_size() -> void:
	var size := Vector2.ZERO
	var pictures: Array = []
	for hero in _data.heroes["heroes"]:
		pictures.append([hero["id"], Art.hero_picture(hero["id"])])
	for enemy in _data.enemies["enemies"]:
		pictures.append([enemy["id"], Art.enemy_picture(enemy["id"])])
	for entry in pictures:
		var picture: Texture2D = entry[1]
		assert_true(picture != null, "%s has a picture" % entry[0])
		if picture == null:
			continue
		if size == Vector2.ZERO:
			size = picture.get_size()
		assert_eq(picture.get_size(), size, "%s: every picture has the same size" % entry[0])
		assert_eq(picture.get_width(), picture.get_height(), "%s: the picture is square" % entry[0])


func test_every_hero_has_a_portrait_inside_the_picture() -> void:
	for hero in _data.heroes["heroes"]:
		var portrait: AtlasTexture = Art.hero_portrait(hero)
		var picture_rect := Rect2(Vector2.ZERO, portrait.atlas.get_size())
		assert_true(picture_rect.encloses(portrait.region), "%s: the portrait is inside the picture" % hero["id"])
		assert_near(portrait.region.size.x, portrait.region.size.y, 0.01, "%s: the portrait is square" % hero["id"])
		assert_true(portrait.region.position.y < picture_rect.size.y * 0.25, "%s: the portrait is the upper part of the picture" % hero["id"])


func test_the_boss_is_drawn_half_as_big_again() -> void:
	for enemy in _data.enemies["enemies"]:
		var expected := 1.5 if enemy.get("boss", false) else 1.0
		assert_near(float(enemy["art_scale"]), expected, 0.001, "%s: art_scale" % enemy["id"])


func test_five_heroes_and_four_enemies_fit_the_phone_field() -> void:
	for window in [PHONE_SIZE, BASE_SIZE]:
		var screen = await _open_battle(7, window)
		await _reach_wave(screen, 2)
		assert_eq(screen._battle.heroes().size(), 5, "five heroes in the squad")
		assert_eq(screen._battle.enemies().size(), 4, "stage 7, wave 3: four enemies")
		_check_field(screen, "stage 7 at %s" % window)
		_close(screen)


func test_the_boss_stands_bigger_on_the_field() -> void:
	for window in [PHONE_SIZE, BASE_SIZE]:
		var screen = await _open_battle(10, window)
		await _reach_wave(screen, 2)
		var boss = screen._battle.enemies()[0]
		var boss_view = screen._views[boss.id]
		var hero_view = screen._views[screen._battle.heroes()[0].id]
		assert_near(boss_view.size.x / hero_view.size.x, 1.5, 0.01, "%s: the boss picture is 1.5 times wider" % window)
		_check_field(screen, "boss at %s" % window)
		_close(screen)


func test_fighters_lunge_flash_and_fade() -> void:
	var screen = await _open_battle(1, PHONE_SIZE)
	var tree := Engine.get_main_loop() as SceneTree
	screen.set_process(false)  # the battle stands still: only the animations run
	var hero = screen._battle.heroes()[0]
	var view = screen._views[hero.id]
	var rest: Vector2 = view._pose.position
	view.lunge()
	await tree.create_timer(FighterView.LUNGE_OUT_SECONDS).timeout
	assert_true(view._pose.position.y < rest.y, "a hero lunges up, towards the enemies")
	await tree.create_timer(FighterView.LUNGE_BACK_SECONDS + 0.1).timeout
	assert_near(view._pose.position.distance_to(rest), 0.0, 0.5, "and steps back")

	view.flash()
	assert_true(float(view._art.material.get_shader_parameter("flash")) > 0.0, "a hit flashes the picture")
	await tree.create_timer(FighterView.FLASH_SECONDS + 0.1).timeout
	assert_near(float(view._art.material.get_shader_parameter("flash")), 0.0, 0.01, "the flash is short")

	hero.hp = 0
	view.refresh(hero)
	await tree.create_timer(FighterView.DEATH_SECONDS + 0.1).timeout
	assert_near(view.modulate.a, FighterView.DEAD_ALPHA, 0.01, "a fallen hero fades out")
	_close(screen)


# --- helpers -----------------------------------------------------------------

var _saved_progress
var _saved_window_size: Vector2i


func _open_battle(stage_id: int, window: Vector2i) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	_saved_progress = game_state.progress
	var progress = Progress.new_game(game_state.data)
	progress.jump_to_stage(game_state.data, stage_id)
	progress.mark_hint_shown = true
	game_state.progress = progress
	game_state.selected_stage = stage_id
	_saved_window_size = tree.root.size
	tree.root.size = window
	var screen: Control = load(BATTLE_SCENE).instantiate()
	tree.root.add_child(screen)
	for i in 3:
		await tree.process_frame
	return screen


## Clears the waves before `index` (enemies drop to 0 HP) until the battle shows that wave.
func _reach_wave(screen: Control, index: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for attempt in 600:
		if screen._battle.wave_index >= index:
			break
		for enemy in screen._battle.enemies():
			enemy.hp = 0
		await tree.process_frame
	for i in 3:
		await tree.process_frame
	assert_eq(screen._battle.wave_index, index, "reached wave %d" % (index + 1))


## Every fighter is inside the field, and no two fighters overlap.
func _check_field(screen: Control, where: String) -> void:
	var field: Control = screen.get_node("%Field")
	var field_rect := Rect2(Vector2.ZERO, field.size)
	var rects: Array = []
	for unit in screen._battle.units:
		var view: Control = screen._views[unit.id]
		var rect := Rect2(view.position, view.size)
		assert_true(field_rect.grow(0.5).encloses(rect), "%s: %s is inside the field" % [where, unit.display_name])
		for other in rects:
			assert_true(not rect.intersects(other[1]), "%s: %s does not overlap %s" % [where, unit.display_name, other[0]])
		rects.append([unit.display_name, rect])


func _close(screen: Control) -> void:
	screen.queue_free()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.get_node("GameState").progress = _saved_progress
	tree.root.size = _saved_window_size
