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
## Shows compilation status, errors, statistics, source scripts, nodes,
## variables, localisation tools, and variable storage generation.

const _YarnProgramParser := preload("res://addons/yarn_spinner/core/yarn_program_parser.gd")
const YarnInspectorHeader := preload("res://addons/yarn_spinner/editor/yarn_inspector_header.gd")
const YarnProjectUtility := preload("res://addons/yarn_spinner/editor/yarn_project_utility.gd")
const YarnProjectImporter := preload("res://addons/yarn_spinner/editor/yarn_project_importer.gd")

const ADD_LINE_TAGS_LABEL := "Add Line Tags to Yarn Scripts"
const EXPORT_STRINGS_LABEL := "Export Strings and Metadata as CSV..."
const UPDATE_STRINGS_LABEL := "Update Existing Strings Files"
const DEFAULT_SOURCE_PATTERN := "**/*.yarn"

var _pending: Dictionary = {}
var _tracked_path := ""
var _file_dialog: EditorFileDialog
var _prompt: ConfirmationDialog
var _ui: Dictionary = {}


func _init() -> void:
	var inspector := EditorInterface.get_inspector()
	if inspector != null:
		inspector.edited_object_changed.connect(_on_edited_object_changed)
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.resources_reimported.connect(_on_resources_reimported)


func _can_handle(object: Object) -> bool:
	return object is YarnProjectResource


func _parse_begin(object: Object) -> void:
	var project := object as YarnProjectResource
	var project_path := project.resource_path
	var editable := project_path.get_extension() == "yarnproject" and FileAccess.file_exists(project_path)

	var state: Dictionary = {}
	if editable:
		state = _pending.get(project_path, {})
		if state.is_empty():
			state = _load_state(project_path)
			_pending[project_path] = state

	_ui = {"project_path": project_path, "state": state}

	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	container.add_child(YarnInspectorHeader.create())

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

	var diagnostics: Array = []
	var diagnostics_variant: Variant = project.get("diagnostics")
	if diagnostics_variant is Array:
		diagnostics = diagnostics_variant

	_add_compilation_status(container, has_compiled_data, program, diagnostics)

	if not diagnostics.is_empty():
		_add_errors_section(container, diagnostics)

	if not has_compiled_data and diagnostics.is_empty():
		var help_label := RichTextLabel.new()
		help_label.bbcode_enabled = true
		help_label.fit_content = true
		help_label.scroll_active = false
		help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help_label.meta_clicked.connect(func(meta: Variant) -> void:
			OS.shell_open(str(meta))
		)
		help_label.text = (
			"[center]Yarn Projects are created by importing a [b].yarnproject[/b] file.\n"
			+ "Create one using the [url=https://marketplace.visualstudio.com/items?itemName=SecretLab.yarn-spinner]"
			+ "Yarn Spinner VS Code extension[/url], then import it into your project.\n\n"
			+ "[url=https://docs.yarnspinner.dev/using-yarnspinner-with-godot/overview]"
			+ "Learn more in the docs.[/url][/center]"
		)
		container.add_child(help_label)
		if not editable:
			_finish(container)
			return

	if has_compiled_data:
		_add_statistics(container, project, program)

	if editable:
		_add_source_scripts_section(container, project)
	else:
		_add_source_files(container, project)

	if program != null:
		_add_nodes_section(container, program)
		_add_variables_section(container, program)
		_add_smart_variables_section(container, program)

	if editable:
		_add_localisation_section(container, project, program)
		_add_variable_storage_section(container)
		_add_apply_revert_row(container)
		_update_dirty_state()
	elif program != null:
		_add_localisation_section(container, project, program)

	_finish(container)


func _finish(container: VBoxContainer) -> void:
	var bottom_separator := HSeparator.new()
	bottom_separator.add_theme_constant_override("separation", 8)
	container.add_child(bottom_separator)

	add_custom_control(container)


# =========================================================================
# Pending Changes
# =========================================================================

