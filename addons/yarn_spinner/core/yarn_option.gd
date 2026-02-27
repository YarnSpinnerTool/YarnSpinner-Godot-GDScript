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

class_name YarnOption
extends RefCounted
## represents a dialogue option that can be selected by the player.
## contains the line id, availability, and destination for selection.

var line_id: String = ""
var option_index: int = 0
var is_available: bool = true
var substitutions: Array[String] = []
## instruction index to jump to when selected
var destination: int = 0
## text before substitution
var raw_text: String = ""
## text after substitution
var text: String = ""
var metadata: PackedStringArray = PackedStringArray()


func apply_substitutions() -> void:
	text = raw_text
	for i in range(substitutions.size()):
		text = text.replace("{%d}" % i, substitutions[i])


func get_plain_text() -> String:
	var plain := text
	var markup_regex := RegEx.new()
	markup_regex.compile("\\[[^\\]]+\\]")
	plain = markup_regex.sub(plain, "", true)
	return plain
