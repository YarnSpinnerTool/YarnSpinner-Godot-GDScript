extends GutTest


const REGISTRY_FILE := "user://yarn_action_registry_test.json"


func after_each():
	if FileAccess.file_exists(REGISTRY_FILE):
		DirAccess.remove_absolute(REGISTRY_FILE)


func _write_registry(contents: String) -> void:
	var file := FileAccess.open(REGISTRY_FILE, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func test_only_declarations_count():
	assert_true(YarnActionDiscovery.declares_yarn_action("extends Node\n\nfunc _yarn_command_shake(x: float) -> void:\n\tpass"))
	assert_true(YarnActionDiscovery.declares_yarn_action("static func _yarn_function_twice(x: float) -> float:\n\treturn x * 2"))
	assert_false(YarnActionDiscovery.declares_yarn_action("var prefix := \"_yarn_command_\"\n# _yarn_function_ names"))


func test_registry_lists_scripts():
	_write_registry(JSON.stringify({"version": 1, "scripts": ["res://tests/test_action_discovery.gd"]}))
	var registry := YarnActionDiscovery.load_registry(REGISTRY_FILE)
	assert_true(registry.found)
	assert_eq(registry.scripts, PackedStringArray(["res://tests/test_action_discovery.gd"]))


func test_missing_registry_falls_back_to_scanning():
	assert_false(YarnActionDiscovery.load_registry("user://no_such_yarn_registry.json").found)


func test_unreadable_registry_is_ignored():
	_write_registry("not json")
	assert_false(YarnActionDiscovery.load_registry(REGISTRY_FILE).found)
	_write_registry(JSON.stringify({"version": 99, "scripts": []}))
	assert_false(YarnActionDiscovery.load_registry(REGISTRY_FILE).found)


func test_built_registry_is_readable():
	_write_registry(YarnActionDiscovery.build_registry())
	var registry := YarnActionDiscovery.load_registry(REGISTRY_FILE)
	assert_true(registry.found)
	assert_eq(registry.scripts, YarnActionDiscovery.find_action_script_paths())
	for path in registry.scripts:
		assert_false(path.begins_with("res://addons/yarn_spinner/"))
