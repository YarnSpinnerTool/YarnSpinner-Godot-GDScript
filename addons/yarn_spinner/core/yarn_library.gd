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
	TARGET_NOT_FOUND,
	TARGET_MISSING_COMPONENT,
	INVALID_PARAMETER_COUNT,
	INVALID_PARAMETER,
}

## Sentinel returned by [method call_function] when the invoked function
## reported an error via [method report_function_error]. A StringName is a
## distinct Variant type from String, so it can never collide with a
## legitimate function return value.
const FUNCTION_ERROR := &"__yarn_function_error__"

const _INT32_MIN := -2147483648
const _INT32_MAX := 2147483647

var _function_error: String = ""

var _functions: Dictionary[String, Callable] = {}
var _commands: Dictionary[String, Callable] = {}
var _function_param_counts: Dictionary[String, int] = {}
var _function_signatures: Dictionary[String, Dictionary] = {}
var _command_params: Dictionary[String, PackedStringArray] = {}
var _command_targets: Dictionary[String, Node] = {}
var _target_root: Node
var _instance_commands: Dictionary[String, Dictionary] = {}
var _vm_ref: WeakRef

static var _global_classes: Dictionary = {}


static func is_function_error(value: Variant) -> bool:
	return value is StringName and value == FUNCTION_ERROR


func _init() -> void:
	_register_builtin_functions()


func register_function(func_name: String, callable: Callable, param_count: int = -1) -> void:
	if func_name.is_empty():
		push_error("yarn library: function name cannot be empty")
		return
	if func_name.contains(" "):
		push_error("yarn library: cannot add function %s: function names are not allowed to contain spaces" % func_name)
		return
	if _functions.has(func_name):
		push_error("yarn library: cannot add function %s: one already exists" % func_name)
		return
	if not callable.is_valid():
		push_error("yarn library: cannot add function %s: the callable is not valid" % func_name)
		return
	_add_function(func_name, callable, param_count)


func _add_function(func_name: String, callable: Callable, param_count: int = -1) -> void:
	var signature := _describe_callable(callable, param_count)
	_functions[func_name] = callable
	_function_signatures[func_name] = signature
	_function_param_counts[func_name] = signature.max


func unregister_function(func_name: String) -> void:
	_functions.erase(func_name)
	_function_param_counts.erase(func_name)
	_function_signatures.erase(func_name)


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
	if not _validate_command_name(command_name):
		return
	if not callable.is_valid():
		push_error("yarn library: failed to register command %s: the callable is not valid" % command_name)
		return
	_commands[command_name] = callable
	_command_params[command_name] = param_names


func unregister_command(command_name: String) -> void:
	_commands.erase(command_name)
	_command_params.erase(command_name)


func _validate_command_name(command_name: String) -> bool:
	if command_name.is_empty():
		push_error("yarn library: command name cannot be empty")
		return false
	if command_name.contains(" "):
		push_error("yarn library: failed to register command %s: command names are not allowed to contain spaces" % command_name)
		return false
	if _commands.has(command_name) or _instance_commands.has(command_name):
		push_error("yarn library: failed to register command %s: a command by this name has already been registered" % command_name)
		return false
	return true


## Register a command bound to a specific class. The first argument in the yarn
## command is resolved to a node and type-checked against target_class.
func register_instance_command(command_name: String, target_class: Script, method_name: String = "") -> void:
	if not _validate_command_name(command_name):
		return
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


func set_virtual_machine(vm: YarnVirtualMachine) -> void:
	_vm_ref = weakref(vm) if vm != null else null


func _get_vm() -> YarnVirtualMachine:
	if _vm_ref == null:
		return null
	return _vm_ref.get_ref() as YarnVirtualMachine


