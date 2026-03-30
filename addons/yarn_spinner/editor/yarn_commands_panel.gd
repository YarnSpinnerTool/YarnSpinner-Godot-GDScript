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
## Bottom panel showing discovered Yarn commands and functions, grouped by project.

var _filter_edit: LineEdit
var _project_selector: OptionButton
var _tree: Tree
var _status_label: Label

## Cached per-project YSLS data: { project_path: { commands: [], functions: [] } }
var _project_data: Dictionary = {}
## Ordered list of project paths matching the selector indices
var _project_paths: Array[String] = []

const ALL_PROJECTS := "(All Projects)"


func _init() -> void:
	name = "YarnCommandsPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Toolbar
	var toolbar := HBoxContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_project_selector = OptionButton.new()
	_project_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_project_selector.item_selected.connect(_on_project_selected)
	toolbar.add_child(_project_selector)

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
	_project_data.clear()
	_project_paths.clear()

	# Find all .yarnproject files
	var yarn_projects := _find_yarn_projects("res://")

	# Generate YSLS per project
	for project_path in yarn_projects:
		var generator := YarnYSLSGenerator.new()
		var scan_root := YarnYSLSGenerator.find_scan_root(project_path)
		generator.scan_directory(scan_root)
		var ysls := generator.generate_ysls_dict()
		_project_data[project_path] = ysls
		_project_paths.append(project_path)

	# Update the project selector
	var prev_selected := _project_selector.selected
	_project_selector.clear()
	_project_selector.add_item(ALL_PROJECTS)
	for project_path in _project_paths:
		_project_selector.add_item(project_path.get_file().get_basename())

	if prev_selected >= 0 and prev_selected < _project_selector.item_count:
		_project_selector.selected = prev_selected
	else:
		_project_selector.selected = 0

	_rebuild_tree()


func _on_project_selected(_index: int) -> void:
	_rebuild_tree()


func _on_filter_changed(_new_text: String) -> void:
	_rebuild_tree()


func _rebuild_tree() -> void:
	var selected_idx := _project_selector.selected
	var filter := _filter_edit.text

	# Collect commands and functions for the selected scope
	var commands: Array = []
	var functions: Array = []

	if selected_idx <= 0:
		# "All Projects" — merge all, grouped by project
		_build_tree_grouped(filter)
		return
	else:
		var project_idx := selected_idx - 1  # offset for "All Projects" entry
		if project_idx < _project_paths.size():
			var project_path := _project_paths[project_idx]
			var ysls: Dictionary = _project_data.get(project_path, {})
			commands = ysls.get("commands", [])
			functions = ysls.get("functions", [])

	_build_tree_flat(commands, functions, filter)


func _build_tree_flat(commands: Array, functions: Array, filter_text: String) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var filter := filter_text.to_lower()

	var filtered_commands := _filter_items(commands, filter)
	if not filtered_commands.is_empty():
		var cmd_header := _tree.create_item(root)
		cmd_header.set_text(0, "Commands (%d)" % filtered_commands.size())
		_set_header_style(cmd_header)

		for cmd in filtered_commands:
			_add_item(cmd_header, cmd, "command")

	var filtered_functions := _filter_items(functions, filter)
	if not filtered_functions.is_empty():
		var func_header := _tree.create_item(root)
		func_header.set_text(0, "Functions (%d)" % filtered_functions.size())
		_set_header_style(func_header)

		for fn in filtered_functions:
			_add_item(func_header, fn, "function")

	var total := filtered_commands.size() + filtered_functions.size()
	_status_label.text = "%d commands, %d functions found." % [filtered_commands.size(), filtered_functions.size()]


func _build_tree_grouped(filter_text: String) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var filter := filter_text.to_lower()
	var total_commands := 0
	var total_functions := 0

	for project_path in _project_paths:
		var ysls: Dictionary = _project_data.get(project_path, {})
		var commands: Array = ysls.get("commands", [])
		var functions: Array = ysls.get("functions", [])

		var filtered_commands := _filter_items(commands, filter)
		var filtered_functions := _filter_items(functions, filter)

		if filtered_commands.is_empty() and filtered_functions.is_empty():
			continue

		# Project header
		var project_name := project_path.get_file().get_basename()
		var project_header := _tree.create_item(root)
		project_header.set_text(0, "%s (%d commands, %d functions)" % [
			project_name, filtered_commands.size(), filtered_functions.size()
		])
		_set_header_style(project_header)

		for cmd in filtered_commands:
			_add_item(project_header, cmd, "command")

		for fn in filtered_functions:
			_add_item(project_header, fn, "function")

		total_commands += filtered_commands.size()
		total_functions += filtered_functions.size()

	_status_label.text = "%d projects, %d commands, %d functions found." % [
		_project_paths.size(), total_commands, total_functions
	]


func _add_item(parent: TreeItem, data: Dictionary, type: String) -> void:
	var item := _tree.create_item(parent)
	var yarn_name: String = data.get("yarnName", "")
	var def_name: String = data.get("definitionName", "")
	var is_runtime := def_name == yarn_name
	item.set_text(0, yarn_name)
	item.set_text(1, type)
	item.set_text(2, _format_parameters(data.get("parameters", []), is_runtime))
	item.set_text(3, data.get("fileName", ""))


func _set_header_style(item: TreeItem) -> void:
	for col in range(4):
		item.set_selectable(col, false)


func _filter_items(items: Array, filter: String) -> Array:
	if filter.is_empty():
		return items
	var result: Array = []
	for item in items:
		var item_name: String = item.get("yarnName", "")
		if item_name.to_lower().contains(filter):
			result.append(item)
	return result


func _format_parameters(params: Array, is_runtime_binding: bool = false) -> String:
	if params.is_empty():
		if is_runtime_binding:
			return "(runtime — parameters unknown)"
		return "()"
	var parts: Array[String] = []
	for param in params:
		var param_name: String = param.get("name", "?")
		var param_type: String = param.get("type", "any")
		parts.append("%s: %s" % [param_name, param_type])
	return "(%s)" % ", ".join(parts)


func _find_yarn_projects(root_path: String) -> Array[String]:
	var results: Array[String] = []
	_find_yarn_projects_recursive(root_path, results)
	return results


func _find_yarn_projects_recursive(dir_path: String, results: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != "addons":
				_find_yarn_projects_recursive(full_path, results)
		elif file_name.ends_with(".yarnproject"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
