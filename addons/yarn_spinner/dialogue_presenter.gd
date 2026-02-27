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

@icon("res://addons/yarn_spinner/icons/dialogue_presenter.svg")
class_name YarnDialoguePresenter
extends Control
## base class for presenting yarn dialogue to the player.

## untyped to avoid circular dependency with YarnDialogueRunner
var dialogue_runner

var _cancellation_token: YarnCancellationToken


func on_dialogue_started() -> void:
	pass


func on_dialogue_completed() -> void:
	pass


func on_node_started(node_name: String) -> void:
	pass


func on_node_completed(node_name: String) -> void:
	pass


func prepare_for_lines(line_ids: PackedStringArray) -> void:
	pass


## return a Signal that completes when done, or call dialogue_runner.signal_content_complete().
func run_line(line: YarnLine) -> Variant:
	dialogue_runner.signal_content_complete()
	return null


## cancellation-aware version of run_line.
func run_line_with_token(line: YarnLine, token: YarnCancellationToken) -> Variant:
	_cancellation_token = token
	return run_line(line)


## return selected index, or -1 if not handling options.
func run_options(options: Array[YarnOption]) -> int:
	return -1


## cancellation-aware version of run_options.
func run_options_with_token(options: Array[YarnOption], token: YarnCancellationToken) -> int:
	_cancellation_token = token
	return await run_options(options)


func request_hurry_up() -> void:
	pass


func request_next() -> void:
	if dialogue_runner != null:
		dialogue_runner.signal_content_complete()
