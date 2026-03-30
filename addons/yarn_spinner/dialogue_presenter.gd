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
## [b]Presenter contract:[/b]
## - [method run_line]: Return a [Signal] that completes when the line is done
##   displaying, OR return [code]null[/code] to indicate the line was handled
##   synchronously (the runner advances immediately).
## - [method run_options]: Return the selected option index (>= 0), or -1 if
##   this presenter does not handle options. The first presenter to return a
##   valid selection wins; others are cancelled via the token.

## Reference to the dialogue runner this presenter is registered with.
## Set automatically when the presenter is added to a runner.
var dialogue_runner: YarnDialogueRunner


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
## or skip via [method YarnCancellationToken.is_hurry_up_requested] and
## [method YarnCancellationToken.is_next_content_requested].
##
## [b]Return value:[/b]
## - Return a [Signal] that completes when the line is finished displaying.
##   The runner will await it before advancing.
## - Return [code]null[/code] if the line was handled synchronously. The
##   runner advances immediately.
func run_line(line: YarnLine, _token: YarnCancellationToken = null) -> Variant:
	dialogue_runner.signal_content_complete()
	return null


## Present dialogue options to the player.
##
## Override this in your subclass to display options. Each option's text
## is available via [code]option.text[/code] (lazy-computed).
##
## [param token] can be used to detect cancellation/timeout.
##
## [b]Return value:[/b]
## - Return the selected option index (>= 0).
## - Return -1 if this presenter does not handle options.
##
## When multiple presenters are active, all are started concurrently.
## The first to return a valid selection (>= 0) wins; others are cancelled.
func run_options(_options: Array[YarnOption], _token: YarnCancellationToken = null) -> int:
	return -1


## Called when the runner requests the presenter to hurry up (e.g.,
## skip typewriter animation but keep the line visible).
func request_hurry_up() -> void:
	pass


## Called when the runner requests the presenter to advance to the
## next piece of content (dismiss the current line).
func request_next() -> void:
	if dialogue_runner != null:
		dialogue_runner.signal_content_complete()
