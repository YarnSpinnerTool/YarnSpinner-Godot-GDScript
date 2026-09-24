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
const YarnProjectUtility := preload("res://addons/yarn_spinner/editor/yarn_project_utility.gd")
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
	# Must stay "Resource". Returning a script class name (or any non-ClassDB
	# type) puts the file's importer roundtrip check into a state Godot 4.6
	# can't resolve, which makes "No loader found" errors fire on startup and
	# disables the right-click "Reimport" menu item.
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
		},
		{
			"name": "line_tagger",
			"default_value": 0,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Random,Descriptive",
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "generate_variables_source",
			"default_value": false,
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "variables_class_name",
			"default_value": "YarnVariables",
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "variables_class_parent",
			"default_value": YarnProjectUtility.DEFAULT_VARIABLES_PARENT,
			"usage": PROPERTY_USAGE_EDITOR
		},
	]


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	if option_name == &"variables_class_name" or option_name == &"variables_class_parent":
		return options.get("generate_variables_source", false)
	return true


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_icon() -> Texture2D:
	return preload("res://addons/yarn_spinner/icons/yarn_project.svg")


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var abs_path := ProjectSettings.globalize_path(source_file)
	var source_dir := abs_path.get_base_dir()
	var source_files := parse_project_sources(abs_path, source_dir)

	var resource: YarnProjectResource = null

	# Try native compiler first (bundled, no .NET dependency)
	if YarnNativeCompiler.is_available():
		var result := _compile_native(source_file, abs_path, source_files)
		resource = result.resource
		if resource != null and resource.diagnostics.is_empty():
			_generate_variables_source(source_file, options, result.declarations, result.enums)
		elif resource == null:
			# Native compiler failed — fall through to ysc CLI
			print("yarn project importer: native compiler failed, falling back to ysc CLI")

	if resource == null:
		resource = _compile_ysc(source_file, abs_path, source_files, options)

	for diag: Dictionary in resource.diagnostics:
		var location := ""
		if not str(diag.get("file", "")).is_empty():
			location = "%s:%d: " % [diag.file, diag.get("line", 0)]
		push_error("yarn project importer: %s%s" % [location, diag.get("message", "unknown error")])

	var save_file := save_path + "." + _get_save_extension()
	var save_err := ResourceSaver.save(resource, save_file)

	if options.get("generate_ysls", true):
		var scan_path: String = options.get("ysls_scan_path", "")
		_generate_ysls_file(source_file, scan_path)

	return save_err


func _compile_ysc(source_file: String, abs_path: String, source_files: PackedStringArray, options: Dictionary) -> YarnProjectResource:
	var resource := YarnProjectResource.new()
	resource.source_files = source_files

	var ysc_path: String = _find_ysc_path(options)

	if ysc_path.is_empty():
		resource.diagnostics = [_diagnostic("No compiler available. Either build the native compiler (native/build.sh) or install ysc: dotnet tool install -g YarnSpinner.Console")]
		return resource

	print("yarn project importer: using ysc CLI at '%s'" % ysc_path)

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
		if exit_code == 127:
			resource.diagnostics = [_diagnostic("ysc not found at '%s'. Install it with: dotnet tool install -g YarnSpinner.Console" % ysc_path)]
			return resource
		var diagnostics: Array = []
		for chunk in output:
			for line in str(chunk).split("\n", false):
				if not line.strip_edges().is_empty():
					diagnostics.append(_diagnostic(line.strip_edges()))
		if diagnostics.is_empty():
			diagnostics.append(_diagnostic("ysc failed with exit code %d" % exit_code))
		resource.diagnostics = diagnostics
		return resource

	var yarnc_path := temp_dir.path_join(output_name + ".yarnc")
	var yarnc_file := FileAccess.open(yarnc_path, FileAccess.READ)
	if yarnc_file == null:
		resource.diagnostics = [_diagnostic("Failed to read compiled file %s" % yarnc_path)]
		return resource

	var compiled_data := yarnc_file.get_buffer(yarnc_file.get_length())
	yarnc_file.close()

	var sources_text := ""
	for path in source_files:
		var source := FileAccess.open(path, FileAccess.READ)
		if source != null:
			sources_text += source.get_as_text()
			source.close()

	var string_table := {}
	var line_info := {}
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
					line_info[line_id] = {
						"file": _localize(csv_line[2]) if csv_line.size() > 2 else "",
						"node": csv_line[3] if csv_line.size() > 3 else "",
						"line": int(csv_line[4]) if csv_line.size() > 4 else -1,
						"implicit": not sources_text.contains("#" + line_id),
					}
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

	resource.compiled_program = compiled_data
	resource.string_table = string_table
	resource.line_metadata = line_metadata
	resource.line_info = line_info

	DirAccess.remove_absolute(yarnc_path)
	DirAccess.remove_absolute(lines_csv_path)
	DirAccess.remove_absolute(metadata_csv_path)

	return resource


