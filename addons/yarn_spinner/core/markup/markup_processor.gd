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

class_name YarnMarkupAttributeProcessor
extends RefCounted
## base class for processing markup attributes into bbcode.

var attribute_name: String = ""


## returns text to insert at the opening tag position.
func process_open(attribute_value: String, properties: Dictionary) -> String:
	return ""


## returns text to insert at the closing tag position.
func process_close() -> String:
	return ""


func handles_attribute(attr_name: String) -> bool:
	return attr_name == attribute_name
