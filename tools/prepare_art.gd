## Makes the game-size character pictures from the full-size art (docs/ART_STYLE.md):
##   godot --headless --path . --script res://tools/prepare_art.gd -- --src="<folder with heroes/ and enemies/>"
## Every picture is brought to one format, whatever the source size and margins (Sigrid's source is 1254×1254
## with no margin): the figure is cut out by its opaque pixels, scaled to fit SIZE × CONTENT_SHARE, centred
## horizontally and stood on a common ground line (feet at the same height), on a transparent square SIZE × SIZE.
## Writes assets/art/heroes/*.png, assets/art/enemies/*.png, assets/art/story/*.png (and maps/, settlement/); the editor (or `--import`) imports them.
## Chapter maps (maps/*.png, opaque 1024×1536) are copied as they are into assets/art/maps/: the map fills the screen
## height, about 1560 game pixels on an iPhone, so a smaller copy would blur. Their import settings make them small.
## The settlement (M12, settlement/): its picture settlement.png (opaque 1024×1536, fills the screen height like a map)
## is copied like a map; the buildings (1024×1024 on a transparent background) are made BUILDING_SIZE × BUILDING_SIZE
## whole, margins included (data/buildings.json places them by shares of the square), in the four colours.
## `--only=settlement` (or another folder) prepares only that folder.
## M13.1: the character pictures (heroes/, enemies/, story/) keep at most CHARACTER_COLORS colours of their own and
## ALPHA_LEVELS steps of transparency (_reduce_colors): the resized art had 5 000–30 000 near-identical shades (soft
## noise around the ink), which made each picture ~200 KB in the game; with its own 128 colours it is ~70 KB and looks
## the same (the colours are averages of the picture's own shades, no new tones, the edges stay sharp).
##   godot --headless --path . --script res://tools/prepare_art.gd -- --reduce-colors   (only reduces the pictures
## already in assets/art/heroes, enemies and story, in place; a picture that is reduced already stays as it is)
extends SceneTree

const SIZE := 512  ## enough for a sharp 270 px boss on a 3× iPhone screen (game is 720 px wide)
const CONTENT_SHARE := 920.0 / 1024.0  ## the approved 1024 px pictures leave a 52 px margin around the figure
const ALPHA_CUTOFF := 0.3  ## faint edge pixels below this do not count as the figure
const FOLDERS := ["heroes", "enemies", "story"]  ## story: Odin's ravens for the saga scenes (Hugin faces right, Munin left)
const MAPS_FOLDER := "maps"
const SETTLEMENT_FOLDER := "settlement"
const SETTLEMENT_PICTURE := "settlement.png"
const BUILDING_SIZE := 512  ## a building stands about 270 game pixels wide on the settlement screen
## The game names a picture by the hero/enemy id from data/*.json; the art folder spells one name differently.
const GAME_NAMES := {"thorvald.png": "torvald.png"}
const PALETTE := ["#1a1a1a", "#efe3c8", "#b5442c", "#3f6a96"]  ## docs/ART_STYLE.md: the only four colours
const RED := 2  ## index of the rust red in PALETTE
const REDDISH := 50  ## a source pixel may turn rust red only if its red is this much above its green and blue
const CHARACTER_COLORS := 128  ## colours per character picture (64 is still close, 32 shows on the highlights)
const ALPHA_LEVELS := 16  ## steps of transparency on the soft edges


