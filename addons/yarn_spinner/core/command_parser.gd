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

class_name YarnCommandParser
extends RefCounted
## Parses Yarn command strings with support for quoted arguments and escapes.


## Returns [command_name, arg1, arg2, ...].
static func parse(command_text: String) -> Array[String]:
	var parts: Array[String] = []
	var current := ""
	var quote_char := ""
	var escape_next := false

	for c in command_text:
		if escape_next:
			current += c
			escape_next = false
		elif c == "\\":
			escape_next = true
		elif quote_char.is_empty() and (c == "\"" or c == "'"):
			quote_char = c
		elif c == quote_char:
			quote_char = ""
		elif c == " " and quote_char.is_empty():
			if not current.is_empty():
				parts.append(current)
				current = ""
		else:
			current += c

	if not current.is_empty():
		parts.append(current)

	return parts


## Returns {"name": "command_name", "args": ["arg1", "arg2"]}.
static func parse_to_dict(command_text: String) -> Dictionary:
	var parts := parse(command_text)
	if parts.is_empty():
		return {"name": "", "args": []}
	return {
		"name": parts[0],
		"args": parts.slice(1)
	}


static func get_command_name(command_text: String) -> String:
	var parts := parse(command_text)
	return parts[0] if not parts.is_empty() else ""


static func get_args(command_text: String) -> Array[String]:
	var parts := parse(command_text)
	if parts.size() > 1:
		return parts.slice(1)
	return []
