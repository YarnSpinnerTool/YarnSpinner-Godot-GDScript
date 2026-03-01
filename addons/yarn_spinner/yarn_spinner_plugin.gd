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
extends EditorPlugin
## editor plugin for yarn spinner integration with godot.
## handles import of .yarnproject files and provides editor tooling.

const YarnProjectImporter := preload("res://addons/yarn_spinner/editor/yarn_project_importer.gd")
const YarnFileImporter := preload("res://addons/yarn_spinner/editor/yarn_file_importer.gd")
const YarnEditorScript := preload("res://addons/yarn_spinner/editor/yarn_editor.gd")
const YarnInspectorPlugin := preload("res://addons/yarn_spinner/editor/yarn_inspector_plugin.gd")
const YarnCommandsPanelScript := preload("res://addons/yarn_spinner/editor/yarn_commands_panel.gd")
const YarnVariableInspectorPlugin := preload("res://addons/yarn_spinner/editor/yarn_variable_inspector_plugin.gd")
const YarnProjectInspectorPlugin := preload("res://addons/yarn_spinner/editor/yarn_project_inspector_plugin.gd")

const SETTING_YSC_PATH := "yarn_spinner/compiler/ysc_path"
const SETTING_AUTO_YSLS := "yarn_spinner/ysls/auto_regenerate"

var _yarn_project_importer: EditorImportPlugin
var _yarn_file_importer: EditorImportPlugin
var _yarn_editor: Control
var _inspector_plugin: EditorInspectorPlugin
var _commands_panel: Control
var _variable_inspector_plugin: EditorInspectorPlugin
var _project_inspector_plugin: EditorInspectorPlugin
var _ysls_regenerate_timer: Timer
var _ysls_needs_regenerate: bool = false
var _reimport_timer: Timer
var _reimport_needed: bool = false


func _enter_tree() -> void:
	_register_project_settings()

	_yarn_project_importer = YarnProjectImporter.new()
	_yarn_file_importer = YarnFileImporter.new()
	add_import_plugin(_yarn_project_importer)
	add_import_plugin(_yarn_file_importer)

	# load() not preload() because SVGs may not be imported yet on first load
	var project_icon: Texture2D = null
	if ResourceLoader.exists("res://addons/yarn_spinner/icons/yarn_project.svg"):
		project_icon = load("res://addons/yarn_spinner/icons/yarn_project.svg")
	add_custom_type("YarnProject", "Resource", preload("res://addons/yarn_spinner/yarn_project_resource.gd"), project_icon)

	add_autoload_singleton("YarnSpinner", "res://addons/yarn_spinner/yarn_spinner.gd")

	_inspector_plugin = YarnInspectorPlugin.new()
	add_inspector_plugin(_inspector_plugin)

	_variable_inspector_plugin = YarnVariableInspectorPlugin.new()
	add_inspector_plugin(_variable_inspector_plugin)

	_project_inspector_plugin = YarnProjectInspectorPlugin.new()
	add_inspector_plugin(_project_inspector_plugin)

	_yarn_editor = YarnEditorScript.new()
	add_control_to_bottom_panel(_yarn_editor, "Yarn")

	_commands_panel = YarnCommandsPanelScript.new()
	add_control_to_bottom_panel(_commands_panel, "Yarn Commands")

	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.filesystem_changed.connect(_on_filesystem_changed)
		fs.resources_reimported.connect(_on_resources_reimported)

	_ysls_regenerate_timer = Timer.new()
	_ysls_regenerate_timer.one_shot = true
	_ysls_regenerate_timer.wait_time = 1.0
	_ysls_regenerate_timer.timeout.connect(_do_ysls_regenerate)
	add_child(_ysls_regenerate_timer)

	_reimport_timer = Timer.new()
	_reimport_timer.one_shot = true
	_reimport_timer.wait_time = 0.5
	_reimport_timer.timeout.connect(_do_yarnproject_reimport)
	add_child(_reimport_timer)


func _register_project_settings() -> void:
	if not ProjectSettings.has_setting(SETTING_YSC_PATH):
		ProjectSettings.set_setting(SETTING_YSC_PATH, "")
	ProjectSettings.set_initial_value(SETTING_YSC_PATH, "")
	ProjectSettings.add_property_info({
		"name": SETTING_YSC_PATH,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_GLOBAL_FILE,
		"hint_string": "",
	})

	if not ProjectSettings.has_setting(SETTING_AUTO_YSLS):
		ProjectSettings.set_setting(SETTING_AUTO_YSLS, true)
	ProjectSettings.set_initial_value(SETTING_AUTO_YSLS, true)
	ProjectSettings.add_property_info({
		"name": SETTING_AUTO_YSLS,
		"type": TYPE_BOOL,
	})