func call_function(func_name: String, stack: Array, vm: YarnVirtualMachine) -> Variant:
	_function_error = ""

	if not _functions.has(func_name):
		return _function_failure(("unknown function '%s'. It is not registered at runtime. " +
			"If you defined it with _yarn_function_%s, make sure that script is on a node under " +
			"the DialogueRunner's discovery root (a valid .ysls.json does not register it); " +
			"otherwise register it with runner.add_function(\"%s\", callable).") % [func_name, func_name, func_name])

	# The compiler always pushes arg count before CALL_FUNC
	if stack.is_empty():
		return _function_failure("stack underflow reading arg count for '%s'" % func_name)
	var count_value: Variant = stack.pop_back()
	if not (count_value is float or count_value is int):
		return _function_failure("expected an argument count for '%s', got %s" % [func_name, type_string(typeof(count_value))])
	var arg_count := YarnNumber.to_int32(float(count_value))

	if arg_count < 0 or arg_count > stack.size():
		return _function_failure("stack underflow calling '%s' (need %d, have %d)" % [func_name, arg_count, stack.size()])

	var args: Array = []
	for i in range(arg_count):
		args.push_front(stack.pop_back())

	var signature: Dictionary = _function_signatures[func_name]
	var min_args: int = signature.min
	var max_args: int = signature.max
	if arg_count < min_args or (max_args >= 0 and arg_count > max_args):
		var expected := str(min_args) if min_args == max_args else ("at least %d" % min_args if max_args < 0 else "%d to %d" % [min_args, max_args])
		return _function_failure("function %s expected %s parameters, but received %d" % [func_name, expected, arg_count])

	var types: Array = signature.types
	for i in range(args.size()):
		if i >= types.size():
			break
		var converted := _convert_function_argument(args[i], types[i])
		if not converted.ok:
			return _function_failure("function %s: parameter %d %s" % [func_name, i + 1, converted.error])
		args[i] = converted.value

	var callable: Callable = _functions[func_name]
	if not callable.is_valid():
		return _function_failure("the callable for function %s is no longer valid" % func_name)

	var result: Variant = callable.callv(args)

	if not _function_error.is_empty():
		return FUNCTION_ERROR

	return _convert_function_result(func_name, result)


func _function_failure(message: String) -> Variant:
	report_function_error(message)
	return FUNCTION_ERROR


func _describe_callable(callable: Callable, param_count: int) -> Dictionary:
	var info := _find_method_info(callable.get_object(), callable.get_method())
	if not info.is_empty():
		var args: Array = info.get("args", [])
		var bound := callable.get_bound_arguments_count()
		var fixed := maxi(args.size() - bound, 0)
		var defaults: int = maxi(info.get("default_args", []).size() - bound, 0)
		var types: Array[int] = []
		for i in range(fixed):
			types.append(int(args[i].get("type", TYPE_NIL)))
		var variadic := (int(info.get("flags", 0)) & METHOD_FLAG_VARARG) != 0
		return {"min": maxi(fixed - defaults, 0), "max": -1 if variadic else fixed, "types": types}

	var count := param_count if param_count >= 0 else callable.get_argument_count()
	return {"min": count, "max": count, "types": []}


func _convert_function_result(func_name: String, result: Variant) -> Variant:
	if result is bool or result is float or result is String:
		return result
	if result is int:
		return float(result)
	if result is StringName:
		return String(result)
	if result == null:
		return _function_failure("function %s did not return a value" % func_name)
	if result is Object and (result as Object).get_class() == "GDScriptFunctionState":
		return _function_failure("function %s must return its value immediately, without awaiting" % func_name)
	return _function_failure("function %s returned a %s, which is not a Yarn value (bool, number or string)" % [func_name, type_string(typeof(result))])