## Compile using the bundled native compiler (no .NET required).
func _compile_native(source_file: String, abs_path: String, source_files: PackedStringArray) -> Dictionary:
	print("yarn project importer: using native compiler at '%s'" % YarnNativeCompiler.get_native_bin_path())

	var failed := {"resource": null, "declarations": [], "enums": []}

	# Read all source .yarn files
	var files: Array[Dictionary] = []
	for src_path in source_files:
		var file := FileAccess.open(src_path, FileAccess.READ)
		if file != null:
			files.append({
				# Full path, not get_file() — the compiler keys files by this
				# name, and basenames collide (workshop/hotspots.yarn vs
				# vespuccis_restaurant/hotspots.yarn) which throws a duplicate-
				# key ArgumentException inside the native compiler.
				"fileName": src_path,
				"source": file.get_as_text(),
			})
			file.close()

	# If no source files resolved from the project, try the project directory
	if files.is_empty():
		var project_dir := abs_path.get_base_dir()
		var dir := DirAccess.open(project_dir)
		if dir != null:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while not fname.is_empty():
				if fname.get_extension() == "yarn":
					var fpath := project_dir.path_join(fname)
					var file := FileAccess.open(fpath, FileAccess.READ)
					if file != null:
						files.append({"fileName": fpath, "source": file.get_as_text()})
						file.close()
				fname = dir.get_next()
			dir.list_dir_end()

	if files.is_empty():
		return failed

	var result := YarnNativeCompiler.compile(files)

	if result.get("compiler_failed", false):
		for diag in result.diagnostics:
			push_warning("yarn project importer (native): %s" % diag.get("message", "unknown error"))
		return failed

	var resource := YarnProjectResource.new()
	resource.source_files = source_files

	if not result.success:
		var diagnostics: Array = []
		for diag: Dictionary in result.diagnostics:
			if diag.get("severity", "error") != "error":
				continue
			var line: int = int(diag.get("line", -1))
			diagnostics.append({
				"message": str(diag.get("message", "unknown error")),
				"file": _localize(str(diag.get("fileName", ""))),
				"line": line + 1 if line >= 0 else -1,
				"column": int(diag.get("column", -1)) + 1,
			})
		if diagnostics.is_empty():
			diagnostics.append(_diagnostic("Compilation failed"))
		resource.diagnostics = diagnostics
		return {"resource": resource, "declarations": [], "enums": []}

	resource.compiled_program = result.program

	# Build string table and metadata from native compiler output
	var string_table := {}
	var line_metadata := {}
	var line_info := {}
	for line_id in result.string_table:
		var entry: Dictionary = result.string_table[line_id]
		# Shadow lines compile with null text (their content comes from the
		# line they shadow); store "" so typed String lookups stay valid.
		var text: Variant = entry.get("text", "")
		string_table[line_id] = text if text is String else ""
		line_info[line_id] = {
			"file": _localize(str(entry.get("fileName", ""))),
			"node": str(entry.get("nodeName", "")),
			"line": int(entry.get("lineNumber", -1)),
			"implicit": bool(entry.get("isImplicitTag", false)),
		}
		var meta: Array = entry.get("metadata", [])
		if not meta.is_empty():
			var tags := PackedStringArray()
			for tag in meta:
				tags.append(str(tag))
			line_metadata[line_id] = tags

	resource.string_table = string_table
	resource.line_metadata = line_metadata
	resource.line_info = line_info

	return {"resource": resource, "declarations": result.declarations, "enums": result.enums}


