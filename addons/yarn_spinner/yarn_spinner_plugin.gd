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
const YarnMainScreen := preload("res://addons/yarn_spinner/editor/yarn_main_screen.gd")
const YarnInspectorPlugin := preload("res://addons/yarn_spinner/editor/yarn_inspector_plugin.gd")
const YarnVariableInspectorPlugin := preload("res://addons/yarn_spinner/editor/yarn_variable_inspector_plugin.gd")
const YarnProjectInspectorPlugin := preload("res://addons/yarn_spinner/editor/yarn_project_inspector_plugin.gd")

const MAIN_SCREEN_NAME := "Yarn Spinner"
const PLUGIN_ICON_PATH := "res://addons/yarn_spinner/icons/yarn_script.svg"

const SETTING_YSC_PATH := "yarn_spinner/compiler/ysc_path"
const SETTING_AUTO_YSLS := "yarn_spinner/ysls/auto_regenerate"

var _yarn_project_importer: EditorImportPlugin
var _yarn_file_importer: EditorImportPlugin
var _main_screen: Control
var _inspector_plugin: EditorInspectorPlugin
var _variable_inspector_plugin: EditorInspectorPlugin
var _project_inspector_plugin: EditorInspectorPlugin
var _ysls_regenerate_timer: Timer
var _ysls_needs_regenerate: bool = false
var _reimport_timer: Timer
var _pending_reimport_projects: Dictionary = {}
var _startup_check_done: bool = false


func _enter_tree() -> void:
	_register_project_settings()

	add_tool_menu_item("Create Yarn Project...", _create_yarn_project)

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

	_main_screen = YarnMainScreen.new()
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	_make_visible(false)

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

	if _main_screen:
		_main_screen.queue_free()
		_main_screen = null

	remove_import_plugin(_yarn_project_importer)
	remove_import_plugin(_yarn_file_importer)
	_yarn_project_importer = null
	_yarn_file_importer = null

	remove_custom_type("YarnProject")
	remove_tool_menu_item("Create Yarn Project...")

	remove_autoload_singleton("YarnSpinner")


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return MAIN_SCREEN_NAME


func _get_plugin_icon() -> Texture2D:
	# Godot does not rescale main-screen icons, so the source (256x256) must be
	# downsized to the editor's standard tab icon size (16px, DPI-scaled).
	if not ResourceLoader.exists(PLUGIN_ICON_PATH):
		return null
	var source: Texture2D = load(PLUGIN_ICON_PATH)
	var image := source.get_image()
	if image == null:
		return source
	if image.is_compressed():
		image.decompress()
	var icon_size := int(round(16.0 * EditorInterface.get_editor_scale()))
	image.resize(icon_size, icon_size, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _make_visible(next_visible: bool) -> void:
	if _main_screen:
		_main_screen.visible = next_visible
		if next_visible:
			_main_screen.notify_shown()


func _handles(object: Object) -> bool:
	return object is YarnScriptResource


func _edit(object: Object) -> void:
	if object is YarnScriptResource:
		var yarn_script := object as YarnScriptResource
		if _main_screen and not yarn_script.source_path.is_empty():
			_main_screen.edit_file(yarn_script.source_path)
			EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)


func _on_filesystem_changed() -> void:
	_schedule_ysls_regenerate()
	if not _startup_check_done:
		_startup_check_done = true
		_check_stale_yarnprojects_at_startup.call_deferred()
		_reimport_files_with_stale_type.call_deferred()


func _on_resources_reimported(resources: PackedStringArray) -> void:
	var changed_yarns := PackedStringArray()
	var needs_ysls := false
	for path in resources:
		if path.ends_with(".yarn"):
			changed_yarns.append(path)
			needs_ysls = true
		elif path.ends_with(".gd") or path.ends_with(".yarnproject"):
			needs_ysls = true
	if needs_ysls:
		_schedule_ysls_regenerate()
	if not changed_yarns.is_empty():
		_schedule_yarnproject_reimport_for(changed_yarns)


func _schedule_ysls_regenerate() -> void:
	if not ProjectSettings.get_setting(SETTING_AUTO_YSLS, true):
		return

	_ysls_needs_regenerate = true
	if _ysls_regenerate_timer and not _ysls_regenerate_timer.is_stopped():
		return  # already scheduled
	if _ysls_regenerate_timer:
		_ysls_regenerate_timer.start()


## Queue every yarnproject whose globs match any of `changed_yarns` (res:// paths).
func _schedule_yarnproject_reimport_for(changed_yarns: PackedStringArray) -> void:
	var changed_abs := {}
	for c in changed_yarns:
		changed_abs[ProjectSettings.globalize_path(c)] = true

	var all_projects := _find_yarn_projects("res://")
	for project_path in all_projects:
		if _project_matches_any(project_path, changed_abs):
			_pending_reimport_projects[project_path] = true

	if _pending_reimport_projects.is_empty():
		return
	if _reimport_timer and not _reimport_timer.is_stopped():
		return  # already scheduled
	if _reimport_timer:
		_reimport_timer.start()


func _do_yarnproject_reimport() -> void:
	if _pending_reimport_projects.is_empty():
		return
	var to_reimport := PackedStringArray(_pending_reimport_projects.keys())
	_pending_reimport_projects.clear()
	EditorInterface.get_resource_filesystem().reimport_files(to_reimport)


