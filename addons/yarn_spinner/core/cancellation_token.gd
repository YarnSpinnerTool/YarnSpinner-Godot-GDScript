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

class_name YarnCancellationToken
extends RefCounted
## Token for signalling cancellation to async presenters.

enum CancellationMode {
	NONE,
	HURRY_UP,     ## speed up but wait for acknowledgement
	NEXT_CONTENT, ## skip immediately to next content
}


signal next_content_requested()
signal hurry_up_requested()
signal cancellation_requested(mode: CancellationMode)

var is_next_content_requested: bool = false
var is_hurry_up_requested: bool = false

var is_cancelled: bool:
	get:
		return is_next_content_requested or is_hurry_up_requested


var cancellation_mode: CancellationMode:
	get:
		if is_next_content_requested:
			return CancellationMode.NEXT_CONTENT
		elif is_hurry_up_requested:
			return CancellationMode.HURRY_UP
		return CancellationMode.NONE


func request_next_content() -> void:
	if not is_next_content_requested:
		is_next_content_requested = true
		next_content_requested.emit()
		cancellation_requested.emit(CancellationMode.NEXT_CONTENT)


func request_hurry_up() -> void:
	if not is_hurry_up_requested:
		is_hurry_up_requested = true
		hurry_up_requested.emit()
		cancellation_requested.emit(CancellationMode.HURRY_UP)


func escalate_to_next_content() -> void:
	if is_hurry_up_requested and not is_next_content_requested:
		request_next_content()


func should_skip() -> bool:
	return is_next_content_requested


func should_hurry() -> bool:
	return is_hurry_up_requested and not is_next_content_requested


## Returns the cancellation mode, or NONE if timed out. Tokens are single-use.
func wait_for_cancellation(timeout: float = 0.0) -> CancellationMode:
	if is_cancelled:
		return cancellation_mode

	if timeout > 0.0:
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return CancellationMode.NONE

		var timer := tree.create_timer(timeout)
		var result_mode := CancellationMode.NONE
		var completed := false

		var on_cancel := func(mode: CancellationMode):
			if not completed:
				result_mode = mode
				completed = true

		var on_timeout := func():
			completed = true

		cancellation_requested.connect(on_cancel, CONNECT_ONE_SHOT)

		while not completed:
			if is_cancelled:
				result_mode = cancellation_mode
				completed = true
				break
			if not timer.time_left > 0:
				completed = true
				break
			await tree.process_frame

		if cancellation_requested.is_connected(on_cancel):
			cancellation_requested.disconnect(on_cancel)

		return result_mode
	else:
		var mode: CancellationMode = await cancellation_requested
		return mode


func wait_for_any_cancellation() -> CancellationMode:
	if is_cancelled:
		return cancellation_mode
	var mode: CancellationMode = await cancellation_requested
	return mode