func _load_state(project_path: String) -> Dictionary:
	var data := YarnProjectUtility.read_project_json(project_path)
	var options := YarnProjectUtility.read_import_options(project_path)

	var patterns := PackedStringArray()
	for pattern in data.get("sourceFiles", [DEFAULT_SOURCE_PATTERN]):
		patterns.append(str(pattern))

	return {
		"source_patterns": patterns,
		"base_language": str(data.get("baseLanguage", "en")),
		"line_tagger": int(options.get("line_tagger", 0)),
		"generate_variables": bool(options.get("generate_variables_source", false)),
		"variables_class": str(options.get("variables_class_name", "YarnVariables")),
		"variables_parent": str(options.get("variables_class_parent", YarnProjectUtility.DEFAULT_VARIABLES_PARENT)),
		"dirty": false,
	}


func _mark_dirty() -> void:
	var state: Dictionary = _ui.get("state", {})
	state.dirty = true
	_update_dirty_state()


func _update_dirty_state() -> void:
	var state: Dictionary = _ui.get("state", {})
	var dirty: bool = state.get("dirty", false)

	var apply_button: Button = _ui.get("apply_button")
	var revert_button: Button = _ui.get("revert_button")
	if is_instance_valid(apply_button):
		apply_button.disabled = not dirty
	if is_instance_valid(revert_button):
		revert_button.disabled = not dirty

	var unsaved_message: Control = _ui.get("unsaved_message")
	if is_instance_valid(unsaved_message):
		unsaved_message.visible = dirty

	var tag_button: Button = _ui.get("tag_button")
	if is_instance_valid(tag_button):
		tag_button.disabled = dirty or not _ui.get("can_tag", false)

	var export_button: Button = _ui.get("export_button")
	if is_instance_valid(export_button):
		export_button.disabled = dirty or not _ui.get("can_export", false)

	var update_button: Button = _ui.get("update_button")
	if is_instance_valid(update_button):
		update_button.disabled = dirty or not _ui.get("can_update", false)


func _apply(project_path: String) -> void:
	var state: Dictionary = _pending.get(project_path, {})
	if state.is_empty() or not state.get("dirty", false):
		return

	var data := YarnProjectUtility.read_project_json(project_path)
	data["sourceFiles"] = Array(state.source_patterns)
	data["baseLanguage"] = state.base_language
	var err := YarnProjectUtility.write_project_json(project_path, data)
	if err != OK:
		push_error("yarn project: can't save %s: %s" % [project_path, error_string(err)])
		return

	err = YarnProjectUtility.write_import_options(project_path, {
		"line_tagger": state.line_tagger,
		"generate_variables_source": state.generate_variables,
		"variables_class_name": state.variables_class,
		"variables_class_parent": state.variables_parent,
	})
	if err != OK:
		push_error("yarn project: can't save import settings for %s: %s" % [project_path, error_string(err)])

	_pending.erase(project_path)
	EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray([project_path]))
	_refresh_inspector(project_path)


func _revert(project_path: String) -> void:
	_pending.erase(project_path)
	_refresh_inspector(project_path)


func _refresh_inspector(project_path: String) -> void:
	var edited := EditorInterface.get_inspector().get_edited_object()
	if edited is YarnProjectResource and (edited as Resource).resource_path == project_path:
		edited.notify_property_list_changed()


func _on_resources_reimported(resources: PackedStringArray) -> void:
	for path in resources:
		var state: Dictionary = _pending.get(path, {})
		if not state.is_empty() and not state.get("dirty", false):
			_pending.erase(path)
	var edited := EditorInterface.get_inspector().get_edited_object()
	if edited is YarnProjectResource and (edited as Resource).resource_path in resources:
		_refresh_inspector.call_deferred((edited as Resource).resource_path)


func _on_edited_object_changed() -> void:
	var edited := EditorInterface.get_inspector().get_edited_object()
	var new_path := ""
	if edited is YarnProjectResource:
		new_path = (edited as Resource).resource_path

	var previous := _tracked_path
	_tracked_path = new_path
	if previous.is_empty() or previous == new_path:
		return

	var state: Dictionary = _pending.get(previous, {})
	if state.get("dirty", false):
		_show_unapplied_changes_prompt(previous)
	else:
		_pending.erase(previous)


