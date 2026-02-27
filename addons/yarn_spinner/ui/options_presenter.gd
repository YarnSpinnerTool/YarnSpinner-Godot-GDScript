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
## built-in presenter for displaying dialogue options.
## creates buttons for each option and handles selection.

signal options_shown(options: Array[YarnOption])
signal option_selected(index: int, option: YarnOption)

@export var options_container: Container
@export var option_button_scene: PackedScene
@export var hide_unavailable: bool = false
## input action prefix for keyboard shortcuts (e.g. "option_1", "option_2")
@export var option_action_prefix: String = ""

var _is_showing_options: bool = false
var _current_options: Array[YarnOption] = []
var _option_buttons: Array[BaseButton] = []
var _button_pool: Array[BaseButton] = []
var _max_pool_size: int = 10
var _selected_index: int = -1
signal _selection_made(index: int)


func _ready() -> void:
	if options_container == null:
		for child in get_children():
			if child is Container:
				options_container = child
				break


func run_line(_line: YarnLine) -> Variant:
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


func on_dialogue_completed() -> void:
	_set_presenter_visible(false)
	var was_showing := _is_showing_options
	_is_showing_options = false
	_clear_options()
	if was_showing:
		_selection_made.emit(-1)


func run_options(options: Array[YarnOption]) -> int:
	_current_options = options
	_is_showing_options = true
	_selected_index = -1

	_clear_options()
	_create_option_buttons()

	_set_presenter_visible(true)
	options_shown.emit(options)

	for i in range(_option_buttons.size()):
		if not _option_buttons[i].disabled:
			_option_buttons[i].grab_focus()
			break

	return await _wait_for_selection()


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


var _button_callbacks: Dictionary = {}


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

	option_selected.emit(index, option)
	_selection_made.emit(index)

	_clear_options()
