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
