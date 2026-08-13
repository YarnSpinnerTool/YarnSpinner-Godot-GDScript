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

class_name YarnLibrary
extends RefCounted
## Manages built-in and custom Yarn Spinner functions and commands.
## Command arguments are automatically coerced to match parameter types;
## Node-typed parameters are resolved from the scene tree (matching Unity).


enum CommandDispatchStatus {
	SUCCESS,
	NOT_FOUND,
	INVALID_PARAMS,
	EXECUTION_ERROR,
	INVALID_CALLABLE,
	EMPTY_COMMAND,
	PARSE_ERROR,
}

## Sentinel returned by [method call_function] when the invoked function
## reported an error via [method report_function_error]. A StringName is a
## distinct Variant type from String, so it can never collide with a
## legitimate function return value.
const FUNCTION_ERROR := &"__yarn_function_error__"

var _function_error: String = ""

var _functions: Dictionary[String, Callable] = {}
var _commands: Dictionary[String, Callable] = {}
var _function_param_counts: Dictionary[String, int] = {}
var _command_params: Dictionary[String, PackedStringArray] = {}
var _command_targets: Dictionary[String, Node] = {}
var _target_root: Node
var _instance_commands: Dictionary[String, Dictionary] = {}


func _init() -> void:
	_register_builtin_functions()


func register_function(func_name: String, callable: Callable, param_count: int = -1) -> void:
	_functions[func_name] = callable
	_function_param_counts[func_name] = param_count


func unregister_function(func_name: String) -> void:
	_functions.erase(func_name)
	_function_param_counts.erase(func_name)


## Registers a Yarn command. Declare typed parameters on the handler and the
## dispatcher converts each argument from the Yarn script to that type —
## [code]func give(item: String, count: int, loud: bool)[/code] receives a
## real int and bool from [code]<<give sword 3 true>>[/code]. Supported:
## String, int, float, bool, Vector2, Vector3, Color, and Node-derived
## classes (resolved by node name). A value that can't convert is a command
## error, not a silent default. Use a NAMED method for this — GDScript
## lambdas carry no parameter metadata, so lambda handlers receive raw
## strings.
func register_command(command_name: String, callable: Callable, param_names: PackedStringArray = []) -> void:
	_commands[command_name] = callable
	_command_params[command_name] = param_names


func unregister_command(command_name: String) -> void:
	_commands.erase(command_name)
	_command_params.erase(command_name)


## Register a command bound to a specific class. The first argument in the yarn
## command is resolved to a node and type-checked against target_class.
func register_instance_command(command_name: String, target_class: Script, method_name: String = "") -> void:
	if method_name.is_empty():
		method_name = "_yarn_command_" + command_name
	_instance_commands[command_name] = {
		"script": target_class,
		"method": method_name
	}


func unregister_instance_command(command_name: String) -> void:
	_instance_commands.erase(command_name)


func has_instance_command(command_name: String) -> bool:
	return _instance_commands.has(command_name)


func register_command_target(target_name: String, target: Node) -> void:
	_command_targets[target_name] = target


func unregister_command_target(target_name: String) -> void:
	_command_targets.erase(target_name)


func cleanup_stale_targets() -> void:
	var stale: Array[String] = []
	for name in _command_targets:
		if not is_instance_valid(_command_targets[name]):
			stale.append(name)
	for name in stale:
		_command_targets.erase(name)


func set_target_root(root: Node) -> void:
	_target_root = root


## Resolve a node by name: registered targets, then unique name, then tree search.
func find_command_target(target_name: String) -> Node:
	if _command_targets.has(target_name):
		var target: Node = _command_targets[target_name]
		if is_instance_valid(target):
			return target
		else:
			_command_targets.erase(target_name)

	if _target_root != null and is_instance_valid(_target_root):
		var child := _target_root.get_node_or_null(target_name)
		if child != null:
			return child

		var unique := _target_root.get_node_or_null("%" + target_name)
		if unique != null:
			return unique

		return _find_node_recursive(_target_root, target_name)

	return null


func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node_recursive(child, target_name)
		if found != null:
			return found
	return null


