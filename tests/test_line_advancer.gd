extends GutTest


class FakeRunner:
	extends YarnDialogueRunner

	var calls: Array[String] = []
	var presenting_line: bool = false
	var options_active: bool = false
	var content_frame: int = -100
	var fake_presenters: Array[YarnDialoguePresenter] = []
	var registered: Array[Node] = []

	func _ready() -> void:
		pass

	func request_hurry_up() -> void:
		calls.append("hurry")

	func request_next_content() -> void:
		calls.append("next")

	func request_hurry_up_option() -> void:
		calls.append("hurry_option")

	func stop_dialogue() -> void:
		calls.append("stop")

	func is_presenting_line() -> bool:
		return presenting_line

	func are_options_active() -> bool:
		return options_active

	func get_content_frame() -> int:
		return content_frame

	func get_presenters() -> Array[YarnDialoguePresenter]:
		return fake_presenters

	func register_line_advancer(advancer: Node) -> void:
		registered.append(advancer)

	func unregister_line_advancer(advancer: Node) -> void:
		registered.erase(advancer)


class Catcher:
	extends Node

	var received: int = 0

	func _unhandled_input(_event: InputEvent) -> void:
		received += 1


const TEST_CANCEL_ACTION := "yarn_test_cancel_dialogue"

var runner: FakeRunner
var presenter: YarnLinePresenter
var advancer: YarnLineAdvancer
var catcher: Catcher
var holder: SubViewport


func before_all():
	if not InputMap.has_action(TEST_CANCEL_ACTION):
		InputMap.add_action(TEST_CANCEL_ACTION)


func after_all():
	if InputMap.has_action(TEST_CANCEL_ACTION):
		InputMap.erase_action(TEST_CANCEL_ACTION)


func before_each():
	runner = FakeRunner.new()
	presenter = YarnLinePresenter.new()
	runner.fake_presenters = [presenter]
	holder = SubViewport.new()
	holder.handle_input_locally = true
	add_child(holder)
	catcher = Catcher.new()
	holder.add_child(catcher)
	advancer = YarnLineAdvancer.new()
	advancer.dialogue_runner = runner
	holder.add_child(advancer)
	runner.dialogue_started.emit()


func after_each():
	holder.queue_free()
	runner.queue_free()
	presenter.queue_free()


func _action(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _push(event: InputEvent) -> bool:
	var before := catcher.received
	holder.push_input(event)
	return catcher.received == before


func _use_separate_line_controls() -> void:
	advancer.combine_hurry_and_advance = false
	advancer.option_hurry_action = ""


func _begin_line() -> void:
	runner.presenting_line = true
	presenter.line_started.emit(null)


func _finish_line() -> void:
	presenter.line_finished.emit(null)


func test_registers_with_runner_and_unregisters_on_exit():
	assert_eq(runner.registered, [advancer] as Array[Node])
	holder.remove_child(advancer)
	assert_eq(runner.registered.size(), 0)
	holder.add_child(advancer)
	assert_eq(runner.registered, [advancer] as Array[Node])


func test_default_exports_mirror_unity():
	assert_eq(advancer.hurry_action, "ui_accept")
	assert_eq(advancer.advance_action, "ui_cancel")
	assert_eq(advancer.option_hurry_action, "ui_accept")
	assert_eq(advancer.cancel_dialogue_action, "")
	assert_eq(advancer.hurry_key, KEY_SPACE)
	assert_eq(advancer.advance_key, KEY_ESCAPE)
	assert_eq(advancer.option_hurry_key, KEY_SPACE)
	assert_eq(advancer.cancel_dialogue_key, KEY_NONE)
	assert_true(advancer.combine_hurry_and_advance)
	assert_eq(advancer.multi_press_to_skip, 0)
	assert_eq(advancer.multi_press_window, 0.0)


func test_combined_hurry_then_advance():
	_begin_line()
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry"] as Array[String])
	_finish_line()
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry", "next"] as Array[String])
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry", "next"] as Array[String])


func test_combined_hurry_ignored_without_line():
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)


