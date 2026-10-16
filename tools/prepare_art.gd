## Makes the game-size character pictures from the full-size art (docs/ART_STYLE.md):
##   godot --headless --path . --script res://tools/prepare_art.gd -- --src="<folder with heroes/ and enemies/>"
## Every picture is brought to one format, whatever the source size and margins (Sigrid's source is 1254×1254
## with no margin): the figure is cut out by its opaque pixels, scaled to fit SIZE × CONTENT_SHARE, centred
## horizontally and stood on a common ground line (feet at the same height), on a transparent square SIZE × SIZE.
## Writes assets/art/heroes/*.png and assets/art/enemies/*.png; the editor (or `--import`) imports them.
## Chapter maps (maps/*.png, opaque 1024×1536) are copied as they are into assets/art/maps/: the map fills the screen
## height, about 1560 game pixels on an iPhone, so a smaller copy would blur. Their import settings make them small.
extends SceneTree

const SIZE := 512  ## enough for a sharp 270 px boss on a 3× iPhone screen (game is 720 px wide)
const CONTENT_SHARE := 920.0 / 1024.0  ## the approved 1024 px pictures leave a 52 px margin around the figure
const ALPHA_CUTOFF := 0.3  ## faint edge pixels below this do not count as the figure
const FOLDERS := ["heroes", "enemies"]
const MAPS_FOLDER := "maps"
## The game names a picture by the hero/enemy id from data/*.json; the art folder spells one name differently.
const GAME_NAMES := {"thorvald.png": "torvald.png"}


func _initialize() -> void:
	var src := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="):
			src = arg.trim_prefix("--src=")
	if src.is_empty():
		printerr("Usage: ... -- --src=<folder with heroes/, enemies/ and maps/>")
		quit(1)
		return
	for folder in FOLDERS:
		var out_dir := ProjectSettings.globalize_path("res://assets/art/%s" % folder)
		DirAccess.make_dir_recursive_absolute(out_dir)
		for file in DirAccess.get_files_at(src.path_join(folder)):
			if file.get_extension() != "png":
				continue
			var image := Image.load_from_file(src.path_join(folder).path_join(file))
			var result := _normalize(image)
			var game_name: String = GAME_NAMES.get(file, file)
			result.save_png(out_dir.path_join(game_name))
			print("%s/%s: %s -> %s %d×%d" % [folder, file, image.get_size(), game_name, SIZE, SIZE])
	var maps_dir := src.path_join(MAPS_FOLDER)
	if DirAccess.dir_exists_absolute(maps_dir):
		var out_dir := ProjectSettings.globalize_path("res://assets/art/%s" % MAPS_FOLDER)
		DirAccess.make_dir_recursive_absolute(out_dir)
		for file in DirAccess.get_files_at(maps_dir):
			if file.get_extension() == "png":
				var image := Image.load_from_file(maps_dir.path_join(file))
				image.convert(Image.FORMAT_RGB8)
				image.save_png(out_dir.path_join(file))
				print("%s/%s: %s" % [MAPS_FOLDER, file, image.get_size()])
	quit()


func _normalize(image: Image) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var rect := _figure_rect(image)
	var figure := image.get_region(rect)
	var box := SIZE * CONTENT_SHARE
	var scale := box / maxf(rect.size.x, rect.size.y)
	var scaled := Vector2i(roundi(rect.size.x * scale), roundi(rect.size.y * scale))
	figure.resize(scaled.x, scaled.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var margin := roundi((SIZE - box) / 2.0)
	var at := Vector2i((SIZE - scaled.x) / 2, SIZE - margin - scaled.y)
	result.blit_rect(figure, Rect2i(Vector2i.ZERO, scaled), at)
	return result


func _figure_rect(image: Image) -> Rect2i:
	var top_left := Vector2i(image.get_width(), image.get_height())
	var bottom_right := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > ALPHA_CUTOFF:
				top_left = top_left.min(Vector2i(x, y))
				bottom_right = bottom_right.max(Vector2i(x, y))
	return Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)
