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
## provides a typewriter effect, a continue indicator, and a list of
## [YarnActionMarkupHandler] event handlers that are invoked as each character
## is revealed.

## typewriter animation modes
enum TypewriterMode {
	INSTANT,  ## show all text immediately
	LETTER,   ## reveal one character at a time
	WORD,     ## reveal one word at a time
	CUSTOM,
}

## emitted when a line starts displaying
signal line_started(line: YarnLine)

## emitted when a line finishes displaying
signal line_finished(line: YarnLine)

## emitted when the line is dismissed from screen (after any fade-out).
## YarnLineAdvancer uses this to track presentation state.
signal line_dismissed(line: YarnLine)

## emitted when the player requests to continue
signal continue_requested()

@export var text_label: RichTextLabel
@export var character_label: Label
## hidden when no character name
@export var character_container: Control
@export var show_character_name_in_line: bool = true
## shown when line is fully revealed
@export var continue_indicator: Control

@export var typewriter_mode: TypewriterMode = TypewriterMode.LETTER
@export var custom_typewriter: YarnTypewriter
## Justify (fill-align) the body text, matching themes that set the line text to
## justified. Off by default so ordinary left-aligned presenters are unchanged.
@export var justify_text: bool = false

## characters per second for LETTER mode (0 = instant).
@export var characters_per_second: float = 60.0
@export var words_per_second: float = 10.0
@export var auto_advance: bool = false
## seconds to wait before auto-advancing.
@export var auto_advance_delay: float = 1.0
## fade the panel in and out around each line.
@export var use_fade_effect: bool = true
@export var fade_up_duration: float = 0.25
@export var fade_down_duration: float = 0.1
@export var continue_action: String = "ui_accept"
## Advance on any left click while a line is showing (never while options
## are up). Turn off if your game has clickable UI during dialogue.
@export var click_anywhere_to_continue: bool = true
@export var use_markup: bool = true

## display-time event handlers, invoked as each character is revealed.
## attach [YarnActionMarkupHandlerNode]s in your scene and list them here. a pause
## handler for [pause] markup is always added automatically, ahead of this list.
@export var event_handlers: Array[YarnActionMarkupHandlerNode] = []

var _is_displaying: bool = false
var _is_fully_revealed: bool = false
var _current_line: YarnLine
var _current_token: YarnCancellationToken
var _markup_parser: YarnMarkupParser
var _pause_processor: YarnPauseEventProcessor
## bumped whenever the current line changes or dialogue starts/ends, so a
## superseded line's coroutines can tell they are stale after an await.
var _line_generation := 0
var _hovering_meta: bool = false
var _marker_processors: Dictionary = {}


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
	if character_container == null and character_label != null:
		character_container = character_label
	if continue_indicator == null:
		continue_indicator = _find_child_by_name_contains("continue", "Control") as Control
		if continue_indicator == null:
			continue_indicator = _find_child_by_name_contains("indicator", "Control") as Control

	if continue_indicator != null:
		continue_indicator.visible = false

	if text_label != null:
		text_label.meta_hover_started.connect(_on_meta_hover_started)
		text_label.meta_hover_ended.connect(_on_meta_hover_ended)

	# A pause handler is always present so that [pause] markup works.
	_pause_processor = YarnPauseEventProcessor.new()


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


# Keys arrive via _unhandled_input so UI controls get first look at focus
# and confirm presses. Mouse clicks CANNOT live there: any Control under
# the cursor (the dialogue panel itself, a fullscreen fade ColorRect)
# consumes the click as GUI input first, and click-to-continue dies. So
# clicks are handled in _input, gated to exactly the window where
# click-anywhere is the intended UX: a line is displaying and options are
# not on screen. Set click_anywhere_to_continue false if your game needs
# clickable UI while lines are up.
func _unhandled_input(event: InputEvent) -> void:
	if not _can_take_advance_input():
		return

	if not continue_action.is_empty() and InputMap.has_action(continue_action) and event.is_action_pressed(continue_action):
		_advance_or_hurry()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not click_anywhere_to_continue:
		return
	if not _can_take_advance_input():
		return
	if _hovering_meta:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_advance_or_hurry()
			get_viewport().set_input_as_handled()


func _can_take_advance_input() -> bool:
	if not _is_displaying:
		return false
	if dialogue_runner == null:
		return false
	if dialogue_runner.has_line_advancer():
		return false
	# Don't consume input when options are showing — let buttons handle it
	if dialogue_runner.are_options_active():
		return false
	return true


func _advance_or_hurry() -> void:
	continue_requested.emit()
	if _is_fully_revealed:
		dialogue_runner.request_next_content()
	else:
		dialogue_runner.request_hurry_up()


func _on_meta_hover_started(_meta: Variant) -> void:
	_hovering_meta = true


func _on_meta_hover_ended(_meta: Variant) -> void:
	_hovering_meta = false


func on_dialogue_started() -> void:
	_line_generation += 1
	_set_presenter_visible(false)
	_is_displaying = false
	_is_fully_revealed = false
	_current_line = null
	_current_token = null
	_apply_marker_processors()


func on_dialogue_completed() -> void:
	_line_generation += 1
	_set_presenter_visible(false)
	_is_displaying = false
	_is_fully_revealed = false


