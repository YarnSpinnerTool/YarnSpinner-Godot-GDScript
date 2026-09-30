# ======================================================================== #
#                    Yarn Spinner for Godot (GDScript)                     #
# ======================================================================== #
#                                                                          #
# Native compiler bridge — calls the bundled NativeAOT Yarn Spinner       #
# compiler binary. Editor-only; not needed at runtime.                     #
#                                                                          #
# Falls back to the system `ysc` tool if the native binary isn't found.    #
#                                                                          #
# ======================================================================== #

class_name YarnNativeCompiler
extends RefCounted
## Wrapper for the bundled native Yarn Spinner compiler.
## Editor-only — used by the importer to compile .yarn files without
## requiring the ysc CLI tool or .NET runtime on the user's machine.


const NATIVE_BIN_PATHS := {
	"macos": "res://addons/yarn_spinner/native/bin/ysc-native",
	"windows": "res://addons/yarn_spinner/native/bin/ysc-native.exe",
	"linux": "res://addons/yarn_spinner/native/bin/ysc-native-linux",
}


## Returns the path to the native compiler binary for this platform.
static func get_native_bin_path() -> String:
	var os_name := OS.get_name().to_lower()
	if os_name == "macos" or os_name == "osx":
		return NATIVE_BIN_PATHS.get("macos", "")
	elif os_name == "windows":
		return NATIVE_BIN_PATHS.get("windows", "")
	elif os_name == "linux" or os_name.contains("bsd"):
		return NATIVE_BIN_PATHS.get("linux", "")
	return ""


## Returns true if the native compiler binary is available.
static func is_available() -> bool:
	var res_path := get_native_bin_path()
	if res_path.is_empty():
		return false
	var abs_path := ProjectSettings.globalize_path(res_path)
	return FileAccess.file_exists(abs_path)


## Compile Yarn source files using the native compiler.
##
## Input: array of dictionaries [{ "fileName": "X.yarn", "source": "..." }]
## declarations (optional): functions the game provides, so the compiler
##   knows their types, as [{ name, parameters: [type, ...], returnType,
##   variadicParameterType (optional), description (optional) }]. Types are
##   "string", "number", "bool" or "any". Entries with a missing or "any"
##   return type are ignored.
## Returns: Dictionary with:
##   success: bool
##   program: PackedByteArray (compiled protobuf, empty on error)
##   compiler_failed: bool (the compiler could not run, as opposed to reporting errors)
##   string_table: Dictionary { line_id: { text, nodeName, lineNumber, fileName, isImplicitTag, metadata } }
##   declarations: Array of { name, type, isEnum, description, isInlineExpansion, sourceFileName, defaultValue }
##   enums: Array of { name, description, rawType, cases: [{ name, description, value }] }
##   diagnostics: Array of { message, severity, fileName, line, column, code }
static func compile(files: Array[Dictionary], declarations: Array[Dictionary] = []) -> Dictionary:
	if not is_available():
		return _error_result("Native compiler not available for this platform")

	var bin_path := ProjectSettings.globalize_path(get_native_bin_path())

	# Build input JSON
	var input := {"files": files}
	if not declarations.is_empty():
		input["declarations"] = declarations
	var input_json := JSON.stringify(input)

	return _parse_result(_run_via_pipe(bin_path, input_json))


static func tag_lines(files: Array[Dictionary], excluded_line_ids: PackedStringArray = PackedStringArray(), tagger: String = "random") -> Dictionary:
	if not is_available():
		return {"success": false, "files": [], "errors": [{"message": "Native compiler not available for this platform", "fileName": "", "line": -1}]}

	var bin_path := ProjectSettings.globalize_path(get_native_bin_path())
	var input := {
		"command": "tag",
		"files": files,
		"excludedLineIDs": Array(excluded_line_ids),
		"tagger": tagger,
	}
	var output := _run_via_pipe(bin_path, JSON.stringify(input))
	if output.has("error"):
		return {"success": false, "files": [], "errors": [{"message": output.error, "fileName": "", "line": -1}]}

	var json := JSON.new()
	if json.parse(output.json) != OK or not json.data is Dictionary:
		return {"success": false, "files": [], "errors": [{"message": "Failed to parse compiler output: %s" % json.get_error_message(), "fileName": "", "line": -1}]}

	var data: Dictionary = json.data
	if not data.has("files"):
		return {"success": false, "files": [], "errors": [{"message": "The bundled compiler is out of date and can't add line tags. Rebuild it with native/build.sh.", "fileName": "", "line": -1}]}
	return {
		"success": data.get("success", false),
		"files": data.get("files", []),
		"errors": data.get("errors", []),
	}


