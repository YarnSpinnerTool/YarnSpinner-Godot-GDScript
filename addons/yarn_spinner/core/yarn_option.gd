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
## A dialogue option that can be selected by the player.
##
## Access [member text] directly — substitutions are applied lazily on
## first access. For raw data, use [member raw_text] and [member substitutions].

## The string table ID for this option's text.
var line_id: String = ""

## Index of this option in the option set (0-based).
var option_index: int = 0

## Whether this option is available for selection (false = greyed out).
var is_available: bool = true

## Values replacing {0}, {1}, etc. placeholders in [member raw_text].
var substitutions: Array[String] = []

## Instruction index to jump to when selected (internal).
var destination: int = 0

## Localised text before substitution — still contains {0} placeholders.
var raw_text: String = ""

## #hashtag metadata from the yarn source.
var metadata: PackedStringArray = PackedStringArray()

## BCP-47 locale for [plural] and [ordinal] rules. Set by the line provider.
var locale_code: String = "en"

var source: Object = null

var markup_result: YarnMarkupParseResult = null

var markup_attributes: Array[YarnMarkupAttribute] = []


# ---------------------------------------------------------------------------
# Lazy-computed text
# ---------------------------------------------------------------------------

var _text_override: String = ""
var _has_text_override: bool = false

## Final text after substitution and markup processing (select, plural,
## and ordinal markers resolve here, the same as [member YarnLine.text]).
## Computed lazily on first access.
var text: String:
	get:
		if _has_text_override:
			return _text_override
		_ensure_processed()
		return markup_result.text
	set(value):
		_text_override = value
		_has_text_override = true


## Substitutions are now applied automatically on first access to
## [member text]. This method triggers processing early if needed.
func apply_substitutions() -> void:
	_ensure_processed()


func _ensure_processed() -> void:
	if markup_result != null:
		return
	set_markup_result(YarnLineParser.create_with_builtin_replacers().parse_string(YarnLineParser.expand_substitutions(raw_text, substitutions), locale_code, true))


func set_markup_result(result: YarnMarkupParseResult) -> void:
	markup_result = result
	markup_attributes.clear()
	if result != null:
		markup_attributes.assign(result.attributes)


func get_markup_result() -> YarnMarkupParseResult:
	_ensure_processed()
	return markup_result


func get_markup_result_without_character_name() -> YarnMarkupParseResult:
	_ensure_processed()
	return markup_result.without_character_name()


func try_get_attribute(attr_name: String) -> YarnMarkupAttribute:
	_ensure_processed()
	return markup_result.try_get_attribute_with_name(attr_name)


## Character name from the option's "Name:" prefix, if it has one.
var character_name: String:
	get:
		_ensure_processed()
		return markup_result.get_character_name()

## The option text with any character name prefix removed and markup
## processed, matching [member YarnLine.text_without_character_name].
var text_without_character_name: String:
	get:
		if _has_text_override:
			return _text_override
		return get_markup_result_without_character_name().text


## Returns the option text with markup tags stripped.
func get_plain_text() -> String:
	return YarnMarkupParser.strip_bbcode_tags(text)
