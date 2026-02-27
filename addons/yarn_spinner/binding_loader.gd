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

@icon("res://addons/yarn_spinner/icons/binding_loader.svg")
class_name YarnBindingLoader
extends Node
## Registers Yarn command and function bindings with a dialogue runner.
## Configure bindings in the inspector to connect Yarn commands to methods
## on scene nodes.


signal bindings_registered
signal binding_failed(binding: YarnCommandBinding, reason: String)

## auto-discovers sibling/parent if not set
@export var dialogue_runner: YarnDialogueRunner
@export var bindings: Array[YarnCommandBinding] = []

@export_group("Behaviour")

@export var auto_register: bool = true
@export var auto_find_runner: bool = true
@export var unregister_on_exit: bool = true

@export_group("Debugging")

@export var verbose: bool = false


var _registered_commands: PackedStringArray = []
var _registered_functions: PackedStringArray = []


func _ready() -> void:
	if auto_find_runner and dialogue_runner == null:
		dialogue_runner = _find_dialogue_runner()

	if auto_register:
		call_deferred("register_all")


func _exit_tree() -> void:
	if unregister_on_exit:
		unregister_all()


## Safe to call multiple times - already registered bindings are skipped.
func register_all() -> void:
	if dialogue_runner == null:
		push_error("YarnBindingLoader: No dialogue runner - cannot register bindings")
		return

	var success_count := 0
	var fail_count := 0

	for binding in bindings:
		if _register_binding(binding):
			success_count += 1
		else:
			fail_count += 1

	if verbose:
		print("YarnBindingLoader: Registered %d bindings (%d failed)" % [success_count, fail_count])

	bindings_registered.emit()


func unregister_all() -> void:
	if dialogue_runner == null:
		return

	for cmd_name in _registered_commands:
		dialogue_runner.remove_command(cmd_name)

	for func_name in _registered_functions:
		dialogue_runner.remove_function(func_name)

	if verbose and (_registered_commands.size() > 0 or _registered_functions.size() > 0):
		print("YarnBindingLoader: Unregistered %d commands, %d functions" % [
			_registered_commands.size(), _registered_functions.size()
		])

	_registered_commands.clear()
	_registered_functions.clear()


func register_binding(binding: YarnCommandBinding) -> bool:
	return _register_binding(binding)


## param_count is only used for functions; commands determine it at runtime.
func add_binding(yarn_name: String, type: YarnCommandBinding.Type, target: Node, method: String, param_count: int = 0) -> bool:
	var binding := YarnCommandBinding.new()
	binding.yarn_name = yarn_name
	binding.type = type
	binding.target_node = get_path_to(target)
	binding.method_name = method
	binding.parameter_count = param_count
	bindings.append(binding)
	return _register_binding(binding)


func remove_binding(yarn_name: String) -> void:
	if dialogue_runner == null:
		return

	for i in range(bindings.size() - 1, -1, -1):
		if bindings[i].yarn_name == yarn_name:
			var binding := bindings[i]
			bindings.remove_at(i)

			match binding.type:
				YarnCommandBinding.Type.COMMAND:
					dialogue_runner.remove_command(yarn_name)
					var idx := _registered_commands.find(yarn_name)
					if idx >= 0:
						_registered_commands.remove_at(idx)
				YarnCommandBinding.Type.FUNCTION:
					dialogue_runner.remove_function(yarn_name)
					var idx := _registered_functions.find(yarn_name)
					if idx >= 0:
						_registered_functions.remove_at(idx)

			if verbose:
				print("YarnBindingLoader: Removed binding '%s'" % yarn_name)
			return


func has_binding(yarn_name: String) -> bool:
	return yarn_name in _registered_commands or yarn_name in _registered_functions


func get_registered_count() -> int:
	return _registered_commands.size() + _registered_functions.size()


func get_debug_info() -> String:
	var lines := PackedStringArray()
	lines.append("=== YarnBindingLoader ===")
	lines.append("Dialogue Runner: %s" % (dialogue_runner.name if dialogue_runner else "None"))
	lines.append("")
	lines.append("Commands (%d):" % _registered_commands.size())
	for cmd in _registered_commands:
		lines.append("  - %s" % cmd)
	lines.append("")
	lines.append("Functions (%d):" % _registered_functions.size())
	for fn in _registered_functions:
		lines.append("  - %s" % fn)
	return "\n".join(lines)


func _register_binding(binding: YarnCommandBinding) -> bool:
	if not binding.enabled:
		return false

	if not binding.is_valid():
		var reason := "Invalid binding configuration"
		_emit_failure(binding, reason)
		return false

	var already_registered := binding.yarn_name in _registered_commands or binding.yarn_name in _registered_functions
	if already_registered:
		if verbose:
			print("YarnBindingLoader: Skipping '%s' (already registered)" % binding.yarn_name)
		return true

	var target := get_node_or_null(binding.target_node)
	if target == null:
		var reason := "Target node not found: %s" % binding.target_node
		_emit_failure(binding, reason)
		return false

	if not target.has_method(binding.method_name):
		var reason := "Method not found: %s.%s()" % [target.name, binding.method_name]
		_emit_failure(binding, reason)
		return false

	var callable := Callable(target, binding.method_name)

	match binding.type:
		YarnCommandBinding.Type.COMMAND:
			if binding.parameter_count > 0 and verbose:
				push_warning("YarnBindingLoader: '%s' is a command but has parameter_count set - this is ignored for commands" % binding.yarn_name)
			dialogue_runner.add_command(binding.yarn_name, callable)
			_registered_commands.append(binding.yarn_name)
			if verbose:
				print("YarnBindingLoader: Command '%s' -> %s.%s()" % [
					binding.yarn_name, target.name, binding.method_name
				])

		YarnCommandBinding.Type.FUNCTION:
			dialogue_runner.add_function(binding.yarn_name, callable, binding.parameter_count)
			_registered_functions.append(binding.yarn_name)
			if verbose:
				print("YarnBindingLoader: Function '%s' -> %s.%s() [%d params]" % [
					binding.yarn_name, target.name, binding.method_name, binding.parameter_count
				])

	return true


func _emit_failure(binding: YarnCommandBinding, reason: String) -> void:
	push_error("YarnBindingLoader: %s - %s" % [binding.yarn_name if binding.yarn_name else "unnamed", reason])
	binding_failed.emit(binding, reason)


func _find_dialogue_runner() -> YarnDialogueRunner:
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is YarnDialogueRunner:
				return child

	var node := parent
	while node:
		if node is YarnDialogueRunner:
			return node
		for child in node.get_children():
			if child is YarnDialogueRunner:
				return child
		node = node.get_parent()

	return null
