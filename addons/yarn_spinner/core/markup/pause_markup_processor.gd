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

class_name YarnPauseEventProcessor
extends YarnActionMarkupHandler
## display-time handler for [pause] markup tags in typewriter presentation.
## integers are milliseconds ([pause=500/]), floats are seconds ([pause=0.5/]),
## no value defaults to 1000ms. self-closing tag marking a point in the text.


const DEFAULT_PAUSE_DURATION_MS := 1000.0

## character position -> pause duration in milliseconds.
var _pauses: Dictionary[int, float] = {}


func on_prepare_for_line(line: Variant, text_control: Control = null) -> void:
	_pauses.clear()

	var attributes: Array = []
	if line is YarnMarkupParseResult:
		attributes = line.attributes
	elif line is YarnLine:
		attributes = line.markup_attributes

	for attr in attributes:
		if attr is YarnMarkupAttribute and attr.name == "pause":
			var duration_ms := DEFAULT_PAUSE_DURATION_MS
			var pause_prop: YarnMarkupValue = attr.try_get_property("pause")
			if pause_prop != null:
				match pause_prop.type:
					YarnMarkupValue.ValueType.INTEGER:
						duration_ms = float(pause_prop.integer_value)
					YarnMarkupValue.ValueType.FLOAT:
						duration_ms = pause_prop.float_value * 1000.0
					_:
						push_warning("pause attribute has invalid type, using default duration")
			_pauses[attr.position] = duration_ms


func on_line_display_begin(line: Variant, text_control: Control = null) -> void:
	pass


## returns a timer signal if there is a pause at this character position.
func on_character_will_appear(
	character_index: int,
	line: Variant,
	cancellation_token: Variant = null
) -> Signal:
	if _pauses.has(character_index):
		var duration_sec := _pauses[character_index] / 1000.0
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			return tree.create_timer(duration_sec).timeout

	return Signal()


func on_line_display_complete() -> void:
	_pauses.clear()


func on_line_will_dismiss() -> void:
	_pauses.clear()
func has_pause_at(position: int) -> bool:
	return _pauses.has(position)


func get_pause_duration_ms(position: int) -> float:
	return _pauses.get(position, 0.0)


## returns the pause duration at a position in seconds.
func get_pause_duration(position: int) -> float:
	return _pauses.get(position, 0.0) / 1000.0
func get_all_pauses() -> Dictionary:
	return _pauses.duplicate()
