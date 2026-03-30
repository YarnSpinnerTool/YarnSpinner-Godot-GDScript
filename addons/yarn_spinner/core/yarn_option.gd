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


# ---------------------------------------------------------------------------
# Lazy-computed text
# ---------------------------------------------------------------------------

var _text_computed: bool = false
var _text: String = ""

## Final text after substitution. Computed lazily on first access.
var text: String:
	get:
		if not _text_computed:
			_text_computed = true
			_text = YarnLineParser.expand_substitutions(raw_text, substitutions)
		return _text
	set(value):
		_text = value
		_text_computed = true


## Substitutions are now applied automatically on first access to
## [member text]. This method triggers processing early if needed.
func apply_substitutions() -> void:
	var _t := text  # triggers lazy computation


## Returns the option text with markup tags stripped.
func get_plain_text() -> String:
	var plain := text
	var markup_regex := RegEx.new()
	markup_regex.compile("\\[[^\\]]+\\]")
	plain = markup_regex.sub(plain, "", true)
	return plain
