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

class_name YarnMarkupValue
extends RefCounted
## a typed value associated with a markup property.
enum ValueType {
	INTEGER,
	FLOAT,
	STRING,
	BOOL,
}

var type: ValueType = ValueType.STRING
var integer_value: int = 0
var float_value: float = 0.0
var string_value: String = ""
var bool_value: bool = false
static func from_int(value: int) -> YarnMarkupValue:
	var v := YarnMarkupValue.new()
	v.type = ValueType.INTEGER
	v.integer_value = value
	return v


static func from_float(value: float) -> YarnMarkupValue:
	var v := YarnMarkupValue.new()
	v.type = ValueType.FLOAT
	v.float_value = value
	return v


static func from_string(value: String) -> YarnMarkupValue:
	var v := YarnMarkupValue.new()
	v.type = ValueType.STRING
	v.string_value = value
	return v


static func from_bool(value: bool) -> YarnMarkupValue:
	var v := YarnMarkupValue.new()
	v.type = ValueType.BOOL
	v.bool_value = value
	return v


func to_string_value() -> String:
	match type:
		ValueType.INTEGER:
			return str(integer_value)
		ValueType.FLOAT:
			return str(float_value)
		ValueType.STRING:
			return string_value
		ValueType.BOOL:
			return "true" if bool_value else "false"
	return ""
