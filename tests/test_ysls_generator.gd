extends GutTest


const COMMAND_SOURCE := """extends Node

## Moves somewhere.
## Really.
func _yarn_command_move(destination: Node2D, speed: float = 2.5) -> void:
	await get_tree().process_frame


static func _yarn_command_log_all(prefix: String, ...rest: Array) -> void:
	print("await", prefix, rest) # await


static func _yarn_function_add(a: int, b: float) -> float:
	return a + b


func _yarn_function_not_static(a: int) -> int:
	return a


func _ready() -> void:
	get_parent().add_function("double", _double)
	get_parent().add_command("shout", _shout)


func _double(value: float) -> float:
	return value * 2.0


func _shout(message: String, times: int = 3) -> Signal:
	return get_tree().process_frame
"""


func _make_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = COMMAND_SOURCE
	assert_eq(script.reload(), OK)
	return script


func _find(entries: Array, yarn_name: String) -> Dictionary:
	for entry in entries:
		if entry["yarnName"] == yarn_name:
			return entry
	return {}


func test_version_and_builtin_wait():
	var generator := YarnYSLSGenerator.new()
	var data := generator.generate_ysls_dict()
	assert_eq(data["version"], 2)
	var wait := _find(data["commands"], "wait")
	assert_false(wait.is_empty())
	assert_true(wait["async"])
	assert_eq(wait["parameters"].size(), 1)
	assert_eq(wait["parameters"][0]["type"], "number")
	assert_false(wait["parameters"][0].has("defaultValue"))
	assert_true(_find(data["commands"], "stop").is_empty())


func test_builtin_functions_leave_out_core_functions():
	var generator := YarnYSLSGenerator.new()
	var data := generator.generate_ysls_dict()
	for core_name in ["visited", "visited_count", "has_any_content"]:
		assert_true(_find(data["functions"], core_name).is_empty(), core_name)
	assert_false(_find(data["functions"], "abs").is_empty())
	assert_false(_find(data["functions"], "uppercase").is_empty())
	var file_names: Array = []
	for entry: Dictionary in generator.generate_ysls_file_dict()["functions"]:
		file_names.append(entry["yarnName"])
	assert_false(file_names.has("visited"))
	assert_true(file_names.has("plural"))


func test_file_uses_current_format():
	var generator := YarnYSLSGenerator.new()
	generator._scan_script_methods(_make_script(), "res://fixture/mover.gd")
	var data := generator.generate_ysls_file_dict()
	assert_eq(data.keys(), ["version", "commands", "functions"])
	var add := _find(data["functions"], "add")
	assert_eq(add["return"], {"type": "number"})
	assert_eq(add["parameters"][0]["name"], "a")
	assert_eq(add["parameters"][0]["type"], "number")


func test_node_name_parameters_are_nodes():
	var script := GDScript.new()
	script.source_code = "extends Node\n\nstatic func _yarn_function_go_to(destination: YarnNodeName) -> bool:\n\treturn true\n\n\nstatic func _yarn_command_travel(destination: YarnNodeName) -> void:\n\tpass\n"
	assert_eq(script.reload(), OK)

	var generator := YarnYSLSGenerator.new()
	generator._scan_script_methods(script, "res://fixture/travel.gd")
	var data := generator.generate_ysls_dict()
	assert_eq(_find(data["functions"], "go_to")["parameters"][0], {"name": "destination", "isParamsArray": false, "type": "node"})
	assert_eq(_find(data["commands"], "travel")["parameters"][0]["type"], "node")
	assert_false(_find(data["functions"], "go_to")["containsErrors"])

	generator.instance_parameters_as_strings = true
	assert_eq(_find(generator.generate_ysls_dict()["functions"], "go_to")["parameters"][0]["type"], "string")


func test_deprecated_node_hint_still_works():
	var script := GDScript.new()
	script.source_code = "extends Node\n\n## Goes somewhere.\n## @yarn_node destination\nstatic func _yarn_function_go(destination: String) -> bool:\n\treturn true\n"
	assert_eq(script.reload(), OK)
	var generator := YarnYSLSGenerator.new()
	generator._scan_script_methods(script, "res://fixture/old_travel.gd")
	generator._scan_script_methods(script, "res://fixture/old_travel_again.gd")
	var go := _find(generator.generate_ysls_dict()["functions"], "go")
	assert_eq(go["parameters"][0]["type"], "node")
	assert_eq(go["documentation"], "Goes somewhere.")


func test_node_name_type_from_source_text():
	var generator := YarnYSLSGenerator.new()
	assert_eq(generator._yarn_type_info_from_text("YarnNodeName"), {"type": "node", "rawType": "string"})


const VARIADIC_SOURCE := """extends Node

## Checks the inventory.
## @yarn_variadic string
static func _yarn_function_has_all_items(...items: Array) -> bool:
	return true


## @yarn_variadic strng
static func _yarn_function_misspelt(...items: Array) -> bool:
	return true


static func _yarn_function_unhinted(...items: Array) -> bool:
	return true


## @yarn_variadic number
static func _yarn_command_score(player: String, ...points: Array) -> void:
	pass
"""