func _show_unapplied_changes_prompt(project_path: String) -> void:
	if is_instance_valid(_prompt):
		_prompt.queue_free()

	_prompt = ConfirmationDialog.new()
	_prompt.title = "Unapplied Changes"
	_prompt.dialog_text = "The Yarn Project %s has unapplied changes. Do you want to apply them or revert?" % project_path.get_file()
	_prompt.ok_button_text = "Apply"
	_prompt.cancel_button_text = "Revert"
	_prompt.confirmed.connect(_apply.bind(project_path))
	_prompt.canceled.connect(_revert.bind(project_path))
	EditorInterface.get_base_control().add_child(_prompt)
	_prompt.popup_centered()


# =========================================================================
# Section Builders
# =========================================================================

func _add_compilation_status(container: VBoxContainer, has_compiled_data: bool, program: YarnProgram, diagnostics: Array) -> void:
	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if not diagnostics.is_empty():
		status_label.text = "Compiled with %d error%s" % [diagnostics.size(), "" if diagnostics.size() == 1 else "s"]
		status_label.add_theme_color_override("font_color", _editor_color("error_color"))
	elif program != null:
		status_label.text = "Compiled successfully"
		status_label.add_theme_color_override("font_color", _editor_color("success_color"))
	elif not has_compiled_data:
		status_label.text = "Not compiled"
		status_label.add_theme_color_override("font_color", _editor_color("error_color"))
	else:
		status_label.text = "Parse error"
		status_label.add_theme_color_override("font_color", _editor_color("warning_color"))

	container.add_child(status_label)


func _add_errors_section(container: VBoxContainer, diagnostics: Array) -> void:
	_add_section_header(container, "Errors")

	var by_file := {}
	var order: Array[String] = []
	for diag: Dictionary in diagnostics:
		var file := str(diag.get("file", ""))
		if not by_file.has(file):
			by_file[file] = []
			order.append(file)
		(by_file[file] as Array).append(diag)

	for file in order:
		if not file.is_empty():
			var link := LinkButton.new()
			link.text = file.get_file()
			link.tooltip_text = file
			link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
			link.pressed.connect(_open_script.bind(file))
			container.add_child(link)

		for diag: Dictionary in by_file[file]:
			var line: int = int(diag.get("line", -1))
			var text := str(diag.get("message", ""))
			if line >= 0:
				text = "Line %d: %s" % [line, text]
			_add_message(container, text, "error", 12 if not file.is_empty() else 0)


func _add_statistics(container: VBoxContainer, project: YarnProjectResource, program: YarnProgram) -> void:
	_add_section_header(container, "Statistics")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var node_count := 0
	var st: Variant = project.get("string_table")
	var string_count: int = st.size() if st is Dictionary else 0
	var variable_count := 0

	if program != null:
		node_count = program.nodes.size()
		variable_count = program.initial_values.size()

	var sf: Variant = project.get("source_files")
	var source_count: int = sf.size() if sf is PackedStringArray else 0

	_add_stat(grid, "Nodes:", str(node_count))
	_add_stat(grid, "Strings:", str(string_count))
	_add_stat(grid, "Variables:", str(variable_count))
	_add_stat(grid, "Source Files:", str(source_count))

	container.add_child(grid)


func _add_source_files(container: VBoxContainer, project: YarnProjectResource) -> void:
	var sf: Variant = project.get("source_files")
	if not sf is PackedStringArray or (sf as PackedStringArray).is_empty():
		return

	_add_section_header(container, "Source Files")
	_add_source_file_links(container, sf)


func _add_source_file_links(container: VBoxContainer, files: PackedStringArray) -> void:
	for path in files:
		var local_path := ProjectSettings.localize_path(path)
		var link := LinkButton.new()
		link.text = "  " + local_path.get_file()
		link.tooltip_text = local_path
		link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		link.pressed.connect(_open_script.bind(local_path))
		container.add_child(link)


