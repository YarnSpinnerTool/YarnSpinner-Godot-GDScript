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


## Whitespace characters that separate unquoted tokens in yarn command text.
const _WHITESPACE := [" ", "\t", "\n", "\r"]


## Returns [command_name, arg1, arg2, ...].
##
## Splits on whitespace outside quotes. Only double quotes delimit a quoted
## span; inside one, \\ and \" are the only escapes, and closing the quote
## flushes the token immediately even if more non-whitespace text follows
## (so text before a quote merges with it, but text after does not). Single
## quotes and backslashes outside quotes carry no special meaning.
static func parse(command_text: String) -> Array[String]:
	var parts: Array[String] = []
	var current := ""
	var length := command_text.length()
	var i := 0

	while i < length:
		var c := command_text[i]

		if c in _WHITESPACE:
			if not current.is_empty():
				parts.append(current)
				current = ""
			i += 1
			continue

		if c == "\"":
			i += 1
			var closed := false
			while i < length:
				var qc := command_text[i]
				if qc == "\\":
					var next_c := command_text[i + 1] if i + 1 < length else ""
					if next_c == "\\" or next_c == "\"":
						current += next_c
						i += 2
					else:
						current += qc
						i += 1
				elif qc == "\"":
					i += 1
					closed = true
					break
				else:
					current += qc
					i += 1
			parts.append(current)
			current = ""
			if not closed:
				return parts
			continue

		current += c
		i += 1

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