func _initialize() -> void:
	var src := ""
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--src="):
			src = arg.trim_prefix("--src=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg == "--reduce-colors":
			_reduce_colors_in_place()
			quit()
			return
	if src.is_empty():
		printerr("Usage: ... -- --src=<folder with heroes/, enemies/, story/ and maps/>")
		quit(1)
		return
	for folder in FOLDERS:
		if only != "" and folder != only:
			continue
		var out_dir := ProjectSettings.globalize_path("res://assets/art/%s" % folder)
		DirAccess.make_dir_recursive_absolute(out_dir)
		for file in DirAccess.get_files_at(src.path_join(folder)):
			if file.get_extension() != "png":
				continue
			var image := Image.load_from_file(src.path_join(folder).path_join(file))
			var result := _normalize(image)
			reduce_colors(result, CHARACTER_COLORS, ALPHA_LEVELS)
			var game_name: String = GAME_NAMES.get(file, file)
			result.save_png(out_dir.path_join(game_name))
			print("%s/%s: %s -> %s %d×%d" % [folder, file, image.get_size(), game_name, SIZE, SIZE])
	var maps_dir := src.path_join(MAPS_FOLDER)
	if DirAccess.dir_exists_absolute(maps_dir) and (only == "" or only == MAPS_FOLDER):
		var out_dir := ProjectSettings.globalize_path("res://assets/art/%s" % MAPS_FOLDER)
		DirAccess.make_dir_recursive_absolute(out_dir)
		for file in DirAccess.get_files_at(maps_dir):
			if file.get_extension() == "png":
				var image := Image.load_from_file(maps_dir.path_join(file))
				image.convert(Image.FORMAT_RGB8)
				_snap_to_palette(image)
				image.save_png(out_dir.path_join(file))
				print("%s/%s: %s" % [MAPS_FOLDER, file, image.get_size()])
	var settlement_dir := src.path_join(SETTLEMENT_FOLDER)
	if DirAccess.dir_exists_absolute(settlement_dir) and (only == "" or only == SETTLEMENT_FOLDER):
		var out_dir := ProjectSettings.globalize_path("res://assets/art/%s" % SETTLEMENT_FOLDER)
		DirAccess.make_dir_recursive_absolute(out_dir)
		for file in DirAccess.get_files_at(settlement_dir):
			if file.get_extension() != "png":
				continue
			var image := Image.load_from_file(settlement_dir.path_join(file))
			if file == SETTLEMENT_PICTURE:
				image.convert(Image.FORMAT_RGB8)
				_snap_to_palette(image)
			else:
				image.convert(Image.FORMAT_RGBA8)
				image.resize(BUILDING_SIZE, BUILDING_SIZE, Image.INTERPOLATE_LANCZOS)
				_snap_to_palette(image)
			image.save_png(out_dir.path_join(file))
			print("%s/%s: %s" % [SETTLEMENT_FOLDER, file, image.get_size()])
	quit()


## Every pixel becomes the nearest of the four palette colours (docs/ART_STYLE.md). The Midgard map came in these four
## colours already; the Jotunheim map came with soft noise (about 230 000 shades), 3.6 MB instead of 0.4 MB.
## Rust red only where the source is clearly red (tents, banners): a brownish grey at the edge of a black line is
## nearer to the red than to black or bone and would turn into red specks.
## A picture with transparency keeps its alpha (soft edges); only the colours are snapped.
func _snap_to_palette(image: Image) -> void:
	var colors: Array[Color] = []
	for code in PALETTE:
		colors.append(Color(code))
	var format := image.get_format()
	var step := 4 if format == Image.FORMAT_RGBA8 else 3
	var bytes := image.get_data()
	var palette := PackedByteArray()
	for color in colors:
		palette.append_array([color.r8, color.g8, color.b8])
	for i in range(0, bytes.size(), step):
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
	image.set_data(image.get_width(), image.get_height(), false, format, bytes)


func _reduce_colors_in_place() -> void:
	for folder in FOLDERS:
		var dir := ProjectSettings.globalize_path("res://assets/art/%s" % folder)
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() != "png":
				continue
			var path := dir.path_join(file)
			var image := Image.load_from_file(path)
			image.convert(Image.FORMAT_RGBA8)
			var before := FileAccess.get_file_as_bytes(path).size()
			reduce_colors(image, CHARACTER_COLORS, ALPHA_LEVELS)
			image.save_png(path)
			print("%s/%s: %d -> %d bytes (png)" % [folder, file, before, FileAccess.get_file_as_bytes(path).size()])


## Leaves the RGBA8 picture at most `colors` colours of its own (median cut: the picture's shades split into boxes
## of similar colours, each box becomes its weighted average) and `alpha_levels` steps of transparency. Fully
## transparent pixels become transparent black. A picture with `colors` colours or fewer keeps them as they are.
static func reduce_colors(image: Image, colors: int, alpha_levels: int) -> void:
	var bytes := image.get_data()
	var counts := {}  ## 0xRRGGBB -> pixels (only the mostly opaque ones choose the palette)
	var all_codes := {}
	for i in range(0, bytes.size(), 4):
		var code := (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2]
		all_codes[code] = true
		if bytes[i + 3] >= 128:
			counts[code] = counts.get(code, 0) + 1
	var nearest := {}  ## 0xRRGGBB -> 0xRRGGBB of its palette colour
	if all_codes.size() <= colors:
		for code in all_codes:
			nearest[code] = code
	else:
		var palette := _median_cut(counts, colors)
		for code in all_codes:
			var best := 0
			var best_distance := 1 << 30
			for entry in palette:
				var dr: int = ((code >> 16) & 255) - ((entry >> 16) & 255)
				var dg: int = ((code >> 8) & 255) - ((entry >> 8) & 255)
				var db: int = (code & 255) - (entry & 255)
				var distance := dr * dr + dg * dg + db * db
				if distance < best_distance:
					best_distance = distance
					best = entry
			nearest[code] = best
	var alpha_step := 255.0 / (alpha_levels - 1)
	for i in range(0, bytes.size(), 4):
		var alpha := roundi(roundf(bytes[i + 3] / alpha_step) * alpha_step)
		if alpha == 0:
			bytes[i] = 0
			bytes[i + 1] = 0
			bytes[i + 2] = 0
			bytes[i + 3] = 0
			continue
		var code: int = nearest[(bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2]]
		bytes[i] = (code >> 16) & 255
		bytes[i + 1] = (code >> 8) & 255
		bytes[i + 2] = code & 255
		bytes[i + 3] = alpha
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)


