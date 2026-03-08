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

class_name YarnInMemoryVariableStorage
extends YarnVariableStorage
## In-memory implementation of variable storage.

var _variables: Dictionary = {}
var validate_variable_names: bool = false

## Assign a Label or RichTextLabel to display variables in-game.
@export var debug_text_view: Control

@export var show_debug: bool = false


func _process(_delta: float) -> void:
	if show_debug and debug_text_view != null:
		_update_debug_view()


func _update_debug_view() -> void:
	if debug_text_view == null:
		return

	var debug_text := get_debug_list()

	if debug_text_view is RichTextLabel:
		debug_text_view.text = debug_text
	elif debug_text_view is Label:
		debug_text_view.text = debug_text
	elif debug_text_view.has_method("set_text"):
		debug_text_view.set_text(debug_text)


func _validate_variable_name(variable_name: String) -> bool:
	if not validate_variable_names:
		return true
	if variable_name.is_empty():
		push_error("variable storage: variable name cannot be empty")
		return false
	if not variable_name.begins_with("$"):
		push_warning("variable storage: variable '%s' should start with '$'" % variable_name)
		# don't fail, just warn - many scripts omit the $
	return true


func set_value(variable_name: String, value: Variant) -> void:
	if not _validate_variable_name(variable_name):
		return
	if not validate_value_type(variable_name, value):
		return
	var old_value: Variant = _variables.get(variable_name)
	_variables[variable_name] = value
	if old_value != value:
		_notify_listeners(variable_name, value, old_value)


func try_get_value(variable_name: String) -> Dictionary:
	if _variables.has(variable_name):
		return {found = true, value = _variables[variable_name]}
	return {found = false, value = null}


func clear() -> void:
	_variables.clear()


func get_all_variable_names() -> PackedStringArray:
	return PackedStringArray(_variables.keys())


func get_all_variables() -> Dictionary:
	return _variables.duplicate()


func load_initial_values_from_program(program: YarnProgram) -> void:
	for var_name in program.initial_values:
		if not _variables.has(var_name):
			_variables[var_name] = program.initial_values[var_name]


func to_save_data() -> Dictionary:
	return _variables.duplicate()


func from_save_data(data: Dictionary) -> void:
	_variables = data.duplicate()


func contains(variable_name: String) -> bool:
	return _variables.has(variable_name)


func get_debug_list() -> String:
	var lines := PackedStringArray()
	for var_name in _variables:
		var value: Variant = _variables[var_name]
		var type_name := _get_type_name(value)
		lines.append("%s = %s (%s)" % [var_name, str(value), type_name])
	return "\n".join(lines)


func _get_type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "string"
		_:
			return type_string(typeof(value))


func get_all_variables_typed() -> Dictionary:
	var floats := {}
	var strings := {}
	var bools := {}

	for var_name in _variables:
		var value: Variant = _variables[var_name]
		if value is bool:
			bools[var_name] = value
		elif value is float or value is int:
			floats[var_name] = float(value)
		elif value is String:
			strings[var_name] = value

	return {"floats": floats, "strings": strings, "bools": bools}


func set_all_variables_typed(floats: Dictionary, strings: Dictionary, bools: Dictionary, clear_first: bool = true) -> void:
	if clear_first:
		_variables.clear()

	for var_name in floats:
		set_value(var_name, floats[var_name])
	for var_name in strings:
		set_value(var_name, strings[var_name])
	for var_name in bools:
		set_value(var_name, bools[var_name])
