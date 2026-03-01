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
extends EditorProperty
## Dropdown property editor for selecting a Yarn node name.

const _YarnProgramParser := preload("res://addons/yarn_spinner/core/yarn_program_parser.gd")

var _option_button: OptionButton
var _updating: bool = false


func _init() -> void:
	_option_button = OptionButton.new()
	_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_button.clip_text = true
	_option_button.item_selected.connect(_on_item_selected)
	add_child(_option_button)


func _update_property() -> void:
	_updating = true
	_option_button.clear()

	var current_value: String = str(get_edited_object().get(get_edited_property()))
	var node_names := _get_node_names()

	if node_names.is_empty():
		_option_button.add_item(current_value if not current_value.is_empty() else "Start")
		_option_button.selected = 0
		_updating = false
		return

	var selected_idx := -1
	for i in range(node_names.size()):
		_option_button.add_item(node_names[i])
		if node_names[i] == current_value:
			selected_idx = i

	if selected_idx >= 0:
		_option_button.selected = selected_idx
	elif not current_value.is_empty():
		_option_button.add_item(current_value)
		_option_button.selected = _option_button.item_count - 1
	else:
		_option_button.selected = 0

	_updating = false


func _on_item_selected(index: int) -> void:
	if _updating:
		return
	emit_changed(get_edited_property(), _option_button.get_item_text(index))


func _get_node_names() -> PackedStringArray:
	var obj := get_edited_object()
	if obj == null:
		return PackedStringArray()

	var project_variant: Variant = obj.get("yarn_project")
	if project_variant == null:
		return PackedStringArray()

	var compiled_variant: Variant = (project_variant as Resource).get("compiled_program")
	if not (compiled_variant is PackedByteArray):
		return PackedStringArray()

	var bytes: PackedByteArray = compiled_variant
	if bytes.is_empty():
		return PackedStringArray()

	var program: YarnProgram = _YarnProgramParser.parse_from_bytes(bytes)
	if program == null:
		return PackedStringArray()

	var all_names := program.get_node_names()
	var filtered: PackedStringArray = []
	for node_name in all_names:
		if not node_name.begins_with("$"):
			filtered.append(node_name)
	return filtered