## Records that a built-in function received input it cannot handle.
## [method call_function] returns [constant FUNCTION_ERROR] on the same
## call, which the virtual machine treats as a reason to stop the dialogue.
func report_function_error(message: String) -> void:
	_function_error = message
	push_error("yarn library: %s" % message)


## Returns the pending function error message and clears it.
func take_function_error() -> String:
	var message := _function_error
	_function_error = ""
	return message


func has_function(func_name: String) -> bool:
	return _functions.has(func_name)


func has_command(command_name: String) -> bool:
	return _commands.has(command_name)


func get_function_param_count(func_name: String) -> int:
	return _function_param_counts.get(func_name, -1)


func call_function(func_name: String, stack: Array, vm: YarnVirtualMachine) -> Variant:
	if not _functions.has(func_name):
		push_error(("yarn library: unknown function '%s'. It is not registered at runtime. " +
			"If you defined it with _yarn_function_%s, make sure that script is on a node under " +
			"the DialogueRunner's discovery root (a valid .ysls.json does not register it); " +
			"otherwise register it with runner.add_function(\"%s\", callable).") % [func_name, func_name, func_name])
		return null

	var callable: Callable = _functions[func_name]

	# The compiler always pushes arg count before CALL_FUNC
	if stack.is_empty():
		push_error("yarn library: stack underflow reading arg count for '%s'" % func_name)
		return null
	var arg_count := int(stack.pop_back())

	if arg_count > stack.size():
		push_error("yarn library: stack underflow calling '%s' (need %d, have %d)" % [func_name, arg_count, stack.size()])
		return null

	var args: Array = []
	for i in range(arg_count):
		args.push_front(stack.pop_back())

	# Variadic functions (param_count == -1) receive args as a single array
	var param_count: int = _function_param_counts.get(func_name, -1)
	var result: Variant = callable.call(args) if param_count == -1 else callable.callv(args)

	if not _function_error.is_empty():
		return FUNCTION_ERROR

	return result


## Returns {status, handled, is_async, result, error}.
##
## This is a coroutine and MUST be awaited: coroutine command handlers run
## to completion inside it (so for `<<wait 2>>` the two seconds elapse
## before it returns). Handlers that return a Signal instead are reported
## via is_async/result for the caller to await.
func dispatch_command(command_text: String, dialogue_runner: Node) -> Dictionary:
	if command_text.strip_edges().is_empty():
		return _make_dispatch_result(CommandDispatchStatus.EMPTY_COMMAND, false, false, null, "empty command")

	var parts := _parse_command(command_text)
	if parts.is_empty():
		return _make_dispatch_result(CommandDispatchStatus.PARSE_ERROR, false, false, null, "failed to parse command")

	var command_name: String = parts[0]
	var args: Array[String] = parts.slice(1)

	if _commands.has(command_name):
		var callable: Callable = _commands[command_name]

		if not callable.is_valid():
			push_error("yarn library: command '%s' has invalid callable" % command_name)
			return _make_dispatch_result(CommandDispatchStatus.INVALID_CALLABLE, false, false, null, "command '%s' has invalid callable" % command_name)

		var call_result := await _safe_callv(callable, args, command_name)
		if call_result.success:
			var is_async := _is_async_result(call_result.result)
			return _make_dispatch_result(CommandDispatchStatus.SUCCESS, true, is_async, call_result.result, "")
		else:
			return _make_dispatch_result(call_result.status, false, false, null, call_result.error)

	if _instance_commands.has(command_name):
		if args.is_empty():
			return _make_dispatch_result(CommandDispatchStatus.INVALID_PARAMS, false, false, null,
				"instance command '%s' requires a target node as first argument" % command_name)

		var cmd_info: Dictionary = _instance_commands[command_name]
		var expected_script: Script = cmd_info["script"]
		var method_name: String = cmd_info["method"]

		var target_name: String = args[0]
		var target_node := _find_node_by_name(target_name)

		if target_node == null:
			return _make_dispatch_result(CommandDispatchStatus.NOT_FOUND, false, false, null,
				"could not find node '%s' for command '%s'" % [target_name, command_name])

		if not _node_is_instance_of(target_node, expected_script):
			var expected_class := _get_script_class_name(expected_script)
			return _make_dispatch_result(CommandDispatchStatus.INVALID_PARAMS, false, false, null,
				"node '%s' is not a %s (required for command '%s')" % [target_name, expected_class, command_name])

		var instance_args: Array[String] = args.slice(1)
		var call_result := await _safe_call(target_node, method_name, instance_args)
		if call_result.success:
			var is_async := _is_async_result(call_result.result)
			return _make_dispatch_result(CommandDispatchStatus.SUCCESS, true, is_async, call_result.result, "")
		else:
			return _make_dispatch_result(call_result.status, false, false, null, call_result.error)

	return _make_dispatch_result(CommandDispatchStatus.NOT_FOUND, false, false, null, "")