## Splits the colours (0xRRGGBB -> pixels) into `colors` boxes: each time the box with the widest channel (weighted
## by the root of its pixels) is cut at its pixel median along that channel. Returns the boxes' weighted averages.
static func _median_cut(counts: Dictionary, colors: int) -> Array[int]:
	var boxes: Array[Array] = [counts.keys()]
	while boxes.size() < colors:
		var widest := -1
		var widest_channel := 0
		var widest_score := 0.0
		for b in boxes.size():
			var box: Array = boxes[b]
			if box.size() < 2:
				continue
			var low := [255, 255, 255]
			var high := [0, 0, 0]
			var pixels := 0
			for code in box:
				for channel in 3:
					var value: int = (code >> (16 - 8 * channel)) & 255
					low[channel] = mini(low[channel], value)
					high[channel] = maxi(high[channel], value)
				pixels += counts[code]
			for channel in 3:
				var score := float(high[channel] - low[channel]) * sqrt(pixels)
				if score > widest_score:
					widest_score = score
					widest = b
					widest_channel = channel
		if widest < 0:
			break
		var box: Array = boxes[widest]
		var shift := 16 - 8 * widest_channel
		box.sort_custom(func(a, b): return ((a >> shift) & 255) < ((b >> shift) & 255))
		var total := 0
		for code in box:
			total += counts[code]
		var running := 0
		var cut := 1
		for i in box.size():
			running += counts[box[i]]
			if running * 2 >= total:
				cut = clampi(i + 1, 1, box.size() - 1)
				break
		boxes[widest] = box.slice(0, cut)
		boxes.append(box.slice(cut))
	var palette: Array[int] = []
	for box in boxes:
		var sums := [0.0, 0.0, 0.0]
		var pixels := 0.0
		for code in box:
			var weight: float = counts[code]
			for channel in 3:
				sums[channel] += ((code >> (16 - 8 * channel)) & 255) * weight
			pixels += weight
		palette.append((roundi(sums[0] / pixels) << 16) | (roundi(sums[1] / pixels) << 8) | roundi(sums[2] / pixels))
	return palette


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
