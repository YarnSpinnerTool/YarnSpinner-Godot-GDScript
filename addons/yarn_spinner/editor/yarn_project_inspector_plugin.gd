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
## Rich dashboard inspector for YarnProjectResource files.
## Shows compilation status, statistics, nodes, variables, strings,
## source files, and localization tools.

const _YarnProgramParser := preload("res://addons/yarn_spinner/core/yarn_program_parser.gd")

var _current_project: WeakRef
var _file_dialog: FileDialog


func _can_handle(object: Object) -> bool:
	return object is YarnProjectResource


func _parse_begin(object: Object) -> void:
	var project := object as YarnProjectResource
	_current_project = weakref(project)

	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 1. Header
	_add_section_header(container, "Yarn Project")

	# Parse program directly (YarnProjectResource is not @tool, so we
	# cannot call its methods on the placeholder instance)
	var program: YarnProgram = null
	var compiled_variant: Variant = project.get("compiled_program")
	var has_compiled_data := compiled_variant is PackedByteArray and not (compiled_variant as PackedByteArray).is_empty()
	if has_compiled_data:
		var compiled: PackedByteArray = compiled_variant
		program = _YarnProgramParser.parse_from_bytes(compiled)
		if program != null:
			var st: Variant = project.get("string_table")
			var lm: Variant = project.get("line_metadata")
			if st is Dictionary:
				program.string_table = (st as Dictionary).duplicate()
			if lm is Dictionary:
				program.line_metadata = (lm as Dictionary).duplicate()

	# 2. Compilation Status
	_add_compilation_status(container, has_compiled_data, program)

	# 3. Statistics Grid
	_add_statistics(container, project, program)

	# 4. Source Files
	_add_source_files(container, project)

	if program != null:
		# 5. Nodes
		_add_nodes_section(container, program)

		# 6. Declared Variables
		_add_variables_section(container, program)

		# 7. Smart Variables
		_add_smart_variables_section(container, program)

		# 8. Localization (Feature 5)
		_add_localization_section(container, project, program)

	var bottom_separator := HSeparator.new()
	bottom_separator.add_theme_constant_override("separation", 8)
	container.add_child(bottom_separator)

	add_custom_control(container)


# =========================================================================
# Section Builders
# =========================================================================

func _add_compilation_status(container: VBoxContainer, has_compiled_data: bool, program: YarnProgram) -> void:
	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if program != null:
		status_label.text = "Compiled successfully"
		status_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	elif not has_compiled_data:
		status_label.text = "Not compiled"
		status_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
	else:
		status_label.text = "Parse error"
		status_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))

	container.add_child(status_label)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	container.add_child(sep)


func _add_statistics(container: VBoxContainer, project: YarnProjectResource, program: YarnProgram) -> void:
	_add_section_header(container, "Statistics")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var node_count := 0
	var string_count := project.string_table.size()
	var variable_count := 0

	if program != null:
		node_count = program.nodes.size()
		variable_count = program.initial_values.size()

	_add_stat(grid, "Nodes:", str(node_count))
	_add_stat(grid, "Strings:", str(string_count))
	_add_stat(grid, "Variables:", str(variable_count))
	_add_stat(grid, "Source Files:", str(project.source_files.size()))

	container.add_child(grid)


func _add_source_files(container: VBoxContainer, project: YarnProjectResource) -> void:
	if project.source_files.is_empty():
		return

	_add_section_header(container, "Source Files")

	for path in project.source_files:
		var label := Label.new()
		label.text = "  " + path.get_file()
		label.tooltip_text = path
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		container.add_child(label)


func _add_nodes_section(container: VBoxContainer, program: YarnProgram) -> void:
	var all_names := program.get_node_names()
	var visible_names: PackedStringArray = []
	var internal_count := 0

	for node_name in all_names:
		if node_name.begins_with("$"):
			internal_count += 1
		else:
			visible_names.append(node_name)

	_add_section_header(container, "Nodes (%d)" % visible_names.size())

	for node_name in visible_names:
		var node: YarnNode = program.get_node(node_name)
		var text := "  " + node_name
		var tags := node.get_tags() if node != null else PackedStringArray()
		if not tags.is_empty():
			text += "  [%s]" % ", ".join(tags)

		var label := Label.new()
		label.text = text
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		container.add_child(label)

	if internal_count > 0:
		_add_info_label(container, "  (%d internal nodes hidden)" % internal_count)