## Feed the input JSON to the binary's stdin.
static func _run_via_pipe(bin_path: String, input_json: String) -> Dictionary:
	# The binary reads its job from stdin, and OS.execute can't write to a
	# child's stdin, so the JSON goes into a temp file that the shell
	# redirects. The filename includes the process id and a timestamp so
	# concurrent editor instances sharing one cache dir don't race.
	var temp_path := OS.get_cache_dir().path_join(
		"yarn_compile_input_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		return {"error": "Failed to create temp file: %s" % error_string(FileAccess.get_open_error())}
	temp_file.store_string(input_json)
	temp_file.close()

	var output := []
	var exit_code: int
	var os_name := OS.get_name().to_lower()

	if os_name == "windows":
		# Args are passed separately; Godot's process launcher quotes any
		# argument containing spaces, so paths survive cmd's parsing.
		exit_code = OS.execute("cmd.exe", ["/c", "type", temp_path, "|", bin_path], output, true, false)
	else:
		# Both paths are single-quoted for the shell (embedded quotes
		# escaped), so spaces and metacharacters in either path can't
		# break or inject into the command.
		var cmd := "exec %s < %s" % [_shell_quote(bin_path), _shell_quote(temp_path)]
		exit_code = OS.execute("/bin/sh", ["-c", cmd], output, true, false)

	DirAccess.remove_absolute(temp_path)

	if output.is_empty():
		return {"error": "Native compiler produced no output (exit code %d)" % exit_code}

	var result_json: String = output[0] if output[0] is String else str(output[0])
	if exit_code != 0:
		return {"error": _first_diagnostic_message(result_json, exit_code)}
	return {"json": result_json}


static func _first_diagnostic_message(result_json: String, exit_code: int) -> String:
	var json := JSON.new()
	if json.parse(result_json) == OK and json.data is Dictionary:
		var diagnostics: Array = (json.data as Dictionary).get("diagnostics", [])
		if not diagnostics.is_empty() and diagnostics[0] is Dictionary:
			return str((diagnostics[0] as Dictionary).get("message", ""))
	return "Native compiler failed (exit code %d)" % exit_code


## Wrap a string in single quotes for POSIX sh, escaping embedded quotes.
static func _shell_quote(s: String) -> String:
	return "'" + s.replace("'", "'\\''") + "'"


static func _parse_result(output: Dictionary) -> Dictionary:
	if output.has("error"):
		return _error_result(output.error)

	var json := JSON.new()
	var err := json.parse(output.json)
	if err != OK:
		return _error_result("Failed to parse compiler output: %s" % json.get_error_message())

	var data: Dictionary = json.data
	var result := {
		"success": data.get("success", false),
		"compiler_failed": false,
		"program": PackedByteArray(),
		"string_table": data.get("stringTable", {}),
		"declarations": data.get("declarations", []),
		"enums": data.get("enums", []),
		"diagnostics": data.get("diagnostics", []),
	}

	var program_b64: Variant = data.get("program")
	if program_b64 is String and not (program_b64 as String).is_empty():
		result["program"] = Marshalls.base64_to_raw(program_b64)

	return result


static func _error_result(message: String) -> Dictionary:
	return {
		"success": false,
		"compiler_failed": true,
		"program": PackedByteArray(),
		"string_table": {},
		"declarations": [],
		"enums": [],
		"diagnostics": [{"message": message, "severity": "error", "fileName": "", "line": -1, "column": -1, "code": ""}],
	}