func _make_dispatch_result(status: CommandDispatchStatus, handled: bool, is_async: bool, result: Variant, error_message: String) -> Dictionary:
	return {
		"status": status,
		"handled": handled,
		"is_async": is_async,
		"result": result,
		"error": error_message
	}


func _safe_call(target: Object, method_name: String, args: Array) -> Dictionary:
	var coercion := _coerce_call_args(_find_method_info(target, method_name), args, method_name)
	if not coercion.success:
		return {"success": false, "status": coercion.status, "error": coercion.error, "result": null}

	if not is_instance_valid(target):
		return {"success": false, "status": CommandDispatchStatus.NOT_FOUND, "error": "target node for '%s' has been freed" % method_name, "result": null}

	# Awaited for the same reason as _safe_callv: coroutine handlers.
	var result: Variant = await target.callv(method_name, coercion.args)
	return {"success": true, "status": CommandDispatchStatus.SUCCESS, "error": "", "result": result}


func _safe_callv(callable: Callable, args: Array, command_name: String) -> Dictionary:
	var coercion := _coerce_call_args(
		_find_method_info(callable.get_object(), callable.get_method()), args, command_name)
	if not coercion.success:
		return {"success": false, "status": coercion.status, "error": coercion.error, "result": null}

	if not callable.is_valid():
		return {"success": false, "status": CommandDispatchStatus.INVALID_CALLABLE, "error": "callable for '%s' is no longer valid" % command_name, "result": null}

	# MUST be awaited: un-awaited callv on a coroutine handler is a hard
	# runtime error ("Trying to call an async function without 'await'").
	# For coroutine handlers this waits until they finish; for everything
	# else the await is a no-op and result is the plain return value.
	var result: Variant = await callable.callv(coercion.args)
	return {"success": true, "status": CommandDispatchStatus.SUCCESS, "error": "", "result": result}


## Reflection lookup for a method's parameter metadata. Handles static
## methods registered from a script (Script.get_method_list() describes the
## Script CLASS itself; the script's own methods come from
## get_script_method_list()). Empty dictionary when unavailable — lambdas
## carry no parameter metadata, so their handlers receive raw strings.
func _find_method_info(obj: Object, method_name: String) -> Dictionary:
	if obj == null or method_name.is_empty():
		return {}
	var method_list: Array
	if obj is Script:
		method_list = (obj as Script).get_script_method_list()
	else:
		method_list = obj.get_method_list()
	for method_info in method_list:
		if method_info["name"] == method_name:
			return method_info
	return {}


## Validates argument count and converts each string argument to the
## handler's declared parameter type. Returns {success, status, error, args}.
func _coerce_call_args(method_info: Dictionary, args: Array, command_name: String) -> Dictionary:
	# Deliberately untyped: args arrives as Array[String], and a typed
	# duplicate() would reject the coerced ints/floats/bools/Nodes.
	var coerced: Array = []
	coerced.assign(args)
	if method_info.is_empty():
		return {"success": true, "status": CommandDispatchStatus.SUCCESS, "error": "", "args": coerced}

	var expected_args: Array = method_info.get("args", [])
	var default_count: int = method_info.get("default_args", []).size()
	var min_args := expected_args.size() - default_count
	var max_args := expected_args.size()

	if args.size() < min_args:
		return {"success": false, "status": CommandDispatchStatus.INVALID_PARAMS, "error": "too few arguments for '%s' (expected %d-%d, got %d)" % [command_name, min_args, max_args, args.size()], "args": coerced}
	if args.size() > max_args:
		return {"success": false, "status": CommandDispatchStatus.INVALID_PARAMS, "error": "too many arguments for '%s' (expected %d-%d, got %d)" % [command_name, min_args, max_args, args.size()], "args": coerced}

	for i in range(mini(args.size(), expected_args.size())):
		var expected_type: int = expected_args[i].get("type", TYPE_NIL)
		var expected_class: String = expected_args[i].get("class_name", "")
		var out := _coerce_value(args[i], expected_type, expected_class, expected_args[i].get("name", ""))
		if not out.ok:
			return {"success": false, "status": CommandDispatchStatus.INVALID_PARAMS,
				"error": "argument %d of '%s' %s" % [i + 1, command_name, out.error], "args": coerced}
		coerced[i] = out.value
	return {"success": true, "status": CommandDispatchStatus.SUCCESS, "error": "", "args": coerced}


