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

class_name YarnStyleMarkupProcessor
extends YarnMarkupAttributeProcessor
## converts [style] markup attributes to Godot bbcode.

var _style_stack: Array[String] = []


func _init() -> void:
	attribute_name = "style"


func process_open(attribute_value: String, properties: Dictionary) -> String:
	var style := attribute_value.to_lower()
	_style_stack.push_back(style)

	match style:
		"bold", "b":
			return "[b]"
		"italic", "i":
			return "[i]"
		"underline", "u":
			return "[u]"
		"strikethrough", "s":
			return "[s]"
		"code":
			return "[code]"
		_:
			push_warning("yarn markup: unknown style '%s'" % style)
			return ""


func process_close() -> String:
	if _style_stack.is_empty():
		return ""

	var style := _style_stack.pop_back()

	match style:
		"bold", "b":
			return "[/b]"
		"italic", "i":
			return "[/i]"
		"underline", "u":
			return "[/u]"
		"strikethrough", "s":
			return "[/s]"
		"code":
			return "[/code]"
		_:
			return ""
