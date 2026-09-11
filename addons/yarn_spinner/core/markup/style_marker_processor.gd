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

class_name YarnStyleMarkerProcessor
extends YarnAttributeMarkerProcessor
## parse-time processor that converts [style] markup tags to bbcode.
## supports bold, italic, underline, strikethrough, code, and custom names.


## optional stylesheet consulted before the built-in styles: maps a lowercased
## style name to a Dictionary with "start" and "end" bbcode strings. the Godot
## counterpart of a TextMeshPro style sheet.
var styles: Dictionary = {}


func process_replacement_marker(
	marker: YarnMarkupAttribute,
	child_builder: Array,
	child_attributes: Array,
	locale_code: String
) -> ReplacementMarkerResult:
	var style_prop: YarnMarkupValue = marker.try_get_property("style")
	if style_prop == null:
		var error := MarkupDiagnostic.new("unable to identify a name for the style.")
		return ReplacementMarkerResult.new([error], 0)

	var style_name := style_prop.to_string_value().to_lower()
	var original_length: int = child_builder[0].length()
	var open_tag := ""
	var close_tag := ""

	if styles.has(style_name):
		var style: Dictionary = styles[style_name]
		open_tag = YarnMarkupParser.brackets_to_tags(style.get("start", ""))
		close_tag = YarnMarkupParser.brackets_to_tags(style.get("end", ""))
	else:
		match style_name:
			"bold", "b":
				open_tag = YarnMarkupParser.bbcode_tag("b")
				close_tag = YarnMarkupParser.bbcode_tag("/b")
			"italic", "i":
				open_tag = YarnMarkupParser.bbcode_tag("i")
				close_tag = YarnMarkupParser.bbcode_tag("/i")
			"underline", "u":
				open_tag = YarnMarkupParser.bbcode_tag("u")
				close_tag = YarnMarkupParser.bbcode_tag("/u")
			"strikethrough", "s":
				open_tag = YarnMarkupParser.bbcode_tag("s")
				close_tag = YarnMarkupParser.bbcode_tag("/s")
			"code":
				open_tag = YarnMarkupParser.bbcode_tag("code")
				close_tag = YarnMarkupParser.bbcode_tag("/code")

	child_builder[0] = open_tag + child_builder[0] + close_tag
	var invisible_chars: int = child_builder[0].length() - original_length
	return ReplacementMarkerResult.new([], invisible_chars)
