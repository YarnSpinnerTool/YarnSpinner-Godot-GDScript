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
## is revealed (mirroring Yarn Spinner for Unity's LinePresenter).

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

## emitted when the line is dismissed from screen (after any fade-out).
## YarnLineAdvancer uses this to track presentation state.
signal line_dismissed(line: YarnLine)

## emitted when the player requests to continue
signal continue_requested()

@export var text_label: RichTextLabel
@export var character_label: Label
## hidden when no character name
@export var character_container: Control
## shown when line is fully revealed
@export var continue_indicator: Control

@export var typewriter_mode: TypewriterMode = TypewriterMode.LETTER
## Justify (fill-align) the body text, matching themes that set the line text to
## justified. Off by default so ordinary left-aligned presenters are unchanged.
@export var justify_text: bool = false

## characters per second for LETTER mode (0 = instant).
## matches Unity's LinePresenter default typewriter speed.
@export var characters_per_second: float = 60.0
@export var words_per_second: float = 10.0
@export var auto_advance: bool = false
## seconds to wait before auto-advancing (matches Unity's autoAdvanceDelay).
@export var auto_advance_delay: float = 1.0
## fade the panel in and out around each line (mirrors Unity's LinePresenter).
@export var use_fade_effect: bool = true
@export var fade_up_duration: float = 0.25
@export var fade_down_duration: float = 0.1
@export var continue_action: String = "ui_accept"
## Advance on any left click while a line is showing (never while options
## are up). Turn off if your game has clickable UI during dialogue.
@export var click_anywhere_to_continue: bool = true
@export var hurry_action: String = "ui_accept"
@export var use_markup: bool = true

## display-time event handlers, invoked as each character is revealed.
## attach [YarnActionMarkupHandlerNode]s in your scene and list them here
## (the scene-attached counterpart to Unity's "Event Handlers" list). a pause
## handler for [pause] markup is always added automatically, ahead of this list.
@export var event_handlers: Array[YarnActionMarkupHandlerNode] = []

var _is_displaying: bool = false
var _is_fully_revealed: bool = false
var _hurrying: bool = false
var _current_line: YarnLine
var _current_token: YarnCancellationToken
var _markup_parser: YarnMarkupParser
var _pause_processor: YarnPauseEventProcessor
## the handler list in effect for the current line (pause handler first).
var _active_handlers: Array = []
## bumped whenever the current line changes or dialogue starts/ends, so a
## superseded line's coroutines can tell they are stale after an await.
var _line_generation := 0
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

	# A pause handler is always present so that [pause] markup works, matching
	# Unity's LinePresenter which prepends a PauseEventProcessor.
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

	if event.is_action_pressed(continue_action):
		_advance_or_hurry()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not click_anywhere_to_continue:
		return
	if not _can_take_advance_input():
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_advance_or_hurry()
			get_viewport().set_input_as_handled()


func _can_take_advance_input() -> bool:
	if not _is_displaying:
		return false
	# Don't consume input when options are showing — let buttons handle it
	if dialogue_runner != null and dialogue_runner.are_options_active():
		return false
	return true


func _advance_or_hurry() -> void:
	if _is_fully_revealed:
		_complete_line()
	else:
		request_hurry_up()


func on_dialogue_started() -> void:
	_line_generation += 1
	_set_presenter_visible(false)
	_is_displaying = false
	_is_fully_revealed = false
	_hurrying = false
	_current_line = null
	_current_token = null


func on_dialogue_completed() -> void:
	_line_generation += 1
	_set_presenter_visible(false)
	_is_displaying = false
	_is_fully_revealed = false


func run_line(line: YarnLine, token: YarnCancellationToken = null) -> void:
	_line_generation += 1
	_current_line = line
	_current_token = token
	_is_displaying = true
	_is_fully_revealed = false
	_hurrying = false

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
		if justify_text:
			display_text = "[fill]%s[/fill]" % display_text
		text_label.text = display_text
		text_label.visible_characters = 0

	# Unity's continue arrow is visible for the whole line, not just once the
	# text has fully revealed, so match that here.
	if continue_indicator != null:
		continue_indicator.visible = true

	# Build the handler list for this line and let each one prepare. This is
	# the GDScript equivalent of the typewriter's PrepareForContent step.
	_active_handlers = _build_handlers()
	for handler in _active_handlers:
		if handler.has_method("on_prepare_for_line"):
			handler.on_prepare_for_line(line, text_label)

	line_started.emit(line)

	# Run the typewriter as a detached coroutine; it emits _line_complete
	# once the line has been fully read and dismissed. run_line holds the
	# line open by awaiting that — the presenter contract: return = done.
	_run_typewriter()

	await _line_complete


func _build_handlers() -> Array:
	var handlers: Array = []
	if _pause_processor != null:
		handlers.append(_pause_processor)
	for handler in event_handlers:
		if handler != null:
			handlers.append(handler)
	return handlers


## Registers a custom replacement-marker processor so that markup like
## [code][marker_name]...[/marker_name][/code] is transformed when this presenter
## renders a line. The presenter parses with its own markup parser, so register
## here (not just on the line provider) for the change to be visible. The Godot
## equivalent of registering a ReplacementMarkupHandler in Unity.
func register_marker_processor(marker_name: String, processor: YarnAttributeMarkerProcessor) -> void:
	if _markup_parser == null:
		_markup_parser = YarnMarkupParser.new()
	_markup_parser.register_marker_processor(marker_name, processor)


