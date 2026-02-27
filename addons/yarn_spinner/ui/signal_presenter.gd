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
class_name YarnSignalPresenter
extends YarnDialoguePresenter
## presenter that emits signals for all dialogue events.
## designed for visual scripting tools that connect signals and call
## methods instead of subclassing presenters.
##
## add as a child of a YarnDialogueRunner. connect signals to drive
## dialogue flow. call proceed() and choose_option() to advance.

## line_data keys: text, character_name, line_id, metadata, bbcode_text
signal line_received(line_data: Dictionary)
## each element: text, option_index, is_available, line_id, metadata
signal options_received(options_data: Array)
signal presenter_dialogue_started()
signal presenter_dialogue_completed()
signal presenter_node_started(node_name: String)
signal presenter_node_completed(node_name: String)

@export var include_bbcode: bool = true

var current_line_data: Dictionary = {}
var current_options_data: Array = []
var is_waiting_for_proceed: bool = false
var is_waiting_for_choice: bool = false
signal _line_complete
signal _option_selected(index: int)
var _markup_parser: YarnMarkupParser
var _stored_options: Array[YarnOption] = []


# -- public methods (call from visual scripts) --

func proceed() -> void:
	if is_waiting_for_proceed:
		is_waiting_for_proceed = false
		_line_complete.emit()


func choose_option(index: int) -> void:
	if not is_waiting_for_choice:
		return
	if index < 0 or index >= _stored_options.size():
		push_error("YarnSignalPresenter: invalid option index %d (have %d options)" % [index, _stored_options.size()])
		return
	is_waiting_for_choice = false
	_option_selected.emit(index)


func get_current_text() -> String:
	return current_line_data.get("text", "")


func get_current_character() -> String:
	return current_line_data.get("character_name", "")


func get_option_count() -> int:
	return current_options_data.size()


func get_option_text(index: int) -> String:
	if index < 0 or index >= current_options_data.size():
		return ""
	return current_options_data[index].get("text", "")


func is_option_available(index: int) -> bool:
	if index < 0 or index >= current_options_data.size():
		return false
	return current_options_data[index].get("is_available", false)


# -- presenter overrides --

func run_line(line: YarnLine) -> Variant:
	current_line_data = _build_line_dict(line)
	current_options_data = []
	is_waiting_for_proceed = true
	is_waiting_for_choice = false

	line_received.emit(current_line_data)
	return _line_complete


func run_options(options: Array[YarnOption]) -> int:
	_stored_options = options
	current_options_data = _build_options_array(options)
	current_line_data = {}
	is_waiting_for_proceed = false
	is_waiting_for_choice = true

	options_received.emit(current_options_data)

	var selected: int = await _option_selected
	return selected


func on_dialogue_started() -> void:
	current_line_data = {}
	current_options_data = []
	is_waiting_for_proceed = false
	is_waiting_for_choice = false
	presenter_dialogue_started.emit()


func on_dialogue_completed() -> void:
	var was_waiting_proceed := is_waiting_for_proceed
	var was_waiting_choice := is_waiting_for_choice
	current_line_data = {}
	current_options_data = []
	is_waiting_for_proceed = false
	is_waiting_for_choice = false
	_stored_options = []

	if was_waiting_proceed:
		_line_complete.emit()
	if was_waiting_choice:
		_option_selected.emit(-1)

	presenter_dialogue_completed.emit()


func on_node_started(node_name: String) -> void:
	presenter_node_started.emit(node_name)


func on_node_completed(node_name: String) -> void:
	presenter_node_completed.emit(node_name)


# -- internal helpers --

func _build_line_dict(line: YarnLine) -> Dictionary:
	var data: Dictionary = {
		"text": line.get_plain_text(),
		"character_name": line.character_name,
		"line_id": line.line_id,
		"metadata": Array(line.metadata),
	}
	if include_bbcode:
		if _markup_parser == null:
			_markup_parser = YarnMarkupParser.new()
		data["bbcode_text"] = line.get_bbcode_text(_markup_parser)
	else:
		data["bbcode_text"] = ""
	return data


func _build_options_array(options: Array[YarnOption]) -> Array:
	var arr: Array = []
	for option in options:
		arr.append({
			"text": option.get_plain_text(),
			"option_index": option.option_index,
			"is_available": option.is_available,
			"line_id": option.line_id,
			"metadata": Array(option.metadata),
		})
	return arr
