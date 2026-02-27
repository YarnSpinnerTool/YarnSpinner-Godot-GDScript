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

class_name YarnActionMarkupHandler
extends RefCounted
## interface for handling markup actions during typewriter presentation.
## runs at display-time to react to text being revealed (unlike replacement
## marker processors, which run at parse-time and modify text).
## subclass and override the methods needed for the desired effect.


## called before any text is visible. set up state here.
func on_prepare_for_line(line: Variant, text_control: Control = null) -> void:
	pass


## called immediately before the first character is presented.
func on_line_display_begin(line: Variant, text_control: Control = null) -> void:
	pass


## called for each character during typewriter reveal.
## return a Signal to pause the typewriter, or empty Signal() to continue.
func on_character_will_appear(
	character_index: int,
	line: Variant,
	cancellation_token: Variant = null
) -> Signal:
	return Signal()


## called after all characters have been presented.
func on_line_display_complete() -> void:
	pass


## called right before the line dismisses (may be after typewriter completes).
func on_line_will_dismiss() -> void:
	pass


static func is_index_in_attribute(index: int, attr: YarnMarkupAttribute) -> bool:
	return index >= attr.position and index < attr.position + attr.length


## returns all attributes covering a specific character index.
static func get_attributes_at_index(
	index: int,
	attributes: Array
) -> Array[YarnMarkupAttribute]:
	var result: Array[YarnMarkupAttribute] = []
	for attr in attributes:
		if attr is YarnMarkupAttribute and is_index_in_attribute(index, attr):
			result.append(attr)
	return result


# =============================================================================
# SHAKE EFFECT HANDLER
# =============================================================================
## shakes the text container during [shake] markup.
class ShakeActionHandler extends YarnActionMarkupHandler:
	## the control to shake
	var target: Control

	## shake intensity in pixels
	var intensity: float = 3.0

	## shakes per second
	var frequency: float = 30.0

	var _original_position: Vector2
	var _attributes: Array = []
	var _shake_time: float = 0.0


	func _init(shake_target: Control, shake_intensity: float = 3.0) -> void:
		target = shake_target
		intensity = shake_intensity


	func on_prepare_for_line(line: Variant, text_control: Control = null) -> void:
		if target != null:
			_original_position = target.position
		_shake_time = 0.0
		_attributes = []
		if line is YarnMarkupParseResult:
			_attributes = line.attributes.duplicate()
		elif line is YarnLine:
			_attributes = line.markup_attributes.duplicate()


	func on_character_will_appear(
		character_index: int,
		line: Variant,
		cancellation_token: Variant = null
	) -> Signal:
		var should_shake := false
		var active := get_attributes_at_index(character_index, _attributes)
		for attr in active:
			if attr.name == "shake":
				should_shake = true
				break

		if should_shake and target != null:
			_shake_time += 1.0 / frequency
			var offset := Vector2(
				sin(_shake_time * frequency * TAU) * intensity,
				cos(_shake_time * frequency * TAU * 0.7) * intensity * 0.5
			)
			target.position = _original_position + offset

		return Signal()


	func on_line_display_complete() -> void:
		if target != null:
			target.position = _original_position


	func on_line_will_dismiss() -> void:
		if target != null:
			target.position = _original_position


# =============================================================================
# WAVE EFFECT HANDLER
# =============================================================================
## wave effect for [wave] markup. requires shader or custom rendering
## for per-character animation; stub for api compatibility.
class WaveActionHandler extends YarnActionMarkupHandler:
	## wave amplitude in pixels
	var amplitude: float = 2.0

	## wave speed
	var speed: float = 5.0


	func on_character_will_appear(
		character_index: int,
		line: Variant,
		cancellation_token: Variant = null
	) -> Signal:
		return Signal()


# =============================================================================
# COLOR PULSE HANDLER
# =============================================================================
## colour pulse for [pulse] markup. requires shader or custom bbcode
## for proper per-character pulsing; stub for api compatibility.
class ColorPulseActionHandler extends YarnActionMarkupHandler:
	var label: RichTextLabel
	var color_a: Color = Color.WHITE
	var color_b: Color = Color.YELLOW
	## cycles per second
	var speed: float = 3.0


	func _init(target_label: RichTextLabel, from_color: Color = Color.WHITE, to_color: Color = Color.YELLOW) -> void:
		label = target_label
		color_a = from_color
		color_b = to_color


	func on_character_will_appear(
		character_index: int,
		line: Variant,
		cancellation_token: Variant = null
	) -> Signal:
		return Signal()


# =============================================================================
# CONTINUE BUTTON HANDLER
# =============================================================================
## controls a "continue" button during line presentation.
## shows the button when a line starts, hides on dismiss, requests next
## line on click.
class ContinueButtonHandler extends YarnActionMarkupHandler:
	var continue_button: Button
	var dialogue_runner: Node  # YarnDialogueRunner
	var _button_pressed: bool = false


	func _init(button: Button, runner: Node = null) -> void:
		continue_button = button
		dialogue_runner = runner


	func on_prepare_for_line(line: Variant, text_control: Control = null) -> void:
		_button_pressed = false
		if continue_button != null:
			continue_button.visible = true
			if not continue_button.pressed.is_connected(_on_button_pressed):
				continue_button.pressed.connect(_on_button_pressed)


	func on_character_will_appear(
		character_index: int,
		line: Variant,
		cancellation_token: Variant = null
	) -> Signal:
		return Signal()


	func on_line_display_complete() -> void:
		pass


	func on_line_will_dismiss() -> void:
		if continue_button != null:
			continue_button.visible = false
			if continue_button.pressed.is_connected(_on_button_pressed):
				continue_button.pressed.disconnect(_on_button_pressed)


	func _on_button_pressed() -> void:
		_button_pressed = true
		if dialogue_runner != null and dialogue_runner.has_method("request_next_line"):
			dialogue_runner.request_next_line()
