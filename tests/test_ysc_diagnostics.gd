extends GutTest


const Importer := preload("res://addons/yarn_spinner/editor/yarn_project_importer.gd")
const LABEL := "ysc 3.2.2 (/home/someone/.dotnet/tools/ysc)"


func test_parse_ysc_version():
	assert_eq(Importer.parse_ysc_version("3.2.2+0.Branch.main.Sha.5bea62a809f2505e1806adc1b86a822c758bfd03\n"), "3.2.2")
	assert_eq(Importer.parse_ysc_version("3.3.0+Branch.main.Sha.303a5de22aa24a13e2974bc8e394852bbfa084cd"), "3.3.0")
	assert_eq(Importer.parse_ysc_version("3.1.0+11.Branch.main.Sha.1c16cf302bd560971cf7b84b08ecdfb5709acf28"), "3.1.0")
	assert_eq(Importer.parse_ysc_version("0.0.0+0.Branch.unknown.Sha.0000000000000000000000000000000000000000"), "")
	assert_eq(Importer.parse_ysc_version("You must install or update .NET to run this application."), "")
	assert_eq(Importer.parse_ysc_version(""), "")


func test_ysc_label():
	assert_eq(Importer.ysc_label("/usr/bin/ysc", "3.3.0"), "ysc 3.3.0 (/usr/bin/ysc)")
	assert_eq(Importer.ysc_label("/usr/bin/ysc", ""), "ysc (/usr/bin/ysc)")


func test_explains_duplicate_declaration():
	var output := "🚨 ERROR: Failed to compile because of the following error:\nSystem.ArgumentException: An item with the same key has already been added. Key: visited\n   at Yarn.Compiler.Compiler.Compile(CompilationJob compilationJob)\n"
	var message := Importer.explain_ysc_failure(output, LABEL)
	assert_string_contains(message, LABEL)
	assert_string_contains(message, "visited is declared twice")
	assert_string_contains(message, Importer.YSC_UPDATE_COMMAND)


func test_explains_project_file_version():
	var output := "Unhandled exception: System.ArgumentException: Project file at /p/Test.yarnproject has incorrect file version (expected 4, got 5)\n"
	var message := Importer.explain_ysc_failure(output, LABEL)
	assert_string_contains(message, "up to file version 4, and this one is version 5")
	assert_string_contains(message, Importer.YSC_UPDATE_COMMAND)


func test_explains_missing_dotnet_runtime():
	var output := "You must install or update .NET to run this application.\n\nApp: /home/someone/.dotnet/tools/ysc\nArchitecture: x64\nFramework: 'Microsoft.NETCore.App', version '9.0.11' (x64)\n"
	var message := Importer.explain_ysc_failure(output, LABEL)
	assert_string_contains(message, "needs version 9.0.11 of the .NET runtime")
	assert_string_contains(message, "Install .NET 9,")
	assert_string_contains(message, Importer.YSC_UPDATE_COMMAND)


func test_explains_unreadable_project():
	var output := "Unhandled exception: System.ArgumentException: Project file at /p/Test.yarnproject has invalid JSON\n"
	assert_string_contains(Importer.explain_ysc_failure(output, LABEL), "couldn't read this Yarn Project")


func test_explains_other_crashes():
	var output := "Unhandled exception: System.InvalidOperationException: Something odd\n"
	assert_string_contains(Importer.explain_ysc_failure(output, LABEL), "a problem with ysc, not with your Yarn scripts")


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _find_function(functions: Array, key: String, yarn_name: String) -> Dictionary:
	for entry: Dictionary in functions:
		if entry.get(key, "") == yarn_name:
			return entry
	return {}


