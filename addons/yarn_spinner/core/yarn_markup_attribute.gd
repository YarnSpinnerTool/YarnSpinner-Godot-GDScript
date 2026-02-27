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

class_name YarnMarkupAttribute
extends RefCounted
## a markup attribute in yarn text, tracking name, position, length, and properties.

var name: String = ""
var value: String = ""
## position in the plain text where this attribute begins.
var position: int = 0
## position in the original source text.
var source_position: int = 0
## number of plain text characters this attribute covers.
var length: int = 0
## name -> YarnMarkupValue
var properties: Dictionary = {}


func _init(pos: int = 0, src_pos: int = 0, len: int = 0, attr_name: String = "", props: Array = []) -> void:
	position = pos
	source_position = src_pos
	length = len
	name = attr_name
	for prop in props:
		if prop is YarnMarkupProperty:
			properties[prop.name] = prop.value
			if value.is_empty():
				value = prop.value.to_string_value()


func has_value() -> bool:
	return not value.is_empty()


func get_property(prop_name: String, default_value: Variant = null) -> Variant:
	return properties.get(prop_name, default_value)


## returns YarnMarkupValue for the property name, or null.
func try_get_property(prop_name: String) -> YarnMarkupValue:
	var lower_name := prop_name.to_lower()
	for key in properties:
		if key.to_lower() == lower_name:
			var val: Variant = properties[key]
			if val is YarnMarkupValue:
				return val
				return YarnMarkupValue.from_string(str(val))
	return null


func try_get_string_property(prop_name: String, default_value: String = "") -> String:
	var val := try_get_property(prop_name)
	if val != null and val.type == YarnMarkupValue.ValueType.STRING:
		return val.string_value
	return default_value


func try_get_int_property(prop_name: String, default_value: int = 0) -> int:
	var val := try_get_property(prop_name)
	if val != null and val.type == YarnMarkupValue.ValueType.INTEGER:
		return val.integer_value
	return default_value


func try_get_float_property(prop_name: String, default_value: float = 0.0) -> float:
	var val := try_get_property(prop_name)
	if val != null:
		if val.type == YarnMarkupValue.ValueType.FLOAT:
			return val.float_value
		elif val.type == YarnMarkupValue.ValueType.INTEGER:
			return float(val.integer_value)
	return default_value


func try_get_bool_property(prop_name: String, default_value: bool = false) -> bool:
	var val := try_get_property(prop_name)
	if val != null and val.type == YarnMarkupValue.ValueType.BOOL:
		return val.bool_value
	return default_value


## returns a copy with position shifted by amount.
func shift(amount: int) -> YarnMarkupAttribute:
	var shifted := YarnMarkupAttribute.new()
	shifted.position = position + amount
	shifted.source_position = source_position
	shifted.length = length
	shifted.name = name
	shifted.value = value
	shifted.properties = properties.duplicate()
	return shifted


func _to_string() -> String:
	return "[%s] - %d-%d (%d, %d properties)" % [name, position, position + length, length, properties.size()]