func _generate_variables_source(source_file: String, options: Dictionary, declarations: Array, enums: Array) -> void:
	if not options.get("generate_variables_source", false):
		return
	var variables_class: String = str(options.get("variables_class_name", "")).strip_edges()
	if not variables_class.is_valid_ascii_identifier():
		push_error("yarn project importer: can't generate variables for %s, because '%s' isn't a valid class name" % [source_file, variables_class])
		return
	var parent: String = str(options.get("variables_class_parent", "")).strip_edges()
	if parent.is_empty():
		parent = YarnProjectUtility.DEFAULT_VARIABLES_PARENT
	var path := YarnProjectUtility.variables_source_path(source_file, variables_class)
	var source := YarnProjectUtility.generate_variables_source(source_file, variables_class, parent, declarations, enums)
	if YarnProjectUtility.write_variables_source(path, source):
		print("yarn project importer: generated %s" % path)
		_refresh_generated_file.call_deferred(path)


static func _refresh_generated_file(path: String) -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(path)
		fs.scan()


static func _diagnostic(message: String) -> Dictionary:
	return {"message": message, "file": "", "line": -1, "column": -1}


static func _localize(path: String) -> String:
	if path.is_empty():
		return path
	return ProjectSettings.localize_path(path)


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


## Parses a .yarnproject file and resolves its `sourceFiles` globs.
## Returns absolute filesystem paths.
static func parse_project_sources(project_path: String, base_dir: String) -> PackedStringArray:
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
	var excluded := {}
	for pattern in data.get("excludeFiles", []):
		for path in resolve_glob(base_dir, str(pattern)):
			excluded[path] = true

	var seen := {}
	for pattern in data.get("sourceFiles", []):
		for path in resolve_glob(base_dir, str(pattern)):
			if not seen.has(path) and not excluded.has(path):
				seen[path] = true
				sources.append(path)

	return sources


static func resolve_glob(base_dir: String, pattern: String) -> PackedStringArray:
	var results := PackedStringArray()
	pattern = pattern.replace("\\", "/").trim_prefix("./")

	if not pattern.contains("*") and not pattern.contains("?"):
		var full_path := base_dir.path_join(pattern).simplify_path()
		if FileAccess.file_exists(full_path):
			results.append(full_path)
		return results

	var segments := pattern.split("/")
	var root := base_dir
	var index := 0
	while index < segments.size() - 1 and not segments[index].contains("*") and not segments[index].contains("?"):
		root = root.path_join(segments[index])
		index += 1
	root = root.simplify_path()
	var remainder := "/".join(segments.slice(index))

	var regex := RegEx.create_from_string("^" + _glob_to_regex(remainder) + "$")
	var recursive := remainder.contains("/") or remainder.contains("**")
	_find_files_recursive(root, "", regex, recursive, results)
	results.sort()
	return results


static func _glob_to_regex(glob: String) -> String:
	var out := ""
	var i := 0
	while i < glob.length():
		var c := glob[i]
		if c == "*":
			if i + 1 < glob.length() and glob[i + 1] == "*":
				if i + 2 < glob.length() and glob[i + 2] == "/":
					out += "(?:.*/)?"
					i += 3
				else:
					out += ".*"
					i += 2
				continue
			out += "[^/]*"
		elif c == "?":
			out += "[^/]"
		elif ".+()[]{}^$|\\".contains(c):
			out += "\\" + c
		else:
			out += c
		i += 1
	return out


static func _find_files_recursive(dir_path: String, relative: String, regex: RegEx, recursive: bool, results: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := dir_path.path_join(file_name)
		var relative_path := relative.path_join(file_name) if not relative.is_empty() else file_name
		if dir.current_is_dir():
			if recursive and not file_name.begins_with("."):
				_find_files_recursive(full_path, relative_path, regex, recursive, results)
		elif regex.search(relative_path) != null:
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _generate_ysls_file(yarn_project_path: String, scan_path: String) -> void:
	var generator := YarnYSLSGenerator.new()
	# Use the static helper to find the best scan root, or use explicit path
	var root := scan_path if not scan_path.is_empty() else YarnYSLSGenerator.find_scan_root(yarn_project_path)
	generator.scan_directory(root)

	var ysls_path := yarn_project_path.get_basename() + ".ysls.json"
	var err := generator.save_ysls(ysls_path)

	if err != OK:
		push_warning("yarn project importer: failed to generate ysls file: %s" % error_string(err))
	else:
		print("yarn project importer: generated %s" % ysls_path)