func _add_source_scripts_section(container: VBoxContainer, project: YarnProjectResource) -> void:
	_add_section_header(container, "Source Yarn Scripts")

	var patterns_container := VBoxContainer.new()
	patterns_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(patterns_container)
	_build_pattern_rows(patterns_container)

	var add_button := Button.new()
	add_button.text = "Add"
	add_button.icon = _editor_icon("Add")
	add_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_button.pressed.connect(func() -> void:
		var state: Dictionary = _ui.state
		var patterns: PackedStringArray = state.source_patterns
		patterns.append(DEFAULT_SOURCE_PATTERN)
		state.source_patterns = patterns
		_build_pattern_rows(patterns_container)
		_mark_dirty()
	)
	container.add_child(add_button)

	var sf: Variant = project.get("source_files")
	if sf is PackedStringArray and not (sf as PackedStringArray).is_empty():
		var included := Label.new()
		included.text = "Included Scripts (%d)" % (sf as PackedStringArray).size()
		included.add_theme_color_override("font_color", _editor_color("font_readonly_color"))
		container.add_child(included)
		_add_source_file_links(container, sf)


func _build_pattern_rows(patterns_container: VBoxContainer) -> void:
	for child in patterns_container.get_children():
		patterns_container.remove_child(child)
		child.queue_free()

	var state: Dictionary = _ui.state
	var base_dir := ProjectSettings.globalize_path(str(_ui.project_path).get_base_dir())
	var patterns: PackedStringArray = state.source_patterns

	for index in patterns.size():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var edit := LineEdit.new()
		edit.text = patterns[index]
		edit.placeholder_text = DEFAULT_SOURCE_PATTERN
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(edit)

		var count_label := Label.new()
		count_label.add_theme_color_override("font_color", _editor_color("font_readonly_color"))
		row.add_child(count_label)
		_update_match_count(count_label, base_dir, patterns[index])

		var remove_button := Button.new()
		remove_button.icon = _editor_icon("Remove")
		remove_button.flat = true
		remove_button.tooltip_text = "Remove this pattern"
		row.add_child(remove_button)

		edit.text_changed.connect(func(text: String) -> void:
			var current: PackedStringArray = state.source_patterns
			current[index] = text
			state.source_patterns = current
			_update_match_count(count_label, base_dir, text)
			_mark_dirty()
		)
		remove_button.pressed.connect(func() -> void:
			var current: PackedStringArray = state.source_patterns
			current.remove_at(index)
			state.source_patterns = current
			_build_pattern_rows.call_deferred(patterns_container)
			_mark_dirty()
		)

		patterns_container.add_child(row)


func _update_match_count(label: Label, base_dir: String, pattern: String) -> void:
	var count := YarnProjectImporter.resolve_glob(base_dir, pattern).size() if not pattern.strip_edges().is_empty() else 0
	label.text = "%d file%s" % [count, "" if count == 1 else "s"]


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