func _convert_function_argument(value: Variant, target_type: int) -> Dictionary:
	match target_type:
		TYPE_FLOAT:
			if value is float or value is int:
				return {"ok": true, "value": float(value), "error": ""}
			if value is bool:
				return {"ok": true, "value": 1.0 if value else 0.0, "error": ""}
			if value is String:
				var parsed := parse_single(value)
				if parsed.ok:
					return {"ok": true, "value": parsed.value, "error": ""}
				return {"ok": false, "value": null, "error": "cannot convert '%s' to a number" % value}
		TYPE_INT:
			if value is float or value is int:
				var rounded := YarnNumber.round_half_to_even(float(value))
				if rounded < _INT32_MIN or rounded > _INT32_MAX or is_nan(rounded):
					return {"ok": false, "value": null, "error": "value was either too large or too small for an Int32"}
				return {"ok": true, "value": int(rounded), "error": ""}
			if value is bool:
				return {"ok": true, "value": 1 if value else 0, "error": ""}
			if value is String:
				var parsed := parse_int32(value)
				if parsed.ok:
					return {"ok": true, "value": parsed.value, "error": ""}
				return {"ok": false, "value": null, "error": "cannot convert '%s' to an integer" % value}
		TYPE_BOOL:
			if value is bool:
				return {"ok": true, "value": value, "error": ""}
			if value is float or value is int:
				return {"ok": true, "value": value != 0, "error": ""}
			if value is String:
				var parsed := parse_bool(value)
				if parsed.ok:
					return {"ok": true, "value": parsed.value, "error": ""}
				return {"ok": false, "value": null, "error": "cannot convert '%s' to a bool" % value}
		TYPE_STRING:
			return {"ok": true, "value": YarnVirtualMachine._value_to_string(value), "error": ""}
		TYPE_STRING_NAME:
			return {"ok": true, "value": StringName(YarnVirtualMachine._value_to_string(value)), "error": ""}
	return {"ok": true, "value": value, "error": ""}


static func parse_single(text: String) -> Dictionary:
	var s := text.strip_edges()
	match s.to_lower():
		"nan":
			return {"ok": true, "value": NAN}
		"infinity", "+infinity":
			return {"ok": true, "value": INF}
		"-infinity":
			return {"ok": true, "value": -INF}
	var split_at := s.length()
	for i in range(s.length()):
		var c := s[i]
		if c == "." or c == "e" or c == "E":
			split_at = i
			break
	if s.substr(split_at).contains(","):
		return {"ok": false, "value": 0.0}
	var integral := s.substr(0, split_at)
	if integral.contains(","):
		if integral.begins_with(",") or integral.lstrip("+-").begins_with(","):
			return {"ok": false, "value": 0.0}
		s = integral.replace(",", "") + s.substr(split_at)
	if s.is_empty() or not s.is_valid_float():
		return {"ok": false, "value": 0.0}
	return {"ok": true, "value": YarnNumber.to_f32(s.to_float())}


static func parse_int32(text: String) -> Dictionary:
	var s := text.strip_edges()
	var digits := s.lstrip("+-")
	if digits.is_empty() or s.length() - digits.length() > 1 or not digits.is_valid_int() or digits.length() > 10:
		return {"ok": false, "value": 0}
	var value := s.to_int()
	if value < _INT32_MIN or value > _INT32_MAX:
		return {"ok": false, "value": 0}
	return {"ok": true, "value": value}


static func parse_bool(text: String) -> Dictionary:
	match text.strip_edges().to_lower():
		"true":
			return {"ok": true, "value": true}
		"false":
			return {"ok": true, "value": false}
	return {"ok": false, "value": false}


## Returns {status, handled, is_async, result, error}.
##
## This is a coroutine and MUST be awaited: coroutine command handlers run
## to completion inside it (so for `<<wait 2>>` the two seconds elapse
## before it returns). Handlers that return a Signal instead are reported
## via is_async/result for the caller to await.
func dispatch_command(command_text: String, dialogue_runner: Node) -> Dictionary:
	if command_text.strip_edges().is_empty():
		return _make_dispatch_result(CommandDispatchStatus.EMPTY_COMMAND, false, false, null, "empty command")

	var parts := YarnCommandParser.parse(command_text)
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
			return _make_dispatch_result(CommandDispatchStatus.INVALID_PARAMETER_COUNT, false, false, null,
				"%s needs a target, but none was specified" % command_name)

		var cmd_info: Dictionary = _instance_commands[command_name]
		var expected_script: Script = cmd_info["script"]
		var method_name: String = cmd_info["method"]

		var target_name: String = args[0]
		var target_node := _find_node_by_name(target_name)

		if target_node == null:
			return _make_dispatch_result(CommandDispatchStatus.TARGET_NOT_FOUND, false, false, null,
				"no node named \"%s\" exists" % target_name)

		if not _node_is_instance_of(target_node, expected_script):
			var expected_class := _get_script_class_name(expected_script)
			return _make_dispatch_result(CommandDispatchStatus.TARGET_MISSING_COMPONENT, false, false, null,
				"%s can't be called on %s, because it isn't a %s" % [command_name, target_name, expected_class])

		var instance_args: Array[String] = args.slice(1)
		var call_result := await _safe_call(target_node, method_name, instance_args, command_name)
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


