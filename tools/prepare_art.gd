## Makes the game-size character pictures from the full-size art (docs/ART_STYLE.md):
##   godot --headless --path . --script res://tools/prepare_art.gd -- --src="<folder with heroes/ and enemies/>"
## Every picture is brought to one format, whatever the source size and margins (Sigrid's source is 1254×1254
## with no margin): the figure is cut out by its opaque pixels, scaled to fit SIZE × CONTENT_SHARE, centred
## horizontally and stood on a common ground line (feet at the same height), on a transparent square SIZE × SIZE.
## Writes assets/art/heroes/*.png, assets/art/enemies/*.png and assets/art/story/*.png; the editor (or `--import`) imports them.
## Chapter maps (maps/*.png, opaque 1024×1536) are copied as they are into assets/art/maps/: the map fills the screen
## height, about 1560 game pixels on an iPhone, so a smaller copy would blur. Their import settings make them small.
extends SceneTree

const SIZE := 512  ## enough for a sharp 270 px boss on a 3× iPhone screen (game is 720 px wide)
const CONTENT_SHARE := 920.0 / 1024.0  ## the approved 1024 px pictures leave a 52 px margin around the figure
const ALPHA_CUTOFF := 0.3  ## faint edge pixels below this do not count as the figure
const FOLDERS := ["heroes", "enemies", "story"]  ## story: Odin's ravens for the saga scenes (Hugin faces right, Munin left)
const MAPS_FOLDER := "maps"
## The game names a picture by the hero/enemy id from data/*.json; the art folder spells one name differently.
const GAME_NAMES := {"thorvald.png": "torvald.png"}
const PALETTE := ["#1a1a1a", "#efe3c8", "#b5442c", "#3f6a96"]  ## docs/ART_STYLE.md: the only four colours
const RED := 2  ## index of the rust red in PALETTE
const REDDISH := 50  ## a source pixel may turn rust red only if its red is this much above its green and blue


func _initialize() -> void:
	var src := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="):
			src = arg.trim_prefix("--src=")
	if src.is_empty():
		printerr("Usage: ... -- --src=<folder with heroes/, enemies/, story/ and maps/>")
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
				_snap_to_palette(image)
				image.save_png(out_dir.path_join(file))
				print("%s/%s: %s" % [MAPS_FOLDER, file, image.get_size()])
	quit()


## Every pixel becomes the nearest of the four palette colours (docs/ART_STYLE.md). The Midgard map came in these four
## colours already; the Jotunheim map came with soft noise (about 230 000 shades), 3.6 MB instead of 0.4 MB.
## Rust red only where the source is clearly red (tents, banners): a brownish grey at the edge of a black line is
## nearer to the red than to black or bone and would turn into red specks.
func _snap_to_palette(image: Image) -> void:
	var colors: Array[Color] = []
	for code in PALETTE:
		colors.append(Color(code))
	var bytes := image.get_data()
	var palette := PackedByteArray()
	for color in colors:
		palette.append_array([color.r8, color.g8, color.b8])
	for i in range(0, bytes.size(), 3):
		var best := 0
		var best_distance := 1 << 30
		var reddish := bytes[i] - maxi(bytes[i + 1], bytes[i + 2]) >= REDDISH
		for k in colors.size():
			if k == RED and not reddish:
				continue
			var dr := bytes[i] - palette[k * 3]
			var dg := bytes[i + 1] - palette[k * 3 + 1]
			var db := bytes[i + 2] - palette[k * 3 + 2]
			var distance := dr * dr + dg * dg + db * db
			if distance < best_distance:
				best_distance = distance
				best = k
		bytes[i] = palette[best * 3]
		bytes[i + 1] = palette[best * 3 + 1]
		bytes[i + 2] = palette[best * 3 + 2]
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8, bytes)


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
