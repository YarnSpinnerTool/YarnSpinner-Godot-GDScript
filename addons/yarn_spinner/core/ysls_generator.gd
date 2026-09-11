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


const YSLS_VERSION := 2

var _commands: Dictionary[String, Dictionary] = {}
var _functions: Dictionary[String, Dictionary] = {}
var _scanned_paths: Dictionary[String, bool] = {}
var _source_cache: Dictionary[String, Dictionary] = {}
var _global_class_bases: Dictionary[String, String] = {}


func clear() -> void:
	_commands.clear()
	_functions.clear()
	_scanned_paths.clear()
	_source_cache.clear()
	_global_class_bases.clear()


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
		var info := _extract_callable_info(callable, func_name, false)
		if not info.is_empty():
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

	var builtin_names: Dictionary[String, bool] = {}
	for builtin in _get_builtin_commands():
		builtin_names[builtin["yarnName"]] = true
		commands_array.append(builtin)

	for cmd_name in _commands:
		if not builtin_names.has(cmd_name):
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
	var data := generate_ysls_dict()
	var json := JSON.stringify(data, "  ")

	# Skip the write if contents are unchanged. Godot's filesystem_changed
	# signal retriggers YSLS regeneration, so a no-op write would loop forever.
	if FileAccess.file_exists(path):
		var existing := FileAccess.open(path, FileAccess.READ)
		if existing != null:
			var existing_text := existing.get_as_text()
			existing.close()
			if existing_text == json:
				return OK

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("ysls generator: could not write to '%s': %s" % [path, error_string(err)])
		return err

	file.store_string(json)
	file.close()
	print("ysls generator: saved '%s' with %d commands, %d functions" % [
		path, data["commands"].size(), data["functions"].size()
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

	var file_name := path.get_file()

	# Scan source for runtime binding registrations (add_binding, add_command, etc.)
	var source := FileAccess.get_file_as_string(path)
	if not source.is_empty():
		_scan_runtime_bindings(source, file_name, path)

	# Loading the script (below) compiles it, which is expensive and noisy when
	# scanning a whole project. It is only needed to discover annotated
	# `_yarn_command_*` / `_yarn_function_*` methods, so skip it otherwise.
	if not (source.contains("_yarn_command_") or source.contains("_yarn_function_")):
		return

	var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null:
		return

	_scan_script_methods(script, path)


func _scan_object_methods(obj: Object) -> void:
	if obj == null:
		return

	var script := obj.get_script() as Script
	if script == null:
		return

	_scan_script_methods(script, script.resource_path)


func _scan_script_methods(script: Script, path: String) -> void:
	var file_name := path.get_file() if not path.is_empty() else "unknown"
	var script_class := _get_script_class_name(script, path)

	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		var is_static: bool = (method.get("flags", 0) & METHOD_FLAG_STATIC) != 0

		if method_name.begins_with("_yarn_command_"):
			var yarn_name := method_name.substr(14)  # remove "_yarn_command_"
			var source_method := _find_source_method(script, method_name)
			_commands[yarn_name] = _build_command_info(yarn_name, method_name, method, file_name, not is_static, script_class, source_method)

		elif method_name.begins_with("_yarn_function_"):
			if not is_static:
				continue
			var yarn_name := method_name.substr(15)  # remove "_yarn_function_"
			var source_method := _find_source_method(script, method_name)
			_functions[yarn_name] = _build_function_info(yarn_name, method_name, method, file_name, source_method)


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
				"type": "any",
				"isParamsArray": false
			})

		var info := {
			"yarnName": binding.yarn_name,
			"definitionName": binding.method_name,
			"fileName": file_name,
			"language": "gdscript",
			"parameters": params,
			"async": false,
			"return": {"type": "any"}
		}
		if not binding.description.is_empty():
			info["documentation"] = binding.description
		_functions[binding.yarn_name] = info
	else:
		var info := {
			"yarnName": binding.yarn_name,
			"definitionName": binding.method_name,
			"fileName": file_name,
			"language": "gdscript",
			"parameters": params,
			"async": false
		}
		if not binding.description.is_empty():
			info["documentation"] = binding.description
		_commands[binding.yarn_name] = info


