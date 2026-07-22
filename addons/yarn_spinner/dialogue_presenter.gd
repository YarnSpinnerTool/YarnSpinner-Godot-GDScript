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
extends Node
## Base class for presenting Yarn dialogue to the player.
##
## Subclass this to create your own dialogue UI. Override [method run_line]
## to display dialogue lines and [method run_options] to display choices.
##
## Extends [Node] so presenters can be non-visual (audio, signals, analytics).
## UI presenters can use [method _set_presenter_visible] to toggle visibility.
##
## [b]Presenters...[/b] [method run_line] returns when a
## presenter has finished with the line. Present your content, then
## [code]await[/code] whatever takes time (a typewriter, audio,
## [code]await token.wait_for_next_content()[/code]), clean up, and return.
## A presenter with nothing to wait for simply returns immediately.
## [br]The runner starts every presenter in the same frame and advances only
## when [b]all[/b] of them have returned. Once the token reports next
## content requested you are promising to finish promptly but nothing
## enforces it, the runner just waits (and warns after a few seconds).
## [br][method run_options] follows the same rule, returning the selected
## option index (>= 0), or -1 if this presenter does not handle options.
## The first valid selection wins! The token then fires so the rest wind
## down proeprly

## Reference to the dialogue runner this presenter is registered with.
## Set automatically when the presenter is added to a runner.
var dialogue_runner: YarnDialogueRunner

## Serial of the most recent fade; an older fade bails out once a newer one
## starts, so two fades never fight over the same modulate alpha.
var _fade_serial := 0


## Safely set visibility for this presenter's UI.
## Handles three common layouts:
##   1. Presenter IS a CanvasItem (e.g. extends Control) — toggles own visibility.
##   2. Presenter has CanvasItem children — toggles their visibility.
##   3. Presenter has CanvasLayer children — toggles their visibility.
## No-op for non-visual presenters with no visual children.
func _set_presenter_visible(v: bool) -> void:
	if is_class("CanvasItem"):
		set("visible", v)
		return
	for child in get_children():
		if child is CanvasItem:
			child.visible = v
		elif child is CanvasLayer:
			child.visible = v


## The CanvasItem this presenter fades: itself when it is one, otherwise its
## first CanvasItem child. Null for non-visual presenters.
func _get_presenter_canvas_item() -> CanvasItem:
	# The declared base is Node, but scenes often attach this script to a
	# Control; go via Variant so the analyser allows the cast.
	var target: Variant = self
	if target is CanvasItem:
		return target as CanvasItem
	for child in get_children():
		if child is CanvasItem:
			return child
	return null


## Fade the presenter's UI between two modulate alphas over [param duration]
## seconds (the Godot counterpart of Unity's canvas group fade). Awaitable.
## Finishes early when [param cancel] returns true. No-op for non-visual
## presenters.
func _fade_presenter_alpha(from_alpha: float, to_alpha: float, duration: float, cancel: Callable = Callable()) -> void:
	var item := _get_presenter_canvas_item()
	if item == null:
		return
	_fade_serial += 1
	var serial := _fade_serial
	if duration <= 0.0 or not is_inside_tree():
		item.modulate.a = to_alpha
		return
	item.modulate.a = from_alpha
	var elapsed := 0.0
	while elapsed < duration:
		await get_tree().process_frame
		if serial != _fade_serial:
			return
		if not is_inside_tree() or not is_instance_valid(item):
			return
		if cancel.is_valid() and cancel.call():
			break
		if not can_process():
			continue
		elapsed += get_process_delta_time()
		item.modulate.a = lerpf(from_alpha, to_alpha, clampf(elapsed / duration, 0.0, 1.0))
	item.modulate.a = to_alpha


## Called when dialogue begins. Override to set up your presenter UI.
func on_dialogue_started() -> void:
	pass


## Called when dialogue ends. Override to clean up your presenter UI.
func on_dialogue_completed() -> void:
	pass


## Called when a node begins executing.
func on_node_started(_node_name: String) -> void:
	pass


## Called when a node finishes executing.
func on_node_completed(_node_name: String) -> void:
	pass


## Called before lines are presented, with IDs of upcoming lines.
## Override to pre-cache audio, textures, or translations.
func prepare_for_lines(_line_ids: PackedStringArray) -> void:
	pass


## Present a dialogue line to the player.
##
## Override this in your subclass to display the line. Access the line's
## text via [code]line.text[/code] (lazy-computed with substitutions and
## markup applied) and character name via [code]line.character_name[/code].
##
## [param token] can be used to detect when the runner requests hurry-up
## or skip via [member YarnCancellationToken.is_hurry_up_requested] and
## [member YarnCancellationToken.is_next_content_requested], or awaited via
## [method YarnCancellationToken.wait_for_next_content]. The runner always
## passes a valid token; the [code]null[/code] default exists only so the
## method can be called manually in tests.
##
## Returning ends this presenter's involvement with the line so await
## anything that takes time before you do typically
## [code]await token.wait_for_next_content()[/code] to hold your content on
## screen until the line is dismissed. The runner advances only once every
## presenter has returned.
##
## The base implementation returns immediately ("nothing to present").
## It must not call [method YarnDialogueRunner.signal_content_complete]:
## with several presenters attached, a passive one doing so completes every
## line the instant it appears, cutting off the presenters that actually
## display it. The runner already advances by itself once all presenters
## have returned
func run_line(_line: YarnLine, _token: YarnCancellationToken = null) -> void:
	pass


## Present dialogue options to the player.
##
## Override this in your subclass to display options. Each option's text
## is available via [code]option.text[/code] (lazy-computed).
##
## [b]Return value[/b] (same rule as [method run_line].. return when done):
## - The selected option index (int >= 0), awaiting the player's choice
##   first if needed!
## - -1 if this presenter does not handle options, all done
##
## When multiple presenters are active all are started concurrently. The
## first valid selection (>=0 wins; the token then fires so the others
## wind down — honour it (hide your UI and return -1 when
## [member YarnCancellationToken.is_next_content_requested] becomes true,
## e.g. on option timeout)
func run_options(_options: Array[YarnOption], _token: YarnCancellationToken = null) -> int:
	return -1


## Called when the runner requests the presenter to hurry up (e.g.,
## skip typewriter animation but keep the line visible).
func request_hurry_up() -> void:
	pass


## Called when the runner requests the presenter to advance to the
## next piece of content (dismiss the current line).
##
## No-op in the base class: a presenter with no active content has nothing
## to dismiss. Presenters that display content override this and complete
## their own line (see [YarnLinePresenter], [YarnVoiceOverPresenter]).
## Calling [method YarnDialogueRunner.signal_content_complete] from here
## would complete whatever the runner is waiting on — including async
## commands such as [code]<<wait>>[/code] — whenever the player presses
## "advance", skipping them.
func request_next() -> void:
	pass


## Helper for presenters that want to ask "the line should end now" (e.g. a
## voice-over presenter when audio playback finishes).
##
## Routes through [member YarnLine.source] when available so that wrapper
## presenters like the Interruption add-on can intercept; otherwise falls
## back to calling [method YarnDialogueRunner.signal_content_complete]
## directly. Mirrors Unity Yarn Spinner's
## [code]IRequestLineCancellation.RequestLineCancellation[/code] dispatch.
func _request_line_end(line: YarnLine) -> void:
	if line != null and line.source != null and is_instance_valid(line.source) and line.source.has_method(&"request_line_cancellation"):
		line.source.request_line_cancellation(line)
	elif dialogue_runner != null:
		dialogue_runner.signal_content_complete()
