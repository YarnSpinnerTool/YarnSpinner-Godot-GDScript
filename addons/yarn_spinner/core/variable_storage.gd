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

class_name YarnVariableStorage
extends Node
## Base class for variable storage in Yarn Spinner.
## Matches Unity's IVariableStorage interface.

enum VariableKind {
	STORED,
	SMART,
	UNKNOWN,
}

signal variable_changed(variable_name: String, new_value: Variant)

var _program: YarnProgram
var smart_variable_evaluator: YarnSmartVariableEvaluator
var _change_listeners: Dictionary[String, Array] = {}
var _global_listeners: Array[Callable] = []
var _subscriptions: Dictionary[int, Dictionary] = {}
var _next_subscription_id: int = 0
var _node_subscriptions: Dictionary[int, Array] = {}


func set_program(program: YarnProgram) -> void:
	_program = program


## Listener callable receives (variable_name: String, new_value: Variant, old_value: Variant).
func register_change_listener(variable_name: String, listener: Callable) -> void:
	if not _change_listeners.has(variable_name):
		_change_listeners[variable_name] = []
	var listeners: Array = _change_listeners[variable_name]
	if listener not in listeners:
		listeners.append(listener)


func unregister_change_listener(variable_name: String, listener: Callable) -> void:
	if _change_listeners.has(variable_name):
		var listeners: Array = _change_listeners[variable_name]
		listeners.erase(listener)
		if listeners.is_empty():
			_change_listeners.erase(variable_name)


## Listener callable receives (variable_name: String, new_value: Variant, old_value: Variant).
func register_global_listener(listener: Callable) -> void:
	if listener not in _global_listeners:
		_global_listeners.append(listener)


func unregister_global_listener(listener: Callable) -> void:
	_global_listeners.erase(listener)


## Returns a subscription id. Automatically unsubscribes when owner is freed.
func subscribe(owner: Node, variable_name: String, listener: Callable) -> int:
	var subscription_id := _next_subscription_id
	_next_subscription_id += 1

	_subscriptions[subscription_id] = {
		"variable": variable_name,
		"listener": listener,
		"owner": owner
	}

	register_change_listener(variable_name, listener)

	var owner_id := owner.get_instance_id()
	if not _node_subscriptions.has(owner_id):
		_node_subscriptions[owner_id] = []
		owner.tree_exiting.connect(_on_owner_freed.bind(owner_id), CONNECT_ONE_SHOT)

	_node_subscriptions[owner_id].append(subscription_id)

	return subscription_id


## Listener receives only the new value, coerced to expected_type.
func subscribe_typed(owner: Node, variable_name: String, listener: Callable, expected_type: int) -> int:
	var typed_wrapper := func(var_name: String, new_val: Variant, old_val: Variant):
		var typed_value := _coerce_to_type(new_val, expected_type)
		listener.call(typed_value)

	return subscribe(owner, variable_name, typed_wrapper)


func subscribe_float(owner: Node, variable_name: String, listener: Callable) -> int:
	return subscribe_typed(owner, variable_name, listener, TYPE_FLOAT)


func subscribe_int(owner: Node, variable_name: String, listener: Callable) -> int:
	return subscribe_typed(owner, variable_name, listener, TYPE_INT)


func subscribe_bool(owner: Node, variable_name: String, listener: Callable) -> int:
	return subscribe_typed(owner, variable_name, listener, TYPE_BOOL)


func subscribe_string(owner: Node, variable_name: String, listener: Callable) -> int:
	return subscribe_typed(owner, variable_name, listener, TYPE_STRING)


func unsubscribe(subscription_id: int) -> void:
	if not _subscriptions.has(subscription_id):
		return

	var sub: Dictionary = _subscriptions[subscription_id]
	unregister_change_listener(sub["variable"], sub["listener"])

	var owner: Node = sub["owner"]
	if is_instance_valid(owner):
		var owner_id := owner.get_instance_id()
		if _node_subscriptions.has(owner_id):
			_node_subscriptions[owner_id].erase(subscription_id)
			if _node_subscriptions[owner_id].is_empty():
				_node_subscriptions.erase(owner_id)

	_subscriptions.erase(subscription_id)


func _on_owner_freed(owner_id: int) -> void:
	if not _node_subscriptions.has(owner_id):
		return

	var sub_ids: Array = _node_subscriptions[owner_id].duplicate()
	for sub_id in sub_ids:
		if _subscriptions.has(sub_id):
			var sub: Dictionary = _subscriptions[sub_id]
			unregister_change_listener(sub["variable"], sub["listener"])
			_subscriptions.erase(sub_id)

	_node_subscriptions.erase(owner_id)


func _coerce_to_type(value: Variant, target_type: int) -> Variant:
	if typeof(value) == target_type:
		return value

	match target_type:
		TYPE_FLOAT:
			if value is int:
				return float(value)
			if value is String and value.is_valid_float():
				return float(value)
			if value is bool:
				return 1.0 if value else 0.0
			return 0.0

		TYPE_INT:
			if value is float:
				return int(value)
			if value is String and value.is_valid_int():
				return int(value)
			if value is bool:
				return 1 if value else 0
			return 0

		TYPE_BOOL:
			if value is float or value is int:
				return value != 0
			if value is String:
				return value.to_lower() == "true" or value == "1"
			return bool(value)

		TYPE_STRING:
			return str(value)

		_:
			return value