func _add_localisation_section(container: VBoxContainer, project: YarnProjectResource, program: YarnProgram) -> void:
	_add_section_header(container, "Localisation")

	var state: Dictionary = _ui.state
	var editable := not state.is_empty()

	if editable:
		var grid := _property_grid(container)
		var language_picker := OptionButton.new()
		language_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		language_picker.fit_to_longest_item = false
		_populate_languages(language_picker, state.base_language)
		language_picker.item_selected.connect(func(index: int) -> void:
			state.base_language = language_picker.get_item_metadata(index)
			_mark_dirty()
		)
		_add_property_row(grid, "Base Language", language_picker)

		var tagger_picker := OptionButton.new()
		tagger_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tagger_picker.add_item("Random")
		tagger_picker.add_item("Descriptive")
		tagger_picker.set_item_tooltip(0, "Tags lines with random hexadecimal IDs, like #line:0a1b2c3")
		tagger_picker.set_item_tooltip(1, "Tags lines with IDs made from the node, position and character, like #line:Start_0200_Bob")
		tagger_picker.select(clampi(state.line_tagger, 0, 1))
		tagger_picker.item_selected.connect(func(index: int) -> void:
			state.line_tagger = index
			_mark_dirty()
		)
		_add_property_row(grid, "Line Tagger", tagger_picker)

	var st_loc: Variant = project.get("string_table")
	var total_strings: int = st_loc.size() if st_loc is Dictionary else 0
	_add_info_label(container, "  Localisable strings: %d" % total_strings)

	var loaded_locales := TranslationServer.get_loaded_locales()
	if not loaded_locales.is_empty():
		_add_info_label(container, "  Loaded locales:")
		for locale in loaded_locales:
			var translated := _count_translated_strings(project, locale)
			var percent := 0.0
			if total_strings > 0:
				percent = float(translated) / float(total_strings) * 100.0
			_add_info_label(container, "    %s: %d/%d (%.0f%%)" % [locale, translated, total_strings, percent])

	var translation_files := PackedStringArray()
	if editable and program != null:
		translation_files = YarnProjectUtility.find_translation_csvs(project)
		if not translation_files.is_empty():
			_add_info_label(container, "  Strings files:")
			for csv_path in translation_files:
				var link := LinkButton.new()
				var locales := YarnProjectUtility.csv_locales(csv_path)
				link.text = "    %s (%s)" % [csv_path.get_file(), ", ".join(locales)]
				link.tooltip_text = csv_path
				link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
				link.pressed.connect(func() -> void:
					EditorInterface.select_file(csv_path)
				)
				container.add_child(link)

	var has_implicit := YarnProjectUtility.has_implicit_line_ids(project)
	var sources: Variant = project.get("source_files")
	var has_sources := sources is PackedStringArray and not (sources as PackedStringArray).is_empty()

	if has_implicit:
		_add_message(container, "Some lines don't have a line ID tag. Click '%s' so that translations stay attached to their lines." % ADD_LINE_TAGS_LABEL, "warning")

	if editable:
		_ui.unsaved_message = _add_message(container, "Unable to add line tags or export strings while the project has unapplied changes.", "info")

	var buttons := VBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	container.add_child(buttons)

	if editable:
		var tag_button := Button.new()
		tag_button.text = ADD_LINE_TAGS_LABEL
		if not YarnNativeCompiler.is_available():
			tag_button.tooltip_text = "Adding line tags needs the bundled Yarn Spinner compiler, which isn't available on this platform."
		tag_button.pressed.connect(_add_line_tags.bind(str(_ui.project_path)))
		buttons.add_child(tag_button)
		_ui.tag_button = tag_button
		_ui.can_tag = has_implicit and has_sources and YarnNativeCompiler.is_available()

	var export_button := Button.new()
	export_button.text = EXPORT_STRINGS_LABEL
	export_button.pressed.connect(_show_export_dialog.bind(project))
	buttons.add_child(export_button)
	_ui.export_button = export_button
	_ui.can_export = program != null
	export_button.disabled = program == null

	if editable:
		var update_button := Button.new()
		update_button.text = UPDATE_STRINGS_LABEL
		if translation_files.is_empty():
			update_button.tooltip_text = "No strings files contain this project's lines yet. Export them first, then add the file to Project Settings > Localization > Translations."
		elif has_implicit:
			update_button.tooltip_text = "Every line needs a line ID tag before strings files can be updated."
		update_button.pressed.connect(_update_strings_files.bind(str(_ui.project_path)))
		buttons.add_child(update_button)
		_ui.update_button = update_button
		_ui.can_update = program != null and not translation_files.is_empty() and not has_implicit

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


