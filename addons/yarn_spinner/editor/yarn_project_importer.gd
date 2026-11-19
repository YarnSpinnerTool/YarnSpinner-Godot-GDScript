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
			"default_value": "",
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


func _get_format_version() -> int:
	return 1


func _get_icon() -> Texture2D:
	return preload("res://addons/yarn_spinner/icons/yarn_project.svg")


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var abs_path := ProjectSettings.globalize_path(source_file)
	var source_dir := abs_path.get_base_dir()
	var source_files := parse_project_sources(abs_path, source_dir)

	var resource: YarnProjectResource = null

	# Scan the project's scripts for commands and functions before compiling,
	# so the compiler gets each function's types. The .ysls.json below is
	# written from the same scan.
	var generator := _scan_yarn_actions(source_file, ysls_scan_path_option(options.get("ysls_scan_path", "")))
	var project_version := project_language_version(abs_path)
	generator.instance_parameters_as_strings = project_version > 0 and project_version < CURRENT_PROJECT_FILE_VERSION

	# Write the .ysls.json and list it in the project's "definitions" before
	# compiling. The ysc fallback reads each function's types from it.
	if options.get("generate_ysls", true):
		_save_ysls_file(generator, source_file)
		_add_ysls_to_definitions(source_file)

	# Try native compiler first
	if YarnNativeCompiler.is_available():
		var language_version := project_language_version(abs_path)
		var result := _compile_native(source_file, abs_path, source_files, _function_declarations(generator, abs_path, language_version), language_version)
		resource = result.resource
		if resource != null and resource.diagnostics.is_empty():
			_generate_variables_source(source_file, options, result.declarations, result.enums)
		elif resource == null:
			# Native compiler failed — fall through to ysc CLI
			print("yarn project importer: native compiler failed, falling back to ysc CLI")

	if resource == null:
		resource = _compile_ysc(source_file, abs_path, source_files, options)

	_explain_undeclarable_functions(resource, generator)

	for diag: Dictionary in resource.diagnostics:
		var location := ""
		if not str(diag.get("file", "")).is_empty():
			location = "%s:%d: " % [diag.file, diag.get("line", 0)]
		push_error("yarn project importer: %s%s" % [location, diag.get("message", "unknown error")])

	var save_file := save_path + "." + _get_save_extension()
	var save_err := ResourceSaver.save(resource, save_file)

	return save_err


func _explain_undeclarable_functions(resource: YarnProjectResource, generator: YarnYSLSGenerator) -> void:
	if resource == null or resource.diagnostics.is_empty():
		return
	var untyped: Dictionary = {}
	for info: Dictionary in generator.generate_ysls_dict().get("functions", []):
		var return_info: Dictionary = info.get("return", {})
		if str(return_info.get("type", "any")) == "any":
			untyped[str(info.get("yarnName", ""))] = info
	if untyped.is_empty():
		return
	var pattern := RegEx.create_from_string("no declaration found for (\\S+)")
	var diagnostics: Array = resource.diagnostics
	for i in diagnostics.size():
		var diag: Dictionary = diagnostics[i]
		var found := pattern.search(str(diag.get("message", "")))
		if found == null or not untyped.has(found.get_string(1)):
			continue
		var info: Dictionary = untyped[found.get_string(1)]
		diag["message"] = ("%s. The function %s (%s in %s) doesn't declare a return type Yarn can use, so the compiler can't check calls to it. " +
			"Give it a typed return, for example -> String, and if it needs to wait, await inside it rather than returning a Signal.") % [
			diag.get("message", ""), found.get_string(1), info.get("definitionName", ""), info.get("fileName", "")]
		diagnostics[i] = diag
	resource.diagnostics = diagnostics


func _run_ysc(ysc_path: String, project_path: String, temp_dir: String, output_name: String, output: Array) -> int:
	var args := PackedStringArray([
		"compile",
		project_path,
		"-o", temp_dir,
		"-n", output_name,
	])
	return OS.execute(ysc_path, args, output, true)


func _hit_null_declarations_bug(output: Array) -> bool:
	for chunk in output:
		var text := str(chunk)
		if text.contains("ArgumentNullException") and text.contains("GetCompilationJob"):
			return true
	return false


