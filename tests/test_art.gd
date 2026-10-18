## M7: character art instead of rectangles. Every hero and enemy has a picture of one format, every hero a portrait,
## the boss is drawn bigger, and the battlefield fits the pictures on a phone screen (5 heroes, 4 enemies, the boss).
## M11: chapter 2's enemies, Thjazi's eagle form (its picture replaces his when he changes form) and Jotunheim's map.
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
		for phase in enemy.get("phases", []):
			if phase.has("picture"):  # Fafnir keeps his picture when he burrows into the gold
				pictures.append([phase["picture"], Art.enemy_picture(phase["picture"])])
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


## The boss is half as big again (M7), the bear 1.3 times, the boar a bit smaller than a draugr-sized picture (M9);
## M13: Fafnir as big as the other bosses, the rune golem as the bear.
func test_the_boss_is_drawn_half_as_big_again() -> void:
	var scales := {"draugr_king": 1.5, "bear": 1.3, "boar": 0.9, "thjazi": 1.5, "ice_troll": 1.2, "ironwood_wolf": 1.1, "carrion_eagle": 1.1,
		"fafnir": 1.5, "rune_golem": 1.3}
	for enemy in _data.enemies["enemies"]:
		var expected: float = scales.get(enemy["id"], 1.0)
		assert_near(float(enemy["art_scale"]), expected, 0.001, "%s: art_scale" % enemy["id"])


func test_pack_beasts_have_a_head_portrait_inside_the_picture() -> void:
	for pack in _data.packs["packs"]:
		var portrait: AtlasTexture = Art.enemy_portrait(_data.get_enemy(pack["icon"]))
		var picture_rect := Rect2(Vector2.ZERO, portrait.atlas.get_size())
		assert_true(picture_rect.encloses(portrait.region), "%s: the portrait is inside the picture" % pack["icon"])
		assert_near(portrait.region.size.x, portrait.region.size.y, 0.01, "%s: the portrait is square" % pack["icon"])


func test_the_chapter_map_is_a_tall_picture() -> void:
	for chapter_id in _data.chapter_ids():
		var picture: Texture2D = Art.map_picture(_data.get_chapter(chapter_id)["map"])
		assert_true(picture != null, "chapter %d: the map picture loads" % chapter_id)
		if picture != null:
			assert_eq(picture.get_size(), Vector2(1024, 1536), "chapter %d: the map keeps its full 1024×1536 size (it fills the phone's height)" % chapter_id)


## M13.1: every character picture (heroes, enemies, ravens) has at most prepare_art's CHARACTER_COLORS colours and
## ALPHA_LEVELS steps of transparency — the site stays small (5.81 → ~2.8 MB); a new picture must go through
## tools/prepare_art.gd (or its --reduce-colors). Pixel colours are read from the files in the game (lossless).
func test_character_pictures_keep_their_few_colours() -> void:
	var tool := load("res://tools/prepare_art.gd")
	for folder in ["heroes", "enemies", "story"]:
		for file in DirAccess.get_files_at("res://assets/art/" + folder):
			if file.get_extension() != "png":
				continue
			var image: Image = load("res://assets/art/%s/%s" % [folder, file]).get_image()
			image.convert(Image.FORMAT_RGBA8)
			var pixels := image.get_data().to_int32_array()
			var colours := {}
			var alphas := {}
			for pixel in pixels:
				var alpha := (pixel >> 24) & 255
				if alpha > 0:
					colours[pixel & 0xffffff] = true
					alphas[alpha] = true
			assert_true(colours.size() <= tool.CHARACTER_COLORS, "%s/%s: at most %d colours (%d)" % [
					folder, file, tool.CHARACTER_COLORS, colours.size()])
			assert_true(alphas.size() <= tool.ALPHA_LEVELS, "%s/%s: at most %d steps of transparency (%d)" % [
					folder, file, tool.ALPHA_LEVELS, alphas.size()])


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


