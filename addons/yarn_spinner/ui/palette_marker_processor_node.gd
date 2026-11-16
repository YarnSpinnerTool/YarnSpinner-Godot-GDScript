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

class_name YarnPaletteMarkerProcessorNode
extends Node

@export var dialogue_runner: YarnDialogueRunner
@export var palette: YarnMarkupPalette

var _processor: YarnPaletteMarkerProcessor
var _line_provider: YarnLineProvider


func _ready() -> void:
	if palette == null:
		push_warning("palette marker processor: no palette set")
		return
	_line_provider = await YarnStyleMarkerProcessorNode.find_line_provider(self, dialogue_runner)
	if _line_provider == null:
		push_warning("palette marker processor: no Dialogue Runner found")
		return
	_processor = YarnPaletteMarkerProcessor.new(palette)
	_processor.unregister_from_line_provider(_line_provider)
	_processor.register_with_line_provider(_line_provider)


func _exit_tree() -> void:
	if _processor != null and _line_provider != null:
		_processor.unregister_from_line_provider(_line_provider)
	_processor = null
	_line_provider = null
