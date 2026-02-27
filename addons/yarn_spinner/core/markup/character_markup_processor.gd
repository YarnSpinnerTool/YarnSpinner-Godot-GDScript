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

class_name YarnCharacterMarkupProcessor
extends YarnMarkupAttributeProcessor
## extracts character name from [character] markup attributes.

var character_name: String = ""


func _init() -> void:
	attribute_name = "character"


func process_open(attribute_value: String, properties: Dictionary) -> String:
	character_name = attribute_value
	return ""


func process_close() -> String:
	return ""
func reset() -> void:
	character_name = ""