func _extract_callable_info(callable: Callable, yarn_name: String, is_command: bool) -> Dictionary:
	if not callable.is_valid():
		return {}

	var obj := callable.get_object()
	var method_name := callable.get_method()

	if obj == null or method_name.is_empty():
		return {}

	var script: Script = obj as Script if obj is Script else obj.get_script() as Script
	var file_name := "unknown"
	if script != null and not script.resource_path.is_empty():
		file_name = script.resource_path.get_file()

	var method_list: Array = script.get_script_method_list() if obj is Script else obj.get_method_list()
	var method_info: Dictionary = {}
	for method in method_list:
		if method["name"] == method_name:
			method_info = method
			break

	if method_info.is_empty():
		var fallback := {
			"yarnName": yarn_name,
			"definitionName": method_name,
			"fileName": file_name,
			"language": "gdscript",
			"parameters": [],
			"async": false
		}
		if not is_command:
			fallback["return"] = {"type": "any"}
		return fallback

	var source_method := _find_source_method(script, method_name)

	if is_command:
		return _build_command_info(yarn_name, method_name, method_info, file_name, false, "", source_method)
	else:
		return _build_function_info(yarn_name, method_name, method_info, file_name, source_method)


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
		return {
			"yarnName": yarn_name,
			"definitionName": method_name,
			"fileName": file_name,
			"language": "gdscript",
			"parameters": [_make_target_parameter(target_class)],
			"async": false
		}

	var source_method := _find_source_method(target_script, method_name)
	return _build_command_info(yarn_name, method_name, method_info, file_name, true, target_class, source_method)


func _make_target_parameter(target_class: String) -> Dictionary:
	var target_param := {
		"name": "target",
		"type": "instance",
		"documentation": "The name of the %s node the runner will search for to run this command upon." % (target_class if not target_class.is_empty() else "Node"),
		"isParamsArray": false
	}
	if not target_class.is_empty():
		target_param["subtype"] = target_class
	return target_param


func _build_command_info(yarn_name: String, method_name: String, method_info: Dictionary, file_name: String, is_instance_command: bool = false, target_class: String = "", source_method: Dictionary = {}) -> Dictionary:
	var params := _build_parameters(method_info, source_method)
	var is_async: bool = _is_async_method(method_info) or source_method.get("has_await", false)

	# instance commands prepend a target parameter: <<move mae destination>>
	if is_instance_command:
		params.push_front(_make_target_parameter(target_class))

	var info := {
		"yarnName": yarn_name,
		"definitionName": method_name,
		"fileName": file_name,
		"language": "gdscript",
		"parameters": params,
		"async": is_async
	}
	_apply_source_details(info, source_method)
	return info


func _build_function_info(yarn_name: String, method_name: String, method_info: Dictionary, file_name: String, source_method: Dictionary = {}) -> Dictionary:
	var params := _build_parameters(method_info, source_method)
	var return_type := _get_return_type(method_info)
	if return_type == "any" and not source_method.is_empty():
		return_type = _yarn_return_type_from_text(source_method.get("return_text", ""))

	var info := {
		"yarnName": yarn_name,
		"definitionName": method_name,
		"fileName": file_name,
		"language": "gdscript",
		"parameters": params,
		"async": false,
		"return": {"type": return_type}
	}
	_apply_source_details(info, source_method)
	return info


func _apply_source_details(info: Dictionary, source_method: Dictionary) -> void:
	if source_method.is_empty():
		return
	var documentation: String = source_method.get("documentation", "")
	if not documentation.is_empty():
		info["documentation"] = documentation
	info["location"] = {
		"start": {"line": source_method["start_line"], "character": source_method["start_character"]},
		"end": {"line": source_method["end_line"], "character": source_method["end_character"]}
	}


