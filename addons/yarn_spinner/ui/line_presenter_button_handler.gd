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

class_name YarnLinePresenterButtonHandler
extends YarnActionMarkupHandlerNode

@export var continue_button: BaseButton
@export var dialogue_runner: YarnDialogueRunner


func _ready() -> void:
	if continue_button == null:
		push_warning("line presenter button handler: the continue button is not set")
		return
	continue_button.disabled = true
	if dialogue_runner == null:
		dialogue_runner = YarnDialogueRunner.find_runner(self)


func on_prepare_for_line(_line: Variant, _text_control: Control = null) -> void:
	if continue_button == null:
		push_warning("line presenter button handler: the continue button is not set")
		return
	continue_button.disabled = false
	if not continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.pressed.connect(_on_continue_pressed)


func on_line_will_dismiss() -> void:
	if continue_button == null:
		return
	if continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.pressed.disconnect(_on_continue_pressed)
	continue_button.disabled = true


func _on_continue_pressed() -> void:
	if dialogue_runner == null:
		push_warning("line presenter button handler: the continue button was clicked, but the dialogue runner is not set")
		return
	dialogue_runner.request_next_content()