func _variadic_data() -> Dictionary:
	var script := GDScript.new()
	script.source_code = VARIADIC_SOURCE
	assert_eq(script.reload(), OK)
	var generator := YarnYSLSGenerator.new()
	generator._scan_script_methods(script, "res://fixture/inventory.gd")
	return {"generator": generator, "data": generator.generate_ysls_dict()}


func test_variadic_hint_sets_the_rest_parameter_type():
	var data: Dictionary = _variadic_data()["data"]
	var has_all := _find(data["functions"], "has_all_items")
	assert_eq(has_all["parameters"], [{"name": "items", "type": "string", "isParamsArray": true}])
	assert_eq(has_all["documentation"], "Checks the inventory.")
	var score := _find(data["commands"], "score")
	assert_eq(score["parameters"][0]["type"], "string")
	assert_eq(score["parameters"][1], {"name": "points", "type": "number", "isParamsArray": true})


func test_variadic_hint_ignores_unknown_types():
	var data: Dictionary = _variadic_data()["data"]
	assert_eq(_find(data["functions"], "misspelt")["parameters"][0]["type"], "any")
	assert_eq(_find(data["functions"], "unhinted")["parameters"][0]["type"], "any")


func test_variadic_hint_lets_the_function_be_declared():
	var generator: YarnYSLSGenerator = _variadic_data()["generator"]
	var importer := load("res://addons/yarn_spinner/editor/yarn_project_importer.gd")
	var declared := {}
	for declaration: Dictionary in importer._function_declarations(generator, ProjectSettings.globalize_path("res://none.yarnproject"), 5):
		declared[declaration["name"]] = declaration
	assert_eq(declared["has_all_items"]["parameters"], [])
	assert_eq(declared["has_all_items"]["variadicParameterType"], "string")
	assert_false(declared.has("misspelt"))
	assert_false(declared.has("unhinted"))


func test_legacy_functions():
	var legacy := YarnYSLSGenerator.legacy_functions([
		{
			"yarnName": "feed",
			"definitionName": "_feed",
			"fileName": "pet.gd",
			"parameters": [
				{"name": "target", "type": "instance", "subtype": "Pet", "isParamsArray": false},
				{"name": "amount", "type": "number", "defaultValue": "1", "isParamsArray": false},
			],
			"return": {"type": "bool"},
		},
		{"yarnName": "shout", "parameters": [], "return": "string"},
		"not a function",
	])
	assert_eq(legacy.size(), 2)
	assert_eq(legacy[0]["YarnName"], "feed")
	assert_eq(legacy[0]["ReturnType"], "bool")
	assert_eq(legacy[0]["Documentation"], "")
	assert_eq(legacy[0]["Parameters"][0], {"Name": "target", "Type": "any", "IsParamsArray": false, "Subtype": "Pet"})
	assert_eq(legacy[0]["Parameters"][1]["DefaultValue"], "1")
	assert_eq(legacy[1]["ReturnType"], "string")


func test_node_types_are_instances():
	var generator := YarnYSLSGenerator.new()
	assert_eq(generator._yarn_type_info(TYPE_OBJECT, "Node2D"), {"type": "instance", "subtype": "Node2D"})
	assert_eq(generator._yarn_type_info(TYPE_OBJECT, "Resource"), {"type": "any"})
	assert_eq(generator._yarn_type_info(TYPE_INT, ""), {"type": "number"})


func test_script_methods():
	var generator := YarnYSLSGenerator.new()
	generator._scan_script_methods(_make_script(), "res://fixture/mover.gd")
	var data := generator.generate_ysls_dict()

	var move := _find(data["commands"], "move")
	assert_true(move["async"])
	assert_eq(move["documentation"], "Moves somewhere.\nReally.")
	assert_eq(move["parameters"][0]["type"], "instance")
	assert_eq(move["parameters"][0]["subtype"], "Mover")
	assert_eq(move["parameters"][1], {"name": "destination", "type": "instance", "subtype": "Node2D", "isParamsArray": false})
	assert_eq(move["parameters"][2]["defaultValue"], "2.5")
	assert_eq(move["location"]["start"], {"line": 4, "character": 0})
	assert_eq(move["location"]["end"]["line"], 5)

	var log_all := _find(data["commands"], "log_all")
	assert_false(log_all["async"])
	assert_eq(log_all["parameters"].size(), 2)
	assert_eq(log_all["parameters"][1], {"name": "rest", "type": "any", "isParamsArray": true})

	var add := _find(data["functions"], "add")
	assert_eq(add["return"], {"type": "number"})
	assert_true(_find(data["functions"], "not_static").is_empty())


func test_call_sites_resolve_same_file_handlers():
	var generator := YarnYSLSGenerator.new()
	generator._scan_runtime_bindings(COMMAND_SOURCE, "mover.gd")
	var data := generator.generate_ysls_dict()

	var double := _find(data["functions"], "double")
	assert_eq(double["definitionName"], "_double")
	assert_eq(double["return"], {"type": "number"})
	assert_eq(double["parameters"][0]["type"], "number")

	var shout := _find(data["commands"], "shout")
	assert_true(shout["async"])
	assert_eq(shout["parameters"][1]["defaultValue"], "3")