func _build_parameters(method_info: Dictionary, source_method: Dictionary = {}) -> Array:
	var params: Array = []
	var args: Array = method_info.get("args", [])
	var defaults: Array = method_info.get("default_args", [])

	# defaults are aligned to the end of the args list
	var default_start := args.size() - defaults.size()

	for i in range(args.size()):
		var arg: Dictionary = args[i]
		var param := {
			"name": arg.get("name", "arg%d" % i),
			"isParamsArray": false
		}
		param.merge(_yarn_type_info(arg.get("type", TYPE_NIL), arg.get("class_name", "")))

		if i >= default_start:
			var default_idx := i - default_start
			var default_val: Variant = defaults[default_idx]
			param["defaultValue"] = "null" if typeof(default_val) == TYPE_NIL else str(default_val)

		params.append(param)

	if (method_info.get("flags", 0) & METHOD_FLAG_VARARG) != 0:
		var rest_name := "args"
		for source_param in source_method.get("params", []):
			if source_param["is_rest"]:
				rest_name = source_param["name"]
		params.append({
			"name": rest_name,
			"type": "any",
			"isParamsArray": true
		})

	return params


func _build_parameters_from_source(source_method: Dictionary) -> Array:
	var params: Array = []
	for source_param in source_method.get("params", []):
		var param := {
			"name": source_param["name"],
			"isParamsArray": source_param["is_rest"]
		}
		if source_param["is_rest"]:
			param["type"] = "any"
		else:
			param.merge(_yarn_type_info_from_text(source_param["type_text"]))
			if not source_param["default_text"].is_empty():
				param["defaultValue"] = source_param["default_text"].trim_prefix("\"").trim_suffix("\"")
		params.append(param)
	return params


func _yarn_type_info(type: int, type_class: String) -> Dictionary:
	match type:
		TYPE_BOOL:
			return {"type": "bool"}
		TYPE_INT, TYPE_FLOAT:
			return {"type": "number"}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"type": "string"}
		TYPE_OBJECT:
			if _is_node_class_name(type_class):
				return {"type": "instance", "subtype": type_class}
			return {"type": "any"}
		_:
			return {"type": "any"}


func _yarn_type_info_from_text(type_text: String) -> Dictionary:
	match type_text.strip_edges():
		"bool":
			return {"type": "bool"}
		"int", "float":
			return {"type": "number"}
		"String", "StringName":
			return {"type": "string"}
		var other:
			if _is_node_class_name(other):
				return {"type": "instance", "subtype": other}
			return {"type": "any"}


func _yarn_return_type_from_text(type_text: String) -> String:
	var info := _yarn_type_info_from_text(type_text)
	return "any" if info["type"] == "instance" else info["type"]


func _is_node_class_name(type_class: String) -> bool:
	if type_class.is_empty():
		return false

	if _global_class_bases.is_empty():
		for class_info in ProjectSettings.get_global_class_list():
			_global_class_bases[String(class_info.get("class", ""))] = String(class_info.get("base", ""))

	var current := type_class
	for i in range(64):
		if current == "Node":
			return true
		if ClassDB.class_exists(current):
			return ClassDB.is_parent_class(current, "Node")
		if not _global_class_bases.has(current):
			return false
		current = _global_class_bases[current]
	return false


func _get_return_type(method_info: Dictionary) -> String:
	var return_info: Dictionary = method_info.get("return", {})
	var type: int = return_info.get("type", TYPE_NIL)
	match type:
		TYPE_BOOL:
			return "bool"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_STRING, TYPE_STRING_NAME:
			return "string"
		_:
			return "any"


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


func _get_builtin_commands() -> Array[Dictionary]:
	var wait := {
		"yarnName": "wait",
		"definitionName": "_cmd_wait",
		"fileName": "dialogue_runner.gd",
		"language": "gdscript",
		"documentation": "Pauses the dialogue for the given number of seconds.",
		"async": true,
		"parameters": [{
			"name": "duration",
			"type": "number",
			"documentation": "How long to wait, in seconds.",
			"isParamsArray": false
		}]
	}

	var own_script := get_script() as Script
	if own_script != null and not own_script.resource_path.is_empty():
		var runner_path := own_script.resource_path.get_base_dir().get_base_dir().path_join("dialogue_runner.gd")
		var source_method: Dictionary = _get_source_methods(runner_path, "").get("_cmd_wait", {})
		if not source_method.is_empty():
			wait["location"] = {
				"start": {"line": source_method["start_line"], "character": source_method["start_character"]},
				"end": {"line": source_method["end_line"], "character": source_method["end_character"]}
			}

	return [wait]