func _notify_listeners(variable_name: String, new_value: Variant, old_value: Variant) -> void:
	if _change_listeners.has(variable_name):
		var listeners: Array = _change_listeners[variable_name].duplicate()
		for listener in listeners:
			if listener.is_valid():
				listener.call(variable_name, new_value, old_value)

	var global_copy := _global_listeners.duplicate()
	for listener in global_copy:
		if listener.is_valid():
			listener.call(variable_name, new_value, old_value)

	variable_changed.emit(variable_name, new_value)


func set_value(variable_name: String, value: Variant) -> void:
	push_error("variable storage: set_value not implemented")


## Returns the Yarn type name for a value: "string", "number", "bool", or "unknown".
static func yarn_type_name(value: Variant) -> String:
	if value is bool:
		return "bool"
	if value is float or value is int:
		return "number"
	if value is String:
		return "string"
	return "unknown"


## Returns true if two values have compatible Yarn types.
## int and float are both "number" and are considered compatible.
static func is_yarn_type_compatible(a: Variant, b: Variant) -> bool:
	return yarn_type_name(a) == yarn_type_name(b)


## Validate that value has the correct type for variable_name.
## Checks against the currently stored value or the program's declared initial value.
## Returns true if the value is acceptable, false if it should be rejected.
func validate_value_type(variable_name: String, value: Variant) -> bool:
	# Reject non-Yarn types (arrays, objects, etc.) regardless
	var type_name := yarn_type_name(value)
	if type_name == "unknown":
		push_error("variable storage: cannot store %s in Yarn variable '%s' — Yarn variables must be string, number, or bool" % [type_string(typeof(value)), variable_name])
		return false

	# Find the existing value to check type against
	var existing: Variant = null
	var has_existing := false

	var result := try_get_value(variable_name)
	if result.found:
		existing = result.value
		has_existing = true
	elif _program != null and _program.has_initial_value(variable_name):
		existing = _program.get_initial_value(variable_name)
		has_existing = true

	if not has_existing:
		# New variable with no declared type — allow any Yarn-compatible type
		return true

	if not is_yarn_type_compatible(existing, value):
		push_error("variable storage: cannot assign %s value to variable '%s' (expected %s)" % [type_name, variable_name, yarn_type_name(existing)])
		return false

	return true


## Returns {found: bool, value: Variant}.
func try_get_value(variable_name: String) -> Dictionary:
	push_error("variable storage: try_get_value not implemented")
	return {found = false, value = null}


## Checks stored, then smart variables, then program initial values.
##
## Smart variables are checked before initial values because they are
## expression-based and should always re-evaluate.
func get_value(variable_name: String) -> Variant:
	var result := try_get_value(variable_name)
	if result.found:
		return result.value
	if smart_variable_evaluator != null:
		var smart_result := smart_variable_evaluator.try_get_smart_variable(variable_name)
		if smart_result.found:
			return smart_result.value
	if _program != null and _program.has_initial_value(variable_name):
		return _program.get_initial_value(variable_name)
	# Internal Yarn variables are expected to not exist on first access
	if not variable_name.begins_with("$Yarn.Internal."):
		push_warning("variable storage: variable '%s' not found" % variable_name)
	return null


func get_variable_kind(variable_name: String) -> VariableKind:
	if try_get_value(variable_name).found:
		return VariableKind.STORED
	if smart_variable_evaluator != null and smart_variable_evaluator.is_smart_variable(variable_name):
		return VariableKind.SMART
	if _program != null:
		var kind: int = _program.get_variable_kind(variable_name)
		if kind != YarnProgram.VariableKind.UNKNOWN:
			if kind == YarnProgram.VariableKind.STORED:
				return VariableKind.STORED
			elif kind == YarnProgram.VariableKind.SMART:
				return VariableKind.SMART
	return VariableKind.UNKNOWN


func has_value(variable_name: String) -> bool:
	if try_get_value(variable_name).found:
		return true
	if smart_variable_evaluator != null and smart_variable_evaluator.is_smart_variable(variable_name):
		return true
	if _program != null and _program.has_initial_value(variable_name):
		return true
	return false


## Returns {found: bool, value: float}.
func try_get_float(variable_name: String) -> Dictionary:
	var value: Variant = get_value(variable_name)
	if value == null:
		return {found = false, value = 0.0}
	if value is float:
		return {found = true, value = value}
	if value is int:
		return {found = true, value = float(value)}
	return {found = false, value = 0.0}


## Returns {found: bool, value: String}.
func try_get_string(variable_name: String) -> Dictionary:
	var value: Variant = get_value(variable_name)
	if value == null:
		return {found = false, value = ""}
	if value is String:
		return {found = true, value = value}
	return {found = false, value = ""}


## Returns {found: bool, value: bool}.
func try_get_bool(variable_name: String) -> Dictionary:
	var value: Variant = get_value(variable_name)
	if value == null:
		return {found = false, value = false}
	if value is bool:
		return {found = true, value = value}
	return {found = false, value = false}


func get_float(variable_name: String, default_value: float = 0.0) -> float:
	var result := try_get_float(variable_name)
	return result.value if result.found else default_value


func get_string(variable_name: String, default_value: String = "") -> String:
	var result := try_get_string(variable_name)
	return result.value if result.found else default_value


func get_bool(variable_name: String, default_value: bool = false) -> bool:
	var result := try_get_bool(variable_name)
	return result.value if result.found else default_value


func clear() -> void:
	push_error("variable storage: clear not implemented")


func get_all_variable_names() -> PackedStringArray:
	push_error("variable storage: get_all_variable_names not implemented")
	return PackedStringArray()


func get_all_variables() -> Dictionary:
	push_error("variable storage: get_all_variables not implemented")
	return {}


func set_all_variables(variables: Dictionary) -> void:
	for name in variables:
		set_value(name, variables[name])