## reveals the line one unit at a time, invoking each event handler as every
## character appears. mirrors Unity's Letter/Word/Instant typewriters.
func _run_typewriter() -> void:
	var label := text_label
	var handlers := _active_handlers
	var line := _current_line
	var generation := _line_generation

	if use_fade_effect:
		await _fade_presenter_alpha(0.0, 1.0, fade_up_duration, _is_cancelled)
		if generation != _line_generation or not _is_displaying:
			return

	for handler in handlers:
		if handler.has_method("on_line_display_begin"):
			handler.on_line_display_begin(line, label)

	var visible_count := 0
	if label != null:
		visible_count = label.get_total_character_count()

	var seconds_per_unit := 0.0
	var word_boundaries := PackedInt32Array()
	match typewriter_mode:
		TypewriterMode.LETTER:
			if characters_per_second > 0:
				seconds_per_unit = 1.0 / characters_per_second
		TypewriterMode.WORD:
			if words_per_second > 0:
				seconds_per_unit = 1.0 / words_per_second
			word_boundaries = _calculate_word_boundaries(line.get_plain_text())

	# Start with a full time budget so the first unit appears immediately.
	var accumulated := seconds_per_unit
	var next_boundary := 0

	for i in visible_count:
		if generation != _line_generation or not _is_displaying:
			return  # replaced, dismissed, or dialogue stopped mid-reveal

		# Is this character a timing gate? Letter mode gates on every
		# character; word mode only on word boundaries.
		var gate := false
		if typewriter_mode == TypewriterMode.LETTER:
			gate = true
		elif typewriter_mode == TypewriterMode.WORD:
			if next_boundary < word_boundaries.size() and i == word_boundaries[next_boundary]:
				gate = true
				next_boundary += 1

		if gate and seconds_per_unit > 0.0:
			while not _is_cancelled() and accumulated < seconds_per_unit:
				if not is_inside_tree():
					return
				var before := Time.get_ticks_usec()
				await get_tree().process_frame
				if generation != _line_generation or not _is_displaying:
					return
				if not can_process():
					continue  # paused: the reveal clock stops too
				accumulated += float(Time.get_ticks_usec() - before) / 1_000_000.0
			accumulated -= seconds_per_unit

		# Let each handler react to this character, awaiting any signal it
		# returns (e.g. a pause, an emotion change, a walk). When hurrying we
		# still fire the handler for its side effect but skip the wait.
		for handler in handlers:
			if handler.has_method("on_character_will_appear"):
				var result: Variant = handler.on_character_will_appear(i, line, _current_token)
				if result is Signal and not (result as Signal).is_null() and not _is_cancelled():
					await result
					if generation != _line_generation or not _is_displaying:
						return

		if label != null:
			label.visible_characters = i + 1

	if label != null:
		label.visible_characters = -1

	for handler in handlers:
		if handler.has_method("on_line_display_complete"):
			handler.on_line_display_complete()

	_on_typewriter_complete(generation)


## returns the character index just past the end of each word, used as the
## word-mode timing gates (matches Unity's word.lastCharacterIndex + 1).
func _calculate_word_boundaries(text: String) -> PackedInt32Array:
	var boundaries := PackedInt32Array()
	var in_word := false
	for i in text.length():
		var c := text[i]
		var is_space := c == " " or c == "\t" or c == "\n"
		if is_space and in_word:
			boundaries.append(i)
			in_word = false
		elif not is_space:
			in_word = true
	if in_word:
		boundaries.append(text.length())
	return boundaries


func _on_typewriter_complete(generation: int) -> void:
	if generation != _line_generation or not _is_displaying:
		return
	_is_fully_revealed = true
	line_finished.emit(_current_line)

	if auto_advance and is_inside_tree():
		await YarnAsync.wait(self, auto_advance_delay)
		if generation != _line_generation:
			return
		if is_inside_tree() and _is_displaying and _is_fully_revealed:
			_complete_line()


func _complete_line() -> void:
	if not _is_displaying:
		return
	_is_displaying = false
	_is_fully_revealed = false
	var generation := _line_generation
	var dismissed_line := _current_line

	for handler in _active_handlers:
		if handler.has_method("on_line_will_dismiss"):
			handler.on_line_will_dismiss()

	_current_line = null
	_current_token = null

	if use_fade_effect:
		await _fade_presenter_alpha(1.0, 0.0, fade_down_duration)
		if generation != _line_generation:
			return

	if continue_indicator != null:
		continue_indicator.visible = false

	_set_presenter_visible(false)
	var item := _get_presenter_canvas_item()
	if item != null:
		item.modulate.a = 1.0
	line_dismissed.emit(dismissed_line)
	_line_complete.emit()


func _is_cancelled() -> bool:
	if _hurrying:
		return true
	if _current_token != null and _current_token.is_cancelled:
		return true
	return false


func request_hurry_up() -> void:
	_hurrying = true
	if _current_token != null:
		_current_token.request_hurry_up()


func request_next() -> void:
	# Next-content means the line ends now, revealed or not (like Unityy:
	# RequestNextLine dismisses the line; two-stage hurry-then-advance is
	# YarnLineAdvancer's job, not the presenter's... this presenter's own
	# _unhandled_input still offers single-press hurry for direct input).
	if _is_displaying:
		_complete_line()