var _func_decl_regex: RegEx
var _param_regex: RegEx
var _return_regex: RegEx
var _await_regex: RegEx


func _find_source_method(script: Script, method_name: String) -> Dictionary:
	var current := script
	while current != null:
		var fallback_source := ""
		if current is GDScript:
			fallback_source = (current as GDScript).source_code
		var methods := _get_source_methods(current.resource_path, fallback_source)
		if methods.has(method_name):
			return methods[method_name]
		current = current.get_base_script()
	return {}


func _get_source_methods(path: String, fallback_source: String) -> Dictionary:
	if not path.is_empty() and _source_cache.has(path):
		return _source_cache[path]

	var source := ""
	if not path.is_empty() and FileAccess.file_exists(path):
		source = FileAccess.get_file_as_string(path)
	if source.is_empty():
		source = fallback_source

	var methods := _parse_source_methods(source)
	if not path.is_empty():
		_source_cache[path] = methods
	return methods


func _parse_source_methods(source: String) -> Dictionary:
	var methods: Dictionary = {}
	if source.is_empty():
		return methods

	if _func_decl_regex == null:
		_func_decl_regex = RegEx.new()
		_func_decl_regex.compile("^(?:static\\s+)?func\\s+([A-Za-z_]\\w*)\\s*\\(")
		_return_regex = RegEx.new()
		_return_regex.compile("^\\s*->\\s*([A-Za-z_][\\w.]*)")
		_await_regex = RegEx.new()
		_await_regex.compile("\\bawait\\b")

	var lines := source.replace("\r", "").split("\n")
	var line_index := 0

	while line_index < lines.size():
		var match_result := _func_decl_regex.search(lines[line_index])
		if match_result == null:
			line_index += 1
			continue

		var method_name := match_result.get_string(1)
		var start_line := line_index

		var signature := lines[line_index].substr(match_result.get_end())
		var sig_end_line := line_index
		var depth := 1
		var param_text := ""
		var after_params := ""
		var closed := false
		while not closed:
			var in_string := ""
			for char_index in range(signature.length()):
				var c := signature[char_index]
				if not in_string.is_empty():
					if c == in_string:
						in_string = ""
					param_text += c
					continue
				if c == "\"" or c == "'":
					in_string = c
				elif c == "(" or c == "[" or c == "{":
					depth += 1
				elif c == ")" or c == "]" or c == "}":
					depth -= 1
					if depth == 0:
						after_params = signature.substr(char_index + 1)
						closed = true
						break
				param_text += c
			if closed or sig_end_line + 1 >= lines.size():
				break
			param_text += " "
			sig_end_line += 1
			signature = lines[sig_end_line]

		var return_text := ""
		var return_match := _return_regex.search(after_params)
		if return_match != null:
			return_text = return_match.get_string(1)

		var body_code := ""
		var colon_index := after_params.find(":")
		if colon_index >= 0:
			body_code += _strip_code_line(after_params.substr(colon_index + 1)) + "\n"

		var end_line := sig_end_line
		var body_index := sig_end_line + 1
		while body_index < lines.size():
			var body_line := lines[body_index]
			if body_line.strip_edges().is_empty() or body_line.begins_with("#"):
				body_index += 1
				continue
			if not (body_line.begins_with("\t") or body_line.begins_with(" ")):
				break
			body_code += _strip_code_line(body_line) + "\n"
			end_line = body_index
			body_index += 1

		if not methods.has(method_name):
			methods[method_name] = {
				"start_line": start_line,
				"start_character": 0,
				"end_line": end_line,
				"end_character": lines[end_line].length(),
				"documentation": _read_doc_comment(lines, start_line),
				"has_await": _await_regex.search(body_code) != null,
				"params": _parse_param_list(param_text),
				"return_text": return_text
			}

		line_index = maxi(body_index, line_index + 1)

	return methods


