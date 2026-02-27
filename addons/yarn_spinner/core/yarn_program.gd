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

class_name YarnProgram
extends Resource
## Represents a compiled yarn spinner program.

@export var program_name: String = ""
@export var nodes: Dictionary = {}
@export var initial_values: Dictionary = {}
@export var language_version: int = 0
@export var string_table: Dictionary = {}
@export var line_metadata: Dictionary = {}


func get_node(node_name: String) -> YarnNode:
	return nodes.get(node_name)


func has_node(node_name: String) -> bool:
	return nodes.has(node_name)


func get_node_names() -> PackedStringArray:
	return PackedStringArray(nodes.keys())


func get_initial_value(variable_name: String) -> Variant:
	return initial_values.get(variable_name)


func has_initial_value(variable_name: String) -> bool:
	return initial_values.has(variable_name)


func get_string(line_id: String) -> String:
	return string_table.get(line_id, "")


func has_string(line_id: String) -> bool:
	return string_table.has(line_id)


func get_line_metadata(line_id: String) -> PackedStringArray:
	return line_metadata.get(line_id, PackedStringArray())


func has_line_metadata(line_id: String) -> bool:
	return line_metadata.has(line_id)


## Returns the value after tag_prefix, e.g. "shadow:other_line" -> "other_line".
func get_metadata_value(line_id: String, tag_prefix: String) -> String:
	if not line_metadata.has(line_id):
		return ""
	var metadata: PackedStringArray = line_metadata[line_id]
	for tag in metadata:
		if tag.begins_with(tag_prefix):
			return tag.substr(tag_prefix.length())
	return ""


func has_metadata_tag(line_id: String, tag: String) -> bool:
	if not line_metadata.has(line_id):
		return false
	var metadata: PackedStringArray = line_metadata[line_id]
	return tag in metadata


const SMART_VARIABLE_TAG := "Yarn.SmartVariable"
const NODE_GROUP_HUB_HEADER := "$Yarn.Internal.NodeGroupHub"
const NODE_GROUP_HEADER := "$Yarn.Internal.NodeGroup"

enum VariableKind {
	STORED,
	SMART,
	UNKNOWN,
}


func get_smart_variable_nodes() -> Array[YarnNode]:
	var result: Array[YarnNode] = []
	for node_name in nodes:
		var node: YarnNode = nodes[node_name]
		var tags := node.get_tags()
		if SMART_VARIABLE_TAG in tags:
			result.append(node)
	return result


func get_variable_kind(variable_name: String) -> int:
	if initial_values.has(variable_name):
		return VariableKind.STORED
	var smart_nodes := get_smart_variable_nodes()
	for node in smart_nodes:
		if node.node_name == variable_name:
			return VariableKind.SMART
	return VariableKind.UNKNOWN


func is_node_group_hub(node_name: String) -> bool:
	var node := get_node(node_name)
	if node == null:
		return false
	return node.headers.has(NODE_GROUP_HUB_HEADER)
