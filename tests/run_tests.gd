## Headless test runner. Runs every test_* method in tests/test_*.gd:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exit code 0 = all passed, 1 = something failed.
## Any engine/script error printed during a test also fails that test.
extends SceneTree


class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		errors.append("%s (%s:%d)" % [rationale if not rationale.is_empty() else code, file, line])

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var passed := 0
	var failed := 0

	var files := Array(DirAccess.get_files_at("res://tests"))
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")):
			continue
		catcher.errors.clear()
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate() or not catcher.errors.is_empty():
			failed += 1
			print("FAIL  %s: cannot load" % file)
			for error in catcher.errors:
				print("        " + error)
			continue
		print(file)
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			catcher.errors.clear()
			var suite = script.new()
			suite.call(test_name)
			var problems: Array = suite.failures + catcher.errors
			if problems.is_empty():
				passed += 1
				print("  ok    " + test_name)
			else:
				failed += 1
				print("  FAIL  " + test_name)
				for problem in problems:
					print("        " + problem)

	OS.remove_logger(catcher)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