## Converts one command argument to the handler's declared parameter type.
## Returns {ok, value, error}: a conversion that cannot be performed is a
## dispatch error naming what was expected, never a silent zero.
func _coerce_value(value: Variant, target_type: int, type_class: String = "", param_name: String = "") -> Dictionary:
	if typeof(value) == target_type:
		return {"ok": true, "value": value, "error": ""}

	if target_type == TYPE_NIL:
		return {"ok": true, "value": value, "error": ""}

	# Node-typed parameters: resolve string to node via scene tree lookup
	if target_type == TYPE_OBJECT and value is String:
		if _is_node_class(type_class):
			var node := _find_node_by_name(value)
			if node != null:
				return {"ok": true, "value": node, "error": ""}
			return {"ok": false, "value": null,
				"error": "expects a %s, but no node named '%s' was found" % [type_class, value]}

	if not value is String:
		return {"ok": true, "value": value, "error": ""}

	var str_value: String = value

	match target_type:
		TYPE_INT:
			if str_value.is_valid_int():
				return {"ok": true, "value": int(str_value), "error": ""}
			if str_value.is_valid_float():
				return {"ok": true, "value": int(float(str_value)), "error": ""}
			return {"ok": false, "value": 0, "error": "expects an int, got '%s'" % str_value}

		TYPE_FLOAT:
			if str_value.is_valid_float():
				return {"ok": true, "value": float(str_value), "error": ""}
			if str_value.is_valid_int():
				return {"ok": true, "value": float(int(str_value)), "error": ""}
			return {"ok": false, "value": 0.0, "error": "expects a number, got '%s'" % str_value}

		TYPE_BOOL:
			match str_value.to_lower():
				"true", "1", "yes", "on":
					return {"ok": true, "value": true, "error": ""}
				"false", "0", "no", "off":
					return {"ok": true, "value": false, "error": ""}
			# Flag style (matches Yarn Spinner): passing a bool parameter's own
			# name as a bareword infers true, e.g. <<play_animation ... wait>>
			# for a parameter named "wait".
			if not param_name.is_empty() and str_value == param_name:
				return {"ok": true, "value": true, "error": ""}
			return {"ok": false, "value": false, "error": "expects true/false, got '%s'" % str_value}

		TYPE_VECTOR2:
			return {"ok": true, "value": _parse_vector2(str_value), "error": ""}

		TYPE_VECTOR3:
			return {"ok": true, "value": _parse_vector3(str_value), "error": ""}

		TYPE_COLOR:
			return {"ok": true, "value": _parse_color(str_value), "error": ""}

		_:
			return {"ok": true, "value": value, "error": ""}


func _parse_vector2(s: String) -> Vector2:
	s = s.strip_edges().trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() >= 2:
		var x := float(parts[0].strip_edges()) if parts[0].strip_edges().is_valid_float() else 0.0
		var y := float(parts[1].strip_edges()) if parts[1].strip_edges().is_valid_float() else 0.0
		return Vector2(x, y)
	return Vector2.ZERO