func _safe_call(target: Object, method_name: String, args: Array, command_name: String = "") -> Dictionary:
	if command_name.is_empty():
		command_name = method_name
	var coercion := _coerce_call_args(_find_method_info(target, method_name), args, command_name, Callable(), 0)
	if not coercion.success:
		return {"success": false, "status": coercion.status, "error": coercion.error, "result": null}

	if not is_instance_valid(target):
		return {"success": false, "status": CommandDispatchStatus.TARGET_NOT_FOUND, "error": "target node for '%s' has been freed" % command_name, "result": null}

	# Awaited for the same reason as _safe_callv: coroutine handlers.
	var result: Variant = await target.callv(method_name, coercion.args)
	return {"success": true, "status": CommandDispatchStatus.SUCCESS, "error": "", "result": result}


func _safe_callv(callable: Callable, args: Array, command_name: String) -> Dictionary:
	var coercion := _coerce_call_args(
		_find_method_info(callable.get_object(), callable.get_method()), args, command_name,
		callable, callable.get_bound_arguments_count())
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
func _coerce_call_args(method_info: Dictionary, args: Array, command_name: String, callable: Callable = Callable(), bound_count: int = 0) -> Dictionary:
	# Deliberately untyped: args arrives as Array[String], and a typed
	# duplicate() would reject the coerced ints/floats/bools/Nodes.
	var coerced: Array = []
	coerced.assign(args)

	var expected_args: Array = []
	var min_args := 0
	var max_args := -1

	if method_info.is_empty():
		if not callable.is_valid():
			return {"success": true, "status": CommandDispatchStatus.SUCCESS, "error": "", "args": coerced}
		min_args = callable.get_argument_count()
		max_args = min_args
	else:
		expected_args = method_info.get("args", [])
		expected_args = expected_args.slice(0, maxi(expected_args.size() - bound_count, 0))
		var default_count: int = method_info.get("default_args", []).size()
		min_args = maxi(expected_args.size() - default_count, 0)
		var variadic := (int(method_info.get("flags", 0)) & METHOD_FLAG_VARARG) != 0
		max_args = -1 if variadic else expected_args.size()

	if args.size() < min_args or (max_args >= 0 and args.size() > max_args):
		return {"success": false, "status": CommandDispatchStatus.INVALID_PARAMETER_COUNT,
			"error": _parameter_count_message(command_name, min_args, max_args, args.size()), "args": coerced}

	for i in range(mini(args.size(), expected_args.size())):
		var expected_type: int = expected_args[i].get("type", TYPE_NIL)
		var expected_class: String = expected_args[i].get("class_name", "")
		var out := _coerce_value(args[i], expected_type, expected_class, expected_args[i].get("name", ""), i)
		if not out.ok:
			return {"success": false, "status": CommandDispatchStatus.INVALID_PARAMETER,
				"error": "can't convert parameter %d of %s: %s" % [i, command_name, out.error], "args": coerced}
		coerced[i] = out.value
	return {"success": true, "status": CommandDispatchStatus.SUCCESS, "error": "", "args": coerced}


