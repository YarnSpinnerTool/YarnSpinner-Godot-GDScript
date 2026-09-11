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

## Optional source that handles requests to end this line early.
##
## The dialogue runner sets this to itself when it dispatches the line to its
## presenters. Wrapper presenters (such as the Interruption add-on) may
## substitute themselves as the source so that requests from child presenters
## to end the line can be intercepted.
##
## A source object should implement [code]request_line_cancellation(line: YarnLine)[/code].
## Presenters should route end-of-line requests through
## [method YarnDialoguePresenter._request_line_end], which uses this field if
## set and otherwise falls back to calling
## [method YarnDialogueRunner.signal_content_complete] directly.
var source: Object = null


# ---------------------------------------------------------------------------
# Lazy-computed properties
# ---------------------------------------------------------------------------

var _text_override: String = ""
var _has_text_override: bool = false
var _character_name_override: String = ""
var _has_character_name_override: bool = false

## Final text after substitution and markup processing. Computed lazily on
## first access.
var text: String:
	get:
		if _has_text_override:
			return _text_override
		_ensure_processed()
		return markup_result.text
	set(value):
		_text_override = value
		_has_text_override = true

## Character name extracted from [character] markup or implicit "Name:" pattern.
## Computed lazily alongside [member text].
var character_name: String:
	get:
		if _has_character_name_override:
			return _character_name_override
		_ensure_processed()
		return markup_result.get_character_name()
	set(value):
		_character_name_override = value
		_has_character_name_override = true

## The text with the character name prefix removed.
var text_without_character_name: String:
	get:
		if _has_text_override:
			return _text_override
		return get_markup_result_without_character_name().text


# ---------------------------------------------------------------------------
# Processing
# ---------------------------------------------------------------------------

func _ensure_processed() -> void:
	if markup_result != null:
		return
	set_markup_result(YarnLineParser.create_with_builtin_replacers().parse_string(YarnLineParser.expand_substitutions(raw_text, substitutions), locale_code, true))


func set_markup_result(result: YarnMarkupParseResult) -> void:
	markup_result = result
	markup_attributes.clear()
	if result != null:
		markup_attributes.assign(result.attributes)


## Force reprocessing (e.g. if raw_text or substitutions changed after creation).
func invalidate() -> void:
	markup_result = null
	markup_attributes.clear()
	_text_override = ""
	_has_text_override = false
	_character_name_override = ""
	_has_character_name_override = false


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


## Returns [member text_without_character_name] (substitutions and markup already applied).
func get_plain_text() -> String:
	return text_without_character_name


## Returns text with markup converted to BBCode for RichTextLabel.
func get_bbcode_text(parser: YarnMarkupParser = null, include_character_name: bool = false) -> String:
	if parser == null:
		parser = YarnMarkupParser.new()
	var result := get_markup_result() if include_character_name else get_markup_result_without_character_name()
	return parser.convert_to_bbcode(result)


## Ensures processing, then returns the full markup result.
func get_markup_result() -> YarnMarkupParseResult:
	_ensure_processed()
	return markup_result


func get_markup_result_without_character_name() -> YarnMarkupParseResult:
	_ensure_processed()
	return markup_result.without_character_name()


## Deletes the text covered by an attribute and re-parses.
func delete_attribute_text(attr: YarnMarkupAttribute) -> void:
	_ensure_processed()
	for result_attr in markup_result.attributes:
		if result_attr.name == attr.name and result_attr.position == attr.position:
			set_markup_result(markup_result.delete_range(result_attr))
			break


## Returns the first attribute with the given name, or null.
func try_get_attribute(attr_name: String) -> YarnMarkupAttribute:
	_ensure_processed()
	return markup_result.try_get_attribute_with_name(attr_name)


## Returns the substring of text covered by an attribute.
func text_for_attribute(attr: YarnMarkupAttribute) -> String:
	_ensure_processed()
	if attr.length == 0:
		return ""
	if markup_result.text.length() < attr.position + attr.length:
		return ""
	return markup_result.text.substr(attr.position, attr.length)