func _add_variable_storage_section(container: VBoxContainer) -> void:
	_add_section_header(container, "Variable Storage")

	var state: Dictionary = _ui.state
	var grid := _property_grid(container)

	var generate_check := CheckBox.new()
	generate_check.text = "On"
	generate_check.button_pressed = state.generate_variables
	_add_property_row(grid, "Generate Variables Source File", generate_check)

	var class_edit := LineEdit.new()
	class_edit.text = state.variables_class
	class_edit.placeholder_text = "YarnVariables"
	class_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var class_row := _add_property_row(grid, "Variables Class Name", class_edit)

	var parent_picker := OptionButton.new()
	parent_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_picker.fit_to_longest_item = false
	var classes := YarnProjectUtility.variable_storage_classes()
	if not state.variables_parent in classes:
		classes.insert(0, state.variables_parent)
	for storage_class in classes:
		parent_picker.add_item(storage_class)
		if storage_class == state.variables_parent:
			parent_picker.select(parent_picker.item_count - 1)
	var parent_row := _add_property_row(grid, "Variables Parent Class", parent_picker)

	var output_label := Label.new()
	output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_label.add_theme_color_override("font_color", _editor_color("font_readonly_color"))
	container.add_child(output_label)

	var update_visibility := func() -> void:
		var enabled: bool = state.generate_variables
		for control: Control in class_row + parent_row:
			control.visible = enabled
		output_label.visible = enabled
		var class_text := str(state.variables_class).strip_edges()
		if class_text.is_valid_ascii_identifier():
			output_label.text = "  Writes %s" % YarnProjectUtility.variables_source_path(str(_ui.project_path), class_text)
		else:
			output_label.text = "  '%s' isn't a valid class name." % class_text

	generate_check.toggled.connect(func(pressed: bool) -> void:
		state.generate_variables = pressed
		update_visibility.call()
		_mark_dirty()
	)
	class_edit.text_changed.connect(func(text: String) -> void:
		state.variables_class = text
		update_visibility.call()
		_mark_dirty()
	)
	parent_picker.item_selected.connect(func(index: int) -> void:
		state.variables_parent = parent_picker.get_item_text(index)
		_mark_dirty()
	)
	update_visibility.call()