func _parameter_count_message(command_name: String, min_args: int, max_args: int, provided: int) -> String:
	var description: String
	if max_args < 0:
		description = "at least %d %s" % [min_args, "parameter" if min_args == 1 else "parameters"]
	elif min_args == 0:
		description = "at most %d %s" % [max_args, "parameter" if max_args == 1 else "parameters"]
	elif min_args != max_args:
		description = "between %d and %d parameters" % [min_args, max_args]
	else:
		description = "%d %s" % [min_args, "parameter" if min_args == 1 else "parameters"]
	return "%s requires %s, but %d %s provided." % [command_name, description, provided, "was" if provided == 1 else "were"]


## Converts one command argument to the handler's declared parameter type.
## Returns {ok, value, error}: a conversion that cannot be performed is a
## dispatch error naming what was expected, never a silent zero.
func _coerce_value(value: Variant, target_type: int, type_class: String = "", param_name: String = "", index: int = 0) -> Dictionary:
	if not value is String:
		return {"ok": true, "value": value, "error": ""}

	var str_value: String = value
	var failure := func(type_description: String) -> Dictionary:
		return {"ok": false, "value": null,
			"error": "can't convert the given parameter at position %d (\"%s\") to parameter %s of type %s" % [index + 1, str_value, param_name, type_description]}

	match target_type:
		TYPE_NIL, TYPE_STRING:
			return {"ok": true, "value": str_value, "error": ""}

		TYPE_STRING_NAME:
			return {"ok": true, "value": StringName(str_value), "error": ""}

		TYPE_OBJECT:
			# Node-typed parameters: resolve string to node via scene tree lookup
			if _is_node_class(type_class):
				var node := _find_node_by_name(str_value)
				var match_node: Node = null
				if node != null:
					match_node = _find_matching_node(node, type_class)
				if match_node == null:
					push_warning("yarn library: no %s named '%s' was found for parameter %s" % [type_class, str_value, param_name])
				return {"ok": true, "value": match_node, "error": ""}
			return failure.call(type_class if not type_class.is_empty() else "Object")

		TYPE_INT:
			var parsed := parse_int32(str_value)
			if parsed.ok:
				return {"ok": true, "value": parsed.value, "error": ""}
			return failure.call("int")

		TYPE_FLOAT:
			var parsed := parse_single(str_value)
			if parsed.ok:
				return {"ok": true, "value": parsed.value, "error": ""}
			return failure.call("float")

		TYPE_BOOL:
			# Flag style (matches Yarn Spinner): passing a bool parameter's own
			# name as a bareword infers true, e.g. <<play_animation ... wait>>
			# for a parameter named "wait".
			if not param_name.is_empty() and str_value.to_lower() == param_name.to_lower():
				return {"ok": true, "value": true, "error": ""}
			var parsed := parse_bool(str_value)
			if parsed.ok:
				return {"ok": true, "value": parsed.value, "error": ""}
			return failure.call("bool")

		TYPE_VECTOR2:
			var components := _parse_vector_components(str_value, 2)
			if components.is_empty():
				return failure.call("Vector2")
			return {"ok": true, "value": Vector2(components[0], components[1]), "error": ""}

		TYPE_VECTOR3:
			var components := _parse_vector_components(str_value, 3)
			if components.is_empty():
				return failure.call("Vector3")
			return {"ok": true, "value": Vector3(components[0], components[1], components[2]), "error": ""}

		TYPE_COLOR:
			var color := _parse_color(str_value)
			if color.ok:
				return {"ok": true, "value": color.value, "error": ""}
			return failure.call("Color")

	return failure.call(type_string(target_type))


func _parse_vector_components(s: String, count: int) -> PackedFloat64Array:
	var trimmed := s.strip_edges().trim_prefix("(").trim_suffix(")")
	var parts := trimmed.split(",")
	var result := PackedFloat64Array()
	if parts.size() != count:
		return result
	for part in parts:
		var parsed := parse_single(part)
		if not parsed.ok:
			return PackedFloat64Array()
		result.append(parsed.value)
	return result