func _strip_code_line(line: String) -> String:
	var result := ""
	var in_string := ""
	for char_index in range(line.length()):
		var c := line[char_index]
		if not in_string.is_empty():
			if c == in_string:
				in_string = ""
			continue
		if c == "\"" or c == "'":
			in_string = c
			continue
		if c == "#":
			break
		result += c
	return result


func _read_doc_comment(lines: PackedStringArray, func_line: int) -> String:
	var doc_lines: Array[String] = []
	var index := func_line - 1
	while index >= 0:
		var line := lines[index].strip_edges()
		if line.begins_with("@"):
			index -= 1
			continue
		if not line.begins_with("##"):
			break
		var text := line.substr(2)
		if text.begins_with(" "):
			text = text.substr(1)
		doc_lines.push_front(text)
		index -= 1
	return "\n".join(doc_lines).strip_edges()


func _parse_param_list(param_text: String) -> Array:
	if _param_regex == null:
		_param_regex = RegEx.new()
		_param_regex.compile("^(\\.\\.\\.)?\\s*([A-Za-z_]\\w*)\\s*(?::\\s*([^=]+?))?\\s*(?::?=\\s*(.+))?$")

	var pieces: Array[String] = []
	var current := ""
	var depth := 0
	var in_string := ""
	for char_index in range(param_text.length()):
		var c := param_text[char_index]
		if not in_string.is_empty():
			if c == in_string:
				in_string = ""
			current += c
			continue
		if c == "\"" or c == "'":
			in_string = c
		elif c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		elif c == "," and depth == 0:
			pieces.append(current)
			current = ""
			continue
		current += c
	pieces.append(current)

	var params: Array = []
	for piece in pieces:
		var trimmed := piece.strip_edges()
		if trimmed.is_empty():
			continue
		var param_match := _param_regex.search(trimmed)
		if param_match == null:
			continue
		params.append({
			"name": param_match.get_string(2),
			"type_text": param_match.get_string(3).strip_edges(),
			"default_text": param_match.get_string(4).strip_edges(),
			"is_rest": not param_match.get_string(1).is_empty()
		})
	return params


# =============================================================================
# RUNTIME BINDING CALL-SITE DETECTION
# =============================================================================
#
# Scans .gd source for calls to add_binding(), add_command(),
# add_command_handler(), register_command(), register_function() etc.
# Extracts the yarn name from the first string argument so the YSLS
# file includes commands/functions that are only registered at runtime.
#
# When the callable argument names a method declared in the same file, its
# signature is read from source. Otherwise entries are emitted with empty
# parameter lists, which still gives users autocomplete for names.

var _binding_call_regex: RegEx


func _get_binding_call_regex() -> RegEx:
	if _binding_call_regex == null:
		_binding_call_regex = RegEx.new()
		# Matches calls like:
		#   .add_binding("yarn_name", TYPE.COMMAND, ...)
		#   .add_command("yarn_name", ...)
		#   .add_command_handler("yarn_name", ...)
		#   .register_command("yarn_name", ...)
		#   .register_function("yarn_name", ...)
		#   .register_instance_command("yarn_name", ...)
		# Captures: (1) method name, (2) yarn name string, (3) optional second arg for type
		_binding_call_regex.compile(
			"\\.(add_binding|add_command|add_function|add_command_handler|register_command|register_function|register_instance_command)\\s*\\(\\s*\"([^\"]+)\"\\s*(?:,\\s*([^,)]+))?"
		)
	return _binding_call_regex