static func _ysc_project_copy_path(abs_path: String) -> String:
	return abs_path.get_base_dir().path_join("." + abs_path.get_file().get_basename() + ".ysc.yarnproject")


static func _write_ysc_project_copy(abs_path: String, temp_dir: String, output_name: String) -> Dictionary:
	if resolve_definitions_files(abs_path).is_empty():
		return {}
	var functions: Array = []
	for declaration in definitions_function_declarations(abs_path, project_language_version(abs_path)):
		functions.append(_ysls_function_from_declaration(declaration))
	var definitions_path := temp_dir.path_join("%s.definitions.ysls.json" % output_name)
	var definitions := {
		"version": YarnYSLSGenerator.YSLS_VERSION,
		"commands": [],
		"functions": functions,
		"Functions": YarnYSLSGenerator.legacy_functions(functions),
	}
	if YarnProjectUtility.write_project_json(definitions_path, definitions) != OK:
		return {}

	var project := YarnProjectUtility.read_project_json(abs_path)
	project["definitions"] = definitions_path if project.get("definitions") is String else [definitions_path]
	var project_path := _ysc_project_copy_path(abs_path)
	if YarnProjectUtility.write_project_json(project_path, project) != OK:
		DirAccess.remove_absolute(definitions_path)
		return {}
	return {"project": project_path, "files": [definitions_path, project_path]}


static func _ysls_function_from_declaration(declaration: Dictionary) -> Dictionary:
	var parameters: Array = []
	for parameter: Variant in declaration.get("parameters", []):
		parameters.append(_ysls_parameter(parameter, "p%d" % parameters.size(), false))
	if declaration.has("variadicParameterType"):
		parameters.append(_ysls_parameter(declaration["variadicParameterType"], "p%d" % parameters.size(), true))
	var result := {
		"yarnName": declaration["name"],
		"parameters": parameters,
		"return": {"type": str(declaration.get("returnType", "any"))},
	}
	if declaration.has("description"):
		result["documentation"] = declaration["description"]
	return result


static func _ysls_parameter(parameter: Variant, fallback_name: String, is_params_array: bool) -> Dictionary:
	var entry := {"name": fallback_name, "type": "any", "isParamsArray": is_params_array}
	if parameter is String:
		entry["type"] = compiler_parameter_type(parameter)
	elif parameter is Dictionary:
		var info := parameter as Dictionary
		if not str(info.get("name", "")).is_empty():
			entry["name"] = str(info["name"])
		entry["type"] = compiler_parameter_type(str(info.get("type", "any")))
		if info.has("subtype"):
			entry["subtype"] = str(info["subtype"])
		if info.get("defaultValue", false):
			entry["defaultValue"] = ""
	return entry


const YSC_UPDATE_COMMAND := "dotnet tool update -g YarnSpinner.Console"

static var _ysc_versions: Dictionary[String, String] = {}


static func ysc_version(ysc_path: String) -> String:
	var key := "%s@%d" % [ysc_path, FileAccess.get_modified_time(ysc_path)]
	if _ysc_versions.has(key):
		return _ysc_versions[key]
	var output: Array = []
	var version := ""
	if OS.execute(ysc_path, ["--version"], output, true) == 0 and not output.is_empty():
		version = parse_ysc_version(str(output[0]))
	_ysc_versions[key] = version
	return version


static func parse_ysc_version(text: String) -> String:
	var first_line := text.strip_edges().get_slice("\n", 0).strip_edges()
	var found := RegEx.create_from_string("^(\\d+\\.\\d+\\.\\d+(?:-[0-9A-Za-z.]+)?)(?:\\+|$)").search(first_line)
	if found == null or found.get_string(1) == "0.0.0":
		return ""
	return found.get_string(1)


static func ysc_label(ysc_path: String, version: String) -> String:
	if version.is_empty():
		return "ysc (%s)" % ysc_path
	return "ysc %s (%s)" % [version, ysc_path]


static func native_compiler_status() -> String:
	var bin_path := YarnNativeCompiler.get_native_bin_path()
	if bin_path.is_empty():
		return "Yarn Spinner for Godot doesn't bundle a compiler for %s on %s, so it used ysc instead." % [OS.get_name(), Engine.get_architecture_name()]
	if not YarnNativeCompiler.is_available():
		return "The bundled compiler (%s) is missing, so Yarn Spinner used ysc instead. Reinstall the addons folder from a Yarn Spinner for Godot release to get it back." % bin_path
	return "The bundled compiler (%s) couldn't run, so Yarn Spinner used ysc instead. Check the errors above for why." % bin_path


