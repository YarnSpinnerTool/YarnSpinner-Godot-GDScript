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

@icon("res://addons/yarn_spinner/icons/line_presenter.svg")
class_name YarnLinePresenter
extends YarnDialoguePresenter
## built-in presenter for displaying dialogue lines.
## provides typewriter effect and continue button functionality.

## typewriter animation modes
enum TypewriterMode {
	INSTANT,  ## show all text immediately
	LETTER,   ## reveal one character at a time
	WORD      ## reveal one word at a time
}

## emitted when a line starts displaying
signal line_started(line: YarnLine)

## emitted when a line finishes displaying
signal line_finished(line: YarnLine)

## emitted when the player requests to continue
signal continue_requested()

@export var text_label: RichTextLabel
@export var character_label: Label
## hidden when no character name
@export var character_container: Control
## shown when line is fully revealed
@export var continue_indicator: Control

@export var typewriter_mode: TypewriterMode = TypewriterMode.LETTER
## characters per second for LETTER mode (0 = instant)
@export var characters_per_second: float = 30.0
@export var words_per_second: float = 10.0
@export var auto_advance: bool = false
## seconds to wait before auto-advancing
@export var auto_advance_delay: float = 2.0
@export var continue_action: String = "ui_accept"
@export var hurry_action: String = "ui_accept"
@export var use_markup: bool = true

var _is_displaying: bool = false
var _is_fully_revealed: bool = false
var _current_line: YarnLine
var _typewriter_tween: Tween
var _markup_parser: YarnMarkupParser
var _word_positions: PackedInt32Array
signal _line_complete


func _ready() -> void:
	if text_label == null:
		text_label = _find_child_of_type("RichTextLabel") as RichTextLabel
		if text_label == null:
			# try finding a Label and use it (won't support BBCode)
			var label := _find_child_of_type("Label")
			if label != null:
				push_warning("YarnLinePresenter: No RichTextLabel found, BBCode markup will not work")
	if character_label == null:
		character_label = _find_child_by_name_contains("character", "Label") as Label
	if continue_indicator == null:
		continue_indicator = _find_child_by_name_contains("continue", "Control") as Control
		if continue_indicator == null:
			continue_indicator = _find_child_by_name_contains("indicator", "Control") as Control

	if continue_indicator != null:
		continue_indicator.visible = false


func _find_child_of_type(type_name: String) -> Node:
	return _find_child_of_type_recursive(self, type_name)


func _find_child_of_type_recursive(node: Node, type_name: String) -> Node:
	for child in node.get_children():
		if child.get_class() == type_name:
			return child
		var found := _find_child_of_type_recursive(child, type_name)
		if found != null:
			return found
	return null


func _find_child_by_name_contains(name_part: String, type_name: String) -> Node:
	return _find_child_by_name_recursive(self, name_part.to_lower(), type_name)


func _find_child_by_name_recursive(node: Node, name_part: String, type_name: String) -> Node:
	for child in node.get_children():
		if child.name.to_lower().contains(name_part):
			if type_name.is_empty() or child.get_class() == type_name or child.is_class(type_name):
				return child
		var found := _find_child_by_name_recursive(child, name_part, type_name)
		if found != null:
			return found
	return null


func _input(event: InputEvent) -> void:
	if not _is_displaying:
		return

	if event.is_action_pressed(continue_action):
		if _is_fully_revealed:
			_complete_line()
		else:
			request_hurry_up()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _is_fully_revealed:
				_complete_line()
			else:
				request_hurry_up()
			get_viewport().set_input_as_handled()


func on_dialogue_started() -> void:
	pass


func on_dialogue_completed() -> void:
	_set_presenter_visible(false)
	_is_displaying = false
	_is_fully_revealed = false
	_kill_typewriter_tween()


func _kill_typewriter_tween() -> void:
	if _typewriter_tween != null:
		if _typewriter_tween.is_valid() and _typewriter_tween.is_running():
			_typewriter_tween.kill()
		_typewriter_tween = null


