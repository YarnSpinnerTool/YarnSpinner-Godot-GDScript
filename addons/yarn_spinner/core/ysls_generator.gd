# ======================================================================== #
#                    Yarn Spinner for Godot (GDScript)                     #
# ======================================================================== #
#                                                                          #
# (C) Yarn Spinner Pty. Ltd.                                               #
#                                                                          #
# Yarn Spinner is a trademark of Secret Lab Pty. Ltd.,                     #
# used under license.                                                      #
#                                                                          #
# This code is subject to the terms of the license defined                 #
# in LICENSE.md.                                                           #
#                                                                          #
# For help, support, and more information, visit:                          #
#   https://yarnspinner.dev                                                #
#   https://docs.yarnspinner.dev                                           #
#                                                                          #
# ======================================================================== #

@tool
class_name YarnYSLSGenerator
extends RefCounted
## generates .ysls.json files for yarn spinner language server integration.
## scans for YarnCommandBinding resources, _yarn_command_*/_yarn_function_*
## methods, and registered library commands/functions.


const YSLS_VERSION := 1

var _commands: Dictionary[String, Dictionary] = {}
var _functions: Dictionary[String, Dictionary] = {}
var _scanned_paths: Dictionary[String, bool] = {}


func clear() -> void:
	_commands.clear()
	_functions.clear()
	_scanned_paths.clear()