func _scan_runtime_bindings(source: String, file_name: String, path: String = "") -> void:
	# Collapse multi-line calls into single lines so the regex can match
	# calls where arguments are on separate lines, e.g.:
	#   binding_loader.add_binding(
	#       "give_item",
	#       YarnCommandBinding.Type.COMMAND,
	#       ...
	#   )
	var collapsed := source.replace("\n", " ").replace("\r", " ")
	# Collapse multiple spaces to single
	while collapsed.contains("  "):
		collapsed = collapsed.replace("  ", " ")

	var regex := _get_binding_call_regex()
	var results := regex.search_all(collapsed)
	var source_methods: Dictionary = {}
	if not results.is_empty():
		source_methods = _get_source_methods(path, source)

	for result in results:
		var method_name := result.get_string(1)
		var yarn_name := result.get_string(2)
		var second_arg := result.get_string(3).strip_edges() if result.get_string(3) else ""

		if yarn_name.is_empty():
			continue

		# Determine if this is a command or function
		var is_function := method_name == "register_function" or method_name == "add_function"

		# For add_binding, check the Type enum argument
		if method_name == "add_binding" and second_arg.contains("FUNCTION"):
			is_function = true

		# register_instance_command is always a command
		# (already false by default, but explicit for clarity)

		var handler_name := second_arg.trim_prefix("self.")
		var source_method: Dictionary = {}
		if method_name != "add_binding" and method_name != "register_instance_command" and source_methods.has(handler_name):
			source_method = source_methods[handler_name]

		if is_function:
			if not _functions.has(yarn_name):
				var info := {
					"yarnName": yarn_name,
					"definitionName": yarn_name,
					"fileName": file_name,
					"language": "gdscript",
					"parameters": [],
					"async": false,
					"return": {"type": "any"},
				}
				if not source_method.is_empty():
					info["definitionName"] = handler_name
					info["parameters"] = _build_parameters_from_source(source_method)
					info["return"] = {"type": _yarn_return_type_from_text(source_method["return_text"])}
					_apply_source_details(info, source_method)
				_functions[yarn_name] = info
		else:
			if not _commands.has(yarn_name):
				var info := {
					"yarnName": yarn_name,
					"definitionName": yarn_name,
					"fileName": file_name,
					"language": "gdscript",
					"parameters": [],
					"async": false,
				}
				if not source_method.is_empty():
					info["definitionName"] = handler_name
					info["parameters"] = _build_parameters_from_source(source_method)
					info["async"] = source_method["has_await"] or source_method["return_text"] == "Signal"
					_apply_source_details(info, source_method)
				_commands[yarn_name] = info


# =============================================================================
# STATIC HELPERS
# =============================================================================

## Generate YSLS for a project. scan_root defaults to the nearest ancestor
## directory containing .gd scripts (walks up from the .yarnproject).
## Pass "res://" to scan the entire Godot project.
static func generate_for_project(yarn_project_path: String, scan_root: String = "") -> Error:
	var generator := YarnYSLSGenerator.new()
	var root := scan_root if not scan_root.is_empty() else find_scan_root(yarn_project_path)
	generator.scan_directory(root)
	return generator.save_ysls_for_project(yarn_project_path)


## Find the best directory to scan for a .yarnproject file. Walks up from
## the project file's directory looking for .gd files in the directory or
## its immediate children (e.g. a sibling "scripts/" folder).
static func find_scan_root(yarn_project_path: String) -> String:
	var dir := yarn_project_path.get_base_dir()
	while dir != "res://" and dir != "res:/" and not dir.is_empty():
		var d := DirAccess.open(dir)
		if d != null:
			d.list_dir_begin()
			var fname := d.get_next()
			var has_gd := false
			while not fname.is_empty():
				if fname.ends_with(".gd"):
					has_gd = true
					break
				if d.current_is_dir() and not fname.begins_with(".") and fname != "addons":
					var sub := DirAccess.open(dir.path_join(fname))
					if sub != null:
						sub.list_dir_begin()
						var sf := sub.get_next()
						while not sf.is_empty():
							if sf.ends_with(".gd"):
								has_gd = true
								break
							sf = sub.get_next()
						sub.list_dir_end()
				if has_gd:
					break
				fname = d.get_next()
			d.list_dir_end()
			if has_gd:
				return dir
		dir = dir.get_base_dir()
	# No code directory found near the .yarnproject (e.g. scripts live elsewhere
	# under res://). Fall back to scanning the whole project rather than just the
	# project file's folder, so commands defined anywhere are still discovered.
	return "res://"


static func generate_from_runner(yarn_project_path: String, dialogue_runner) -> Error:
	var generator := YarnYSLSGenerator.new()
	generator.scan_dialogue_runner(dialogue_runner)
	return generator.save_ysls_for_project(yarn_project_path)
