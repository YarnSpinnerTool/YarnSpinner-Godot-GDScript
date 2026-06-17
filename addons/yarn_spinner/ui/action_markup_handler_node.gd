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

class_name YarnActionMarkupHandlerNode
extends Node
## Node-based base class for display-time action markup handlers.
##
## Mirrors Yarn Spinner for Unity's [code]ActionMarkupHandler : MonoBehaviour[/code]:
## attach this as a node in your scene (so it can reference other nodes, find
## characters, and so on), then add it to a [YarnLinePresenter]'s
## [member YarnLinePresenter.event_handlers] list. The presenter invokes these
## methods as each character of a line is revealed.
##
## Override only the methods you need; the defaults are no-ops. This is the
## scene-attached counterpart to the RefCounted [YarnActionMarkupHandler]
## interface, which is used for handlers constructed in code (such as the
## built-in pause processor).


## Called once when the line is received, before any text is visible.
## Set up per-line state here (e.g. scan the line's markup attributes).
func on_prepare_for_line(_line: Variant, _text_control: Control = null) -> void:
	pass


## Called immediately before the first character is presented.
func on_line_display_begin(_line: Variant, _text_control: Control = null) -> void:
	pass


## Called for each character as it is about to be revealed.
## Return a [Signal] to pause the typewriter until it fires, or an empty
## [code]Signal()[/code] to continue immediately.
func on_character_will_appear(
	_character_index: int,
	_line: Variant,
	_cancellation_token: Variant = null
) -> Signal:
	return Signal()


## Called after every character has been presented.
func on_line_display_complete() -> void:
	pass


## Called right before the line is dismissed.
func on_line_will_dismiss() -> void:
	pass


## Returns true if [param index] falls within [param attr]'s span.
static func is_index_in_attribute(index: int, attr: YarnMarkupAttribute) -> bool:
	return YarnActionMarkupHandler.is_index_in_attribute(index, attr)


## Returns all attributes covering a specific character index.
static func get_attributes_at_index(index: int, attributes: Array) -> Array[YarnMarkupAttribute]:
	return YarnActionMarkupHandler.get_attributes_at_index(index, attributes)