static func explain_ysc_failure(output_text: String, label: String) -> String:
	var update := "Update ysc with: %s" % YSC_UPDATE_COMMAND

	if output_text.contains("You must install or update .NET"):
		var runtime := RegEx.create_from_string("Framework: 'Microsoft\\.NETCore\\.App', version '([^']+)'").search(output_text)
		if runtime != null:
			return "%s can't start, because it needs version %s of the .NET runtime and that isn't installed. Install .NET %s, or update ysc with: %s" % [
				label, runtime.get_string(1), runtime.get_string(1).get_slice(".", 0), YSC_UPDATE_COMMAND]
		return "%s can't start, because the .NET runtime it needs isn't installed. Install a newer .NET runtime, or update ysc with: %s" % [label, YSC_UPDATE_COMMAND]

	var file_version := RegEx.create_from_string("incorrect file version \\(expected (\\d+), got (\\d+)\\)").search(output_text)
	if file_version != null:
		return "%s can only open Yarn Projects up to file version %s, and this one is version %s. %s" % [
			label, file_version.get_string(1), file_version.get_string(2), update]

	var duplicate := RegEx.create_from_string("An item with the same key has already been added\\. Key: (\\S+)").search(output_text)
	if duplicate != null:
		return "%s stopped because %s is declared twice. Versions of ysc before 3.3 do this when a definitions file declares a function ysc already declares itself. %s, or remove %s from the definitions files." % [
			label, duplicate.get_string(1), update, duplicate.get_string(1)]

	if output_text.contains("has invalid JSON"):
		return "%s couldn't read this Yarn Project. It's probably older than the format the project uses. %s" % [label, update]

	if output_text.contains("Unhandled exception") or output_text.contains("Failed to compile because of the following error"):
		return "%s crashed while compiling, so this is a problem with ysc, not with your Yarn scripts. %s" % [label, update]

	return ""


