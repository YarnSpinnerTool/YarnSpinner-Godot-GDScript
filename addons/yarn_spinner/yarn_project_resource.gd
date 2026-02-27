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

@icon("res://addons/yarn_spinner/icons/yarn_project.svg")
class_name YarnProjectResource
extends Resource
## resource containing a compiled yarn project.
## created by importing .yarnproject files.

const _YarnProgramParser := preload("res://addons/yarn_spinner/core/yarn_program_parser.gd")

@export var compiled_program: PackedByteArray = PackedByteArray()
## line_id -> text
@export var string_table: Dictionary = {}
## line_id -> tags array
@export var line_metadata: Dictionary = {}
@export var source_files: PackedStringArray = PackedStringArray()

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


