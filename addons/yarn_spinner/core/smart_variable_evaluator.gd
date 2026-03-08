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

class_name YarnSmartVariableEvaluator
extends RefCounted
## Evaluates smart (computed) variables at runtime.
## Matches Unity's ISmartVariableEvaluator interface.

signal variable_changed(variable_name: String)

var _external_variables: Dictionary[String, Callable] = {}
var _variable_storage: YarnVariableStorage


func attach_to_storage(storage: YarnVariableStorage) -> void:
	_variable_storage = storage


## The callable should take no arguments and return the computed value.
func register_external_variable(variable_name: String, evaluator: Callable) -> void:
	_external_variables[variable_name] = evaluator


func unregister_external_variable(variable_name: String) -> void:
	_external_variables.erase(variable_name)


var _program: YarnProgram
var _library: YarnLibrary


func set_program_context(program: YarnProgram, library: YarnLibrary) -> void:
	_program = program
	_library = library


func is_smart_variable(variable_name: String) -> bool:
	if _external_variables.has(variable_name):
		return true
	if _program != null:
		var smart_nodes := _program.get_smart_variable_nodes()
		for node in smart_nodes:
			if node.node_name == variable_name:
				return true
	return false


## Returns {found: bool, value: Variant}.
func try_get_smart_variable(variable_name: String) -> Dictionary:
	if _external_variables.has(variable_name):
		var evaluator: Callable = _external_variables[variable_name]
		if not evaluator.is_valid():
			push_warning("External variable '%s' has invalid evaluator" % variable_name)
			return {found = false, value = null}
		var value: Variant = evaluator.call()
		return {found = true, value = value}

	if _program != null and _library != null:
		var result := try_evaluate_from_program(variable_name, _program, _library)
		if result.found:
			return result

	return {found = false, value = null}


## Returns {found: bool, value: Variant}.
func try_evaluate_from_program(variable_name: String, program: YarnProgram, library: YarnLibrary) -> Dictionary:
	var smart_nodes := program.get_smart_variable_nodes()
	for node in smart_nodes:
		if node.node_name == variable_name:
			return YarnSmartVariableVM.try_evaluate(node, _variable_storage, library)
	return {found = false, value = null}


func get_smart_variable_names() -> PackedStringArray:
	var names := PackedStringArray()
	for name in _external_variables.keys():
		names.append(name)
	return names


func notify_variable_changed(variable_name: String) -> void:
	if _external_variables.has(variable_name):
		variable_changed.emit(variable_name)


func clear() -> void:
	_external_variables.clear()


static func create_time_evaluator() -> Callable:
	return func() -> float:
		return Time.get_unix_time_from_system()


static func create_random_evaluator(min_value: float = 0.0, max_value: float = 1.0) -> Callable:
	return func() -> float:
		return randf_range(min_value, max_value)


static func create_frame_count_evaluator() -> Callable:
	return func() -> int:
		return Engine.get_process_frames()


static func create_delta_time_evaluator(scene_tree: SceneTree) -> Callable:
	return func() -> float:
		return scene_tree.root.get_process_delta_time()