func _compile_ysc(source_file: String, abs_path: String, source_files: PackedStringArray, options: Dictionary) -> YarnProjectResource:
	var resource := YarnProjectResource.new()
	resource.source_files = source_files

	var ysc_path: String = _find_ysc_path(options)

	if ysc_path.is_empty():
		resource.diagnostics = [_diagnostic("No compiler is available. The bundled compiler isn't there for %s on %s, and ysc isn't installed. Reinstall the addons folder from a Yarn Spinner for Godot release, or install ysc with: dotnet tool install -g YarnSpinner.Console" % [OS.get_name(), Engine.get_architecture_name()])]
		return resource

	var label := ysc_label(ysc_path, ysc_version(ysc_path))
	print("yarn project importer: using %s" % label)

	var temp_dir := OS.get_temp_dir().path_join("yarn_spinner_compile")
	DirAccess.make_dir_recursive_absolute(temp_dir)

	var output_name := source_file.get_file().get_basename()

	var ysc_copy := _write_ysc_project_copy(abs_path, temp_dir, output_name)
	var output: Array = []
	var exit_code := _run_ysc(ysc_path, ysc_copy.get("project", abs_path), temp_dir, output_name, output)
	for path: String in ysc_copy.get("files", []):
		DirAccess.remove_absolute(path)

	if exit_code != 0 and _hit_null_declarations_bug(output):
		var stripped_path := _ysc_project_copy_path(abs_path)
		var data := YarnProjectUtility.read_project_json(abs_path)
		data.erase("definitions")
		if YarnProjectUtility.write_project_json(stripped_path, data) == OK:
			var consequence := "calls to those functions fail as unknown functions" if project_language_version(abs_path) >= CURRENT_PROJECT_FILE_VERSION else "calls to those functions aren't type checked"
			push_warning("yarn project importer: %s can't read function declarations from the definitions in %s, so it compiled without them, and %s. This is a bug in ysc 3.3.0 that's fixed in later versions, so update ysc with: %s once a newer version is out. %s" % [label, source_file, consequence, YSC_UPDATE_COMMAND, native_compiler_status()])
			output.clear()
			exit_code = _run_ysc(ysc_path, stripped_path, temp_dir, output_name, output)
			DirAccess.remove_absolute(stripped_path)

	if exit_code != 0:
		if exit_code == 127:
			resource.diagnostics = [_diagnostic("ysc not found at '%s'. Install it with: dotnet tool install -g YarnSpinner.Console" % ysc_path)]
			return resource
		var output_text := ""
		for chunk in output:
			output_text += str(chunk)
		var explanation := explain_ysc_failure(output_text, label)
		if not explanation.is_empty():
			print("yarn project importer: %s output:\n%s" % [label, output_text])
			resource.diagnostics = [_diagnostic("%s %s" % [explanation, native_compiler_status()])]
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
				var kept := PackedStringArray()
				for tag in tags.split(" ", false):
					if not tag.begins_with("line:"):
						kept.append(tag)
				if not line_id.is_empty() and not kept.is_empty():
					line_metadata[line_id] = kept
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
func _compile_native(source_file: String, abs_path: String, source_files: PackedStringArray, function_declarations: Array[Dictionary] = [], language_version: int = 0) -> Dictionary:
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

	var result := YarnNativeCompiler.compile(files, function_declarations, language_version)

	if result.get("compiler_failed", false):
		for diag in result.diagnostics:
			push_warning("yarn project importer (native): %s" % diag.get("message", "unknown error"))
		return failed

	var resource := YarnProjectResource.new()
	resource.source_files = source_files

	for diag: Dictionary in result.diagnostics:
		if str(diag.get("severity", "error")).to_lower() != "warning":
			continue
		var warning_file := _localize(str(diag.get("fileName", "")))
		var warning_line: int = int(diag.get("line", -1))
		var warning_location := ""
		if not warning_file.is_empty():
			warning_location = "%s:%d: " % [warning_file, warning_line + 1] if warning_line >= 0 else "%s: " % warning_file
		push_warning("yarn project importer: %s%s" % [warning_location, diag.get("message", "")])

	if not result.success:
		var diagnostics: Array = []
		for diag: Dictionary in result.diagnostics:
			if str(diag.get("severity", "error")).to_lower() != "error":
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
				if not str(tag).begins_with("line:"):
					tags.append(str(tag))
			if not tags.is_empty():
				line_metadata[line_id] = tags

	resource.string_table = string_table
	resource.line_metadata = line_metadata
	resource.line_info = line_info
	resource.enums = _enums_from_result(result.enums)
	resource.variable_types = _variable_types_from_result(result.declarations)

	return {"resource": resource, "declarations": result.declarations, "enums": result.enums}


static func _enums_from_result(compiled_enums: Array) -> Dictionary:
	var enums := {}
	for info: Dictionary in compiled_enums:
		var cases: Array = []
		for entry: Dictionary in info.get("cases", []):
			var value: Variant = entry.get("value")
			if value is int:
				value = float(value)
			cases.append({
				"name": str(entry.get("name", "")),
				"value": value,
				"description": str(entry.get("description", "")),
			})
		enums[str(info.get("name", ""))] = {
			"raw_type": str(info.get("rawType", "")),
			"description": str(info.get("description", "")),
			"cases": cases,
		}
	return enums


static func _variable_types_from_result(declarations: Array) -> Dictionary:
	var types := {}
	for declaration: Dictionary in declarations:
		var variable_name := str(declaration.get("name", ""))
		if variable_name.begins_with("$"):
			types[variable_name] = str(declaration.get("type", ""))
	return types


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


func _scan_yarn_actions(yarn_project_path: String, scan_path: String) -> YarnYSLSGenerator:
	var generator := YarnYSLSGenerator.new()
	generator.scan_for_project(yarn_project_path, scan_path)
	return generator


static func ysls_scan_path_option(value: Variant) -> String:
	var path := String(value).strip_edges()
	return "" if path.trim_suffix("/") in ["res:/", "res:"] else path


static func ysls_import_option(yarn_project_path: String, option: String, default_value: Variant) -> Variant:
	var config := ConfigFile.new()
	if config.load(yarn_project_path + ".import") != OK:
		return default_value
	return config.get_value("params", option, default_value)


