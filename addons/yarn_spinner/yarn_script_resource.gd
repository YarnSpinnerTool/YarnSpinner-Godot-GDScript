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

@icon("res://addons/yarn_spinner/icons/yarn_script.svg")
class_name YarnScriptResource
extends Resource
## resource representing a single .yarn script file.
## used for editor integration and reference.

@export_multiline var content: String = ""
@export var source_path: String = ""
@export var node_names: PackedStringArray = PackedStringArray()


func get_node_content(node_name: String) -> String:
	var lines := content.split("\n")
	var in_target_node := false
	var in_header := false
	var result := ""

	for line in lines:
		var stripped := line.strip_edges()
		if stripped == "---":
			in_header = true
		elif stripped == "===":
			if in_target_node:
				return result
			in_header = false
			in_target_node = false
		elif in_header and stripped.begins_with("title:"):
			var name := stripped.substr(6).strip_edges()
			if name == node_name:
				in_target_node = true
		elif in_target_node and not in_header:
			result += line + "\n"

	return result