func test_input_ignored_when_dialogue_not_running():
	runner.dialogue_completed.emit()
	_begin_line()
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)


func test_next_line_input_does_not_require_full_reveal():
	_begin_line()
	assert_true(_push(_action("ui_cancel")))
	assert_eq(runner.calls, ["next"] as Array[String])


func test_next_line_input_not_consumed_without_content():
	assert_false(_push(_action("ui_cancel")))
	assert_eq(runner.calls, ["next"] as Array[String])


func test_separate_mode_hurry_never_advances():
	_use_separate_line_controls()
	_begin_line()
	_finish_line()
	assert_true(_push(_action("ui_accept")))
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry", "hurry"] as Array[String])
	assert_true(_push(_action("ui_cancel")))
	assert_eq(runner.calls, ["hurry", "hurry", "next"] as Array[String])


func test_separate_mode_hurry_acts_without_status():
	_use_separate_line_controls()
	runner.presenting_line = true
	runner.content_frame = -50
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry"] as Array[String])


func test_multi_advance_threshold_combined():
	advancer.multi_press_to_skip = 2
	_begin_line()
	_push(_action("ui_accept"))
	_push(_action("ui_accept"))
	assert_eq(runner.calls, ["hurry", "next"] as Array[String])


func test_multi_advance_threshold_separate():
	_use_separate_line_controls()
	advancer.multi_press_to_skip = 3
	_begin_line()
	_push(_action("ui_accept"))
	_push(_action("ui_accept"))
	_push(_action("ui_accept"))
	assert_eq(runner.calls, ["hurry", "hurry", "next"] as Array[String])


func test_multi_advance_count_resets_per_line():
	_use_separate_line_controls()
	advancer.multi_press_to_skip = 2
	_begin_line()
	_push(_action("ui_accept"))
	_begin_line()
	_push(_action("ui_accept"))
	assert_eq(runner.calls, ["hurry", "hurry"] as Array[String])


func test_multi_press_window_expires():
	_use_separate_line_controls()
	advancer.multi_press_to_skip = 2
	advancer.multi_press_window = 0.05
	_begin_line()
	_push(_action("ui_accept"))
	await wait_seconds(0.15)
	_push(_action("ui_accept"))
	assert_eq(runner.calls, ["hurry", "hurry"] as Array[String])
	_push(_action("ui_accept"))
	assert_eq(runner.calls, ["hurry", "hurry", "next"] as Array[String])


func test_same_frame_guard_blocks_hurry():
	runner.content_frame = Engine.get_process_frames()
	_begin_line()
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)
	await wait_process_frames(1)
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry"] as Array[String])


func test_same_frame_guard_can_be_disabled():
	advancer.block_input_one_frame = false
	runner.content_frame = Engine.get_process_frames()
	_begin_line()
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry"] as Array[String])


func test_same_frame_guard_does_not_block_next_line():
	runner.content_frame = Engine.get_process_frames()
	_begin_line()
	assert_true(_push(_action("ui_cancel")))
	assert_eq(runner.calls, ["next"] as Array[String])


func test_options_hurry_combined_only_during_options():
	_begin_line()
	_push(_action("ui_accept"))
	assert_eq(runner.calls, ["hurry"] as Array[String])
	runner.presenting_line = false
	presenter.line_dismissed.emit(null)
	runner.options_active = true
	runner.content_frame = -10
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry", "hurry_option"] as Array[String])
	runner.options_active = false
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry", "hurry_option"] as Array[String])


func test_options_hurry_same_frame_guard():
	runner.options_active = true
	runner.content_frame = Engine.get_process_frames()
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)


func test_options_hurry_separate_always_requests():
	advancer.combine_hurry_and_advance = false
	runner.options_active = true
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry", "hurry_option"] as Array[String])
	advancer.request_option_hurry_up()
	assert_eq(runner.calls, ["hurry", "hurry_option", "hurry_option"] as Array[String])


