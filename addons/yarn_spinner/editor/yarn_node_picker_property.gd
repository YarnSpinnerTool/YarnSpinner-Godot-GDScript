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

var source_property: StringName = &"yarn_project"
var value_type: Variant.Type = TYPE_STRING

var filter: String = ""
var filter_type: String = "contains"
var filter_header: String = "title"

var _option_button: OptionButton
var _updating: bool = false
var _read_only: bool = false


func _init() -> void:
	_option_button = OptionButton.new()
	_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_button.clip_text = true
	_option_button.item_selected.connect(_on_item_selected)
	add_child(_option_button)


## Reads filter settings from a hint string like
## "yarn_node:yarn_project;filter=Start;filter_type=starts_with;header=tags".
## filter_type is contains, starts_with, ends_with or matches_regex.
func configure_filter(hint_string: String) -> void:
	var parts := hint_string.split(";")
	for i in range(1, parts.size()):
		var pair := parts[i].split("=", true, 1)
		if pair.size() != 2:
			continue
		var key := pair[0].strip_edges()
		var value := pair[1].strip_edges()
		match key:
			"filter":
				filter = value
			"filter_type":
				filter_type = value
			"header":
				filter_header = value


func _enter_tree() -> void:
	var inspector := EditorInterface.get_inspector()
	if not inspector.property_edited.is_connected(_on_inspector_property_edited):
		inspector.property_edited.connect(_on_inspector_property_edited)


func _exit_tree() -> void:
	var inspector := EditorInterface.get_inspector()
	if inspector.property_edited.is_connected(_on_inspector_property_edited):
		inspector.property_edited.disconnect(_on_inspector_property_edited)


func _set_read_only(read_only: bool) -> void:
	_read_only = read_only
	_option_button.disabled = _read_only or _option_button.item_count == 0


func _update_property() -> void:
	_updating = true
	_option_button.clear()

	var current_value: String = str(get_edited_object().get(get_edited_property()))
	var node_names := _get_node_names()

	if node_names.is_empty():
		if not current_value.is_empty():
			_option_button.add_item(current_value)
			_option_button.selected = 0
		_option_button.disabled = _read_only or _option_button.item_count == 0
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

	_option_button.disabled = _read_only
	_updating = false


func _on_item_selected(index: int) -> void:
	if _updating:
		return
	var text := _option_button.get_item_text(index)
	if value_type == TYPE_STRING_NAME:
		emit_changed(get_edited_property(), StringName(text))
	else:
		emit_changed(get_edited_property(), text)


func _on_inspector_property_edited(property: String) -> void:
	if property == source_property and get_edited_object() != null:
		update_property()


func _get_node_names() -> PackedStringArray:
	var project := _find_project()
	if project == null or project.compiled_program.is_empty():
		return PackedStringArray()

	var program := project.get_program()
	if program == null:
		return PackedStringArray()

	return apply_filter(program, filter_node_names(program), filter, filter_type, filter_header)


static func apply_filter(program: YarnProgram, names: PackedStringArray, filter_text: String, type: String, header: String) -> PackedStringArray:
	if filter_text.is_empty():
		return names
	var regex: RegEx = null
	if type == "matches_regex":
		regex = RegEx.create_from_string(filter_text)
		if regex == null or not regex.is_valid():
			push_warning("yarn node picker: \"%s\" isn't a valid regular expression" % filter_text)
			return names
	var needle := filter_text.to_lower().replace("-", "_")
	var result: PackedStringArray = []
	for node_name in names:
		var value := node_name
		if header != "title":
			var node := program.get_node(node_name)
			if node == null or not node.headers.has(header):
				continue
			value = str(node.headers[header])
		var matched := false
		match type:
			"starts_with":
				matched = value.to_lower().begins_with(needle)
			"ends_with":
				matched = value.to_lower().ends_with(needle)
			"matches_regex":
				matched = regex.search(value) != null
			_:
				matched = value.to_lower().contains(needle)
		if matched:
			result.append(node_name)
	return result


func _find_project() -> YarnProjectResource:
	var obj := get_edited_object()
	if obj == null:
		return null

	var source: Variant = obj.get(source_property)
	if source is NodePath and obj is Node:
		var path: NodePath = source
		source = (obj as Node).get_node_or_null(path)

	if typeof(source) != TYPE_OBJECT or not is_instance_valid(source):
		return null
	if source is YarnProjectResource:
		return source

	var nested: Variant = (source as Object).get("yarn_project")
	if nested is YarnProjectResource:
		return nested
	return null


static func filter_node_names(program: YarnProgram) -> PackedStringArray:
	var filtered: PackedStringArray = []
	for node_name in program.get_node_names():
		if node_name.begins_with("$"):
			continue
		var node := program.get_node(node_name)
		if node != null and node.headers.has(YarnProgram.NODE_GROUP_HEADER):
			continue
		filtered.append(node_name)
	filtered.sort()
	return filtered