func scan_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("ysls generator: could not open directory '%s'" % path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while not file_name.is_empty():
		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != "addons":
				scan_directory(full_path)
		else:
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				_scan_resource_file(full_path)
			elif file_name.ends_with(".gd"):
				_scan_gdscript_file(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


func scan_gdscript_file(path: String) -> void:
	_scan_gdscript_file(path)


func scan_library(library: YarnLibrary) -> void:
	if library == null:
		return

	for cmd_name in library._commands:
		var callable: Callable = library._commands[cmd_name]
		var info := _extract_callable_info(callable, cmd_name, true)
		if not info.is_empty():
			_commands[cmd_name] = info

	for cmd_name in library._instance_commands:
		var cmd_info: Dictionary = library._instance_commands[cmd_name]
		var target_script: Script = cmd_info["script"]
		var method_name: String = cmd_info["method"]
		var info := _extract_instance_command_info(target_script, method_name, cmd_name)
		if not info.is_empty():
			_commands[cmd_name] = info

	for func_name in library._functions:
		var callable: Callable = library._functions[func_name]
		var param_count: int = library._function_param_counts.get(func_name, -1)
		var info := _extract_callable_info(callable, func_name, false)
		if not info.is_empty():
			info["return"] = {"type": "any"}
			_functions[func_name] = info


func scan_dialogue_runner(runner) -> void:
	if runner == null:
		return
	if runner.has_method("get_library"):
		scan_library(runner.get_library())


func scan_node(node: Node, recursive: bool = true) -> void:
	_scan_object_methods(node)

	if recursive:
		for child in node.get_children():
			scan_node(child, true)


func generate_ysls_dict() -> Dictionary:
	var commands_array: Array = []
	var functions_array: Array = []

	for cmd_name in _commands:
		commands_array.append(_commands[cmd_name])

	for func_name in _functions:
		functions_array.append(_functions[func_name])

	return {
		"version": YSLS_VERSION,
		"commands": commands_array,
		"functions": functions_array
	}


func generate_ysls_json(pretty: bool = true) -> String:
	var data := generate_ysls_dict()
	if pretty:
		return JSON.stringify(data, "  ")
	return JSON.stringify(data)


func save_ysls(path: String) -> Error:
	var json := generate_ysls_json(true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("ysls generator: could not write to '%s': %s" % [path, error_string(err)])
		return err

	file.store_string(json)
	file.close()
	print("ysls generator: saved '%s' with %d commands, %d functions" % [
		path, _commands.size(), _functions.size()
	])
	return OK


func save_ysls_for_project(yarn_project_path: String) -> Error:
	var ysls_path := yarn_project_path.get_basename() + ".ysls.json"
	return save_ysls(ysls_path)


# =============================================================================
# INTERNAL SCANNING METHODS
# =============================================================================

func _scan_resource_file(path: String) -> void:
	if _scanned_paths.has(path):
		return
	_scanned_paths[path] = true

	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		return

	if res is YarnCommandBinding:
		_process_command_binding(res, path)


func _scan_gdscript_file(path: String) -> void:
	if _scanned_paths.has(path):
		return
	_scanned_paths[path] = true

	var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null:
		return

	var is_node_script := _script_extends_node(script)
	var methods := script.get_script_method_list()
	var file_name := path.get_file()
	var script_class := _get_script_class_name(script, path)

	for method in methods:
		var method_name: String = method["name"]

		if method_name.begins_with("_yarn_command_"):
			var yarn_name := method_name.substr(14)  # remove "_yarn_command_"
			var info := _build_command_info(yarn_name, method_name, method, file_name, is_node_script, script_class)
			_commands[yarn_name] = info

		elif method_name.begins_with("_yarn_function_"):
			var yarn_name := method_name.substr(15)  # remove "_yarn_function_"
			var info := _build_function_info(yarn_name, method_name, method, file_name)
			_functions[yarn_name] = info


func _scan_object_methods(obj: Object) -> void:
	if obj == null:
		return

	var script := obj.get_script() as Script
	if script == null:
		return

	var path: String = script.resource_path if script.resource_path else ""
	var file_name := path.get_file() if not path.is_empty() else "unknown"

	for method in script.get_script_method_list():
		var method_name: String = method["name"]

		if method_name.begins_with("_yarn_command_"):
			var yarn_name := method_name.substr(14)
			var info := _build_command_info(yarn_name, method_name, method, file_name)
			_commands[yarn_name] = info

		elif method_name.begins_with("_yarn_function_"):
			var yarn_name := method_name.substr(15)
			var info := _build_function_info(yarn_name, method_name, method, file_name)
			_functions[yarn_name] = info


func _process_command_binding(binding: YarnCommandBinding, path: String) -> void:
	if not binding.is_valid() or not binding.enabled:
		return

	var file_name := path.get_file()

	# binding resources lack full method signatures, so entries are approximate
	var params: Array = []

	if binding.type == YarnCommandBinding.Type.FUNCTION:
		for i in range(binding.parameter_count):
			params.append({
				"name": "arg%d" % i,
				"type": "any"
			})

		_functions[binding.yarn_name] = {
			"yarnName": binding.yarn_name,
			"definitionName": binding.method_name,
			"fileName": file_name,
			"language": "gdscript",
			"documentation": binding.description,
			"parameters": params,
			"return": {"type": "any"}
		}
	else:
		_commands[binding.yarn_name] = {
			"yarnName": binding.yarn_name,
			"definitionName": binding.method_name,
			"fileName": file_name,
			"language": "gdscript",
			"documentation": binding.description,
			"parameters": params
		}


func _extract_callable_info(callable: Callable, yarn_name: String, is_command: bool) -> Dictionary:
	if not callable.is_valid():
		return {}

	var obj := callable.get_object()
	var method_name := callable.get_method()

	if obj == null or method_name.is_empty():
		return {}

	var method_info: Dictionary = {}
	for method in obj.get_method_list():
		if method["name"] == method_name:
			method_info = method
			break

	if method_info.is_empty():
		return {
			"yarnName": yarn_name,
			"definitionName": method_name,
			"language": "gdscript",
			"parameters": []
		}

	var file_name := "unknown"
	var script := obj.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		file_name = script.resource_path.get_file()

	if is_command:
		return _build_command_info(yarn_name, method_name, method_info, file_name)
	else:
		return _build_function_info(yarn_name, method_name, method_info, file_name)


func _extract_instance_command_info(target_script: Script, method_name: String, yarn_name: String) -> Dictionary:
	if target_script == null:
		return {}

	var method_info: Dictionary = {}
	var methods := target_script.get_script_method_list()
	for method in methods:
		if method["name"] == method_name:
			method_info = method
			break

	var file_name := "unknown"
	var target_class := ""
	if not target_script.resource_path.is_empty():
		file_name = target_script.resource_path.get_file()
		target_class = _get_script_class_name(target_script, target_script.resource_path)

	if method_info.is_empty():
		var params: Array = [{
			"name": "target",
			"type": "instance",
			"documentation": "the %s to call this command on" % (target_class if not target_class.is_empty() else "node")
		}]
		if not target_class.is_empty():
			params[0]["subtype"] = target_class
		return {
			"yarnName": yarn_name,
			"definitionName": method_name,
			"fileName": file_name,
			"language": "gdscript",
			"parameters": params
		}

	return _build_command_info(yarn_name, method_name, method_info, file_name, true, target_class)


func _build_command_info(yarn_name: String, method_name: String, method_info: Dictionary, file_name: String, is_instance_command: bool = false, target_class: String = "") -> Dictionary:
	var params := _build_parameters(method_info)
	var is_async := _is_async_method(method_info)

	# instance commands prepend a target parameter: <<move mae destination>>
	if is_instance_command:
		var target_param := {
			"name": "target",
			"type": "instance",
			"documentation": "the %s to call this command on" % (target_class if not target_class.is_empty() else "node")
		}
		if not target_class.is_empty():
			target_param["subtype"] = target_class
		params.push_front(target_param)

	return {
		"yarnName": yarn_name,
		"definitionName": method_name,
		"fileName": file_name,
		"language": "gdscript",
		"parameters": params,
		"async": is_async
	}


func _build_function_info(yarn_name: String, method_name: String, method_info: Dictionary, file_name: String) -> Dictionary:
	var params := _build_parameters(method_info)
	var return_type := _get_return_type(method_info)

	return {
		"yarnName": yarn_name,
		"definitionName": method_name,
		"fileName": file_name,
		"language": "gdscript",
		"parameters": params,
		"return": {"type": return_type}
	}


func _build_parameters(method_info: Dictionary) -> Array:
	var params: Array = []
	var args: Array = method_info.get("args", [])
	var defaults: Array = method_info.get("default_args", [])

	# defaults are aligned to the end of the args list
	var default_start := args.size() - defaults.size()

	for i in range(args.size()):
		var arg: Dictionary = args[i]
		var param := {
			"name": arg.get("name", "arg%d" % i),
			"type": _gdscript_type_to_yarn_type(arg.get("type", TYPE_NIL), arg.get("class_name", ""))
		}

		if i >= default_start:
			var default_idx := i - default_start
			var default_val: Variant = defaults[default_idx]
			param["defaultValue"] = str(default_val)

		params.append(param)

	return params


func _gdscript_type_to_yarn_type(type: int, type_class: String) -> String:
	match type:
		TYPE_BOOL:
			return "bool"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_STRING, TYPE_STRING_NAME:
			return "string"
		TYPE_OBJECT:
			if not type_class.is_empty():
				if type_class == "Node" or ClassDB.is_parent_class(type_class, "Node"):
					return "node"
				return "instance"
			return "any"
		TYPE_NIL:
			return "any"
		_:
			return "any"


func _get_return_type(method_info: Dictionary) -> String:
	var return_info: Dictionary = method_info.get("return", {})
	var type: int = return_info.get("type", TYPE_NIL)
	var type_class: String = return_info.get("class_name", "")
	return _gdscript_type_to_yarn_type(type, type_class)


func _is_async_method(method_info: Dictionary) -> bool:
	var return_info: Dictionary = method_info.get("return", {})
	var type: int = return_info.get("type", TYPE_NIL)
	var type_class: String = return_info.get("class_name", "")

	if type == TYPE_SIGNAL:
		return true

	if type == TYPE_OBJECT and type_class == "Signal":
		return true

	return false


func _script_extends_node(script: Script) -> bool:
	if script == null:
		return false

	var current: Script = script
	while current != null:
		var base := current.get_instance_base_type()
		if base == &"Node" or ClassDB.is_parent_class(base, "Node"):
			return true
		current = current.get_base_script()

	return false


func _get_script_class_name(script: Script, path: String) -> String:
	var global_classes := ProjectSettings.get_global_class_list()
	for class_info in global_classes:
		if class_info.get("path", "") == path:
			return class_info.get("class", "")

	# fallback: derive from file name (e.g., "character.gd" -> "Character")
	var file_name := path.get_file().get_basename()
	return file_name.to_pascal_case()


# =============================================================================
# STATIC HELPERS
# =============================================================================

static func generate_for_project(yarn_project_path: String, scan_root: String = "res://") -> Error:
	var generator := YarnYSLSGenerator.new()
	generator.scan_directory(scan_root)
	return generator.save_ysls_for_project(yarn_project_path)


static func generate_from_runner(yarn_project_path: String, dialogue_runner) -> Error:
	var generator := YarnYSLSGenerator.new()
	generator.scan_dialogue_runner(dialogue_runner)
	return generator.save_ysls_for_project(yarn_project_path)
