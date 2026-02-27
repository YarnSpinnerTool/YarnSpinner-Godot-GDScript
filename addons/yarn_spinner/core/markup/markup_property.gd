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

class_name YarnMarkupProperty
extends RefCounted
## a named property with a typed value, associated with a markup attribute.

var name: String = ""
var value: YarnMarkupValue


func _init(prop_name: String = "", prop_value: YarnMarkupValue = null) -> void:
	name = prop_name
	value = prop_value if prop_value != null else YarnMarkupValue.new()


static func from_string(prop_name: String, prop_value: String) -> YarnMarkupProperty:
	return YarnMarkupProperty.new(prop_name, YarnMarkupValue.from_string(prop_value))


static func from_int(prop_name: String, prop_value: int) -> YarnMarkupProperty:
	return YarnMarkupProperty.new(prop_name, YarnMarkupValue.from_int(prop_value))


static func from_float(prop_name: String, prop_value: float) -> YarnMarkupProperty:
	return YarnMarkupProperty.new(prop_name, YarnMarkupValue.from_float(prop_value))


static func from_bool(prop_name: String, prop_value: bool) -> YarnMarkupProperty:
	return YarnMarkupProperty.new(prop_name, YarnMarkupValue.from_bool(prop_value))