func _parse_vector3(s: String) -> Vector3:
	s = s.strip_edges().trim_prefix("(").trim_suffix(")")
	var parts := s.split(",")
	if parts.size() >= 3:
		var x := float(parts[0].strip_edges()) if parts[0].strip_edges().is_valid_float() else 0.0
		var y := float(parts[1].strip_edges()) if parts[1].strip_edges().is_valid_float() else 0.0
		var z := float(parts[2].strip_edges()) if parts[2].strip_edges().is_valid_float() else 0.0
		return Vector3(x, y, z)
	return Vector3.ZERO


func _parse_color(s: String) -> Color:
	s = s.strip_edges()
	if s.begins_with("#"):
		return Color.html(s)
	match s.to_lower():
		"white": return Color.WHITE
		"black": return Color.BLACK
		"red": return Color.RED
		"green": return Color.GREEN
		"blue": return Color.BLUE
		"yellow": return Color.YELLOW
		"cyan": return Color.CYAN
		"magenta": return Color.MAGENTA
		"transparent": return Color.TRANSPARENT
		_:
			if s.length() == 6 or s.length() == 8:
				return Color.html("#" + s)
			return Color.WHITE


func _is_node_class(type_class: String) -> bool:
	if type_class.is_empty():
		return false
	if type_class == "Node":
		return true
	if ClassDB.class_exists(type_class):
		return ClassDB.is_parent_class(type_class, "Node")
	return false


func _find_node_by_name(node_name: String) -> Node:
	if _command_targets.has(node_name):
		var target: Node = _command_targets[node_name]
		if is_instance_valid(target):
			return target
		else:
			_command_targets.erase(node_name)

	var search_root: Node = _target_root
	if search_root == null:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			search_root = tree.current_scene

	if search_root == null:
		return null

	var unique := search_root.get_node_or_null("%" + node_name)
	if unique != null:
		return unique

	var direct := search_root.get_node_or_null(node_name)
	if direct != null:
		return direct

	return _find_node_recursive(search_root, node_name)


func _node_is_instance_of(node: Node, expected_script: Script) -> bool:
	if node == null or expected_script == null:
		return false

	var node_script := node.get_script() as Script
	while node_script != null:
		if node_script == expected_script:
			return true
		node_script = node_script.get_base_script()

	return false


func _get_script_class_name(script: Script) -> String:
	if script == null:
		return "unknown"

	var global_classes := ProjectSettings.get_global_class_list()
	for class_info in global_classes:
		if class_info.get("path", "") == script.resource_path:
			var name: String = class_info.get("class", "")
			if not name.is_empty():
				return name

	if not script.resource_path.is_empty():
		return script.resource_path.get_file().get_basename().to_pascal_case()

	return "unknown"


func _is_async_result(result: Variant) -> bool:
	if result is Signal:
		return true
	if result is Object and result != null:
		# GDScript coroutines (functions containing `await`) return a
		# GDScriptFunctionState when invoked via Callable.call/callv. The
		# dispatcher's `await async_result` resolves it correctly, but we
		# have to flag it as async so the await branch is taken.
		if result.get_class() == "GDScriptFunctionState":
			return true
		if result.has_method("is_coroutine"):
			return true
	return false


func _parse_command(command_text: String) -> Array:
	return YarnCommandParser.parse(command_text)


var _program: YarnProgram
var _saliency_strategy: YarnSaliencyStrategy
var _variable_storage: YarnVariableStorage


func set_program(program: YarnProgram) -> void:
	_program = program


func set_vm_context(strategy: YarnSaliencyStrategy, storage: YarnVariableStorage) -> void:
	_saliency_strategy = strategy
	_variable_storage = storage


