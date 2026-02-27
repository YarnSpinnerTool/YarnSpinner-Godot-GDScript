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
extends EditorImportPlugin
## imports .yarnproject files by compiling them with ysc.

const YarnProjectResource := preload("res://addons/yarn_spinner/yarn_project_resource.gd")
const SETTING_YSC_PATH := "yarn_spinner/compiler/ysc_path"


func _get_importer_name() -> String:
	return "yarn_spinner.project"


func _get_visible_name() -> String:
	return "Yarn Project"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["yarnproject"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset_index: int) -> String:
	return "Default"


func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return [
		{
			"name": "ysc_path",
			"default_value": "ysc",
			"hint": PROPERTY_HINT_GLOBAL_FILE,
			"hint_string": "",
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "generate_ysls",
			"default_value": true,
			"hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "ysls_scan_path",
			"default_value": "res://",
			"hint": PROPERTY_HINT_DIR,
			"usage": PROPERTY_USAGE_EDITOR
		}
	]


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_icon() -> Texture2D:
	return preload("res://addons/yarn_spinner/icons/yarn_project.svg")


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var ysc_path: String = _find_ysc_path(options)

	if ysc_path.is_empty():
		push_error("yarn project importer: ysc compiler not found. install it with: dotnet tool install -g YarnSpinner.Console\nor set the path in Project Settings > Yarn Spinner > Compiler > Ysc Path")
		return ERR_FILE_NOT_FOUND

	var abs_path := ProjectSettings.globalize_path(source_file)
	var source_dir := abs_path.get_base_dir()

	var temp_dir := OS.get_temp_dir().path_join("yarn_spinner_compile")
	DirAccess.make_dir_recursive_absolute(temp_dir)

	var output_name := source_file.get_file().get_basename()

	var args := PackedStringArray([
		"compile",
		abs_path,
		"-o", temp_dir,
		"-n", output_name,
	])

	var output: Array = []
	var exit_code := OS.execute(ysc_path, args, output, true)

	if exit_code != 0:
		var error_text := ""
		for line in output:
			error_text += str(line)
		if exit_code == 127:
			push_error("yarn project importer: ysc not found at '%s'. install it with: dotnet tool install -g YarnSpinner.Console" % ysc_path)
		else:
			push_error("yarn project importer: ysc failed with exit code %d\n%s" % [exit_code, error_text])
		return ERR_COMPILATION_FAILED

	var yarnc_path := temp_dir.path_join(output_name + ".yarnc")
	var yarnc_file := FileAccess.open(yarnc_path, FileAccess.READ)
	if yarnc_file == null:
		push_error("yarn project importer: failed to read compiled file %s" % yarnc_path)
		return ERR_FILE_NOT_FOUND

	var compiled_data := yarnc_file.get_buffer(yarnc_file.get_length())
	yarnc_file.close()

	var string_table := {}
	var lines_csv_path := temp_dir.path_join(output_name + "-Lines.csv")
	var lines_file := FileAccess.open(lines_csv_path, FileAccess.READ)
	if lines_file != null:
		lines_file.get_csv_line()
		while not lines_file.eof_reached():
			var csv_line := lines_file.get_csv_line()
			if csv_line.size() >= 2:
				var line_id := csv_line[0]
				var text := csv_line[1]
				if not line_id.is_empty():
					string_table[line_id] = text
		lines_file.close()

	var line_metadata := {}
	var metadata_csv_path := temp_dir.path_join(output_name + "-Metadata.csv")
	var metadata_file := FileAccess.open(metadata_csv_path, FileAccess.READ)
	if metadata_file != null:
		metadata_file.get_csv_line()
		while not metadata_file.eof_reached():
			var csv_line := metadata_file.get_csv_line()
			if csv_line.size() >= 4:
				var line_id := csv_line[0]
				var tags := csv_line[3] if csv_line.size() > 3 else ""
				if not line_id.is_empty() and not tags.is_empty():
					line_metadata[line_id] = PackedStringArray(tags.split(" "))
		metadata_file.close()

	var source_files := _parse_project_sources(abs_path, source_dir)

	var resource := YarnProjectResource.new()
	resource.compiled_program = compiled_data
	resource.string_table = string_table
	resource.line_metadata = line_metadata
	resource.source_files = source_files

	DirAccess.remove_absolute(yarnc_path)
	DirAccess.remove_absolute(lines_csv_path)
	DirAccess.remove_absolute(metadata_csv_path)

	var save_file := save_path + "." + _get_save_extension()
	var save_err := ResourceSaver.save(resource, save_file)

	if options.get("generate_ysls", true):
		_generate_ysls_file(source_file, options.get("ysls_scan_path", "res://"))

	return save_err