func test_options_begin_resets_advance_count():
	_use_separate_line_controls()
	advancer.multi_press_to_skip = 2
	_begin_line()
	_push(_action("ui_accept"))
	runner.presenting_line = false
	runner.options_active = true
	runner.content_frame = -20
	await wait_process_frames(1)
	_push(_action("ui_accept"))
	assert_eq(runner.calls, ["hurry", "hurry"] as Array[String])


func test_cancel_dialogue_action():
	advancer.cancel_dialogue_action = TEST_CANCEL_ACTION
	var signalled := [false]
	advancer.dialogue_cancellation_requested.connect(func(): signalled[0] = true)
	_begin_line()
	assert_true(_push(_action(TEST_CANCEL_ACTION)))
	assert_eq(runner.calls, ["stop"] as Array[String])
	assert_true(signalled[0])


func test_cancel_disabled_by_default():
	_begin_line()
	advancer.input_mode = YarnLineAdvancer.InputMode.KEY_CODE
	assert_false(_push(_key(KEY_NONE)))
	assert_eq(runner.calls.size(), 0)


func test_key_code_mode():
	advancer.input_mode = YarnLineAdvancer.InputMode.KEY_CODE
	advancer.cancel_dialogue_key = KEY_C
	_begin_line()
	assert_true(_push(_key(KEY_SPACE)))
	_finish_line()
	assert_true(_push(_key(KEY_SPACE)))
	_begin_line()
	assert_true(_push(_key(KEY_ESCAPE)))
	_begin_line()
	assert_true(_push(_key(KEY_C)))
	assert_false(_push(_key(KEY_A)))
	assert_eq(runner.calls, ["hurry", "next", "next", "stop"] as Array[String])


func test_key_code_mode_ignores_echo_and_actions():
	advancer.input_mode = YarnLineAdvancer.InputMode.KEY_CODE
	_begin_line()
	var echo := _key(KEY_SPACE)
	echo.echo = true
	assert_false(_push(echo))
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)


func test_key_code_mode_options_hurry():
	advancer.input_mode = YarnLineAdvancer.InputMode.KEY_CODE
	runner.options_active = true
	assert_true(_push(_key(KEY_SPACE)))
	assert_eq(runner.calls, ["hurry_option"] as Array[String])


func test_empty_action_disables_input():
	advancer.hurry_action = ""
	advancer.option_hurry_action = ""
	_begin_line()
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)


func test_manual_mode_ignores_input():
	advancer.input_mode = YarnLineAdvancer.InputMode.NONE
	_begin_line()
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)


func test_public_line_hurry_up_counts_advances():
	advancer.multi_press_to_skip = 2
	var hurried := [0]
	var advanced := [0]
	advancer.hurry_up_requested.connect(func(): hurried[0] += 1)
	advancer.advance_requested.connect(func(): advanced[0] += 1)
	advancer.request_line_hurry_up()
	advancer.request_hurry_up()
	assert_eq(runner.calls, ["hurry", "next"] as Array[String])
	assert_eq(hurried[0], 1)
	assert_eq(advanced[0], 1)


func test_public_wrappers():
	advancer.request_advance()
	advancer.request_hurry_up()
	advancer.request_next_line()
	advancer.request_dialogue_cancellation()
	assert_eq(runner.calls, ["next", "hurry", "next", "stop"] as Array[String])


func test_line_dismissed_clears_line_status():
	_begin_line()
	_finish_line()
	runner.presenting_line = false
	presenter.line_dismissed.emit(null)
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls.size(), 0)


func test_manual_hooks_track_status():
	advancer.on_line_presentation_started()
	advancer.on_line_fully_revealed()
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["next"] as Array[String])
	advancer.on_line_presentation_started()
	advancer.on_line_presentation_ended()
	assert_false(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["next"] as Array[String])


func test_edge_detects_line_from_runner_without_presenter_signal():
	runner.presenting_line = true
	runner.content_frame = -30
	assert_true(_push(_action("ui_accept")))
	assert_eq(runner.calls, ["hurry"] as Array[String])
