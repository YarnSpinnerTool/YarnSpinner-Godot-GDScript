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
extends VBoxContainer
## Bottom panel showing all discovered Yarn commands and functions.

var _filter_edit: LineEdit
var _tree: Tree
var _status_label: Label


func _init() -> void:
	name = "YarnCommandsPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Toolbar
	var toolbar := HBoxContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter commands..."
	_filter_edit.clear_button_enabled = true
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(_on_filter_changed)
	toolbar.add_child(_filter_edit)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_refresh)
	toolbar.add_child(refresh_button)

	add_child(toolbar)

	# Tree
	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 4
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Name")
	_tree.set_column_title(1, "Type")
	_tree.set_column_title(2, "Parameters")
	_tree.set_column_title(3, "Source File")
	_tree.set_column_expand_ratio(0, 3)
	_tree.set_column_expand_ratio(1, 1)
	_tree.set_column_expand_ratio(2, 4)
	_tree.set_column_expand_ratio(3, 2)
	_tree.hide_root = true
	add_child(_tree)

	# Status label
	_status_label = Label.new()
	_status_label.text = "Click Refresh to scan for commands and functions."
	add_child(_status_label)


func _refresh() -> void:
	var generator := YarnYSLSGenerator.new()
	generator.scan_directory("res://")
	var ysls := generator.generate_ysls_dict()

	var commands: Array = ysls.get("commands", [])
	var functions: Array = ysls.get("functions", [])

	_build_tree(commands, functions, _filter_edit.text)

	_status_label.text = "%d commands, %d functions found." % [commands.size(), functions.size()]


func _on_filter_changed(_new_text: String) -> void:
	# Re-scan is expensive, so just rebuild the tree with cached data
	_refresh()


func _build_tree(commands: Array, functions: Array, filter_text: String) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var filter := filter_text.to_lower()

	# Commands section
	var filtered_commands := _filter_items(commands, filter)
	if not filtered_commands.is_empty():
		var cmd_header := _tree.create_item(root)
		cmd_header.set_text(0, "Commands (%d)" % filtered_commands.size())
		cmd_header.set_selectable(0, false)
		cmd_header.set_selectable(1, false)
		cmd_header.set_selectable(2, false)
		cmd_header.set_selectable(3, false)

		for cmd in filtered_commands:
			var item := _tree.create_item(cmd_header)
			item.set_text(0, cmd.get("yarnName", ""))
			item.set_text(1, "command")
			item.set_text(2, _format_parameters(cmd.get("parameters", [])))
			item.set_text(3, cmd.get("fileName", ""))

	# Functions section
	var filtered_functions := _filter_items(functions, filter)
	if not filtered_functions.is_empty():
		var func_header := _tree.create_item(root)
		func_header.set_text(0, "Functions (%d)" % filtered_functions.size())
		func_header.set_selectable(0, false)
		func_header.set_selectable(1, false)
		func_header.set_selectable(2, false)
		func_header.set_selectable(3, false)

		for fn in filtered_functions:
			var item := _tree.create_item(func_header)
			item.set_text(0, fn.get("yarnName", ""))
			item.set_text(1, "function")
			item.set_text(2, _format_parameters(fn.get("parameters", [])))
			item.set_text(3, fn.get("fileName", ""))


func _filter_items(items: Array, filter: String) -> Array:
	if filter.is_empty():
		return items
	var result: Array = []
	for item in items:
		var name: String = item.get("yarnName", "")
		if name.to_lower().contains(filter):
			result.append(item)
	return result


func _format_parameters(params: Array) -> String:
	if params.is_empty():
		return "()"
	var parts: Array[String] = []
	for param in params:
		var param_name: String = param.get("name", "?")
		var param_type: String = param.get("type", "any")
		parts.append("%s: %s" % [param_name, param_type])
	return "(%s)" % ", ".join(parts)