## One-shot migration: when the addon is updated, existing .import sidecars
## still report type="Resource" from older versions. Reimport any .yarn /
## .yarnproject whose sidecar type no longer matches what the importers now
## declare, so the FileSystem dock picks up the registered custom icons.
func _reimport_files_with_stale_type() -> void:
	var stale := PackedStringArray()
	_collect_files_with_stale_type("res://", ".yarn", "Resource", stale)
	_collect_files_with_stale_type("res://", ".yarnproject", "Resource", stale)
	if stale.is_empty():
		return
	print("yarn spinner: refreshing import type for %d file(s) so FileSystem icons appear" % stale.size())
	EditorInterface.get_resource_filesystem().reimport_files(stale)


func _collect_files_with_stale_type(dir_path: String, ext: String, expected_type: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != "addons":
				_collect_files_with_stale_type(full_path, ext, expected_type, out)
		elif file_name.ends_with(ext):
			if not _import_type_matches(full_path, expected_type):
				out.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


## Returns true if the file's .import sidecar already declares the expected
## type (or is missing/unreadable — in which case Godot will create one on its
## own and we don't need to force a reimport).
func _import_type_matches(file_path: String, expected: String) -> bool:
	var f := FileAccess.open(file_path + ".import", FileAccess.READ)
	if f == null:
		return true
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("type="):
			var raw := line.substr(5).strip_edges()
			if raw.begins_with("\"") and raw.ends_with("\""):
				raw = raw.substr(1, raw.length() - 2)
			f.close()
			return raw == expected
	f.close()
	return true


## Scan every .yarnproject and reimport any whose compiled output is missing or stale.
func _check_stale_yarnprojects_at_startup() -> void:
	var projects := _find_yarn_projects("res://")
	var stale := PackedStringArray()
	for p in projects:
		if _is_yarnproject_stale(p):
			stale.append(p)
	if stale.is_empty():
		return
	print("yarn spinner: recompiling %d stale yarnproject(s): %s" % [stale.size(), ", ".join(stale)])
	EditorInterface.get_resource_filesystem().reimport_files(stale)


func _is_yarnproject_stale(yarnproject_path: String) -> bool:
	var imported := _get_imported_dest_path(yarnproject_path)
	if imported.is_empty():
		return true  # .import is missing, marked invalid, or has no dest path
	var imported_abs := ProjectSettings.globalize_path(imported)
	if not FileAccess.file_exists(imported_abs):
		return true

	if ResourceLoader.exists(yarnproject_path, "Resource"):
		var res := ResourceLoader.load(yarnproject_path)
		if res is YarnProjectResource and (res as YarnProjectResource).compiled_program.is_empty():
			return true

	var imported_mtime := FileAccess.get_modified_time(imported_abs)
	var abs_yp := ProjectSettings.globalize_path(yarnproject_path)
	var sources := YarnProjectImporter.parse_project_sources(abs_yp, abs_yp.get_base_dir())
	for s in sources:
		if FileAccess.get_modified_time(s) > imported_mtime:
			return true
	return false


## Reads the .import sidecar; returns the dest_files path, or "" if invalid/missing.
func _get_imported_dest_path(yarnproject_path: String) -> String:
	var f := FileAccess.open(yarnproject_path + ".import", FileAccess.READ)
	if f == null:
		return ""
	var path := ""
	var valid := true
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "valid=false":
			valid = false
		elif line.begins_with("path="):
			var raw := line.substr(5)
			if raw.begins_with('"') and raw.ends_with('"'):
				raw = raw.substr(1, raw.length() - 2)
			path = raw
	f.close()
	return "" if not valid else path


func _project_matches_any(project_path: String, changed_abs_set: Dictionary) -> bool:
	var abs_proj := ProjectSettings.globalize_path(project_path)
	var sources := YarnProjectImporter.parse_project_sources(abs_proj, abs_proj.get_base_dir())
	for s in sources:
		if changed_abs_set.has(s):
			return true
	return false


func _do_ysls_regenerate() -> void:
	if not _ysls_needs_regenerate:
		return
	_ysls_needs_regenerate = false

	var yarn_projects := _find_yarn_projects("res://")
	if yarn_projects.is_empty():
		return

	# Generate per-project YSLS — each scoped to its own directory tree
	for project_path in yarn_projects:
		YarnYSLSGenerator.generate_for_project(project_path)


func _create_yarn_project() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = PackedStringArray(["*.yarnproject ; Yarn Project Files"])
	dialog.current_file = "Project.yarnproject"
	dialog.title = "Create Yarn Project"

	dialog.file_selected.connect(func(path: String) -> void:
		var project := {
			"projectFileVersion": 4,
			"sourceFiles": ["**/*.yarn"],
			"baseLanguage": "en",
		}
		var json := JSON.stringify(project, "    ")
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(json)
			file.close()

			# Create a starter .yarn file if none exist in the same directory
			var dir_path := path.get_base_dir()
			var has_yarn_files := false
			var dir := DirAccess.open(dir_path)
			if dir:
				dir.list_dir_begin()
				var fname := dir.get_next()
				while not fname.is_empty():
					if fname.ends_with(".yarn"):
						has_yarn_files = true
						break
					fname = dir.get_next()
				dir.list_dir_end()

			if not has_yarn_files:
				var yarn_name := path.get_file().get_basename()
				var yarn_path := dir_path.path_join(yarn_name + ".yarn")
				var yarn_file := FileAccess.open(yarn_path, FileAccess.WRITE)
				if yarn_file:
					yarn_file.store_string("title: Start\n---\n\n===\n")
					yarn_file.close()

			EditorInterface.get_resource_filesystem().scan()
			print("Created Yarn project: ", path)
		else:
			push_error("Failed to create Yarn project at: ", path)
		dialog.queue_free()
	)

	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)

	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


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
