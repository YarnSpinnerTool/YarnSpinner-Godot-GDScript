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

enum PresentationStatus {
	UNKNOWN,
	LINE_BEGAN,
	LINE_WAITING,
	OPTIONS_BEGAN,
	OPTIONS_WAITING,
}

signal advance_requested()
signal hurry_up_requested()
signal option_hurry_up_requested()
signal dialogue_cancellation_requested()

@export var dialogue_runner: YarnDialogueRunner
@export var input_mode: InputMode = InputMode.INPUT_ACTION
@export var advance_action: String = "ui_cancel"
@export var hurry_action: String = "ui_accept"
@export var option_hurry_action: String = "ui_accept"
@export var cancel_dialogue_action: String = ""
@export var advance_key: Key = KEY_ESCAPE
@export var hurry_key: Key = KEY_SPACE
@export var option_hurry_key: Key = KEY_SPACE
@export var cancel_dialogue_key: Key = KEY_NONE
## pressing once hurries, twice advances
@export var combine_hurry_and_advance: bool = true
## hurry presses on one line required to force-advance (0 = disabled)
@export var multi_press_to_skip: int = 0
@export var multi_press_window: float = 0.0
## ignores hurry presses on the frame new content arrives
@export var block_input_one_frame: bool = true
@export var is_active: bool = true

var _status: PresentationStatus = PresentationStatus.UNKNOWN
var _number_of_advances_this_line: int = 0
var _press_times: Array[float] = []
var _frame_content_received: int = -1
var _is_dialogue_running: bool = false
var _current_line: YarnLine
var _registered_runner: YarnDialogueRunner


func _ready() -> void:
	if dialogue_runner == null:
		dialogue_runner = _find_dialogue_runner()

	if dialogue_runner != null:
		_connect_dialogue_runner_signals()


func _enter_tree() -> void:
	if is_node_ready() and dialogue_runner != null:
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


func _exit_tree() -> void:
	if dialogue_runner != null:
		if dialogue_runner.dialogue_started.is_connected(_on_dialogue_started):
			dialogue_runner.dialogue_started.disconnect(_on_dialogue_started)
		if dialogue_runner.dialogue_completed.is_connected(_on_dialogue_completed):
			dialogue_runner.dialogue_completed.disconnect(_on_dialogue_completed)
	if _registered_runner != null and is_instance_valid(_registered_runner):
		_registered_runner.unregister_line_advancer(self)
	_registered_runner = null


func _connect_dialogue_runner_signals() -> void:
	if dialogue_runner == null:
		return

	if not dialogue_runner.dialogue_started.is_connected(_on_dialogue_started):
		dialogue_runner.dialogue_started.connect(_on_dialogue_started)
	if not dialogue_runner.dialogue_completed.is_connected(_on_dialogue_completed):
		dialogue_runner.dialogue_completed.connect(_on_dialogue_completed)

	if _registered_runner != dialogue_runner:
		if _registered_runner != null and is_instance_valid(_registered_runner):
			_registered_runner.unregister_line_advancer(self)
		dialogue_runner.register_line_advancer(self)
		_registered_runner = dialogue_runner


func _on_dialogue_started() -> void:
	_is_dialogue_running = true
	_current_line = null
	_reset_line_tracking()
	_connect_dialogue_runner_signals()
	# Presenters are discovered by the runner's _ready, which runs after
	# ours when we're its child — so bind to line presenters here, at the
	# first moment the merged presenter list is guaranteed complete.
	_connect_line_presenter_signals()


func _connect_line_presenter_signals() -> void:
	if dialogue_runner == null:
		return
	for presenter in dialogue_runner.get_presenters():
		if presenter is YarnLinePresenter:
			var lp := presenter as YarnLinePresenter
			if not lp.line_started.is_connected(_on_line_started):
				lp.line_started.connect(_on_line_started)
			if not lp.line_finished.is_connected(_on_line_finished):
				lp.line_finished.connect(_on_line_finished)
			if not lp.line_dismissed.is_connected(_on_line_dismissed):
				lp.line_dismissed.connect(_on_line_dismissed)


func _on_line_started(line: YarnLine) -> void:
	_current_line = line
	on_line_presentation_started()


func _on_line_finished(_line: YarnLine) -> void:
	on_line_fully_revealed()


func _on_line_dismissed(line: YarnLine) -> void:
	if _current_line != null and line != _current_line:
		return
	_current_line = null
	on_line_presentation_ended()


func _on_dialogue_completed() -> void:
	_is_dialogue_running = false
	_current_line = null
	_reset_line_tracking()


func on_line_presentation_started() -> void:
	_reset_line_tracking()
	_status = PresentationStatus.LINE_BEGAN
	_frame_content_received = _get_runner_content_frame()


func on_line_fully_revealed() -> void:
	if _status == PresentationStatus.LINE_BEGAN:
		_status = PresentationStatus.LINE_WAITING
	elif _status == PresentationStatus.OPTIONS_BEGAN:
		_status = PresentationStatus.OPTIONS_WAITING


func on_line_presentation_ended() -> void:
	if _status == PresentationStatus.LINE_BEGAN or _status == PresentationStatus.LINE_WAITING:
		_status = PresentationStatus.UNKNOWN


func _get_runner_content_frame() -> int:
	if dialogue_runner != null:
		return dialogue_runner.get_content_frame()
	return Engine.get_process_frames()


func _is_options_status() -> bool:
	return _status == PresentationStatus.OPTIONS_BEGAN or _status == PresentationStatus.OPTIONS_WAITING


