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
@icon("res://addons/yarn_spinner/icons/yarn_project.svg")
class_name YarnProjectResource
extends Resource
## resource containing a compiled yarn project.
## created by importing .yarnproject files.

const _YarnProgramParser := preload("res://addons/yarn_spinner/core/yarn_program_parser.gd")

@export var compiled_program: PackedByteArray = PackedByteArray():
	set(value):
		compiled_program = value
		_cached_program = null
## line_id -> text
@export var string_table: Dictionary = {}:
	set(value):
		string_table = value
		_cached_program = null
## line_id -> tags array
@export var line_metadata: Dictionary = {}:
	set(value):
		line_metadata = value
		_cached_program = null
@export var source_files: PackedStringArray = PackedStringArray()
@export var line_info: Dictionary = {}
@export var diagnostics: Array = []
## enum name -> { "raw_type": "Number" or "String", "description": String,
## "cases": [{ "name": String, "value": float or String, "description": String }] }
@export var enums: Dictionary = {}
## variable name -> type name: "Number", "String", "Bool", or an enum's name
@export var variable_types: Dictionary = {}

var _cached_program: YarnProgram


func get_program() -> YarnProgram:
	if _cached_program != null:
		return _cached_program

	if compiled_program.is_empty():
		push_error("yarn project: no compiled program data")
		return null

	_cached_program = _YarnProgramParser.parse_from_bytes(compiled_program)
	if _cached_program != null:
		_cached_program.string_table = string_table.duplicate()
		_cached_program.line_metadata = line_metadata.duplicate()

	return _cached_program


## Whether the project declares an enum called [param enum_name].
func has_enum(enum_name: String) -> bool:
	return enums.has(enum_name)


## The cases of an enum in teh order they're declared. Each gets a Dictionary
## with "name", "value" and "description". Empty if there's no such enum!
func get_enum_cases(enum_name: String) -> Array:
	if not enums.has(enum_name):
		return []
	return (enums[enum_name] as Dictionary).get("cases", [])


## The raw value of [param case_name] in [param enum_name], or null if the
## enum or the case doesn't exist.
func get_enum_value(enum_name: String, case_name: String) -> Variant:
	for entry: Dictionary in get_enum_cases(enum_name):
		if entry.get("name", "") == case_name:
			return entry.get("value")
	return null


## The name of the case of [param enum_name] whose raw value is
## [param value], or an empty string if there isn't one.
func get_enum_case_name(enum_name: String, value: Variant) -> String:
	for entry: Dictionary in get_enum_cases(enum_name):
		var case_value: Variant = entry.get("value")
		if (case_value is float or case_value is int) and (value is float or value is int):
			if is_equal_approx(float(case_value), float(value)):
				return entry.get("name", "")
		elif typeof(case_value) == typeof(value) and case_value == value:
			return entry.get("name", "")
	return ""


## The declared type of [param variable_name]: "Number", "String", "Bool",
## or the name of an enum. Empty if the variable isn't declared...
func get_variable_type(variable_name: String) -> String:
	return variable_types.get(variable_name, "")


func clear_cache() -> void:
	_cached_program = null


func get_node_names() -> PackedStringArray:
	var program := get_program()
	if program == null:
		return PackedStringArray()
	return program.get_node_names()


func has_node(node_name: String) -> bool:
	var program := get_program()
	if program == null:
		return false
	return program.has_node(node_name)


func get_line_ids_for_nodes(node_names: PackedStringArray) -> PackedStringArray:
	var ids := PackedStringArray()
	var program := get_program()
	if program == null:
		return ids
	for node_name in node_names:
		ids.append_array(program.get_line_ids_for_node(node_name))
	return ids