## Function declarations for the compiler: the built-in functions it doesn't
## already know about, then every function the scan found. Without these the
## compiler can only work out a function's types from where it's used, so a
## call inside a line, like {coin_count()}, wouldn't compile.
static func _function_declarations(generator: YarnYSLSGenerator, abs_project_path: String, language_version: int = 0) -> Array[Dictionary]:
	var declarations: Array[Dictionary] = []
	var declared: Dictionary[String, bool] = {}

	for declaration: Dictionary in YarnLibrary.COMPILER_DECLARATIONS:
		declarations.append(declaration)
		declared[declaration["name"]] = true

	var functions: Array = generator.generate_ysls_dict().get("functions", [])
	for info: Dictionary in functions:
		var yarn_name := str(info.get("yarnName", ""))
		if yarn_name.is_empty() or declared.has(yarn_name):
			continue
		var return_info: Dictionary = info.get("return", {})
		var untyped_parameter := false
		for parameter: Dictionary in info.get("parameters", []):
			if str(parameter.get("type", "any")) == "any":
				untyped_parameter = true
		if untyped_parameter:
			continue
		var declaration := {
			"name": yarn_name,
			"returnType": str(return_info.get("type", "any")),
			"parameters": [],
		}
		for parameter: Dictionary in info.get("parameters", []):
			var parameter_type := compiler_parameter_type(str(parameter.get("type", "any")))
			if parameter.get("isParamsArray", false):
				declaration["variadicParameterType"] = parameter_type
				break
			if parameter.has("subtype"):
				declaration["parameters"].append({"name": str(parameter.get("name", "")), "type": parameter_type, "subtype": str(parameter["subtype"])})
			else:
				declaration["parameters"].append(parameter_type)
		declarations.append(declaration)
		declared[yarn_name] = true

	for declaration: Dictionary in definitions_function_declarations(abs_project_path, language_version):
		if declared.has(declaration["name"]):
			continue
		declarations.append(declaration)
		declared[declaration["name"]] = true

	return declarations


const WORKSPACE_ROOT_PLACEHOLDER := "${workspaceRoot}"
const CURRENT_PROJECT_FILE_VERSION := 5
const ENUM_AND_INSTANCE_MIN_VERSION := 5
const WORKSPACE_ROOT_MIN_VERSION := 5
const SINGLE_DEFINITION_MAX_VERSION := 3


static func workspace_root() -> String:
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


static func definition_entries(data: Dictionary) -> PackedStringArray:
	var entries := PackedStringArray()
	var raw: Variant = data.get("definitions", null)
	if raw is String:
		if not (raw as String).strip_edges().is_empty():
			entries.append(raw)
	elif raw is Array:
		for entry: Variant in raw:
			if entry is String and not (entry as String).strip_edges().is_empty():
				entries.append(entry)
	return entries


static func resolve_definitions_files(abs_project_path: String, warn: bool = false) -> PackedStringArray:
	var results := PackedStringArray()
	var data := YarnProjectUtility.read_project_json(abs_project_path)
	if data.is_empty():
		return results
	var project_dir := abs_project_path.get_base_dir()
	var root := workspace_root()
	var seen := {}
	for entry in definition_entries(data):
		var unknown := RegEx.create_from_string("\\$\\{[^}]*\\}").search_all(entry.replace(WORKSPACE_ROOT_PLACEHOLDER, ""))
		if warn and not unknown.is_empty():
			push_warning("yarn project importer: \"%s\" in the definitions of %s uses %s, which isn't supported. Only %s is." % [entry, abs_project_path, unknown[0].get_string(), WORKSPACE_ROOT_PLACEHOLDER])
		var matches := _resolve_definition_entry(entry, project_dir, root)
		if matches.is_empty() and warn and not _is_glob(entry):
			push_warning("yarn project importer: couldn't find the definitions file \"%s\" listed in %s" % [entry, abs_project_path])
		for path in matches:
			if not seen.has(path):
				seen[path] = true
				results.append(path)
	return results


static func _is_glob(text: String) -> bool:
	return text.replace(WORKSPACE_ROOT_PLACEHOLDER, "").contains("*") or text.contains("?")