func _is_line_status() -> bool:
	return _status == PresentationStatus.LINE_BEGAN or _status == PresentationStatus.LINE_WAITING


func _sync_with_runner() -> void:
	if dialogue_runner == null:
		return
	var content_frame := dialogue_runner.get_content_frame()
	if dialogue_runner.are_options_active():
		if not _is_options_status() or content_frame != _frame_content_received:
			_reset_line_tracking()
			_status = PresentationStatus.OPTIONS_BEGAN
			_frame_content_received = content_frame
	elif _is_options_status():
		_status = PresentationStatus.UNKNOWN
	elif dialogue_runner.is_presenting_line() and content_frame != _frame_content_received:
		_reset_line_tracking()
		_status = PresentationStatus.LINE_BEGAN
		_frame_content_received = content_frame


func _is_content_frame() -> bool:
	if not block_input_one_frame:
		return false
	var current_frame := Engine.get_process_frames()
	if dialogue_runner != null and dialogue_runner.get_content_frame() == current_frame:
		return true
	return _frame_content_received == current_frame


func _reset_line_tracking() -> void:
	_number_of_advances_this_line = 0
	_press_times.clear()
	_status = PresentationStatus.UNKNOWN


func _count_advance() -> bool:
	_number_of_advances_this_line += 1
	var count := _number_of_advances_this_line
	if multi_press_window > 0.0:
		var current_time := Time.get_ticks_msec() / 1000.0
		_press_times.append(current_time)
		while _press_times.size() > 0 and current_time - _press_times[0] > multi_press_window:
			_press_times.remove_at(0)
		count = _press_times.size()
	return multi_press_to_skip > 0 and count >= multi_press_to_skip


func _process(_delta: float) -> void:
	_sync_with_runner()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return

	if input_mode == InputMode.NONE:
		return

	var hurry_line_pressed := _event_matches(event, hurry_action, hurry_key)
	var next_line_pressed := _event_matches(event, advance_action, advance_key)
	var hurry_options_pressed := _event_matches(event, option_hurry_action, option_hurry_key)
	var cancel_pressed := _event_matches(event, cancel_dialogue_action, cancel_dialogue_key)

	if not (hurry_line_pressed or next_line_pressed or hurry_options_pressed or cancel_pressed):
		return

	if not _is_dialogue_running:
		return

	_sync_with_runner()

	var handled := false
	if hurry_line_pressed:
		handled = _on_input_hurry_up_lines() or handled
	if next_line_pressed:
		handled = _on_input_next_content() or handled
	if hurry_options_pressed:
		handled = _on_input_hurry_up_options() or handled
	if cancel_pressed:
		handled = _on_input_cancel_dialogue() or handled

	if handled:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _event_matches(event: InputEvent, action: String, key: Key) -> bool:
	match input_mode:
		InputMode.INPUT_ACTION:
			if action.is_empty() or not InputMap.has_action(action):
				return false
			return event.is_action_pressed(action)
		InputMode.KEY_CODE:
			if key == KEY_NONE:
				return false
			if event is InputEventKey and event.pressed and not event.echo:
				return event.keycode == key
	return false


func _has_line_content() -> bool:
	if _is_line_status():
		return true
	return dialogue_runner != null and dialogue_runner.is_presenting_line()


func _has_options_content() -> bool:
	if dialogue_runner != null:
		return dialogue_runner.are_options_active()
	return _is_options_status()


func _on_input_hurry_up_lines() -> bool:
	return _request_line_hurry_up_internal()


func _on_input_next_content() -> bool:
	var acted := _has_line_content()
	request_next_line()
	return acted


func _on_input_hurry_up_options() -> bool:
	var acted := _has_options_content()
	return _request_option_hurry_up_internal() and acted


func _on_input_cancel_dialogue() -> bool:
	request_dialogue_cancellation()
	return true


func _request_line_hurry_up_internal() -> bool:
	if _is_content_frame():
		return false

	if combine_hurry_and_advance and not _is_line_status():
		return false

	var acted := _has_line_content()

	if _count_advance():
		request_next_line()
	elif not combine_hurry_and_advance:
		_send_hurry_up()
	elif _status == PresentationStatus.LINE_WAITING:
		request_next_line()
	else:
		_send_hurry_up()
	return acted


func _send_hurry_up() -> void:
	hurry_up_requested.emit()
	if dialogue_runner != null:
		dialogue_runner.request_hurry_up()
	else:
		push_error("YarnLineAdvancer: dialogue runner is null")


func request_line_hurry_up() -> void:
	if _count_advance():
		request_next_line()
	else:
		_send_hurry_up()


func request_option_hurry_up() -> void:
	_request_option_hurry_up_internal()


func _request_option_hurry_up_internal() -> bool:
	if _is_content_frame():
		return false

	if dialogue_runner == null:
		push_error("YarnLineAdvancer: unable to hurry up options, dialogue runner is null")
		return false

	_sync_with_runner()
	if combine_hurry_and_advance and not _is_options_status():
		return false

	option_hurry_up_requested.emit()
	dialogue_runner.request_hurry_up_option()
	return true


func request_next_line() -> void:
	_reset_line_tracking()
	advance_requested.emit()
	if dialogue_runner != null:
		dialogue_runner.request_next_content()
	else:
		push_error("YarnLineAdvancer: dialogue runner is null")


func request_dialogue_cancellation() -> void:
	_reset_line_tracking()
	dialogue_cancellation_requested.emit()
	if dialogue_runner != null:
		dialogue_runner.stop_dialogue()


func request_advance() -> void:
	request_next_line()


func request_hurry_up() -> void:
	request_line_hurry_up()
