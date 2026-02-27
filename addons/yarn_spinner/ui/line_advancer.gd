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

@icon("res://addons/yarn_spinner/icons/line_advancer.svg")
class_name YarnLineAdvancer
extends Node
## handles input for advancing dialogue lines.
## separates input handling from presentation.

enum InputMode {
	NONE,           ## manual control only
	INPUT_ACTION,   ## Godot Input actions
	KEY_CODE,       ## direct key codes
}

signal advance_requested()
signal hurry_up_requested()

@export var dialogue_runner: YarnDialogueRunner
@export var input_mode: InputMode = InputMode.INPUT_ACTION
@export var advance_action: String = "ui_accept"
@export var hurry_action: String = "ui_accept"
@export var advance_key: Key = KEY_SPACE
@export var hurry_key: Key = KEY_SPACE
## pressing once hurries, twice advances
@export var combine_hurry_and_advance: bool = true
## rapid presses required to force-advance (0 = disabled)
@export var multi_press_to_skip: int = 0
@export var multi_press_window: float = 0.5
## prevents double-triggers across frames
@export var block_input_one_frame: bool = true
@export var is_active: bool = true

var _is_presenting_line: bool = false
var _is_line_complete: bool = false
var _frames_since_advance: int = 0
var _press_times: Array[float] = []
var _last_input_frame: int = -1


func _ready() -> void:
	if dialogue_runner == null:
		dialogue_runner = _find_dialogue_runner()

	if dialogue_runner != null:
		_connect_dialogue_runner_signals()


func _find_dialogue_runner() -> YarnDialogueRunner:
	var parent := get_parent()
	while parent != null:
		if parent is YarnDialogueRunner:
			return parent
		for sibling in parent.get_children():
			if sibling is YarnDialogueRunner:
				return sibling
		parent = parent.get_parent()
	return null


func _connect_dialogue_runner_signals() -> void:
	if dialogue_runner == null:
		return

	if not dialogue_runner.dialogue_started.is_connected(_on_dialogue_started):
		dialogue_runner.dialogue_started.connect(_on_dialogue_started)
	if not dialogue_runner.dialogue_completed.is_connected(_on_dialogue_completed):
		dialogue_runner.dialogue_completed.connect(_on_dialogue_completed)


func _on_dialogue_started() -> void:
	_is_presenting_line = false
	_is_line_complete = false
	_frames_since_advance = 0


func _on_dialogue_completed() -> void:
	_is_presenting_line = false
	_is_line_complete = false


func on_line_presentation_started() -> void:
	_is_presenting_line = true
	_is_line_complete = false
	_frames_since_advance = 0


func on_line_fully_revealed() -> void:
	_is_line_complete = true


func on_line_presentation_ended() -> void:
	_is_presenting_line = false
	_is_line_complete = false


func _process(_delta: float) -> void:
	if block_input_one_frame:
		_frames_since_advance += 1


func _input(event: InputEvent) -> void:
	if not is_active:
		return

	if input_mode == InputMode.NONE:
		return

	var current_frame := Engine.get_process_frames()
	if current_frame == _last_input_frame:
		return

	if block_input_one_frame and _frames_since_advance < 2:
		return

	var advance_pressed := false
	var hurry_pressed := false

	match input_mode:
		InputMode.INPUT_ACTION:
			advance_pressed = event.is_action_pressed(advance_action)
			hurry_pressed = event.is_action_pressed(hurry_action)
		InputMode.KEY_CODE:
			if event is InputEventKey and event.pressed and not event.echo:
				advance_pressed = event.keycode == advance_key
				hurry_pressed = event.keycode == hurry_key

	if not advance_pressed and not hurry_pressed:
		return

	_last_input_frame = current_frame

	if multi_press_to_skip > 0:
		var current_time := Time.get_ticks_msec() / 1000.0
		_press_times.append(current_time)

		while _press_times.size() > 0 and current_time - _press_times[0] > multi_press_window:
			_press_times.remove_at(0)

		if _press_times.size() >= multi_press_to_skip:
			_press_times.clear()
			_frames_since_advance = 0
			advance_requested.emit()
			if dialogue_runner != null:
				dialogue_runner.request_next_content()
			get_viewport().set_input_as_handled()
			return

	if combine_hurry_and_advance:
		if _is_presenting_line and not _is_line_complete:
			hurry_up_requested.emit()
			if dialogue_runner != null:
				dialogue_runner.request_hurry_up()
		elif _is_line_complete:
			_frames_since_advance = 0
			advance_requested.emit()
			if dialogue_runner != null:
				dialogue_runner.request_next_content()
		get_viewport().set_input_as_handled()
		return

	if hurry_pressed and _is_presenting_line and not _is_line_complete:
		hurry_up_requested.emit()
		if dialogue_runner != null:
			dialogue_runner.request_hurry_up()
		get_viewport().set_input_as_handled()

	if advance_pressed and _is_line_complete:
		_frames_since_advance = 0
		advance_requested.emit()
		if dialogue_runner != null:
			dialogue_runner.request_next_content()
		get_viewport().set_input_as_handled()


func request_advance() -> void:
	_frames_since_advance = 0
	advance_requested.emit()
	if dialogue_runner != null:
		dialogue_runner.request_next_content()


func request_hurry_up() -> void:
	hurry_up_requested.emit()
	if dialogue_runner != null:
		dialogue_runner.request_hurry_up()
