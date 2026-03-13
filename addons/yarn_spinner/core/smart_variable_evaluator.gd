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
## Evaluates smart variables declared in Yarn scripts at runtime.
##
## Smart variables are declared in Yarn scripts using expressions
## (e.g., <<declare $is_powerful = $strength > 50>>). They are compiled
## into bytecode nodes tagged "Yarn.SmartVariable" and re-evaluated each
## time they are accessed.

var _variable_storage: YarnVariableStorage
var _program: YarnProgram
var _library: YarnLibrary


func attach_to_storage(storage: YarnVariableStorage) -> void:
	_variable_storage = storage


func set_program_context(program: YarnProgram, library: YarnLibrary) -> void:
	_program = program
	_library = library


## Returns true if the variable is a smart variable declared in the program.
func is_smart_variable(variable_name: String) -> bool:
	if _program != null:
		var smart_nodes := _program.get_smart_variable_nodes()
		for node in smart_nodes:
			if node.node_name == variable_name:
				return true
	return false


## Returns {found: bool, value: Variant}.
func try_get_smart_variable(variable_name: String) -> Dictionary:
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


## Returns names of all smart variables declared in the program.
func get_smart_variable_names() -> PackedStringArray:
	var names := PackedStringArray()
	if _program != null:
		var smart_nodes := _program.get_smart_variable_nodes()
		for node in smart_nodes:
			names.append(node.node_name)
	return names