func _parse_color(s: String) -> Dictionary:
	var trimmed := s.strip_edges()
	if Color.html_is_valid(trimmed):
		return {"ok": true, "value": Color.html(trimmed)}
	var first := Color.from_string(trimmed, Color(0, 0, 0, 0))
	var second := Color.from_string(trimmed, Color(1, 1, 1, 1))
	if first == second:
		return {"ok": true, "value": first}
	return {"ok": false, "value": Color.WHITE}


func _find_matching_node(node: Node, type_class: String) -> Node:
	if _node_matches_class(node, type_class):
		return node
	for child in node.get_children():
		var found := _find_matching_node(child, type_class)
		if found != null:
			return found
	return null


func _node_matches_class(node: Node, type_class: String) -> bool:
	if type_class.is_empty() or type_class == "Node":
		return true
	if ClassDB.class_exists(type_class):
		return node.is_class(type_class)
	var info := _get_global_class(type_class)
	if info.is_empty():
		return false
	var script := node.get_script() as Script
	while script != null:
		if script.resource_path == info.get("path", ""):
			return true
		script = script.get_base_script()
	return false


func _is_node_class(type_class: String) -> bool:
	var current := type_class
	for i in range(64):
		if current.is_empty():
			return false
		if current == "Node":
			return true
		if ClassDB.class_exists(current):
			return ClassDB.is_parent_class(current, "Node")
		var info := _get_global_class(current)
		if info.is_empty():
			return false
		current = info.get("base", "")
	return false


static func _get_global_class(class_name_to_find: String) -> Dictionary:
	var classes: Dictionary = _global_classes
	if not classes.has(class_name_to_find):
		classes = {}
		for class_info in ProjectSettings.get_global_class_list():
			classes[String(class_info.get("class", ""))] = class_info
		_global_classes = classes
	return classes.get(class_name_to_find, {})


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


func _get_variable_storage() -> YarnVariableStorage:
	if _variable_storage != null:
		return _variable_storage
	var vm := _get_vm()
	if vm != null:
		return vm.variable_storage
	return null


func _get_program() -> YarnProgram:
	var vm := _get_vm()
	if vm != null and vm.program != null:
		return vm.program
	return _program


func _register_builtin_functions() -> void:
	_add_function("Number.Add", _op_number_add)
	_add_function("Number.Minus", _op_number_minus)
	_add_function("Number.Multiply", _op_number_multiply)
	_add_function("Number.Divide", _op_number_divide)
	_add_function("Number.Modulo", _op_number_modulo)
	_add_function("Number.UnaryMinus", _op_number_unary_minus)

	_add_function("Number.EqualTo", _op_number_equal)
	_add_function("Number.NotEqualTo", _op_number_not_equal)
	_add_function("Number.LessThan", _op_number_less_than)
	_add_function("Number.LessThanOrEqualTo", _op_number_less_than_or_equal)
	_add_function("Number.GreaterThan", _op_number_greater_than)
	_add_function("Number.GreaterThanOrEqualTo", _op_number_greater_than_or_equal)

	_add_function("Bool.Not", _op_bool_not)
	_add_function("Bool.And", _op_bool_and)
	_add_function("Bool.Or", _op_bool_or)
	_add_function("Bool.Xor", _op_bool_xor)
	_add_function("Bool.EqualTo", _op_bool_equal)
	_add_function("Bool.NotEqualTo", _op_bool_not_equal)

	_add_function("String.Add", _op_string_add)
	_add_function("String.EqualTo", _op_string_equal)
	_add_function("String.NotEqualTo", _op_string_not_equal)

	_add_function("Enum.EqualTo", _op_enum_equal)
	_add_function("Enum.NotEqualTo", _op_enum_not_equal)

	_add_function("string", _builtin_string)
	_add_function("number", _builtin_number)
	_add_function("bool", _builtin_bool)

	_add_function("random", _builtin_random)
	_add_function("random_range", _builtin_random_range)
	_add_function("random_range_float", _builtin_random_range_float)
	_add_function("dice", _builtin_dice)
	_add_function("round", _builtin_round)
	_add_function("round_places", _builtin_round_places)
	_add_function("floor", _builtin_floor)
	_add_function("ceil", _builtin_ceil)
	_add_function("inc", _builtin_inc)
	_add_function("dec", _builtin_dec)
	_add_function("decimal", _builtin_decimal)
	_add_function("int", _builtin_int)

	_add_function("min", _builtin_min)
	_add_function("max", _builtin_max)
	_add_function("abs", _builtin_abs)
	_add_function("sign", _builtin_sign)
	_add_function("clamp", _builtin_clamp)
	_add_function("lerp", _builtin_lerp)
	_add_function("inverse_lerp", _builtin_inverse_lerp)
	_add_function("smoothstep", _builtin_smoothstep)
	_add_function("pow", _builtin_pow)
	_add_function("sqrt", _builtin_sqrt)
	_add_function("wrap", _builtin_wrap)
	_add_function("mod", _builtin_mod)

	_add_function("visited", _builtin_visited)
	_add_function("visited_count", _builtin_visited_count)
	_add_function("has_any_content", _builtin_has_any_content)

	_add_function("format_invariant", _builtin_format_invariant)
	_add_function("format", _builtin_format)

	_add_function("plural", _builtin_plural)
	_add_function("ordinal", _builtin_ordinal)

	_add_function("length", _builtin_length)
	_add_function("uppercase", _builtin_uppercase)
	_add_function("lowercase", _builtin_lowercase)
	_add_function("first_letter_caps", _builtin_first_letter_caps)


