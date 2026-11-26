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

# expose a godot variable for the ysc path setting
const SETTING_YSC_PATH := "yarn_spinner/compiler/ysc_path"

# if we ever need to push them to a specific version, update this
const YSC_UPDATE_COMMAND := "dotnet tool update -g YarnSpinner.Console"

# bump this when a newer ysc is requried. compared against what `ysc --version` reports 
# the assembly or whatever, or nuget, version, may report differently.
const MIN_YSC_VERSION := "3.3.4"

# cache of ysc versions for different paths to avoid repeatedly calling `ysc --version`
static var _ysc_versions: Dictionary[String, String] = {}

# environment variable for the workspace root, used by ysc, to locate the project files correctly. 
# set by the user or the Godot editor environment when running ysc...
const YSC_WORKSPACE_ROOT_ENV := "YARN_SPINNER_WORKSPACE_ROOT"

#Placeholder for the workspace root in paths, replaced with the actual workspace root at runtime.
const WORKSPACE_ROOT_PLACEHOLDER := "${workspaceRoot}"

# keep track of the current project file version for compatibility checks, pls.
const CURRENT_PROJECT_FILE_VERSION := 5


func _get_importer_name() -> String:
	return "yarn_spinner.project"


func _get_visible_name() -> String:
	return "Yarn Project"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["yarnproject"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	# Must stay "Resource"! Returning a script class name (or any non-ClassDB
	# type) puts the file's importer into a state Godot 4.6 still
	# can't resolve which makes "No loader found" errors fire on startup and
	# disables the right-click "Reimport" menu item...
	# TODO: Update, checked again in November 2026, still no better way to do this in Godot 4.7 or newer.
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
			"property_hint": PROPERTY_HINT_GLOBAL_FILE,
			"hint_string": "",
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "generate_ysls",
			"default_value": true,
			"property_hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_EDITOR
		},
		{
			"name": "ysls_scan_path",
			"default_value": "",
			"property_hint": PROPERTY_HINT_DIR,
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

	if project_version != CURRENT_PROJECT_FILE_VERSION:
		resource = YarnProjectResource.new()
		resource.source_files = source_files
		resource.diagnostics = [_diagnostic(project_version_message(project_version))]
	else:
		# Write the .ysls.json and list it in the project's "definitions" before
		# compiling. The ysc fallback reads each function's types from it.
		if options.get("generate_ysls", true):
			_save_ysls_file(generator, source_file)
			_add_ysls_to_definitions(source_file)

		# Try native compiler first
		if YarnNativeCompiler.is_available():
			var result := _compile_native(source_file, abs_path, source_files, _function_declarations(generator, abs_path), CURRENT_PROJECT_FILE_VERSION)
			resource = result.resource
			if resource != null and resource.diagnostics.is_empty():
				_generate_variables_source(source_file, options, result.declarations, result.enums)
			elif resource == null:
				# Native compiler failed — fall through to ysc CLI
				print("yarn project importer: native compiler failed, falling back to ysc CLI")

		if resource == null:
			resource = _compile_ysc(source_file, abs_path, source_files, options)

	_explain_undeclarable_functions(resource, generator, abs_path)

	for diag: Dictionary in resource.diagnostics:
		var location := ""
		if not str(diag.get("file", "")).is_empty():
			location = "%s:%d: " % [diag.file, diag.get("line", 0)]
		push_error("yarn project importer: %s%s" % [location, diag.get("message", "unknown error")])

	## added toolchain fingerprint to the resource before saving
	resource.toolchain = toolchain_fingerprint(options)
	var save_file := save_path + "." + _get_save_extension()
	var save_err := ResourceSaver.save(resource, save_file)

	return save_err


## The definitions file that lists a function by this Yarn name, or "".
## i.e. we find which file declares what function.
static func definitions_file_listing(abs_project_path: String, yarn_name: String) -> String:
	# look at all the definfitions files.
	for path in resolve_definitions_files(abs_project_path):
		# make the file JSON.
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			continue
		# get the functions.
		var functions: Variant = _get_key(data as Dictionary, "functions", [])
		# iterate over the functions to find a match with the yarn_name.
		for info: Variant in functions if functions is Array else []:
			# find the function that matches the yarn_name we want and return its path.
			if info is Dictionary and str(_get_key(info as Dictionary, "yarnName", "")) == yarn_name:
				return path
	return ""


func _explain_undeclarable_functions(resource: YarnProjectResource, generator: YarnYSLSGenerator, abs_path: String) -> void:
	if resource == null or resource.diagnostics.is_empty():
		return
	var scanned: Dictionary = {}
	for info: Dictionary in generator.generate_ysls_dict().get("functions", []):
		scanned[str(info.get("yarnName", ""))] = info
	var pattern := RegEx.create_from_string("no declaration found for ([A-Za-z_][A-Za-z0-9_.]*)")
	var diagnostics: Array = resource.diagnostics
	for i in diagnostics.size():
		var diag: Dictionary = diagnostics[i]
		var found := pattern.search(str(diag.get("message", "")))
		if found == null:
			continue
		var yarn_name := found.get_string(1)
		var reason := undeclarable_reason(scanned.get(yarn_name, {}), yarn_name)
		if not scanned.has(yarn_name):
			var listed_in := definitions_file_listing(abs_path, yarn_name)
			if not listed_in.is_empty():
				reason = "%s is listed in %s, but the compiler couldn't use that entry. Check that every parameter has a type and that it has a return type." % [yarn_name, listed_in]
		if reason.is_empty():
			continue
		diag["message"] = "%s. %s" % [str(diag.get("message", "")).trim_suffix("."), reason]
		diagnostics[i] = diag
	resource.diagnostics = diagnostics


## Why the compiler has no declaration for a function the scan found (or
## didn't find). Empty when the scan has nothing useful to add..
static func undeclarable_reason(info: Dictionary, yarn_name: String) -> String:
	# first we check if the scan found any information for this function)
	if info.is_empty():
		# TODO: we have too many messages, they shoudl be a table of strings somewhere.
		return ("Yarn Spinner didn't find %s in this project's scripts, so the compiler doesn't know its types. " +
			"If you register it with add_function(), the compiler can't see that. Declare it with a _yarn_function_%s method, a YarnCommandBinding, or in a .ysls.json listed in the project's \"definitions\".") % [yarn_name, yarn_name]
	# if we have information, we construct a description of where it was found.
	var where := "%s in %s" % [info.get("definitionName", yarn_name), info.get("fileName", "its script")]
	# we include the definition name and file name to help the user locate the function.
	# so we iterate over the parameters to check if any of them lack a usable type..
	for param: Dictionary in info.get("parameters", []):
		# if the parameter has a type other than "any", we can skip it (because it's usable)
		if str(param.get("type", "any")) != "any":
			continue
		# and if it's a variadic parameter with no type, we can't check calls to it..
		if param.get("isParamsArray", false):
			return ("The function %s (%s) takes extra arguments (...%s) with no type, so the compiler can't check calls to it. " +
				"Add a line like ## @yarn_variadic number to its ## comment (string, bool, node and enum <Name> work too).") % [yarn_name, where, param.get("name", "args")]
		return ("The function %s (%s) has a parameter, %s, with no type Yarn can use, so the compiler can't check calls to it. " +
			"Give it a type, for example %s: String.") % [yarn_name, where, param.get("name", "?"), param.get("name", "value")]
	# if we get here, all parameters have usable types, so we check the return type next.
	var return_info: Variant = info.get("return", {})
	# if the return type is "any" or not specified, we can't check calls to this function.
	# per internal YS discussions, a return type of "any" is considered unusable
	# even tho Godot could technically handle an "any" return type, Yarn Spinner treats it as unusable for type checking.
	if return_info is Dictionary and str((return_info as Dictionary).get("type", "any")) == "any":
		return ("The function %s (%s) doesn't declare a return type Yarn can use, so the compiler can't check calls to it. " +
			"Give it a typed return, for example -> String, and if it needs to wait, await inside it rather than returning a Signal.") % [yarn_name, where]
	return ""



func _run_ysc(ysc_path: String, project_path: String, temp_dir: String, output_name: String, output: Array) -> int:
	var args := PackedStringArray([
		"compile",
		project_path,
		"-o", temp_dir,
		"-n", output_name,
	])
	# ysc otherwise guesses ${workspaceRoot} by looking for engine project files
	var previous := OS.get_environment(YSC_WORKSPACE_ROOT_ENV)
	OS.set_environment(YSC_WORKSPACE_ROOT_ENV, workspace_root())
	var exit_code := OS.execute(ysc_path, args, output, true)
	if previous.is_empty():
		OS.unset_environment(YSC_WORKSPACE_ROOT_ENV)
	else:
		OS.set_environment(YSC_WORKSPACE_ROOT_ENV, previous)
	return exit_code



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


## Compares major.minor.patch only!
## this is used to check if the installed ysc version meets the minimum required version.
static func ysc_version_supported(version: String) -> bool:
	# strip any prerelease or build metadata from the version string as it was breaking things
	var have := version.get_slice("-", 0).split(".")

	var need := MIN_YSC_VERSION.split(".")

	for i in need.size():
		var a := int(have[i]) if i < have.size() else 0
		var b := int(need[i])
		if a != b:
			return a > b
	return true

## The start of a ncier message system, in some ways.
## Returns a user-friendly message about the project file version.
static func project_version_message(version: int) -> String:
	if version <= 0:
		return ("This Yarn Project doesn't say which file version it uses. Yarn Spinner for Godot needs file version %d. " +
			"Set \"projectFileVersion\": %d in the .yarnproject, or use Upgrade Yarn Project in the Inspector, then reimport.") % [CURRENT_PROJECT_FILE_VERSION, CURRENT_PROJECT_FILE_VERSION]
	if version > CURRENT_PROJECT_FILE_VERSION:
		return "This Yarn Project uses file version %d, which is newer than this version of Yarn Spinner for Godot supports (%d). Update Yarn Spinner for Godot to use it." % [version, CURRENT_PROJECT_FILE_VERSION]
	return ("This Yarn Project uses file version %d, and Yarn Spinner for Godot needs file version %d. " +
		"Use Upgrade Yarn Project in the Inspector, or set \"projectFileVersion\": %d in the .yarnproject, then reimport.") % [version, CURRENT_PROJECT_FILE_VERSION, CURRENT_PROJECT_FILE_VERSION]


## The first definitions file listed in the project that isn't valid JSON, as
## { path, error }, or an empty dictionary when they all parse..
static func broken_definitions_file(abs_project_path: String) -> Dictionary:
	# Return an empty dictionary if the project path is empty.
	if abs_project_path.is_empty():
		return {}
	# Check each definitions file for validity.
	# we do this by attempting to parse each file as JSON.
	# and returning the first one that fails.
	for path in resolve_definitions_files(abs_project_path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK:
			return {"path": path, "error": "%s at line %d" % [json.get_error_message(), json.get_error_line() + 1]}
	return {}


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


static func explain_ysc_failure(output_text: String, label: String, abs_project_path: String = "") -> String:
	var update := "Update ysc with: %s." % YSC_UPDATE_COMMAND

	if output_text.contains("JsonReaderException") or output_text.contains("JsonException"):
		var broken := broken_definitions_file(abs_project_path)
		if not broken.is_empty():
			return "%s couldn't read the definitions file %s, because it isn't valid JSON: %s. Fix the JSON in that file, then reimport." % [label, broken["path"], broken["error"]]

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

	if output_text.contains("has invalid JSON"):
		return "%s couldn't read this Yarn Project. It's probably older than the format the project uses. %s" % [label, update]

	# Check for functions with untyped parameters.
	# which are a problem in older versions of ysc?
	# this regex looks for the string that ysc outputs when it encounters an untyped parameter. 
	# TODO: is there a better way of doing this?
	# the syntax of the call to RegEx.create_from_string is: RegEx.create_from_string(pattern: String) -> RegEx
	var untyped := RegEx.create_from_string("Error in function (\\S+): Parameter has an unresolved type of \"any\"").search(output_text)
	if untyped != null:
		return "%s stopped because the function %s has a parameter with no type. Give that parameter a type, or update ysc to 3.3.4 or later, which reports this only where the function is called. %s" % [
			label, untyped.get_string(1), update]

	if output_text.contains("KeyNotFoundException") and output_text.contains("Yarn.Compiler.Definitions"):
		return "%s couldn't read one of the definitions files listed in this Yarn Project. Versions of ysc before 3.3.4 need every key in lower camelCase (\"yarnName\", not \"YarnName\") and stop when a key is missing. %s" % [label, update]

	if output_text.contains("Unhandled exception") or output_text.contains("Failed to compile because of the following error"):
		return "%s crashed while compiling, so this is a problem with ysc, not with your Yarn scripts. %s" % [label, update]

	return ""


func _compile_ysc(source_file: String, abs_path: String, source_files: PackedStringArray, options: Dictionary) -> YarnProjectResource:
	# for 3.3.4+ we no longer copy a project, but we use tehe real one
	# and we only support v5...
	var resource := YarnProjectResource.new()
	resource.source_files = source_files

	var ysc_path: String = _find_ysc_path(options)

	if ysc_path.is_empty():
		resource.diagnostics = [_diagnostic("No compiler is available. The bundled compiler isn't there for %s on %s, and ysc isn't installed. Reinstall the addons folder from a Yarn Spinner for Godot release, or install ysc with: dotnet tool install -g YarnSpinner.Console" % [OS.get_name(), Engine.get_architecture_name()])]
		return resource

	var version := ysc_version(ysc_path)
	var label := ysc_label(ysc_path, version)
	if version.is_empty():
		push_warning("yarn project importer: couldn't tell which version %s is. Yarn Spinner for Godot needs ysc %s or later, so compiling may fail. Update ysc with: %s" % [label, MIN_YSC_VERSION, YSC_UPDATE_COMMAND])
	elif not ysc_version_supported(version):
		resource.diagnostics = [_diagnostic("%s is too old. Yarn Spinner for Godot needs ysc %s or later. Update it with: %s. %s" % [label, MIN_YSC_VERSION, YSC_UPDATE_COMMAND, native_compiler_status()])]
		return resource
	print("yarn project importer: using %s" % label)

	for entry in definition_entries(YarnProjectUtility.read_project_json(abs_path)):
		var trimmed := entry.strip_edges()
		if trimmed.begins_with("res://"):
			push_warning("yarn project importer: %s lists the definitions file \"%s\", but ysc can't read res:// paths, so it's ignored. Use \"%s/%s\" instead." % [source_file, entry, WORKSPACE_ROOT_PLACEHOLDER, trimmed.trim_prefix("res://")])
		elif trimmed.begins_with("user://"):
			push_warning("yarn project importer: %s lists the definitions file \"%s\", but ysc can't read user:// paths, so it's ignored. Use a path relative to the .yarnproject, or one starting with %s." % [source_file, entry, WORKSPACE_ROOT_PLACEHOLDER])

	var temp_dir := OS.get_temp_dir().path_join("yarn_spinner_compile")
	DirAccess.make_dir_recursive_absolute(temp_dir)

	var output_name := source_file.get_file().get_basename()

	var output: Array = []
	var exit_code := _run_ysc(ysc_path, abs_path, temp_dir, output_name, output)

	if exit_code != 0:
		if exit_code == 127:
			resource.diagnostics = [_diagnostic("ysc not found at '%s'. Install it with: dotnet tool install -g YarnSpinner.Console" % ysc_path)]
			return resource
		var output_text := ""
		for chunk in output:
			output_text += str(chunk)
		var explanation := explain_ysc_failure(output_text, label, abs_path)
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


## Identifies the installed compilers by path and modification time, so
## installing, updating or swapping either one changes it...
## TODO: figure out if we can do some sort of sub-asset thing like Unity?
## TODO: also look at turning it into a dependencies record, with the source, definitions, etc.? And hash at compilation time? Something like that.
static func toolchain_fingerprint(options: Dictionary) -> String:
	## the way this works is it records the modification times of the native compiler and the ysc compiler, so any changes to these files will result in a different fingerprint..
	var parts := PackedStringArray()
	var native_path := YarnNativeCompiler.get_native_bin_path()
	if not native_path.is_empty():
		var abs_native := ProjectSettings.globalize_path(native_path)
		parts.append("native:%d" % (FileAccess.get_modified_time(abs_native) if FileAccess.file_exists(abs_native) else 0))
	var ysc_path := _find_ysc_path(options)
	parts.append("ysc:%s@%d" % [ysc_path, FileAccess.get_modified_time(ysc_path) if not ysc_path.is_empty() else 0])
	return "|".join(parts)


static func _find_ysc_path(options: Dictionary) -> String:
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
static func _function_declarations(generator: YarnYSLSGenerator, abs_project_path: String) -> Array[Dictionary]:
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
				if parameter.has("subtype"):
					declaration["variadicParameterType"] = {"type": parameter_type, "subtype": str(parameter["subtype"])}
				else:
					declaration["variadicParameterType"] = parameter_type
				break
			# same shape as _declaration_from_definition, so both routes declare defaults alike
			if parameter.has("subtype") or parameter.has("defaultValue"):
				var entry := {"name": str(parameter.get("name", "")), "type": parameter_type}
				if parameter.has("subtype"):
					entry["subtype"] = str(parameter["subtype"])
				if parameter.has("defaultValue"):
					entry["defaultValue"] = true
				declaration["parameters"].append(entry)
			else:
				declaration["parameters"].append(parameter_type)
		declarations.append(declaration)
		declared[yarn_name] = true

	for declaration: Dictionary in definitions_function_declarations(abs_project_path):
		if declared.has(declaration["name"]):
			continue
		declarations.append(declaration)
		declared[declaration["name"]] = true

	return declarations



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


static func definitions_function_declarations(abs_project_path: String) -> Array[Dictionary]:
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
			push_warning("yarn project importer: couldn't read the definitions file %s: %s at line %d" % [path, json.get_error_message(), json.get_error_line() + 1])
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
			var declaration := _declaration_from_definition(info as Dictionary)
			if declaration.is_empty() or declared.has(declaration["name"]):
				continue
			declared[declaration["name"]] = true
			declarations.append(declaration)
	return declarations


static func _declaration_from_definition(info: Dictionary) -> Dictionary:
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

	var entry_to_add := WORKSPACE_ROOT_PLACEHOLDER + "/" + (yarn_project_path.get_basename() + ".ysls.json").trim_prefix("res://")
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