func _register_builtin_functions() -> void:
	register_function("Number.Add", _op_number_add, 2)
	register_function("Number.Minus", _op_number_minus, 2)
	register_function("Number.Multiply", _op_number_multiply, 2)
	register_function("Number.Divide", _op_number_divide, 2)
	register_function("Number.Modulo", _op_number_modulo, 2)
	register_function("Number.UnaryMinus", _op_number_unary_minus, 1)

	register_function("Number.EqualTo", _op_number_equal, 2)
	register_function("Number.NotEqualTo", _op_number_not_equal, 2)
	register_function("Number.LessThan", _op_number_less_than, 2)
	register_function("Number.LessThanOrEqualTo", _op_number_less_than_or_equal, 2)
	register_function("Number.GreaterThan", _op_number_greater_than, 2)
	register_function("Number.GreaterThanOrEqualTo", _op_number_greater_than_or_equal, 2)

	register_function("Bool.Not", _op_bool_not, 1)
	register_function("Bool.And", _op_bool_and, 2)
	register_function("Bool.Or", _op_bool_or, 2)
	register_function("Bool.Xor", _op_bool_xor, 2)
	register_function("Bool.EqualTo", _op_bool_equal, 2)
	register_function("Bool.NotEqualTo", _op_bool_not_equal, 2)

	register_function("String.Add", _op_string_add, 2)
	register_function("String.EqualTo", _op_string_equal, 2)
	register_function("String.NotEqualTo", _op_string_not_equal, 2)

	register_function("Enum.EqualTo", _op_enum_equal, 2)
	register_function("Enum.NotEqualTo", _op_enum_not_equal, 2)

	register_function("string", _builtin_string, 1)
	register_function("number", _builtin_number, 1)
	register_function("bool", _builtin_bool, 1)

	register_function("random", _builtin_random, 0)
	register_function("random_range", _builtin_random_range, 2)
	register_function("random_range_float", _builtin_random_range_float, 2)
	register_function("dice", _builtin_dice, 1)
	register_function("round", _builtin_round, 1)
	register_function("round_places", _builtin_round_places, 2)
	register_function("floor", _builtin_floor, 1)
	register_function("ceil", _builtin_ceil, 1)
	register_function("inc", _builtin_inc, 1)
	register_function("dec", _builtin_dec, 1)
	register_function("decimal", _builtin_decimal, 1)
	register_function("int", _builtin_int, 1)

	register_function("min", _builtin_min, 2)
	register_function("max", _builtin_max, 2)
	register_function("abs", _builtin_abs, 1)
	register_function("sign", _builtin_sign, 1)
	register_function("clamp", _builtin_clamp, 3)
	register_function("lerp", _builtin_lerp, 3)
	register_function("inverse_lerp", _builtin_inverse_lerp, 3)
	register_function("smoothstep", _builtin_smoothstep, 3)
	register_function("pow", _builtin_pow, 2)
	register_function("sqrt", _builtin_sqrt, 1)
	register_function("wrap", _builtin_wrap, 3)
	register_function("mod", _builtin_mod, 2)

	register_function("has_any_content", _builtin_has_any_content, 1)

	register_function("format_invariant", _builtin_format_invariant, 1)
	register_function("format", _builtin_format, 2)

	register_function("plural", _builtin_plural, -1)
	register_function("ordinal", _builtin_ordinal, -1)

	register_function("length", _builtin_length, 1)
	register_function("uppercase", _builtin_uppercase, 1)
	register_function("lowercase", _builtin_lowercase, 1)
	register_function("first_letter_caps", _builtin_first_letter_caps, 1)


func _builtin_string(value: Variant) -> String:
	if value is float:
		return YarnNumber.to_display_string(value)
	return str(value)


func _builtin_number(value: Variant) -> float:
	if value is String:
		if value.is_valid_float():
			return float(value)
		elif value.is_valid_int():
			return float(int(value))
		else:
			report_function_error("number(): cannot convert '%s' to a number" % value)
			return 0.0
	if value is bool:
		return 1.0 if value else 0.0
	if value is float or value is int:
		return float(value)
	report_function_error("number(): cannot convert value to a number")
	return 0.0


func _builtin_bool(value: Variant) -> bool:
	if value is String:
		match value.to_lower():
			"true":
				return true
			"false":
				return false
			_:
				report_function_error("bool(): cannot convert '%s' to a bool, expected 'true' or 'false'" % value)
				return false
	if value is float or value is int:
		return value != 0
	if value is bool:
		return value
	report_function_error("bool(): cannot convert value to a bool")
	return false


func _builtin_random() -> float:
	return randf()


func _builtin_random_range(min_val: float, max_val: float) -> float:
	# Unity returns discrete integers in [min, max] inclusive
	var range_size := int(max_val) - int(min_val) + 1
	if range_size <= 0:
		return min_val
	return float(randi() % range_size) + min_val


