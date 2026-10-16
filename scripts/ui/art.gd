## Character pictures: assets/art/heroes/<id>.png and assets/art/enemies/<id>.png, made by tools/prepare_art.gd
## from the approved art (docs/ART_STYLE.md). Heroes face right, enemies face left.
extends RefCounted

const HEROES_DIR := "res://assets/art/heroes/"
const ENEMIES_DIR := "res://assets/art/enemies/"


static func hero_picture(hero_id: String) -> Texture2D:
	return load(HEROES_DIR + hero_id + ".png")


static func enemy_picture(enemy_id: String) -> Texture2D:
	return load(ENEMIES_DIR + enemy_id + ".png")


## Head and shoulders: the square from data/heroes.json → portrait (centre x, y and side as shares of the picture),
## kept inside the picture.
static func hero_portrait(hero: Dictionary) -> AtlasTexture:
	var picture := hero_picture(hero["id"])
	var picture_size := picture.get_size()
	var portrait: Dictionary = hero["portrait"]
	var side := float(portrait["size"]) * picture_size.x
	var corner := Vector2(float(portrait["x"]) * picture_size.x, float(portrait["y"]) * picture_size.y) - Vector2(side, side) / 2.0
	var atlas := AtlasTexture.new()
	atlas.atlas = picture
	atlas.region = Rect2(corner.clamp(Vector2.ZERO, picture_size - Vector2(side, side)), Vector2(side, side))
	return atlas