func _find_ysc_path(options: Dictionary) -> String:
	var option_path: String = options.get("ysc_path", "")
	if not option_path.is_empty() and option_path != "ysc":
		if FileAccess.file_exists(option_path):
			return option_path

	if ProjectSettings.has_setting(SETTING_YSC_PATH):
		var setting_path: String = ProjectSettings.get_setting(SETTING_YSC_PATH, "")
		if not setting_path.is_empty() and FileAccess.file_exists(setting_path):
			return setting_path

	var home_dir: String = OS.get_environment("HOME")
	var common_paths: PackedStringArray = [
		home_dir.path_join(".dotnet/tools/ysc"),
		"/usr/local/bin/ysc",
		"/usr/bin/ysc",
		"C:/Users/" + OS.get_environment("USERNAME") + "/.dotnet/tools/ysc.exe",
	]

	for path in common_paths:
		if FileAccess.file_exists(path):
			return path

	var output: Array = []
	var exit_code: int = -1

	if OS.get_name() == "Windows":
		exit_code = OS.execute("where", ["ysc"], output, true)
	else:
		exit_code = OS.execute("which", ["ysc"], output, true)

	if exit_code == 0 and output.size() > 0:
		var found_path: String = str(output[0]).strip_edges()
		if not found_path.is_empty():
			return found_path

	return ""


func _parse_project_sources(project_path: String, base_dir: String) -> PackedStringArray:
	var sources := PackedStringArray()

	var file := FileAccess.open(project_path, FileAccess.READ)
	if file == null:
		return sources

	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		return sources

	var data: Dictionary = json.data
	if data.has("sourceFiles"):
		var patterns: Array = data["sourceFiles"]
		for pattern in patterns:
			var resolved := _resolve_glob(base_dir, pattern)
			sources.append_array(resolved)

	return sources


func _resolve_glob(base_dir: String, pattern: String) -> PackedStringArray:
	var results := PackedStringArray()

	if pattern.contains("**"):
		var parts := pattern.split("**/")
		var ext := parts[1] if parts.size() > 1 else "*.yarn"
		_find_files_recursive(base_dir, ext, results)
	elif pattern.contains("*"):
		var dir := DirAccess.open(base_dir)
		if dir != null:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while not file_name.is_empty():
				if not dir.current_is_dir() and file_name.match(pattern):
					results.append(base_dir.path_join(file_name))
				file_name = dir.get_next()
			dir.list_dir_end()
	else:
		var full_path := base_dir.path_join(pattern)
		if FileAccess.file_exists(full_path):
			results.append(full_path)

	return results


func _find_files_recursive(dir_path: String, pattern: String, results: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_find_files_recursive(full_path, pattern, results)
		else:
			if file_name.match(pattern):
				results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _generate_ysls_file(yarn_project_path: String, scan_path: String) -> void:
	var generator := YarnYSLSGenerator.new()
	generator.scan_directory(scan_path)

	var ysls_path := yarn_project_path.get_basename() + ".ysls.json"
	var err := generator.save_ysls(ysls_path)

	if err != OK:
		push_warning("yarn project importer: failed to generate ysls file: %s" % error_string(err))
	else:
		print("yarn project importer: generated %s" % ysls_path)
