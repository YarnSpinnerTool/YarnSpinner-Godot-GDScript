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

class_name YarnPaletteMarkupProcessor
extends YarnMarkupAttributeProcessor
## converts [color] markup attributes to bbcode color tags.

var palette: Dictionary = {}
var _has_open_tag: bool = false


func _init() -> void:
	attribute_name = "color"
	palette = {
		"red": Color.RED,
		"green": Color.GREEN,
		"blue": Color.BLUE,
		"yellow": Color.YELLOW,
		"orange": Color.ORANGE,
		"purple": Color.PURPLE,
		"pink": Color.HOT_PINK,
		"cyan": Color.CYAN,
		"white": Color.WHITE,
		"black": Color.BLACK,
		"gray": Color.GRAY,
		"grey": Color.GRAY,
	}


func process_open(attribute_value: String, properties: Dictionary) -> String:
	_has_open_tag = true
	var color_str := _resolve_color(attribute_value)
	return "[color=%s]" % color_str


func process_close() -> String:
	if _has_open_tag:
		_has_open_tag = false
		return "[/color]"
	return ""


func _resolve_color(value: String) -> String:
	var lower := value.to_lower()

	# check custom palette first
	if palette.has(lower):
		var color = palette[lower]
		if color is Color:
			return "#" + color.to_html(false)
		elif color is String:
			return color
		return value

	# check if it's already a hex color
	if value.begins_with("#"):
		return value

	# try to parse as Godot named color
	var color := Color.from_string(value, Color.WHITE)
	if color != Color.WHITE or value.to_lower() == "white":
		return "#" + color.to_html(false)

	# return as-is and let BBCode handle it
	return value


## add a color to the palette
func add_palette_color(name: String, color: Variant) -> void:
	palette[name.to_lower()] = color


## remove a color from the palette
func remove_palette_color(name: String) -> void:
	palette.erase(name.to_lower())
