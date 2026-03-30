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

@icon("res://addons/yarn_spinner/icons/options_presenter.svg")
class_name YarnOptionsPresenter
extends YarnDialoguePresenter
## Built-in presenter for displaying dialogue options.
## Creates buttons for each option and handles selection.
##
## When [member show_last_line] is enabled, the most recent dialogue line
## is shown above the options (matching Unity's OptionsPresenter behaviour).
## The [code][lastline][/code] markup tag can be used to truncate the
## displayed text at that point.

signal options_shown(options: Array[YarnOption])
signal option_selected(index: int, option: YarnOption)

@export_group("Options")

@export var options_container: Container

@export var option_button_scene: PackedScene

## Hide options whose is_available is false (instead of showing them greyed out).
@export var hide_unavailable: bool = false

## Input action prefix for keyboard shortcuts (e.g. "option_" → "option_1", "option_2").
@export var option_action_prefix: String = ""

@export_group("Last Line")

## Show the most recent dialogue line above the options.
@export var show_last_line: bool = false

## Label or RichTextLabel to display the last line's text.
## Only used when [member show_last_line] is enabled.
@export var last_line_text: Control

## Container holding the last line display (hidden when no last line).
@export var last_line_container: Control

## Label for the character name of the last line.
@export var last_line_character_name_text: Control

## Container for the character name (hidden when line has no character).
@export var last_line_character_name_container: Control


# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

const LASTLINE_MARKUP := "lastline"

var _is_showing_options: bool = false
var _current_options: Array[YarnOption] = []
var _option_buttons: Array[BaseButton] = []
var _button_pool: Array[BaseButton] = []
var _max_pool_size: int = 10
var _selected_index: int = -1
var _last_seen_line: YarnLine = null
var _button_callbacks: Dictionary = {}
signal _selection_made(index: int)


func _ready() -> void:
	if options_container == null:
		for child in get_children():
			if child is Container:
				options_container = child
				break


func run_line(line: YarnLine, _token: YarnCancellationToken = null) -> Variant:
	# Remember the last line for display above options (only if feature is on)
	if show_last_line:
		_last_seen_line = line
	return null


func _input(event: InputEvent) -> void:
	if not _is_showing_options or option_action_prefix.is_empty():
		return

	for i in range(_current_options.size()):
		var action := option_action_prefix + str(i + 1)
		if InputMap.has_action(action) and event.is_action_pressed(action):
			if _current_options[i].is_available:
				_select_option(i)
				get_viewport().set_input_as_handled()
				return


func on_dialogue_started() -> void:
	_set_presenter_visible(false)
	_clear_options()
	_last_seen_line = null
	_hide_last_line()


func on_dialogue_completed() -> void:
	_set_presenter_visible(false)
	var was_showing := _is_showing_options
	_is_showing_options = false
	_clear_options()
	_hide_last_line()
	_last_seen_line = null
	if was_showing:
		_selection_made.emit(-1)


func run_options(options: Array[YarnOption], _token: YarnCancellationToken = null) -> int:
	_current_options = options
	_is_showing_options = true
	_selected_index = -1

	_clear_options()
	_show_last_line()
	_create_option_buttons()

	_set_presenter_visible(true)
	options_shown.emit(options)

	for i in range(_option_buttons.size()):
		if not _option_buttons[i].disabled:
			_option_buttons[i].grab_focus()
			break

	return await _wait_for_selection()


# ---------------------------------------------------------------------------
# Last line display
# ---------------------------------------------------------------------------