func _add_variables_section(container: VBoxContainer, program: YarnProgram) -> void:
	if program.initial_values.is_empty():
		return

	_add_section_header(container, "Declared Variables (%d)" % program.initial_values.size())

	for var_name in program.initial_values:
		var value: Variant = program.initial_values[var_name]
		var type_name := _type_name_for(value)
		var label := Label.new()
		label.text = "  %s: %s = %s" % [var_name, type_name, str(value)]
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		container.add_child(label)


func _add_smart_variables_section(container: VBoxContainer, program: YarnProgram) -> void:
	var smart_nodes := program.get_smart_variable_nodes()
	if smart_nodes.is_empty():
		return

	_add_section_header(container, "Smart Variables (%d)" % smart_nodes.size())

	for node in smart_nodes:
		var label := Label.new()
		label.text = "  %s (computed)" % node.node_name
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		container.add_child(label)


func _add_localization_section(container: VBoxContainer, project: YarnProjectResource, program: YarnProgram) -> void:
	_add_section_header(container, "Localization")

	# Total strings count
	var total_strings := project.string_table.size()
	_add_info_label(container, "  Localizable strings: %d" % total_strings)

	# Per-locale coverage
	var loaded_locales := TranslationServer.get_loaded_locales()
	if not loaded_locales.is_empty():
		_add_info_label(container, "  Loaded locales:")
		for locale in loaded_locales:
			var translated := _count_translated_strings(project, locale)
			var percent := 0.0
			if total_strings > 0:
				percent = float(translated) / float(total_strings) * 100.0
			_add_info_label(container, "    %s: %d/%d (%.0f%%)" % [locale, translated, total_strings, percent])

	# Export button
	var export_button := Button.new()
	export_button.text = "Export Strings to CSV..."
	export_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	export_button.pressed.connect(_show_export_dialog.bind(program))
	container.add_child(export_button)

	# Locale test row
	var locale_row := HBoxContainer.new()
	locale_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var locale_label := Label.new()
	locale_label.text = "  Test locale:"
	locale_row.add_child(locale_label)

	var locale_edit := LineEdit.new()
	locale_edit.text = TranslationServer.get_locale()
	locale_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	locale_edit.custom_minimum_size = Vector2(80, 0)
	locale_row.add_child(locale_edit)

	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(func() -> void:
		TranslationServer.set_locale(locale_edit.text)
	)
	locale_row.add_child(apply_button)

	container.add_child(locale_row)


# =========================================================================
# Helpers
# =========================================================================

func _add_section_header(container: VBoxContainer, title: String) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	container.add_child(sep)

	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	container.add_child(label)


func _add_info_label(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	container.add_child(label)


func _add_stat(grid: GridContainer, label_text: String, value_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(label)

	var value := Label.new()
	value.text = value_text
	grid.add_child(value)


func _type_name_for(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "Bool"
		TYPE_INT:
			return "Number"
		TYPE_FLOAT:
			return "Number"
		TYPE_STRING:
			return "String"
		_:
			return type_string(typeof(value))


func _count_translated_strings(project: YarnProjectResource, locale: String) -> int:
	var count := 0
	var prefix := "YARN_"
	for line_id: String in project.string_table:
		var key: String = prefix + line_id
		var translated: String = TranslationServer.translate(key)
		if translated != key:
			count += 1
	return count


func _show_export_dialog(program: YarnProgram) -> void:
	if _file_dialog != null and is_instance_valid(_file_dialog):
		_file_dialog.queue_free()

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.filters = PackedStringArray(["*.csv ; CSV Files"])
	_file_dialog.title = "Export Strings to CSV"
	_file_dialog.size = Vector2i(600, 400)

	_file_dialog.file_selected.connect(func(path: String) -> void:
		var err := YarnGodotLocalisation.export_strings_for_translation(program, path)
		if err == OK:
			print("Yarn: exported strings to '%s'" % path)
			EditorInterface.get_resource_filesystem().scan()
		else:
			push_error("Yarn: failed to export strings to '%s': %s" % [path, error_string(err)])
	)

	EditorInterface.get_base_control().add_child(_file_dialog)
	_file_dialog.popup_centered()
