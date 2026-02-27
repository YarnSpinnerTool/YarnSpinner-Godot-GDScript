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

class_name YarnAttributeMarkerProcessor
extends RefCounted
## base class for processing replacement markers during parsing.
## these run at parse-time to modify text (e.g. [select], [plural], [ordinal]).
## subclass and override process_replacement_marker() for custom markers.


## tag types for markup attributes.
enum TagType {
	OPEN,         ## opening tag like [a]
	CLOSE,        ## closing tag like [/a]
	SELF_CLOSING, ## self-closing tag like [a/]
	CLOSE_ALL,    ## close all open tags: [/]
}


## an error or warning produced during markup parsing.
class MarkupDiagnostic extends RefCounted:
	var message: String = ""

	## zero-based column index where the problem occurred (-1 if unknown).
	var column: int = -1
	func _init(msg: String = "", col: int = -1) -> void:
		message = msg
		column = col

	func _to_string() -> String:
		if column >= 0:
			return "column %d: %s" % [column, message]
		return message


## result of processing a replacement marker.
class ReplacementMarkerResult extends RefCounted:
	var diagnostics: Array = []  # Array[MarkupDiagnostic]

	## count of non-rendering characters added (e.g. bbcode tags),
	## needed for correct attribute position tracking.
	var invisible_characters: int = 0
	func _init(diags: Array = [], invisible: int = 0) -> void:
		diagnostics = diags
		invisible_characters = invisible


## override to process a replacement marker. modify child_builder[0] to
## change output text. return diagnostics and invisible character count.
func process_replacement_marker(
	marker: YarnMarkupAttribute,
	child_builder: Array,  # single-element array containing the string to modify
	child_attributes: Array,  # Array[YarnMarkupAttribute]
	locale_code: String
) -> ReplacementMarkerResult:
	push_error("process_replacement_marker not implemented")
	return ReplacementMarkerResult.new()
