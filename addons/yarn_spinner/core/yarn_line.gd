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
## A line of dialogue with substitution, markup, and localisation support.
##
## Access [member text] and [member character_name] directly — substitutions
## and markup are applied lazily on first access. For raw data, use
## [member raw_text] and [member substitutions].


## The string table ID for this line (e.g. "line:tutorial-tom-01").
var line_id: String = ""

## Values replacing {0}, {1}, etc. placeholders in [member raw_text].
var substitutions: Array[String] = []

## Localised text before substitution — still contains {0} placeholders
## and markup tags. Set by the line provider.
var raw_text: String = ""

## #hashtag metadata from the yarn source.
var metadata: PackedStringArray = PackedStringArray()

## BCP-47 locale for [plural] and [ordinal] rules.
var locale_code: String = "en"

## Parsed markup attributes — populated on first access to [member text].
var markup_attributes: Array[YarnMarkupAttribute] = []

## Full markup parse result — populated on first access to [member text].
var markup_result: YarnMarkupParseResult = null


# ---------------------------------------------------------------------------
# Lazy-computed properties
# ---------------------------------------------------------------------------

var _text_computed: bool = false
var _text: String = ""
var _character_name: String = ""

## Final text after substitution, markup processing, and character name
## extraction. Computed lazily on first access.
var text: String:
	get:
		_ensure_processed()
		return _text
	set(value):
		_text = value
		_text_computed = true

## Character name extracted from [character] markup or implicit "Name:" pattern.
## Computed lazily alongside [member text].
var character_name: String:
	get:
		_ensure_processed()
		return _character_name
	set(value):
		_character_name = value

## The text with the character name prefix removed.
## Equivalent to Unity's TextWithoutCharacterName.
var text_without_character_name: String:
	get:
		_ensure_processed()
		return _text


# ---------------------------------------------------------------------------
# Processing
# ---------------------------------------------------------------------------

static var _line_parser: YarnLineParser


static func _ensure_parser_initialized() -> void:
	if _line_parser == null:
		_line_parser = YarnLineParser.new()
		var builtin_replacer := YarnBuiltInMarkupReplacer.new()
		_line_parser.register_marker_processor("select", builtin_replacer)
		_line_parser.register_marker_processor("plural", builtin_replacer)
		_line_parser.register_marker_processor("ordinal", builtin_replacer)


func _ensure_processed() -> void:
	if _text_computed:
		return
	_text_computed = true

	# Step 1: Apply substitutions
	_text = YarnLineParser.expand_substitutions(raw_text, substitutions)

	# Step 2: Parse markup
	_ensure_parser_initialized()
	markup_result = _line_parser.parse_string(_text, locale_code, true)
	_text = markup_result.text

	# Step 3: Extract character name
	var char_attr: YarnMarkupAttribute = null
	for attr in markup_result.attributes:
		if attr.name == YarnLineParser.CHARACTER_ATTRIBUTE and _character_name.is_empty():
			char_attr = attr
			var name_prop: YarnMarkupValue = attr.try_get_property(YarnLineParser.CHARACTER_ATTRIBUTE_NAME_PROPERTY)
			if name_prop != null:
				_character_name = name_prop.string_value
			else:
				_character_name = markup_result.text_for_attribute(attr).strip_edges().trim_suffix(":")

	# Step 4: Strip character prefix from displayed text
	if char_attr != null and char_attr.length > 0:
		markup_result = markup_result.delete_range(char_attr)
		_text = markup_result.text

	# Step 5: Populate markup_attributes
	markup_attributes.clear()
	for attr in markup_result.attributes:
		markup_attributes.append(attr)


## Force reprocessing (e.g. if raw_text or substitutions changed after creation).
func invalidate() -> void:
	_text_computed = false
	_text = ""
	_character_name = ""
	markup_attributes.clear()
	markup_result = null


# ---------------------------------------------------------------------------
# Legacy / compatibility methods (still callable but processing is automatic)
# ---------------------------------------------------------------------------

## Substitutions and markup are now applied automatically on first access
## to [member text]. This method triggers processing early if needed.
func apply_substitutions() -> void:
	_ensure_processed()


## Markup is now parsed automatically on first access to [member text].
## This method triggers processing early if needed.
func parse_markup() -> void:
	_ensure_processed()


## Returns [member text] (substitutions and markup already applied).
func get_plain_text() -> String:
	return text


## Returns text with markup converted to BBCode for RichTextLabel.
func get_bbcode_text(parser: YarnMarkupParser = null) -> String:
	if parser == null:
		parser = YarnMarkupParser.new()
	parser.locale_code = locale_code
	var source_text := raw_text if not raw_text.is_empty() else _text
	source_text = YarnLineParser.expand_substitutions(source_text, substitutions)
	var result := parser.parse(source_text)
	if result.character_name and _character_name.is_empty():
		_character_name = result.character_name
	return result.text


## Ensures processing, then returns the full markup result.
func get_markup_result() -> YarnMarkupParseResult:
	_ensure_processed()
	return markup_result


## Deletes the text covered by an attribute and re-parses.
func delete_attribute_text(attr: YarnMarkupAttribute) -> void:
	_ensure_processed()
	if markup_result == null:
		return
	for result_attr in markup_result.attributes:
		if result_attr.name == attr.name and result_attr.position == attr.position:
			markup_result = markup_result.delete_range(result_attr)
			_text = markup_result.text
			break


## Returns the first attribute with the given name, or null.
func try_get_attribute(attr_name: String) -> YarnMarkupAttribute:
	_ensure_processed()
	for attr in markup_attributes:
		if attr.name == attr_name:
			return attr
	return null


## Returns the substring of text covered by an attribute.
func text_for_attribute(attr: YarnMarkupAttribute) -> String:
	_ensure_processed()
	if attr.length == 0:
		return ""
	if _text.length() < attr.position + attr.length:
		return ""
	return _text.substr(attr.position, attr.length)