func _add_apply_revert_row(container: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	container.add_child(sep)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	container.add_child(row)

	var project_path: String = _ui.project_path

	var revert_button := Button.new()
	revert_button.text = "Revert"
	revert_button.pressed.connect(_revert.bind(project_path))
	row.add_child(revert_button)
	_ui.revert_button = revert_button

	var apply_button := Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(_apply.bind(project_path))
	row.add_child(apply_button)
	_ui.apply_button = apply_button


# =========================================================================
# Actions
# =========================================================================

func _add_line_tags(project_path: String) -> void:
	var tagger: String = YarnProjectUtility.TAGGERS[clampi(int(YarnProjectUtility.read_import_options(project_path).get("line_tagger", 0)), 0, 1)]
	var summary := YarnProjectUtility.add_line_tags(project_path, tagger)

	for error: String in summary.errors:
		push_error("yarn project: %s" % error)

	var modified: PackedStringArray = summary.modified
	if modified.is_empty():
		print("yarn project: no files needed updating.")
		return

	print("yarn project: updated the following files: %s" % ", ".join(modified))
	var fs := EditorInterface.get_resource_filesystem()
	fs.reimport_files(modified)
	fs.reimport_files(PackedStringArray([project_path]))


func _update_strings_files(project_path: String) -> void:
	var state: Dictionary = _pending.get(project_path, {})
	var base_language: String = state.get("base_language", str(YarnProjectUtility.read_project_json(project_path).get("baseLanguage", "en")))
	var summary := YarnProjectUtility.update_translation_csvs(project_path, base_language)

	for error: String in summary.errors:
		push_error("yarn project: %s" % error)

	var modified: PackedStringArray = summary.modified
	if modified.is_empty():
		print("yarn project: no files needed updating.")
		return

	print("yarn project: updated the following files: %s" % ", ".join(modified))
	EditorInterface.get_resource_filesystem().reimport_files(modified)


func _show_export_dialog(project: YarnProjectResource) -> void:
	if is_instance_valid(_file_dialog):
		_file_dialog.queue_free()

	var project_path := project.resource_path
	var base_language := "en"
	if project_path.get_extension() == "yarnproject":
		base_language = str(YarnProjectUtility.read_project_json(project_path).get("baseLanguage", "en"))

	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.add_filter("*.csv", "CSV Files")
	_file_dialog.title = "Export Strings CSV"
	if not project_path.is_empty():
		_file_dialog.current_dir = project_path.get_base_dir()
		_file_dialog.current_file = project_path.get_file().get_basename() + ".csv"

	_file_dialog.file_selected.connect(func(path: String) -> void:
		var err := YarnProjectUtility.write_strings_csv(project, path, base_language)
		if err != OK:
			push_error("yarn project: failed to export strings to '%s': %s" % [path, error_string(err)])
			return
		var metadata_path := path.get_base_dir().path_join(path.get_file().get_basename() + "-metadata.csv")
		err = YarnProjectUtility.write_metadata_csv(project, metadata_path)
		if err != OK:
			push_error("yarn project: failed to export metadata to '%s': %s" % [metadata_path, error_string(err)])
		print("yarn project: exported strings to '%s' and metadata to '%s'" % [path, metadata_path])
		EditorInterface.get_resource_filesystem().scan()
	)

	EditorInterface.get_base_control().add_child(_file_dialog)
	_file_dialog.popup_file_dialog()


func _open_script(path: String) -> void:
	if ResourceLoader.exists(path):
		EditorInterface.edit_resource(load(path))
	else:
		EditorInterface.select_file(path)


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


func _add_message(container: VBoxContainer, text: String, kind: String, indent: int = 0) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if indent > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(indent, 0)
		row.add_child(spacer)

	var icon_name := "NodeInfo"
	var color := _editor_color("font_color")
	match kind:
		"error":
			icon_name = "StatusError"
			color = _editor_color("error_color")
		"warning":
			icon_name = "StatusWarning"
			color = _editor_color("warning_color")

	var icon := TextureRect.new()
	icon.texture = _editor_icon(icon_name)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(80, 0)
	label.add_theme_color_override("font_color", color)
	row.add_child(label)

	container.add_child(row)
	return row


func _add_stat(grid: GridContainer, label_text: String, value_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(label)

	var value := Label.new()
	value.text = value_text
	grid.add_child(value)


func _property_grid(container: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(grid)
	return grid


func _add_property_row(grid: GridContainer, label_text: String, control: Control) -> Array[Control]:
	var label := Label.new()
	label.text = label_text
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(60, 0)
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return [label, control]


func _populate_languages(picker: OptionButton, selected: String) -> void:
	var standard_selected := TranslationServer.standardize_locale(selected)
	var codes := Array(TranslationServer.get_all_languages())
	codes.sort_custom(func(a: String, b: String) -> bool:
		return TranslationServer.get_language_name(a) < TranslationServer.get_language_name(b)
	)

	var found := false
	for code: String in codes:
		if TranslationServer.standardize_locale(code) == standard_selected:
			found = true
			break
	if not found:
		picker.add_item(selected)
		picker.set_item_metadata(0, selected)
		picker.select(0)

	for code: String in codes:
		picker.add_item("%s (%s)" % [TranslationServer.get_language_name(code), code])
		picker.set_item_metadata(picker.item_count - 1, code)
		if found and TranslationServer.standardize_locale(code) == standard_selected:
			picker.select(picker.item_count - 1)
			picker.set_item_metadata(picker.item_count - 1, selected)


func _editor_color(color_name: String) -> Color:
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_color(color_name, "Editor"):
		return theme.get_color(color_name, "Editor")
	return Color.WHITE


func _editor_icon(icon_name: String) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	if theme != null and theme.has_icon(icon_name, "EditorIcons"):
		return theme.get_icon(icon_name, "EditorIcons")
	return null


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
	var st_val: Variant = project.get("string_table")
	if not st_val is Dictionary:
		return 0
	for line_id: String in st_val:
		var key: String = prefix + line_id
		var translated: String = TranslationServer.translate(key)
		if translated != key:
			count += 1
	return count
