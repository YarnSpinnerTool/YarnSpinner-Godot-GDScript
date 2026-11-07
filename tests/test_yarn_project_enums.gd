extends GutTest


const Importer := preload("res://addons/yarn_spinner/editor/yarn_project_importer.gd")

const SOURCE := """title: Start
---
<<enum Item>>
    <<case Nothing = "nothing">>
    <<case BrassKey = "brass key">>
<<endenum>>
<<enum Door>>
    <<case Locked>>
    <<case Open>>
<<endenum>>
<<declare $held = Item.Nothing>>
<<declare $door = Door.Locked>>
<<declare $count = 0>>
Line.
===
"""


func _project() -> YarnProjectResource:
	var files: Array[Dictionary] = [{"fileName": "Test.yarn", "source": SOURCE}]
	var result := YarnNativeCompiler.compile(files)
	var resource := YarnProjectResource.new()
	resource.enums = Importer._enums_from_result(result.get("enums", []))
	resource.variable_types = Importer._variable_types_from_result(result.get("declarations", []))
	return resource


func test_enums_are_stored_with_their_cases() -> void:
	if not YarnNativeCompiler.is_available():
		pending("The native compiler isn't available on this platform.")
		return
	var project := _project()
	assert_true(project.has_enum("Item"))
	assert_true(project.has_enum("Door"))
	assert_false(project.has_enum("Room"))
	var names: Array = project.get_enum_cases("Item").map(func(entry: Dictionary) -> String: return entry.name)
	assert_eq(names, ["Nothing", "BrassKey"])
	assert_eq(project.enums["Item"].raw_type, "String")
	assert_eq(project.enums["Door"].raw_type, "Number")


func test_enum_values_and_case_names() -> void:
	if not YarnNativeCompiler.is_available():
		pending("The native compiler isn't available on this platform.")
		return
	var project := _project()
	assert_eq(project.get_enum_value("Item", "BrassKey"), "brass key")
	assert_eq(project.get_enum_value("Door", "Open"), 1.0)
	assert_null(project.get_enum_value("Door", "Ajar"))
	assert_eq(project.get_enum_case_name("Item", "brass key"), "BrassKey")
	assert_eq(project.get_enum_case_name("Door", 1), "Open")
	assert_eq(project.get_enum_case_name("Door", 0.0), "Locked")
	assert_eq(project.get_enum_case_name("Door", "1"), "")


func test_variable_types() -> void:
	if not YarnNativeCompiler.is_available():
		pending("The native compiler isn't available on this platform.")
		return
	var project := _project()
	assert_eq(project.get_variable_type("$held"), "Item")
	assert_eq(project.get_variable_type("$door"), "Door")
	assert_eq(project.get_variable_type("$count"), "Number")
	assert_eq(project.get_variable_type("$missing"), "")
