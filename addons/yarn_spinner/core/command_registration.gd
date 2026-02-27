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

extends RefCounted
## Handles registration and discovery of yarn commands and functions.

var _registered_instances: Array[Object] = []


func register_instance(instance: Object, library: YarnLibrary) -> void:
	if instance in _registered_instances:
		return

	_registered_instances.append(instance)

	var methods := _get_yarn_methods(instance)

	for method_info in methods.commands:
		var callable := Callable(instance, method_info.method_name)
		library.register_command(method_info.yarn_name, callable)

	for method_info in methods.functions:
		var callable := Callable(instance, method_info.method_name)
		library.register_function(method_info.yarn_name, callable, method_info.param_count)


func unregister_instance(instance: Object, library: YarnLibrary) -> void:
	var index := _registered_instances.find(instance)
	if index < 0:
		return

	_registered_instances.remove_at(index)

	var methods := _get_yarn_methods(instance)

	for method_info in methods.commands:
		library.unregister_command(method_info.yarn_name)

	for method_info in methods.functions:
		library.unregister_function(method_info.yarn_name)


## Discovers _yarn_command_ and _yarn_function_ prefixed methods, and _get_yarn_commands()/_get_yarn_functions().
func _get_yarn_methods(instance: Object) -> Dictionary:
	var commands: Array[Dictionary] = []
	var functions: Array[Dictionary] = []

	var script: Script = instance.get_script()
	if script == null:
		return {"commands": commands, "functions": functions}

	for method in script.get_script_method_list():
		var method_name: String = method.name

		if method_name.begins_with("_yarn_command_"):
			var yarn_name := method_name.substr(14)  # remove prefix
			commands.append({
				"method_name": method_name,
				"yarn_name": yarn_name
			})

		elif method_name.begins_with("_yarn_function_"):
			var yarn_name := method_name.substr(15)  # remove prefix
			var param_count: int = method.args.size()
			functions.append({
				"method_name": method_name,
				"yarn_name": yarn_name,
				"param_count": param_count
			})

	if instance.has_method("_get_yarn_commands"):
		var custom_commands: Dictionary = instance.call("_get_yarn_commands")
		for yarn_name in custom_commands:
			var method_name: String = custom_commands[yarn_name]
			commands.append({
				"method_name": method_name,
				"yarn_name": yarn_name
			})

	if instance.has_method("_get_yarn_functions"):
		var custom_functions: Dictionary = instance.call("_get_yarn_functions")
		for yarn_name in custom_functions:
			var info: Variant = custom_functions[yarn_name]
			var method_name: String = info.method if info is Dictionary else info
			var param_count: int = info.params if info is Dictionary and info.has("params") else -1
			functions.append({
				"method_name": method_name,
				"yarn_name": yarn_name,
				"param_count": param_count
			})

	return {"commands": commands, "functions": functions}
