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

extends RefCounted
## Handles async command execution via signals, coroutines, and awaitables.

var _dialogue_runner: Node


func _init(dialogue_runner: Node) -> void:
	_dialogue_runner = dialogue_runner


func execute_command(callable: Callable, args: Array) -> void:
	var result: Variant = callable.callv(args)

	if result == null:
		_complete()
		return

	if result is Signal:
		await result
		_complete()
		return

	if result is Object:
		if result.has_signal("completed"):
			await result.completed
			_complete()
			return

	_complete()


func _complete() -> void:
	if _dialogue_runner != null and _dialogue_runner.has_method("signal_content_complete"):
		_dialogue_runner.signal_content_complete()


static func wait_for_signal(sig: Signal) -> Signal:
	return sig


static func wait_seconds(duration: float, scene_tree: SceneTree) -> Signal:
	return scene_tree.create_timer(duration).timeout


static func wait_for_input(input_action: String) -> Callable:
	return func() -> void:
		while not Input.is_action_just_pressed(input_action):
			await Engine.get_main_loop().process_frame
