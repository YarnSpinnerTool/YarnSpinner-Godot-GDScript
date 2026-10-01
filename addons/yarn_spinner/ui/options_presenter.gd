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
## is shown above the options.
## The [code][lastline][/code] markup tag can be used to truncate the
## displayed text at that point.

signal options_shown(options: Array[YarnOption])
signal option_selected(index: int, option: YarnOption)

@export_group("Options")

@export var options_container: Container

## Scene instantiated per option. The root may be a [YarnOptionItem] (preferred) or any
## [BaseButton]. Edit the default scene or point this at your own to
## restyle options.
@export var option_button_scene: PackedScene = preload("res://addons/yarn_spinner/ui/option_item.tscn")

## Hide options whose is_available is false (instead of showing them greyed out).
@export var hide_unavailable: bool = true

## Input action prefix for keyboard shortcuts (e.g. "option_" → "option_1", "option_2").
@export var option_action_prefix: String = ""

@export_group("Fade")

## fade the panel in and out around the options.
@export var use_fade_effect: bool = true
@export var fade_up_duration: float = 0.25
@export var fade_down_duration: float = 0.1

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
var _current_token: YarnCancellationToken
var _option_buttons: Array[Control] = []
var _button_pool: Array[Control] = []
var _max_pool_size: int = 10
var _selected_index: int = -1
var _last_seen_line: YarnLine = null
var _button_callbacks: Dictionary = {}
var _markup_parser: YarnMarkupParser
signal _selection_made(index: int)


func _ready() -> void:
	if options_container == null:
		for child in get_children():
			if child is Container:
				options_container = child
				break
	if last_line_container == null and last_line_text != null:
		last_line_container = last_line_text
	if last_line_character_name_container == null and last_line_character_name_text != null:
		last_line_character_name_container = last_line_character_name_text


func run_line(line: YarnLine, _token: YarnCancellationToken = null) -> void:
	# Remember the last line for display above options (only if feature is on)
	if show_last_line:
		_last_seen_line = line


func _unhandled_input(event: InputEvent) -> void:
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


func run_options(options: Array[YarnOption], token: YarnCancellationToken = null) -> int:
	if token != null and token.is_next_content_requested:
		return -1

	# If every option is unavailable there is nothing to present; decline
	# and let the runner's fallthrough handling decide what happens.
	var any_available := false
	for option in options:
		if option.is_available:
			any_available = true
			break
	if not any_available:
		return -1

	_current_options = options
	_current_token = token
	_is_showing_options = true
	_selected_index = -1

	_clear_options()
	_show_last_line()
	_create_option_buttons()

	_set_presenter_visible(true)
	options_shown.emit(options)

	for item in _option_buttons:
		if item is YarnOptionItem:
			var opt_item := item as YarnOptionItem
			if opt_item.is_available:
				opt_item.grab_focus_if_available()
				break
		elif item is BaseButton and not (item as BaseButton).disabled:
			(item as BaseButton).grab_focus()
			break

	# Honour the wind-down contract: when the token fires (option timeout,
	# or another presenter selected first), dismiss the buttons and finish
	# with "no selection" instead of staying parked on a click forever.
	var on_wind_down := func() -> void:
		if _is_showing_options:
			_is_showing_options = false
			_set_presenter_visible(false)
			_clear_options()
			_selection_made.emit(-1)
	if token != null:
		token.next_content_requested.connect(on_wind_down, CONNECT_ONE_SHOT)

	if use_fade_effect:
		await _fade_presenter_alpha(0.0, 1.0, fade_up_duration, _hurry_check(token))

	var result: int = await _wait_for_selection()

	if token != null and token.next_content_requested.is_connected(on_wind_down):
		token.next_content_requested.disconnect(on_wind_down)

	_current_token = null

	if token != null and token.is_next_content_requested:
		return -1

	return result


static func _hurry_check(token: YarnCancellationToken) -> Callable:
	return func() -> bool:
		return token != null and token.is_hurry_up_requested


# ---------------------------------------------------------------------------
# Last line display
# ---------------------------------------------------------------------------