func _show_last_line() -> void:
	if not show_last_line or _last_seen_line == null:
		_hide_last_line()
		return

	var line_text := _last_seen_line.text
	var char_name := _last_seen_line.character_name

	# Show character name separately if we have a nameplate
	if last_line_character_name_container != null:
		if char_name.is_empty():
			last_line_character_name_container.visible = false
		else:
			last_line_character_name_container.visible = true
			if last_line_character_name_text != null:
				_set_label_text(last_line_character_name_text, char_name)
			# Use text without character prefix when showing name separately
			line_text = _last_seen_line.text_without_character_name
	else:
		# No nameplate — use text without character prefix
		line_text = _last_seen_line.text_without_character_name

	# Handle [lastline] markup — show text AFTER the marker with "..." prefix
	# (matching Unity: truncates everything before the marker)
	var lastline_attr := _last_seen_line.try_get_attribute(LASTLINE_MARKUP)
	if lastline_attr != null and lastline_attr.position >= 0 and lastline_attr.position <= line_text.length():
		line_text = "..." + line_text.substr(lastline_attr.position).strip_edges()

	# Show the line text
	if last_line_text != null:
		_set_label_text(last_line_text, line_text)

	if last_line_container != null:
		last_line_container.visible = true


func _hide_last_line() -> void:
	if last_line_container != null:
		last_line_container.visible = false
	if last_line_character_name_container != null:
		last_line_character_name_container.visible = false


func _set_label_text(control: Control, value: String) -> void:
	if control is RichTextLabel:
		control.text = value
	elif control is Label:
		control.text = value
	elif control.has_method("set_text"):
		control.set_text(value)


# ---------------------------------------------------------------------------
# Option buttons
# ---------------------------------------------------------------------------

func _wait_for_selection() -> int:
	if not _is_showing_options:
		return _selected_index

	var result: int = await _selection_made
	return result


func _clear_options() -> void:
	for button in _option_buttons:
		_return_to_pool(button)
	_option_buttons.clear()


func _return_to_pool(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return

	if _button_callbacks.has(button):
		var callback: Callable = _button_callbacks[button]
		if button.pressed.is_connected(callback):
			button.pressed.disconnect(callback)
		_button_callbacks.erase(button)

	button.visible = false
	if button.get_parent() != null:
		button.get_parent().remove_child(button)

	if _button_pool.size() < _max_pool_size:
		_button_pool.append(button)
	else:
		button.queue_free()


func _get_pooled_button() -> BaseButton:
	while not _button_pool.is_empty():
		var button: BaseButton = _button_pool.pop_back()
		if is_instance_valid(button):
			button.visible = true
			button.disabled = false
			return button

	var button: BaseButton = null
	if option_button_scene != null:
		var instance := option_button_scene.instantiate()
		if instance is BaseButton:
			button = instance
		else:
			push_error("options presenter: option_button_scene must instantiate a BaseButton, got %s" % instance.get_class())
			if instance != null:
				instance.queue_free()

	if button == null:
		button = Button.new()

	return button


func _exit_tree() -> void:
	for button in _button_pool:
		if is_instance_valid(button):
			button.queue_free()
	_button_pool.clear()
	_button_callbacks.clear()


func _create_option_buttons() -> void:
	for i in range(_current_options.size()):
		var option := _current_options[i]

		if hide_unavailable and not option.is_available:
			continue

		var button := _get_pooled_button()

		if button is Button:
			button.text = option.get_plain_text()
			# Only apply default styling when no custom button scene is set.
			# When using a custom scene, respect its existing theme/size.
			if option_button_scene == null:
				button.custom_minimum_size = Vector2(0, 80)
				button.add_theme_font_size_override("font_size", 40)
		elif button.has_method("set_option_text"):
			button.set_option_text(option.get_plain_text())

		button.disabled = not option.is_available

		var index := i
		var callback := func(): _select_option(index)
		_button_callbacks[button] = callback
		button.pressed.connect(callback)

		if options_container != null:
			options_container.add_child(button)
		else:
			add_child(button)

		_option_buttons.append(button)


func _select_option(index: int) -> void:
	if not _is_showing_options:
		return

	if index < 0 or index >= _current_options.size():
		push_error("options presenter: invalid option index %d" % index)
		return

	var option := _current_options[index]
	if not option.is_available:
		return

	_selected_index = index
	_is_showing_options = false
	_set_presenter_visible(false)
	_hide_last_line()

	option_selected.emit(index, option)
	_selection_made.emit(index)

	_clear_options()