static func _resolve_definition_entry(entry: String, project_dir: String, root: String) -> PackedStringArray:
	var expanded := entry.strip_edges().replace(WORKSPACE_ROOT_PLACEHOLDER, root).replace("\\", "/")
	if expanded.begins_with("res://") or expanded.begins_with("user://"):
		expanded = ProjectSettings.globalize_path(expanded)
	elif not expanded.is_absolute_path():
		expanded = project_dir.path_join(expanded.trim_prefix("./"))

	var segments := expanded.split("/")
	var first_glob := -1
	for i in segments.size():
		if segments[i].contains("*") or segments[i].contains("?"):
			first_glob = i
			break

	if first_glob == -1:
		var path := expanded.simplify_path()
		return PackedStringArray([path]) if FileAccess.file_exists(path) else PackedStringArray()

	var prefix := "/".join(segments.slice(0, first_glob))
	if prefix.is_empty():
		prefix = "/"
	elif prefix.ends_with(":"):
		prefix += "/"
	var remainder := "/".join(segments.slice(first_glob))
	var found := PackedStringArray()
	for path in resolve_glob(prefix.simplify_path(), remainder):
		if path.ends_with(".ysls.json"):
			found.append(path.simplify_path())
	return found


static func project_language_version(abs_project_path: String) -> int:
	var version: Variant = YarnProjectUtility.read_project_json(abs_project_path).get("projectFileVersion", null)
	if (version is int or version is float) and int(version) > 0:
		return int(version)
	return 0


static func definitions_function_declarations(abs_project_path: String, language_version: int = 0) -> Array[Dictionary]:
	var declarations: Array[Dictionary] = []
	var declared := {}
	for path in resolve_definitions_files(abs_project_path, true):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_warning("yarn project importer: couldn't open the definitions file %s: %s" % [path, error_string(FileAccess.get_open_error())])
			continue
		var json := JSON.new()
		var err := json.parse(file.get_as_text())
		file.close()
		if err != OK:
			push_warning("yarn project importer: couldn't read the definitions file %s: %s at line %d" % [path, json.get_error_message(), json.get_error_line()])
			continue
		if not json.data is Dictionary:
			push_warning("yarn project importer: the definitions file %s doesn't contain a JSON object" % path)
			continue
		var functions: Variant = _get_key(json.data as Dictionary, "functions")
		if functions == null:
			continue
		if not functions is Array:
			push_warning("yarn project importer: \"functions\" in %s isn't a list" % path)
			continue
		for info: Variant in functions as Array:
			if not info is Dictionary:
				continue
			var declaration := _declaration_from_definition(info as Dictionary, language_version, path)
			if declaration.is_empty() or declared.has(declaration["name"]):
				continue
			declared[declaration["name"]] = true
			declarations.append(declaration)
	return declarations


static func _declaration_from_definition(info: Dictionary, language_version: int = 0, path: String = "") -> Dictionary:
	var yarn_name := str(_get_key(info, "yarnName", ""))
	if yarn_name.is_empty():
		return {}

	var return_type := ""
	var return_info: Variant = _get_key(info, "return")
	if return_info is Dictionary:
		return_type = str(_get_key(return_info as Dictionary, "type", ""))
	elif return_info is String:
		return_type = return_info as String
	if return_type.is_empty():
		return_type = str(_get_key(info, "returnType", ""))
	if return_type.is_empty():
		return {}

	var declaration := {
		"name": yarn_name,
		"returnType": return_type.to_lower(),
		"parameters": [],
	}
	var documentation: Variant = _get_key(info, "documentation")
	if documentation is String and not (documentation as String).is_empty():
		declaration["description"] = documentation as String

	var parameters: Variant = _get_key(info, "parameters", [])
	if not parameters is Array:
		return declaration
	var parameter_list := parameters as Array
	for i in parameter_list.size():
		if not parameter_list[i] is Dictionary:
			return {}
		var parameter := parameter_list[i] as Dictionary
		var parameter_type := str(_get_key(parameter, "type", "any")).to_lower()
		if parameter_type == "any":
			return {}
		if parameter_type == "enum" or parameter_type == "instance":
			var effective_version := language_version if language_version > 0 else CURRENT_PROJECT_FILE_VERSION
			if effective_version < ENUM_AND_INSTANCE_MIN_VERSION:
				push_warning("yarn project importer: %s in %s has an %s parameter, which needs project file version %d or later. This project is version %d, so %s isn't declared." % [yarn_name, path, parameter_type, ENUM_AND_INSTANCE_MIN_VERSION, effective_version, yarn_name])
				return {}
		var entry := {"type": compiler_parameter_type(parameter_type)}
		var subtype: Variant = _get_key(parameter, "subtype")
		if subtype is String:
			entry["subtype"] = subtype
		if _get_key(parameter, "defaultValue") != null:
			entry["defaultValue"] = true
		if _get_key(parameter, "isParamsArray", false) == true and i == parameter_list.size() - 1:
			declaration["variadicParameterType"] = entry
		else:
			declaration["parameters"].append(entry)
	return declaration