## M11: chapter 2's widest waves fit the field; Thjazi stands as big as the draugr king and, at half HP, his picture
## becomes the eagle's, with the announcement over him.
func test_chapter_two_on_the_field_and_thjazis_change_of_form() -> void:
	for window in [PHONE_SIZE, BASE_SIZE]:
		for stage_id in _data.chapter_stage_ids(2):
			var screen = await _open_battle(stage_id, window)
			for wave_index in _data.get_stage(stage_id)["waves"].size():
				await _reach_wave(screen, wave_index)
				_check_field(screen, "stage %d wave %d at %s" % [stage_id, wave_index + 1, window])
			_close(screen)
	var stage_18 = await _open_battle(18, PHONE_SIZE)
	var hero_size: float = stage_18._views[stage_18._battle.heroes()[0].id].size.x
	await _reach_wave(stage_18, 2)
	assert_eq(stage_18._views[stage_18._battle.heroes()[0].id].size.x, hero_size, "the heroes keep their size from wave to wave")
	_close(stage_18)
	var screen = await _open_battle(20, PHONE_SIZE)
	await _reach_wave(screen, 2)
	var thjazi = screen._battle.enemies()[0]
	assert_eq(thjazi.def_id, "thjazi", "Thjazi in the last wave")
	var view = screen._views[thjazi.id]
	var hero_view = screen._views[screen._battle.heroes()[0].id]
	assert_near(view.size.x / hero_view.size.x, 1.5, 0.01, "Thjazi is 1.5 times wider")
	assert_eq(view._art.texture, Art.enemy_picture("thjazi"), "a giant first")
	thjazi.hp = thjazi.max_hp / 2 + 1
	screen._battle.battle._deal_damage(screen._battle.heroes()[0], thjazi, 0.0, "attack")
	screen._battle._collect_battle_events()
	screen._process(0.0)
	assert_eq(view._art.texture, Art.enemy_picture("thjazi_eagle"), "an eagle from half HP")
	var texts: Array = screen.get_node("%Field").find_children("*", "Label", true, false).map(func(label): return label.text)
	assert_true("Тьяцци обращается в орла!" in texts, "the announcement")
	_close(screen)


func test_fighters_lunge_flash_shake_and_fade() -> void:
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

	var visual: Dictionary = _data.visual
	assert_true(view.hit(), "a hit shows")
	assert_near(float(view._art.material.get_shader_parameter("flash")), float(visual["hit_flash"]["strength"]), 0.001,
			"a hit flashes the picture at full strength (visual.json)")
	assert_true(not view.hit(), "a second hit right after it does not flash again (no flicker at x2)")
	await tree.create_timer(float(visual["hit_shake"]["seconds"]) / 4.0).timeout
	assert_true(absf(view._art.position.x) > 0.5, "and shakes the picture")
	var flash_seconds := float(visual["hit_flash"]["hold_seconds"]) + float(visual["hit_flash"]["fade_seconds"])
	await tree.create_timer(maxf(flash_seconds, float(visual["hit_shake"]["seconds"])) + 0.1).timeout
	assert_near(float(view._art.material.get_shader_parameter("flash")), 0.0, 0.01, "the flash is short")
	assert_near(view._art.position.x, 0.0, 0.01, "the shake ends where it started")
	await tree.create_timer(float(visual["hit_min_gap_seconds"])).timeout
	assert_true(view.hit(), "a later hit flashes again")

	hero.hp = 0
	view.refresh(hero)
	await tree.create_timer(FighterView.DEATH_SECONDS + 0.1).timeout
	assert_near(view.modulate.a, FighterView.DEAD_ALPHA, 0.01, "a fallen hero fades out")
	_close(screen)