func _builtin_string(value: Variant) -> String:
	return YarnVirtualMachine._value_to_string(value)


func _builtin_number(value: Variant) -> float:
	if value is String:
		var parsed := parse_single(value)
		if parsed.ok:
			return parsed.value
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
		var parsed := parse_bool(value)
		if parsed.ok:
			return parsed.value
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
	var range_size := int(max_val) - int(min_val) + 1
	if range_size < 0:
		report_function_error("random_range(): the maximum must not be less than the minimum")
		return 0.0
	if range_size == 0:
		return min_val
	return float(randi_range(0, range_size - 1)) + min_val


func _builtin_random_range_float(min_val: float, max_val: float) -> float:
	var range_size := int(max_val) - int(min_val) + 1
	if range_size < 0:
		report_function_error("random_range_float(): the maximum must not be less than the minimum")
		return 0.0
	if range_size == 0:
		return min_val
	return float(randi_range(0, range_size - 1)) + min_val


func _builtin_dice(sides: int) -> int:
	if sides < 0:
		report_function_error("dice(): the number of sides must not be negative")
		return 0
	if sides == 0:
		return 1
	return randi_range(1, sides)


func _builtin_round(value: float) -> int:
	return int(YarnNumber.round_half_to_even(value))


func _builtin_round_places(value: float, places: int) -> float:
	if places < 0 or places > 15:
		report_function_error("round_places(): rounding digits must be between 0 and 15, inclusive")
		return 0.0
	if absf(value) >= 1e16:
		return value
	var power := pow(10.0, places)
	return YarnNumber.round_half_to_even(value * power) / power


func _builtin_floor(value: float) -> int:
	return int(floorf(value))


func _builtin_ceil(value: float) -> int:
	return int(ceilf(value))


func _builtin_inc(value: float) -> int:
	# Unity: no decimal -> value + 1, else ceil
	if _builtin_decimal(value) == 0.0:
		return int(YarnNumber.to_f32(value + 1.0))
	return int(ceilf(value))


func _builtin_dec(value: float) -> int:
	# Unity: no decimal -> value - 1, else floor
	if _builtin_decimal(value) == 0.0:
		return int(value) - 1
	return int(floorf(value))


func _builtin_decimal(value: float) -> float:
	# Truncation-based: decimal(-3.5) = -0.5, not 0.5
	return YarnNumber.to_f32(value - float(int(value)))


func _builtin_int(value: float) -> int:
	return int(value)


func _builtin_format_invariant(value: float) -> String:
	return YarnNumber.to_display_string(value)


