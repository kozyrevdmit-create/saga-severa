## Character pictures: assets/art/heroes/<id>.png and assets/art/enemies/<id>.png, made by tools/prepare_art.gd
## from the approved art (docs/ART_STYLE.md). Heroes face right, enemies face left.
## Chapter maps: assets/art/maps/<name>.png (stages.json → chapters[].map).
## Odin's ravens for the saga scenes: assets/art/story/<id>.png (Hugin faces right, Munin left).
extends RefCounted

const HEROES_DIR := "res://assets/art/heroes/"
const ENEMIES_DIR := "res://assets/art/enemies/"
const MAPS_DIR := "res://assets/art/maps/"
const STORY_DIR := "res://assets/art/story/"


static func hero_picture(hero_id: String) -> Texture2D:
	return load(HEROES_DIR + hero_id + ".png")


static func enemy_picture(enemy_id: String) -> Texture2D:
	return load(ENEMIES_DIR + enemy_id + ".png")


static func map_picture(map_name: String) -> Texture2D:
	return load(MAPS_DIR + map_name + ".png")


static func raven_picture(raven_id: String) -> Texture2D:
	return load(STORY_DIR + raven_id + ".png")


## Head and shoulders of a hero (data/heroes.json → portrait).
static func hero_portrait(hero: Dictionary) -> AtlasTexture:
	return _portrait(hero_picture(hero["id"]), hero["portrait"])


## A beast's head for its pack on the map (data/enemies.json → portrait).
static func enemy_portrait(enemy: Dictionary) -> AtlasTexture:
	return _portrait(enemy_picture(enemy["id"]), enemy["portrait"])


## A raven's head for the dialog panel (story.json → speakers[id].portrait).
static func raven_portrait(raven_id: String, speaker: Dictionary) -> AtlasTexture:
	return _portrait(raven_picture(raven_id), speaker["portrait"])


## The square from `portrait` (centre x, y and side as shares of the picture), kept inside the picture.
static func _portrait(picture: Texture2D, portrait: Dictionary) -> AtlasTexture:
	var picture_size := picture.get_size()
	var side := float(portrait["size"]) * picture_size.x
	var corner := Vector2(float(portrait["x"]) * picture_size.x, float(portrait["y"]) * picture_size.y) - Vector2(side, side) / 2.0
	var atlas := AtlasTexture.new()
	atlas.atlas = picture
	atlas.region = Rect2(corner.clamp(Vector2.ZERO, picture_size - Vector2(side, side)), Vector2(side, side))
	return atlas