func _exit_tree() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		if fs.filesystem_changed.is_connected(_on_filesystem_changed):
			fs.filesystem_changed.disconnect(_on_filesystem_changed)
		if fs.resources_reimported.is_connected(_on_resources_reimported):
			fs.resources_reimported.disconnect(_on_resources_reimported)

	if _reimport_timer:
		_reimport_timer.queue_free()
		_reimport_timer = null
	if _ysls_regenerate_timer:
		_ysls_regenerate_timer.queue_free()
		_ysls_regenerate_timer = null

	if _project_inspector_plugin:
		remove_inspector_plugin(_project_inspector_plugin)
		_project_inspector_plugin = null

	if _variable_inspector_plugin:
		remove_inspector_plugin(_variable_inspector_plugin)
		_variable_inspector_plugin = null

	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null

	if _commands_panel:
		remove_control_from_bottom_panel(_commands_panel)
		_commands_panel.queue_free()
		_commands_panel = null

	if _yarn_editor:
		remove_control_from_bottom_panel(_yarn_editor)
		_yarn_editor.queue_free()
		_yarn_editor = null

	remove_import_plugin(_yarn_project_importer)
	remove_import_plugin(_yarn_file_importer)
	_yarn_project_importer = null
	_yarn_file_importer = null

	remove_custom_type("YarnProject")

	remove_autoload_singleton("YarnSpinner")


func _handles(object: Object) -> bool:
	return object is YarnScriptResource


func _edit(object: Object) -> void:
	if object is YarnScriptResource:
		var yarn_script := object as YarnScriptResource
		if _yarn_editor and not yarn_script.source_path.is_empty():
			_yarn_editor.edit_file(yarn_script.source_path)
			make_bottom_panel_item_visible(_yarn_editor)


func _on_filesystem_changed() -> void:
	_schedule_ysls_regenerate()


func _on_resources_reimported(resources: PackedStringArray) -> void:
	var has_yarn_file := false
	var needs_ysls := false
	for path in resources:
		if path.ends_with(".yarn"):
			has_yarn_file = true
			needs_ysls = true
		elif path.ends_with(".gd") or path.ends_with(".yarnproject"):
			needs_ysls = true
	if needs_ysls:
		_schedule_ysls_regenerate()
	if has_yarn_file:
		_schedule_yarnproject_reimport()


func _schedule_ysls_regenerate() -> void:
	if not ProjectSettings.get_setting(SETTING_AUTO_YSLS, true):
		return

	_ysls_needs_regenerate = true
	if _ysls_regenerate_timer and not _ysls_regenerate_timer.is_stopped():
		return  # already scheduled
	if _ysls_regenerate_timer:
		_ysls_regenerate_timer.start()


func _schedule_yarnproject_reimport() -> void:
	_reimport_needed = true
	if _reimport_timer and not _reimport_timer.is_stopped():
		return  # already scheduled
	if _reimport_timer:
		_reimport_timer.start()


func _do_yarnproject_reimport() -> void:
	if not _reimport_needed:
		return
	_reimport_needed = false

	var yarn_projects := _find_yarn_projects("res://")
	if yarn_projects.is_empty():
		return

	EditorInterface.get_resource_filesystem().reimport_files(yarn_projects)


func _do_ysls_regenerate() -> void:
	if not _ysls_needs_regenerate:
		return
	_ysls_needs_regenerate = false

	var yarn_projects := _find_yarn_projects("res://")
	if yarn_projects.is_empty():
		return

	var generator := YarnYSLSGenerator.new()
	generator.scan_directory("res://")

	for project_path in yarn_projects:
		var ysls_path := project_path.get_basename() + ".ysls.json"
		generator.save_ysls(ysls_path)


func _find_yarn_projects(path: String) -> PackedStringArray:
	var results := PackedStringArray()
	var dir := DirAccess.open(path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				results.append_array(_find_yarn_projects(full_path))
		elif file_name.ends_with(".yarnproject"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

	return results
