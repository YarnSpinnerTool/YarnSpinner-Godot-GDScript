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
@icon("res://addons/yarn_spinner/icons/command_binding.svg")
class_name YarnCommandBinding
extends Resource
## Binds a Yarn command or function to a method on a node.


enum Type {
	COMMAND,
	FUNCTION,
}


## The name used in Yarn scripts (snake_case).
@export var yarn_name: String = "":
	set(value):
		yarn_name = value.strip_edges()
		if not yarn_name.is_empty():
			resource_name = yarn_name

@export var type: Type = Type.COMMAND:
	set(value):
		type = value
		notify_property_list_changed()

## Resolved relative to the YarnBindingLoader node.
@export var target_node: NodePath

## Commands can return void or Signal. Functions must return a value.
@export var method_name: String = ""

@export_group("Function Parameters", "")

## Only for FUNCTION type. The VM needs this to pop the right number of stack values.
@export_range(0, 10) var parameter_count: int = 0

@export_group("")

@export var enabled: bool = true

@export_group("Documentation")

## Documentation only - not used at runtime.
@export_multiline var description: String = ""

## Documentation only - not used at runtime.
@export_multiline var example: String = ""


func _validate_property(property: Dictionary) -> void:
	if property.name == "parameter_count" and type == Type.COMMAND:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func is_valid() -> bool:
	return not yarn_name.is_empty() and not method_name.is_empty() and not target_node.is_empty()


func _to_string() -> String:
	var type_str := "command" if type == Type.COMMAND else "function"
	if not is_valid():
		return "[YarnCommandBinding: INVALID]"
	return "[YarnCommandBinding: %s '%s' -> %s.%s()]" % [type_str, yarn_name, target_node, method_name]


func get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if yarn_name.is_empty():
		warnings.append("Yarn name is required")
	if method_name.is_empty():
		warnings.append("Method name is required")
	if target_node.is_empty():
		warnings.append("Target node path is required")
	if type == Type.COMMAND and parameter_count > 0:
		warnings.append("Parameter count is only used for functions, not commands")
	return warnings