## M8: «Показывать имена в бою» off hides the names; the fighters keep their places.
func test_names_under_fighters_follow_the_setting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	var saved_names: bool = game_state.settings.show_names_in_battle
	var places := {}
	for show_names in [true, false]:
		game_state.settings.show_names_in_battle = show_names
		var screen = await _open_battle(7, PHONE_SIZE)
		screen.set_process(false)
		for unit in screen._battle.units:
			var view = screen._views[unit.id]
			assert_eq(view._name.visible, show_names, "%s: name shown = %s" % [unit.display_name, show_names])
			if show_names:
				places[unit.id] = view.position
			else:
				assert_eq(view.position, places.get(unit.id), "%s stands where it stood with names" % unit.display_name)
		_close(screen)
	game_state.settings.show_names_in_battle = saved_names


## M8: the «Новый герой присоединился к дружине» window shows the hero's portrait.
func test_new_hero_window_shows_the_portrait() -> void:
	var screen = await _open_battle(1, PHONE_SIZE)
	var tree := Engine.get_main_loop() as SceneTree
	screen.set_process(false)
	for hero_id in ["angrboda", "skadi"]:
		screen._new_heroes = [hero_id] as Array[String]
		screen._show_next_new_hero()
		await tree.process_frame
		var holder: Control = screen.get_node("%NewHeroPortrait")
		var pictures := holder.find_children("*", "TextureRect", true, false)
		assert_eq(pictures.size(), 1, "%s: one portrait in the window" % hero_id)
		if pictures.size() == 1:
			var portrait: AtlasTexture = pictures[0].texture
			assert_eq(portrait.atlas, Art.hero_picture(hero_id), "%s: the portrait is cut from the hero's picture" % hero_id)
			assert_true(pictures[0].size.x >= 200.0, "%s: the portrait is big" % hero_id)
	_close(screen)


# --- helpers -----------------------------------------------------------------

var _saved_progress
var _saved_window_size: Vector2i


func _open_battle(stage_id: int, window: Vector2i, hero_level := 0) -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	var game_state = tree.root.get_node("GameState")
	while game_state.data == null:
		await tree.process_frame
	_saved_progress = game_state.progress
	var progress = Progress.new_game(game_state.data)
	progress.jump_to_stage(game_state.data, stage_id)
	for hero_id in progress.hero_levels if hero_level > 0 else []:
		progress.hero_levels[hero_id] = hero_level
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


## M13.1 (playtest): Fafnir is darker only for the 5 s he is burrowed into his gold. After them his figure has its
## own colour again; so does it when the battle ends while he is burrowed («Отступить»).
func test_fafnir_is_dark_only_while_burrowed() -> void:
	for ending in ["comes out", "retreat"]:
		var screen = await _open_battle(30, PHONE_SIZE, 45)
		await _reach_wave(screen, screen._battle.wave_count - 1)
		screen.set_process(false)  # the test moves the battle on itself, 0.05 s at a time
		var fafnir = null
		for enemy in screen._battle.enemies():
			if enemy.def_id == "fafnir":
				fafnir = enemy
		fafnir.hp = int(fafnir.max_hp * 0.52)
		var view = screen._views[fafnir.id]
		for i in 400:
			if fafnir.is_invulnerable():
				break
			screen._process(0.05)
		assert_true(fafnir.is_invulnerable(), "%s: Fafnir burrows into the gold at half HP" % ending)
		assert_eq(view._pose.modulate, view.BURROWED_TINT, "%s: darker while burrowed" % ending)
		if ending == "retreat":
			screen._battle.retreat()
			screen._process(0.05)
		else:
			var burrowed_seconds := 0.0
			while fafnir.is_invulnerable() and burrowed_seconds < 10.0:
				screen._process(0.05)
				burrowed_seconds += 0.05
			assert_near(burrowed_seconds, 5.0, 0.11, "burrowed for 5 s")
			for i in 20:  # one more second of the second phase
				screen._process(0.05)
			assert_true(not screen._battle.finished, "the second phase goes on")
		assert_eq(view._pose.modulate, Color.WHITE, "%s: Fafnir has his own colour again" % ending)
		_close(screen)


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