func _builtin_plural(value: float, ...forms: Array) -> String:
	if forms.is_empty():
		return ""
	var int_value := int(value)

	if forms.size() == 2:
		if int_value == 1:
			return YarnVirtualMachine._value_to_string(forms[0])
		return YarnVirtualMachine._value_to_string(forms[1])
	elif forms.size() == 3:
		if int_value == 0:
			return YarnVirtualMachine._value_to_string(forms[0])
		elif int_value == 1:
			return YarnVirtualMachine._value_to_string(forms[1])
		return YarnVirtualMachine._value_to_string(forms[2])

	return YarnVirtualMachine._value_to_string(forms[forms.size() - 1])


func _builtin_ordinal(value: float, ...forms: Array) -> String:
	if forms.is_empty():
		return ""
	var abs_val := absi(int(value))
	var last := forms.size() - 1

	if abs_val % 100 in [11, 12, 13]:
		return YarnVirtualMachine._value_to_string(forms[mini(3, last)])

	match abs_val % 10:
		1:
			return YarnVirtualMachine._value_to_string(forms[mini(0, last)])
		2:
			return YarnVirtualMachine._value_to_string(forms[mini(1, last)])
		3:
			return YarnVirtualMachine._value_to_string(forms[mini(2, last)])
		_:
			return YarnVirtualMachine._value_to_string(forms[mini(3, last)])


func _builtin_min(a: float, b: float) -> float:
	if is_nan(a) or is_nan(b):
		return NAN
	return minf(a, b)


func _builtin_max(a: float, b: float) -> float:
	if is_nan(a) or is_nan(b):
		return NAN
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


func _builtin_format(format_string: String, argument: Variant) -> String:
	var result: Dictionary = YarnFormat.format(format_string, argument)
	if not result.ok:
		report_function_error("format(): %s" % result.error)
		return ""
	return result.text


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


func _builtin_visited(node_name: String) -> bool:
	return _builtin_visited_count(node_name) > 0.0


func _builtin_visited_count(node_name: String) -> float:
	var storage := _get_variable_storage()
	if storage == null:
		return 0.0
	var value: Variant = storage.get_value(YarnVirtualMachine.generate_visit_variable_name(node_name))
	if value is float or value is int:
		return float(value)
	return 0.0


func _builtin_has_any_content(node_name: String) -> bool:
	var program := _get_program()
	if program == null:
		return false
	var node := program.get_node(node_name)
	if node == null:
		return false
	if not node.has_header(YarnProgram.NODE_GROUP_HUB_HEADER):
		return true
	var saliency := YarnSmartVariableVM.try_get_saliency_options_for_node_group(
		node_name, program, _get_variable_storage(), self)
	var saliency_error: String = saliency.error
	if not saliency_error.is_empty():
		report_function_error(saliency_error)
		return false
	var candidates: Array[Dictionary] = saliency.options
	var strategy := _saliency_strategy
	var vm := _get_vm()
	if vm != null:
		strategy = vm.get_effective_saliency_strategy()
	if strategy == null:
		strategy = YarnSaliencyStrategy.YarnRandomBestLeastRecentlyViewedSaliencyStrategy.new()
	var context := {"vm": vm, "variable_storage": _get_variable_storage()}
	return strategy.select_candidate(candidates, context) >= 0


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


func _op_number_modulo(a: int, b: int) -> int:
	if b == 0:
		report_function_error("attempted to divide by zero")
		return 0
	# Operands convert to int before modulo
	return a % b


func _op_number_unary_minus(a: float) -> float:
	return -a


func _op_number_equal(a: float, b: float) -> bool:
	return YarnNumber.to_f32(a) == YarnNumber.to_f32(b)


func _op_number_not_equal(a: float, b: float) -> bool:
	return YarnNumber.to_f32(a) != YarnNumber.to_f32(b)


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
		return YarnVirtualMachine._value_to_string(a) == YarnVirtualMachine._value_to_string(b)
	return YarnNumber.to_int32(float(a)) == YarnNumber.to_int32(float(b))


func _op_enum_not_equal(a: Variant, b: Variant) -> bool:
	return not _op_enum_equal(a, b)
