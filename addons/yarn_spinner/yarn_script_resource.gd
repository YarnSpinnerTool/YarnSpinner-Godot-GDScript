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


static var _title_regex: RegEx


func get_node_content(node_name: String) -> String:
	if _title_regex == null:
		_title_regex = RegEx.create_from_string("^[ \\t]*title[ \\t]*:[ \\t]*([^\\s/]+)[ \\t]*(?://.*)?$")
	var lines := content.split("\n")
	var in_target_node := false
	var in_header := true
	var result := ""

	for line in lines:
		var stripped := line.strip_edges()
		if in_header:
			if stripped.begins_with("---"):
				in_header = false
			else:
				var title_match := _title_regex.search(line.trim_suffix("\r"))
				if title_match and title_match.get_string(1) == node_name:
					in_target_node = true
		elif stripped.begins_with("==="):
			if in_target_node:
				return result
			in_header = true
		elif in_target_node:
			result += line + "\n"

	return result
