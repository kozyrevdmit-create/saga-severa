## Every script and scene in the project loads without errors (catches mistakes in screens the other tests do not run).
extends "res://tests/base_test.gd"

const SCRIPT_DIRS := ["res://scripts", "res://tools"]
const SCENE_DIR := "res://scenes"


func test_all_scripts_load() -> void:
	var paths := []
	for dir in SCRIPT_DIRS:
		paths.append_array(_files_in(dir, ".gd"))
	assert_true(paths.size() > 10, "found the project's scripts")
	for path in paths:
		var script = load(path)
		assert_true(script is GDScript and script.can_instantiate(), "%s loads" % path)


func test_all_scenes_load_and_build() -> void:
	var paths := _files_in(SCENE_DIR, ".tscn")
	assert_true(paths.size() >= 6, "found the project's scenes")
	for path in paths:
		var scene = load(path)
		assert_true(scene is PackedScene, "%s loads" % path)
		if scene is PackedScene:
			var node: Node = scene.instantiate()
			assert_true(node != null, "%s builds" % path)
			node.free()


func _files_in(dir: String, extension: String) -> Array:
	var result := []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(extension):
			result.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		result.append_array(_files_in(dir.path_join(sub), extension))
	return result
