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

class_name YarnLine
extends RefCounted
## a line of dialogue with substitution, markup, and localisation support.
## corresponds to Unity's LocalizedLine.


var line_id: String = ""


## values replacing {0}, {1}, etc. placeholders in raw_text.
var substitutions: Array[String] = []


## localised text before substitution, still containing placeholders and markup.
var raw_text: String = ""


## final text after substitution and markup removal.
var text: String = ""


## extracted from [character] markup or implicit "Name:" pattern.
var character_name: String = ""


## #hashtag metadata from the yarn source.
var metadata: PackedStringArray = PackedStringArray()


## parsed markup attributes from parse_markup(), each with name, position, and length.
var markup_attributes: Array[YarnMarkupAttribute] = []


var markup_result: YarnMarkupParseResult = null


static var _line_parser: YarnLineParser


## BCP-47 locale for [plural] and [ordinal] rules.
var locale_code: String = "en"


static func _ensure_parser_initialized() -> void:
	if _line_parser == null:
		_line_parser = YarnLineParser.new()
		var builtin_replacer := YarnBuiltInMarkupReplacer.new()
		_line_parser.register_marker_processor("select", builtin_replacer)
		_line_parser.register_marker_processor("plural", builtin_replacer)
		_line_parser.register_marker_processor("ordinal", builtin_replacer)


func apply_substitutions() -> void:
	text = YarnLineParser.expand_substitutions(raw_text, substitutions)


## extracts markup attributes, sets plain text, and populates character_name.
## removes the character prefix (e.g. "Name: ") from the text so presenters
## can show it separately in a nameplate.
func parse_markup() -> void:
	_ensure_parser_initialized()

	markup_result = _line_parser.parse_string(text, locale_code, true)
	text = markup_result.text

	# find and extract the character attribute first
	var char_attr: YarnMarkupAttribute = null
	for attr in markup_result.attributes:
		if attr.name == YarnLineParser.CHARACTER_ATTRIBUTE and character_name.is_empty():
			char_attr = attr
			var name_prop: YarnMarkupValue = attr.try_get_property(YarnLineParser.CHARACTER_ATTRIBUTE_NAME_PROPERTY)
			if name_prop != null:
				character_name = name_prop.string_value
			else:
				character_name = markup_result.text_for_attribute(attr).strip_edges().trim_suffix(":")

	# strip the character prefix from the displayed text
	if char_attr != null and char_attr.length > 0:
		markup_result = markup_result.delete_range(char_attr)
		text = markup_result.text

	markup_attributes.clear()
	for attr in markup_result.attributes:
		markup_attributes.append(attr)


## the text with the character name prefix removed (e.g. "Name: hello" -> "hello").
## equivalent to Unity's TextWithoutCharacterName.
## if no character attribute is present, returns the same as text.
var text_without_character_name: String:
	get:
		if markup_result == null:
			parse_markup()
		return text


func get_plain_text() -> String:
	return text


## returns text with markup converted to BBCode for RichTextLabel.
func get_bbcode_text(parser: YarnMarkupParser = null) -> String:
	if parser == null:
		parser = YarnMarkupParser.new()
	parser.locale_code = locale_code
	var source_text := raw_text if not raw_text.is_empty() else text
	source_text = YarnLineParser.expand_substitutions(source_text, substitutions)
	var result := parser.parse(source_text)
	if result.character_name and character_name.is_empty():
		character_name = result.character_name
	return result.text


## ensures parse_markup() has been called, then returns the result.
func get_markup_result() -> YarnMarkupParseResult:
	if markup_result == null:
		parse_markup()
	return markup_result


func delete_attribute_text(attr: YarnMarkupAttribute) -> void:
	if markup_result == null:
		return

	for result_attr in markup_result.attributes:
		if result_attr.name == attr.name and result_attr.position == attr.position:
			markup_result = markup_result.delete_range(result_attr)
			text = markup_result.text
			parse_markup()
			break


## returns the first attribute with the given name, or null.
func try_get_attribute(attr_name: String) -> YarnMarkupAttribute:
	for attr in markup_attributes:
		if attr.name == attr_name:
			return attr
	return null


## returns the substring of text covered by an attribute.
func text_for_attribute(attr: YarnMarkupAttribute) -> String:
	if attr.length == 0:
		return ""
	if text.length() < attr.position + attr.length:
		return ""
	return text.substr(attr.position, attr.length)