func run_line(line: YarnLine) -> Variant:
	_current_line = line
	_is_displaying = true
	_is_fully_revealed = false

	_set_presenter_visible(true)

	if character_label != null:
		character_label.text = line.character_name
	if character_container != null:
		character_container.visible = not line.character_name.is_empty()

	var display_text: String
	if use_markup:
		if _markup_parser == null:
			_markup_parser = YarnMarkupParser.new()
		display_text = line.get_bbcode_text(_markup_parser)
	else:
		display_text = line.get_plain_text()

	if text_label != null:
		text_label.text = display_text
		text_label.visible_ratio = 0.0

	if continue_indicator != null:
		continue_indicator.visible = false

	line_started.emit(line)

	_kill_typewriter_tween()

	match typewriter_mode:
		TypewriterMode.INSTANT:
			if text_label != null:
				text_label.visible_ratio = 1.0
			_on_typewriter_complete()

		TypewriterMode.LETTER:
			if text_label != null and characters_per_second > 0 and display_text.length() > 0:
				var plain_text := line.get_plain_text()
				var duration := plain_text.length() / characters_per_second
				_typewriter_tween = create_tween()
				_typewriter_tween.tween_property(text_label, "visible_ratio", 1.0, duration)
				_typewriter_tween.finished.connect(_on_typewriter_complete, CONNECT_ONE_SHOT)
			else:
				if text_label != null:
					text_label.visible_ratio = 1.0
				_on_typewriter_complete()

		TypewriterMode.WORD:
			var plain_text := line.get_plain_text()
			_word_positions = _calculate_word_positions(plain_text)
			if text_label != null and words_per_second > 0 and _word_positions.size() > 0:
				var duration := _word_positions.size() / words_per_second
				_typewriter_tween = create_tween()
				_typewriter_tween.tween_method(_reveal_words, 0.0, 1.0, duration)
				_typewriter_tween.finished.connect(_on_typewriter_complete, CONNECT_ONE_SHOT)
			else:
				if text_label != null:
					text_label.visible_ratio = 1.0
				_on_typewriter_complete()

	return _line_complete


func _calculate_word_positions(text: String) -> PackedInt32Array:
	var positions := PackedInt32Array()
	var in_word := false
	for i in range(text.length()):
		var c := text[i]
		if c == " " or c == "\t" or c == "\n":
			in_word = false
		elif not in_word:
			in_word = true
			positions.append(i)
	# add end position
	positions.append(text.length())
	return positions


func _reveal_words(progress: float) -> void:
	if text_label == null or _word_positions.is_empty():
		return
	var word_index := int(progress * (_word_positions.size() - 1))
	word_index = clampi(word_index, 0, _word_positions.size() - 1)
	var char_pos := _word_positions[word_index]
	var plain_length := _word_positions[_word_positions.size() - 1]
	if plain_length > 0:
		text_label.visible_ratio = float(char_pos) / float(plain_length)


func _on_typewriter_complete() -> void:
	_is_fully_revealed = true
	line_finished.emit(_current_line)

	if continue_indicator != null:
		continue_indicator.visible = true

	if auto_advance and is_inside_tree():
		await get_tree().create_timer(auto_advance_delay).timeout
		if is_inside_tree() and _is_displaying and _is_fully_revealed:
			_complete_line()


func _complete_line() -> void:
	_is_displaying = false
	_is_fully_revealed = false
	_current_line = null

	if continue_indicator != null:
		continue_indicator.visible = false

	_line_complete.emit()


func request_hurry_up() -> void:
	if _typewriter_tween != null and _typewriter_tween.is_valid() and _typewriter_tween.is_running():
		_kill_typewriter_tween()
		if text_label != null:
			text_label.visible_ratio = 1.0
		_on_typewriter_complete()


func request_next() -> void:
	if _is_displaying:
		if _is_fully_revealed:
			_complete_line()
		else:
			request_hurry_up()