func _builtin_random_range_float(min_val: float, max_val: float) -> float:
	# Unity also returns discrete integers here despite the name
	var range_size := int(max_val) - int(min_val) + 1
	if range_size <= 0:
		return min_val
	return float(randi() % range_size) + min_val


func _builtin_dice(sides: float) -> int:
	if sides < 1:
		push_warning("yarn library: dice() called with invalid sides %s, returning 1" % sides)
		return 1
	return randi_range(1, int(sides))


func _builtin_round(value: float) -> int:
	return int(_round_half_to_even(value))


func _builtin_round_places(value: float, places: float) -> float:
	var int_places := int(places)
	if int_places < 0:
		push_warning("yarn library: round_places() called with negative places %s, using 0" % places)
		int_places = 0
	var multiplier := pow(10, int_places)
	return _round_half_to_even(value * multiplier) / multiplier


## Round half to even ("banker's rounding"), the rounding yarn's round()
## uses. Godot's own roundf() rounds half away
## from zero (2.5 -> 3), which is not the rounding yarn scripts are
## written against.
func _round_half_to_even(value: float) -> float:
	var floored := floorf(value)
	var diff := value - floored
	if diff > 0.5:
		return floored + 1.0
	if diff < 0.5:
		return floored
	# Exactly halfway: round to the even neighbour.
	if int(floored) % 2 == 0:
		return floored
	return floored + 1.0


func _builtin_floor(value: float) -> int:
	return int(floorf(value))


func _builtin_ceil(value: float) -> int:
	return int(ceilf(value))


func _builtin_inc(value: float) -> int:
	# Unity: no decimal -> value + 1, else ceil
	var decimal_part := value - float(int(value))
	if decimal_part == 0:
		return int(value + 1)
	else:
		return int(ceilf(value))


func _builtin_dec(value: float) -> int:
	# Unity: no decimal -> value - 1, else floor
	var decimal_part := value - float(int(value))
	if decimal_part == 0:
		return int(value) - 1
	else:
		return int(floorf(value))


func _builtin_decimal(value: float) -> float:
	# Truncation-based: decimal(-3.5) = -0.5, not 0.5
	return value - float(int(value))


func _builtin_int(value: float) -> int:
	return int(value)


func _builtin_format_invariant(value: Variant) -> String:
	return _builtin_string(value)


func _builtin_plural(args: Array) -> String:
	if args.size() < 2:
		return ""
	var value: float = args[0]
	var int_value := int(value)

	if args.size() == 3:
		if int_value == 1:
			return args[1]
		return args[2]
	elif args.size() == 4:
		if int_value == 0:
			return args[1]
		elif int_value == 1:
			return args[2]
		return args[3]

	return args[args.size() - 1]


func _builtin_ordinal(args: Array) -> String:
	if args.size() < 2:
		return ""
	var value: int = int(args[0])
	var abs_val := absi(value)

	if abs_val % 100 in [11, 12, 13]:
		return args[mini(4, args.size() - 1)]

	match abs_val % 10:
		1:
			return args[mini(1, args.size() - 1)]
		2:
			return args[mini(2, args.size() - 1)]
		3:
			return args[mini(3, args.size() - 1)]
		_:
			return args[mini(4, args.size() - 1)]


func _builtin_min(a: float, b: float) -> float:
	return minf(a, b)


func _builtin_max(a: float, b: float) -> float:
	return maxf(a, b)


func _builtin_abs(value: float) -> float:
	return absf(value)


func _builtin_sign(value: float) -> float:
	return signf(value)


func _builtin_clamp(value: float, min_val: float, max_val: float) -> float:
	return clampf(value, min_val, max_val)


func _builtin_lerp(a: float, b: float, t: float) -> float:
	return lerpf(a, b, t)


func _builtin_inverse_lerp(a: float, b: float, value: float) -> float:
	if a == b:
		return 0.0
	return (value - a) / (b - a)


func _builtin_smoothstep(from: float, to: float, value: float) -> float:
	return smoothstep(from, to, value)


func _builtin_pow(base: float, exponent: float) -> float:
	return pow(base, exponent)