static func compiler_parameter_type(type: String) -> String:
	match type.to_lower():
		"node":
			return "string"
		"boolean":
			return "bool"
	return type.to_lower()


static func _get_key(dict: Dictionary, key: String, default_value: Variant = null) -> Variant:
	if dict.has(key):
		return dict[key]
	for existing: Variant in dict.keys():
		if existing is String and (existing as String).nocasecmp_to(key) == 0:
			return dict[existing]
	return default_value


## Lists the project's generated .ysls.json in its "definitions" so ysc and
## the VS Code extension read it. Anything already listed stays in the same
## order, and the file is only written when the entry is missing.
func _add_ysls_to_definitions(yarn_project_path: String) -> void:
	var ysls_name := yarn_project_path.get_file().get_basename() + ".ysls.json"
	var data := YarnProjectUtility.read_project_json(yarn_project_path)
	if data.is_empty():
		return

	var definitions: Array = []
	var existing: Variant = data.get("definitions", null)
	if existing is String:
		definitions.append(existing)
	elif existing is Array:
		definitions = (existing as Array).duplicate()
	elif existing != null:
		push_warning("yarn project importer: %s has a \"definitions\" entry that isn't a path or a list of paths, so %s wasn't added to it" % [yarn_project_path, ysls_name])
		return

	var project_dir := ProjectSettings.globalize_path(yarn_project_path).get_base_dir()
	var target := project_dir.path_join(ysls_name).simplify_path()
	var workspace_root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var fold_case := OS.get_name() in ["Windows", "macOS"]
	for entry: Variant in definitions:
		if not entry is String:
			continue
		var text := entry as String
		if text.simplify_path().trim_prefix("./") == ysls_name:
			return
		var expanded := text.replace("${workspaceRoot}", workspace_root)
		var resolved := (expanded if expanded.is_absolute_path() else project_dir.path_join(expanded)).simplify_path()
		if resolved == target or (fold_case and resolved.nocasecmp_to(target) == 0):
			return

	var version := project_language_version(ProjectSettings.globalize_path(yarn_project_path))
	var entry_to_add := ysls_name
	if version >= WORKSPACE_ROOT_MIN_VERSION:
		entry_to_add = WORKSPACE_ROOT_PLACEHOLDER + "/" + (yarn_project_path.get_basename() + ".ysls.json").trim_prefix("res://")

	if version > 0 and version <= SINGLE_DEFINITION_MAX_VERSION and not existing is Array:
		if not definitions.is_empty() and not (definitions[0] as String).strip_edges().is_empty():
			push_warning("yarn project importer: %s is a version %d Yarn Project, which can list only one definitions file, and it already lists %s, so %s wasn't added. To list more than one, upgrade the project to version 4 or later." % [yarn_project_path, version, definitions[0], ysls_name])
			return
		data["definitions"] = entry_to_add
	else:
		definitions.append(entry_to_add)
		data["definitions"] = definitions
	var err := YarnProjectUtility.write_project_json(yarn_project_path, data)
	if err != OK:
		push_warning("yarn project importer: couldn't add %s to the definitions in %s: %s" % [entry_to_add, yarn_project_path, error_string(err)])
	else:
		print("yarn project importer: added %s to the definitions in %s" % [entry_to_add, yarn_project_path])


func _save_ysls_file(generator: YarnYSLSGenerator, yarn_project_path: String) -> void:
	var ysls_path := yarn_project_path.get_basename() + ".ysls.json"
	var err := generator.save_ysls(ysls_path)

	if err != OK:
		push_warning("yarn project importer: failed to generate ysls file: %s" % error_string(err))
	else:
		print("yarn project importer: generated %s" % ysls_path)