func _show_last_line() -> void:
	if not show_last_line or _last_seen_line == null:
		_hide_last_line()
		return

	var markup := _last_seen_line.get_markup_result()
	var char_name := _last_seen_line.character_name

	# Show character name separately if we have a nameplate
	if last_line_character_name_container != null:
		if char_name.strip_edges().is_empty():
			last_line_character_name_container.visible = false
		else:
			markup = _last_seen_line.get_markup_result_without_character_name()
			last_line_character_name_container.visible = true
			if last_line_character_name_text != null:
				_set_label_text(last_line_character_name_text, char_name)
	else:
		markup = _last_seen_line.get_markup_result_without_character_name()

	# Handle [lastline] markup: truncate everything before the marker and show
	# the text after it with a "..." prefix
	var prefix := ""
	var lastline_attr := markup.try_get_attribute_with_name(LASTLINE_MARKUP)
	if lastline_attr != null and lastline_attr.position <= markup.text.length():
		markup = markup.delete_range(YarnMarkupAttribute.new(0, 0, lastline_attr.position, "", []))
		prefix = "..."

	# Show the line text
	if last_line_text != null:
		if last_line_text is RichTextLabel:
			(last_line_text as RichTextLabel).text = prefix + _get_markup_parser().convert_to_bbcode(markup)
		else:
			_set_label_text(last_line_text, prefix + YarnMarkupParser.strip_bbcode_tags(markup.text))

	if last_line_container != null:
		last_line_container.visible = true


func _get_markup_parser() -> YarnMarkupParser:
	if dialogue_runner != null and dialogue_runner.get_line_provider() != null:
		return dialogue_runner.get_line_provider().get_markup_parser()
	if _markup_parser == null:
		_markup_parser = YarnMarkupParser.new()
	return _markup_parser


func _hide_last_line() -> void:
	if last_line_container != null:
		last_line_container.visible = false
	if last_line_character_name_container != null:
		last_line_character_name_container.visible = false


func _set_label_text(control: Control, value: String) -> void:
	if control is RichTextLabel:
		control.text = YarnMarkupParser.escape_text(value)
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


func _return_to_pool(item: Control) -> void:
	if not is_instance_valid(item):
		return

	if _button_callbacks.has(item):
		var callback: Callable = _button_callbacks[item]
		if item is YarnOptionItem:
			var opt_item := item as YarnOptionItem
			if opt_item.option_selected.is_connected(callback):
				opt_item.option_selected.disconnect(callback)
		elif item is BaseButton:
			var button := item as BaseButton
			if button.pressed.is_connected(callback):
				button.pressed.disconnect(callback)
		_button_callbacks.erase(item)

	if item is YarnOptionItem:
		(item as YarnOptionItem).reset()
	item.visible = false
	if item.get_parent() != null:
		item.get_parent().remove_child(item)

	if _button_pool.size() < _max_pool_size:
		_button_pool.append(item)
	else:
		item.queue_free()


func _get_pooled_item() -> Control:
	while not _button_pool.is_empty():
		var pooled: Control = _button_pool.pop_back()
		if is_instance_valid(pooled):
			pooled.visible = true
			if pooled is BaseButton:
				(pooled as BaseButton).disabled = false
			return pooled

	var button: Control = null
	if option_button_scene != null:
		var instance := option_button_scene.instantiate()
		if instance is YarnOptionItem or instance is BaseButton:
			button = instance
		else:
			push_error("options presenter: option_button_scene must instantiate a YarnOptionItem or BaseButton, got %s" % instance.get_class())
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

		var item := _get_pooled_item()

		if item is YarnOptionItem:
			var opt_item := item as YarnOptionItem
			opt_item.setup(option, i)
			var item_callback := func(idx: int): _select_option(idx)
			_button_callbacks[item] = item_callback
			opt_item.option_selected.connect(item_callback)
		elif item is Button:
			var button := item as Button
			button.text = YarnMarkupParser.strip_bbcode_tags(option.text_without_character_name)
			# Only apply default styling when no custom button scene is set.
			# When using a custom scene, respect its existing theme/size.
			if option_button_scene == null:
				button.custom_minimum_size = Vector2(0, 80)
				button.add_theme_font_size_override("font_size", 40)
			button.disabled = not option.is_available
			var index := i
			var callback := func(): _select_option(index)
			_button_callbacks[button] = callback
			button.pressed.connect(callback)
		elif item.has_method("set_option_text"):
			item.set_option_text(option.get_plain_text())

		if options_container != null:
			options_container.add_child(item)
		else:
			add_child(item)

		_option_buttons.append(item)


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

	if use_fade_effect:
		await _fade_presenter_alpha(1.0, 0.0, fade_down_duration, _hurry_check(_current_token))

	_set_presenter_visible(false)
	var item := _get_presenter_canvas_item()
	if item != null:
		item.modulate.a = 1.0
	_hide_last_line()

	option_selected.emit(index, option)
	_selection_made.emit(index)

	_clear_options()