func _builtin_sqrt(value: float) -> float:
	return sqrt(value)


func _builtin_wrap(value: float, min_val: float, max_val: float) -> float:
	return wrapf(value, min_val, max_val)


func _builtin_mod(a: float, b: float) -> float:
	return fmod(a, b)


static var _format_placeholder_regex: RegEx


## format(format_string, argument): replaces every {0} in format_string with
## argument. Any other numbered placeholder ({1}, {2}, ...) is an error —
## format() takes exactly one substitution argument, matching the reference
## runtimes.
func _builtin_format(format_string: String, argument: Variant) -> String:
	if _format_placeholder_regex == null:
		_format_placeholder_regex = RegEx.new()
		_format_placeholder_regex.compile("\\{(\\d+)\\}")

	for m in _format_placeholder_regex.search_all(format_string):
		var index := int(m.get_string(1))
		if index != 0:
			report_function_error("format(): invalid placeholder {%d} in '%s', only {0} is supported" % [index, format_string])
			return format_string

	return format_string.replace("{0}", _builtin_string(argument))


func _builtin_length(value: String) -> int:
	return value.length()


func _builtin_uppercase(value: String) -> String:
	return value.to_upper()


func _builtin_lowercase(value: String) -> String:
	return value.to_lower()


func _builtin_first_letter_caps(value: String) -> String:
	if value.is_empty():
		return value
	return value[0].to_upper() + value.substr(1)


func _builtin_has_any_content(node_name: String) -> bool:
	if _program == null:
		return false
	if not _program.has_node(node_name):
		return false
	if _program.is_node_group_hub(node_name):
		var candidates := YarnSmartVariableVM.get_saliency_options_for_node_group(
			node_name, _program, _variable_storage, self)
		if candidates.is_empty():
			return false
		if _saliency_strategy == null:
			return true
		var context := {"variable_storage": _variable_storage}
		var selected := _saliency_strategy.select_candidate(candidates, context)
		return selected >= 0
	return true


func _op_number_add(a: float, b: float) -> float:
	return a + b


func _op_number_minus(a: float, b: float) -> float:
	return a - b


func _op_number_multiply(a: float, b: float) -> float:
	return a * b


func _op_number_divide(a: float, b: float) -> float:
	# Float division by zero follows IEEE-754 (inf, -inf, or nan for 0/0).
	# No guard: a hand-rolled one
	# gets the 0/0 case wrong.
	return a / b


func _op_number_modulo(a: float, b: float) -> float:
	if int(b) == 0:
		report_function_error("modulo by zero")
		return 0.0
	# Operands convert to int before modulo
	return float(int(a) % int(b))


func _op_number_unary_minus(a: float) -> float:
	return -a


func _op_number_equal(a: float, b: float) -> bool:
	return a == b


func _op_number_not_equal(a: float, b: float) -> bool:
	return a != b


func _op_number_less_than(a: float, b: float) -> bool:
	return a < b


func _op_number_less_than_or_equal(a: float, b: float) -> bool:
	return a <= b


func _op_number_greater_than(a: float, b: float) -> bool:
	return a > b


func _op_number_greater_than_or_equal(a: float, b: float) -> bool:
	return a >= b


func _op_bool_not(a: bool) -> bool:
	return not a


func _op_bool_and(a: bool, b: bool) -> bool:
	return a and b


func _op_bool_or(a: bool, b: bool) -> bool:
	return a or b


func _op_bool_xor(a: bool, b: bool) -> bool:
	return a != b


func _op_bool_equal(a: bool, b: bool) -> bool:
	return a == b


func _op_bool_not_equal(a: bool, b: bool) -> bool:
	return a != b


func _op_string_add(a: String, b: String) -> String:
	return a + b


func _op_string_equal(a: String, b: String) -> bool:
	return a == b


func _op_string_not_equal(a: String, b: String) -> bool:
	return a != b


func _op_enum_equal(a: Variant, b: Variant) -> bool:
	if a is String or b is String:
		return str(a) == str(b)
	return int(a) == int(b)


func _op_enum_not_equal(a: Variant, b: Variant) -> bool:
	if a is String or b is String:
		return str(a) != str(b)
	return int(a) != int(b)
