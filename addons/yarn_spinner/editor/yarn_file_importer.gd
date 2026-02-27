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
## imports .yarn files as resources so they can be opened in the editor.

func _get_importer_name() -> String:
	return "yarn_spinner.yarn_file"


func _get_visible_name() -> String:
	return "Yarn Script"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["yarn"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset_index: int) -> String:
	return "Default"


func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return []


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var resource := YarnScriptResource.new()
	resource.source_path = source_file

	var file := FileAccess.open(source_file, FileAccess.READ)
	if file:
		resource.content = file.get_as_text()
		file.close()

	var save_file := save_path + "." + _get_save_extension()
	return ResourceSaver.save(resource, save_file)