func run_line(line: YarnLine, token: YarnCancellationToken = null) -> void:
	if text_label == null:
		push_error("line presenter: no text label is set, skipping line %s (\"%s\")" % [line.line_id, line.raw_text])
		return

	_line_generation += 1
	var generation := _line_generation
	_current_line = line
	_current_token = token
	_is_displaying = true
	_is_fully_revealed = false

	var markup := _choose_markup(line)
	var display_text := _to_display_text(markup)

	var active_typewriter := _build_typewriter()
	typewriter = active_typewriter
	active_typewriter.prepare_for_content(markup, display_text)

	# The continue indicator is visible for the whole line, not just once the
	# text has fully revealed.
	if continue_indicator != null:
		continue_indicator.visible = true

	var item := _get_presenter_canvas_item()
	_set_presenter_visible(true)
	line_started.emit(line)

	var hurried := func() -> bool:
		return token != null and token.is_hurry_up_requested

	if use_fade_effect:
		await _fade_presenter_alpha(0.0, 1.0, fade_up_duration, hurried)
	elif item != null:
		item.modulate.a = 1.0
	if generation != _line_generation:
		return

	await active_typewriter.run_typewriter(markup, display_text, token)
	if generation != _line_generation:
		return

	_is_fully_revealed = true
	line_finished.emit(line)

	if auto_advance:
		await _wait_for_auto_advance(token)
	elif token != null:
		await token.wait_for_next_content()
	if generation != _line_generation:
		return

	_is_displaying = false
	_is_fully_revealed = false
	active_typewriter.content_will_dismiss()

	if use_fade_effect:
		await _fade_presenter_alpha(1.0, 0.0, fade_down_duration, hurried)
	elif item != null:
		item.modulate.a = 0.0
	if generation != _line_generation:
		return

	active_typewriter.content_did_dismiss()

	if continue_indicator != null:
		continue_indicator.visible = false

	_set_presenter_visible(false)
	if item != null:
		item.modulate.a = 1.0
	_current_line = null
	_current_token = null
	line_dismissed.emit(line)


func _choose_markup(line: YarnLine) -> YarnMarkupParseResult:
	if character_label == null:
		if show_character_name_in_line:
			return line.get_markup_result()
		return line.get_markup_result_without_character_name()

	var name := line.character_name
	if character_container != null:
		if name.strip_edges().is_empty():
			character_container.visible = false
		else:
			character_container.visible = true
			character_label.text = name
	else:
		character_label.text = name

	return line.get_markup_result_without_character_name()


func _to_display_text(markup: YarnMarkupParseResult) -> String:
	var display_text: String
	if use_markup:
		display_text = _get_markup_parser().convert_to_bbcode(markup)
	else:
		display_text = YarnMarkupParser.escape_text(YarnMarkupParser.strip_bbcode_tags(markup.text))
	if justify_text:
		display_text = "[fill]%s[/fill]" % display_text
	return display_text


func _get_markup_parser() -> YarnMarkupParser:
	if dialogue_runner != null and dialogue_runner.get_line_provider() != null:
		return dialogue_runner.get_line_provider().get_markup_parser()
	if _markup_parser == null:
		_markup_parser = YarnMarkupParser.new()
	return _markup_parser


func _build_typewriter() -> YarnTypewriter:
	var handlers: Array = []
	if _pause_processor != null:
		handlers.append(_pause_processor)
	for handler in event_handlers:
		if handler != null:
			handlers.append(handler)

	var result: YarnTypewriter
	match typewriter_mode:
		TypewriterMode.INSTANT:
			result = YarnTypewriter.InstantTypewriter.new()
		TypewriterMode.LETTER:
			var letter := YarnTypewriter.LetterTypewriter.new()
			letter.characters_per_second = characters_per_second
			result = letter
		TypewriterMode.WORD:
			var word := YarnTypewriter.WordTypewriter.new()
			word.words_per_second = words_per_second
			result = word
		TypewriterMode.CUSTOM:
			if custom_typewriter == null:
				push_warning("line presenter: typewriter mode is set to custom but there is no typewriter set")
				result = YarnTypewriter.InstantTypewriter.new()
			else:
				result = custom_typewriter
				for handler in handlers:
					if handler not in result.action_markup_handlers:
						result.action_markup_handlers.append(handler)
				result.text_element = text_label
				return result

	result.action_markup_handlers = handlers
	result.text_element = text_label
	return result


func _wait_for_auto_advance(token: YarnCancellationToken) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var remaining := auto_advance_delay
	while remaining > 0.0:
		if token != null and token.is_next_content_requested:
			return
		await tree.process_frame
		if not is_inside_tree():
			return
		if not can_process():
			continue
		remaining -= get_process_delta_time()


## Registers a custom replacement-marker processor so that markup like
## [code][marker_name]...[/marker_name][/code] is transformed when this presenter
## renders a line.
func register_marker_processor(marker_name: String, processor: YarnAttributeMarkerProcessor) -> void:
	_marker_processors[marker_name] = processor
	_apply_marker_processors()


func _apply_marker_processors() -> void:
	if dialogue_runner == null or dialogue_runner.get_line_provider() == null:
		return
	var provider := dialogue_runner.get_line_provider()
	for marker_name in _marker_processors:
		provider.deregister_marker_processor(marker_name)
		provider.register_marker_processor(marker_name, _marker_processors[marker_name])
