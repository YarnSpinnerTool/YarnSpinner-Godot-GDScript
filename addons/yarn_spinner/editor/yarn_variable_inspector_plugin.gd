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
extends EditorInspectorPlugin
## Shows declared variables and their initial values when inspecting a
## YarnVariableStorage or YarnInMemoryVariableStorage node.

var _display_label: RichTextLabel
var _current_storage: WeakRef


func _can_handle(object: Object) -> bool:
	return object is YarnVariableStorage


func _parse_begin(object: Object) -> void:
	_current_storage = weakref(object)

	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Section header
	var header := Label.new()
	header.text = "Yarn Variable Storage"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	container.add_child(header)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	container.add_child(separator)

	# Variable display
	_display_label = RichTextLabel.new()
	_display_label.bbcode_enabled = true
	_display_label.fit_content = true
	_display_label.scroll_active = false
	_display_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display_label.selection_enabled = true
	container.add_child(_display_label)

	# Refresh button
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	refresh_button.pressed.connect(_update_variable_display)
	container.add_child(refresh_button)

	var bottom_separator := HSeparator.new()
	bottom_separator.add_theme_constant_override("separation", 8)
	container.add_child(bottom_separator)

	add_custom_control(container)
	_update_variable_display()


func _update_variable_display() -> void:
	if _display_label == null:
		return

	var storage: YarnVariableStorage = _current_storage.get_ref() if _current_storage else null
	if storage == null:
		_display_label.text = "(Storage no longer valid)"
		return

	# Use get_debug_list() for InMemoryVariableStorage, fall back to get_all_variables()
	if storage is YarnInMemoryVariableStorage:
		var debug_text: String = storage.get_debug_list()
		if debug_text.is_empty():
			_display_label.text = "[i](No variables stored)[/i]"
		else:
			var bbcode := ""
			var lines := debug_text.split("\n")
			for i in range(lines.size()):
				var line: String = lines[i]
				if line.is_empty():
					continue
				# Format: "$name = value (type)" -> bold name
				var eq_pos: int = line.find(" = ")
				if eq_pos >= 0:
					var var_name: String = line.substr(0, eq_pos)
					var rest: String = line.substr(eq_pos)
					bbcode += "[b]%s[/b]%s\n" % [var_name, rest]
				else:
					bbcode += line + "\n"
			_display_label.text = bbcode.strip_edges()
	else:
		var variables := storage.get_all_variables()
		if variables.is_empty():
			_display_label.text = "[i](No variables stored)[/i]"
		else:
			var bbcode := ""
			for var_name in variables:
				var value: Variant = variables[var_name]
				var type_name := _get_type_name(value)
				bbcode += "[b]%s[/b] = %s (%s)\n" % [var_name, str(value), type_name]
			_display_label.text = bbcode.strip_edges()


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