func _copy_definitions(project_version: int) -> Dictionary:
	var dir := ProjectSettings.globalize_path("user://ysc_copy_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var project_path := dir.path_join("Test.yarnproject")
	_write(dir.path_join("Generated.ysls.json"), JSON.stringify({
		"version": 2,
		"commands": [{"yarnName": "wait", "parameters": [{"name": "duration", "type": "number"}]}],
		"functions": [
			{"yarnName": "gold", "parameters": [], "return": {"type": "number"}},
			{"yarnName": "go", "parameters": [{"name": "where", "type": "node"}], "return": {"type": "bool"}},
			{"yarnName": "loose", "parameters": [{"name": "thing", "type": "any"}], "return": {"type": "bool"}},
			{"yarnName": "pet", "parameters": [{"name": "target", "type": "instance", "subtype": "Pet"}], "return": {"type": "string"}},
		],
	}))
	_write(dir.path_join("Old.ysls.json"), JSON.stringify({
		"Functions": [{"YarnName": "legacy", "Parameters": [{"Name": "a", "Type": "string"}], "ReturnType": "bool", "Documentation": ""}],
	}))
	_write(project_path, JSON.stringify({"projectFileVersion": project_version, "sourceFiles": ["*.yarn"], "definitions": ["Generated.ysls.json", "Old.ysls.json"]}))

	var copy := Importer._write_ysc_project_copy(project_path, dir, "Test")
	var result := {"copy": copy}
	result["project"] = JSON.parse_string(FileAccess.get_file_as_string(copy["project"]))
	result["definitions_text"] = FileAccess.get_file_as_string(result["project"]["definitions"][0])
	result["definitions"] = JSON.parse_string(result["definitions_text"])

	for path: String in copy["files"]:
		DirAccess.remove_absolute(path)
	result["removed"] = not FileAccess.file_exists(copy["project"])
	for name in ["Test.yarnproject", "Generated.ysls.json", "Old.ysls.json"]:
		DirAccess.remove_absolute(dir.path_join(name))
	return result


func test_ysc_project_copy_declares_what_the_bundled_compiler_declares():
	var result := _copy_definitions(5)
	var copy: Dictionary = result["copy"]
	assert_eq(copy["project"], ProjectSettings.globalize_path("user://ysc_copy_test").path_join(".Test.ysc.yarnproject"))
	assert_eq(result["project"]["sourceFiles"], ["*.yarn"])
	assert_eq(result["project"]["definitions"].size(), 1)
	assert_true(result["removed"])

	var definitions: Dictionary = result["definitions"]
	assert_eq(definitions["commands"], [])
	assert_true(result["definitions_text"].contains("\"version\": 2,"))
	var functions: Array = definitions["functions"]
	assert_eq(_find_function(functions, "yarnName", "gold")["return"], {"type": "number"})
	assert_eq(_find_function(functions, "yarnName", "go")["parameters"][0]["type"], "string")
	assert_true(_find_function(functions, "yarnName", "loose").is_empty())
	assert_eq(_find_function(functions, "yarnName", "pet")["parameters"][0]["type"], "instance")
	assert_eq(_find_function(functions, "yarnName", "legacy")["parameters"][0]["type"], "string")

	var legacy: Array = definitions["Functions"]
	assert_eq(legacy.size(), functions.size())
	assert_eq(_find_function(legacy, "YarnName", "gold")["ReturnType"], "number")
	assert_eq(_find_function(legacy, "YarnName", "go")["Parameters"][0]["Type"], "string")


func test_ysc_project_copy_leaves_out_instance_parameters_before_version_5():
	var functions: Array = _copy_definitions(4)["definitions"]["functions"]
	assert_true(_find_function(functions, "yarnName", "pet").is_empty())
	assert_false(_find_function(functions, "yarnName", "gold").is_empty())


func test_ysc_project_copy_skips_projects_without_definitions():
	var dir := ProjectSettings.globalize_path("user://ysc_copy_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var project_path := dir.path_join("Plain.yarnproject")
	_write(project_path, JSON.stringify({"projectFileVersion": 5, "sourceFiles": ["*.yarn"]}))
	assert_eq(Importer._write_ysc_project_copy(project_path, dir, "Plain"), {})
	DirAccess.remove_absolute(project_path)


func test_compiler_parameter_type():
	assert_eq(Importer.compiler_parameter_type("node"), "string")
	assert_eq(Importer.compiler_parameter_type("Boolean"), "bool")
	assert_eq(Importer.compiler_parameter_type("number"), "number")
	assert_eq(Importer.compiler_parameter_type("enum"), "enum")


func test_leaves_script_errors_alone():
	var output := "🚨 ERROR: /p/Test.yarn: 2:18 Syntax error: Unexpected \">>\" while reading an expression\n⚠️ WARNING: /p/Test.yarn: 3:7 Variable '$nope' is used but not declared. Declare it with: <<declare $nope = value>>\n"
	assert_eq(Importer.explain_ysc_failure(output, LABEL), "")
