extends GutTest


class RecordingPresenter:
	extends YarnDialoguePresenter

	var lines: Array[String] = []
	var option_sets: Array = []
	var choice: int = 0
	var hold_options: bool = false
	var hold_lines: bool = false

	func run_line(line: YarnLine, token: YarnCancellationToken = null) -> void:
		lines.append(line.text)
		if hold_lines and token != null:
			await token.wait_for_next_content()

	func run_options(options: Array[YarnOption], token: YarnCancellationToken = null) -> int:
		option_sets.append(options.duplicate())
		if hold_options and token != null:
			await token.wait_for_next_content()
			return -1
		return choice


var _runner: YarnDialogueRunner
var _presenter: RecordingPresenter


func _load_project(case_name: String) -> YarnProjectResource:
	var base_path := "res://tests/testplans/" + case_name
	var project := YarnProjectResource.new()
	project.compiled_program = FileAccess.get_file_as_bytes(base_path + ".yarnc")
	var string_table := {}
	var file := FileAccess.open(base_path + "-Lines.csv", FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 2 and not row[0].is_empty():
			string_table[row[0]] = row[1]
	project.string_table = string_table
	return project


func _make_runner(case_name: String) -> void:
	_runner = YarnDialogueRunner.new()
	_runner.auto_discover_commands = false
	_presenter = RecordingPresenter.new()
	add_child_autofree(_presenter)
	_runner.presenters = [_presenter] as Array[YarnDialoguePresenter]
	add_child_autofree(_runner)
	_runner.yarn_project = _load_project(case_name)


func _wait_until(condition: Callable, max_frames: int = 120) -> bool:
	for i in range(max_frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func test_option_fallthrough_defaults_to_true():
	var runner := YarnDialogueRunner.new()
	assert_true(runner.allow_option_fallthrough)
	runner.free()


func test_lines_and_options_run_to_completion():
	_make_runner("ShortcutOptions")
	watch_signals(_runner)
	_runner.start_dialogue()
	await wait_for_signal(_runner.dialogue_completed, 5.0)

	assert_signal_emit_count(_runner, "dialogue_started", 1)
	assert_signal_emit_count(_runner, "dialogue_completed", 1)
	assert_signal_emit_count(_runner, "dialogue_cancelled", 0)
	assert_gt(_presenter.option_sets.size(), 0)
	var first_options: Array = _presenter.option_sets[0]
	assert_eq(first_options.size(), 3)
	assert_false(first_options[1].is_available)
	assert_true("This line should appear." in _presenter.lines)
	assert_false(_runner.is_running())


func test_next_content_during_options_does_not_skip_the_choice():
	_make_runner("ShortcutOptions")
	_presenter.hold_options = true
	_runner.start_dialogue()
	assert_true(await _wait_until(func(): return _runner.are_options_active()))

	_runner.request_next_content()
	for i in range(5):
		await get_tree().process_frame

	assert_true(_runner.are_options_active())
	assert_eq(_presenter.lines.size(), 0)

	_runner.select_option(0)
	assert_true(await _wait_until(func(): return "This line should appear." in _presenter.lines))
	await _runner.stop_dialogue()


func test_starting_at_a_missing_node_does_not_start():
	_make_runner("Lines")
	watch_signals(_runner)
	_runner.start_dialogue("NoSuchNode")
	assert_false(_runner.is_running())
	assert_signal_not_emitted(_runner, "dialogue_started")
	assert_push_error_count(1)


func test_stop_emits_cancelled_and_completed_once():
	_make_runner("Lines")
	_presenter.hold_lines = true
	watch_signals(_runner)
	_runner.start_dialogue()
	assert_true(await _wait_until(func(): return _presenter.lines.size() > 0))

	await _runner.stop_dialogue()

	assert_false(_runner.is_running())
	assert_signal_emit_count(_runner, "dialogue_cancelled", 1)
	assert_signal_emit_count(_runner, "dialogue_completed", 1)


func test_restarting_from_dialogue_completed_runs_the_new_dialogue():
	_make_runner("Lines")
	var completions := [0]
	_runner.dialogue_completed.connect(func():
		completions[0] += 1
		if completions[0] == 1:
			_runner.start_dialogue()
	)
	_runner.start_dialogue()
	assert_true(await _wait_until(func(): return completions[0] >= 2, 300))
	var first_run_lines := _presenter.lines.size() / 2
	assert_gt(first_run_lines, 0)
	assert_eq(_presenter.lines.size(), first_run_lines * 2)
	assert_false(_runner.is_running())


func test_project_cannot_change_while_running():
	_make_runner("Lines")
	_presenter.hold_lines = true
	var original := _runner.yarn_project
	_runner.start_dialogue()
	assert_true(await _wait_until(func(): return _runner.is_presenting_line()))

	_runner.yarn_project = _load_project("ShortcutOptions")

	assert_eq(_runner.yarn_project, original)
	assert_push_error_count(1)
	await _runner.stop_dialogue()


func test_hurry_up_and_next_content_only_affect_lines():
	_make_runner("Lines")
	_presenter.hold_lines = true
	_runner.start_dialogue()
	assert_true(await _wait_until(func(): return _runner.is_presenting_line()))

	var token := _runner.get_cancellation_token()
	_runner.request_hurry_up_option()
	assert_false(token.is_hurry_up_requested)
	_runner.request_next_content()
	assert_true(token.is_next_content_requested)
	assert_true(token.is_hurry_up_requested)
	await _runner.stop_dialogue()


func test_save_and_load_state():
	_make_runner("Lines")
	var storage := _runner.get_variable_storage()
	storage.set_value("$gold", 12.5)
	storage.set_value("$name", "Bea")
	storage.set_value("$met", true)
	var file_name := "yarn_runner_state_test.json"

	assert_true(_runner.save_state_to_persistent_storage(file_name))
	storage.clear()
	assert_true(_runner.load_state_from_persistent_storage(file_name))

	assert_eq(storage.get_value("$gold"), 12.5)
	assert_eq(storage.get_value("$name"), "Bea")
	assert_eq(storage.get_value("$met"), true)
	DirAccess.remove_absolute("user://" + file_name)


func test_project_lists_line_ids_for_nodes():
	var project := _load_project("ShortcutOptions")
	var start_ids := project.get_line_ids_for_nodes(PackedStringArray(["Start"]))
	assert_gt(start_ids.size(), 0)
	for line_id in start_ids:
		assert_true(project.string_table.has(line_id))
	assert_eq(project.get_line_ids_for_nodes(PackedStringArray(["Start", "Missing"])), start_ids)


func _make_discovering_runner() -> Node:
	var container := Node.new()
	container.name = "DiscoveryRoot"
	add_child_autofree(container)
	_runner = YarnDialogueRunner.new()
	_presenter = RecordingPresenter.new()
	add_child_autofree(_presenter)
	_runner.presenters = [_presenter] as Array[YarnDialoguePresenter]
	add_child_autofree(_runner)
	_runner.discovery_root = _runner.get_path_to(container)
	return container


func _command_script(source: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script


func test_command_scripts_added_later_are_discovered():
	var container := _make_discovering_runner()
	await get_tree().process_frame

	var late := Node.new()
	late.name = "LateCommandNode"
	late.set_script(_command_script("extends Node\n\nvar pinged := false\n\n\nfunc _yarn_command_late_ping() -> void:\n\tpinged = true\n"))
	container.add_child(late)

	var result: Dictionary = await _runner._dispatch_command_with_discovery("late_ping LateCommandNode")

	assert_true(result.handled)
	assert_true(late.get("pinged"))


func test_duplicate_discovered_commands_are_reported():
	var container := _make_discovering_runner()
	await get_tree().process_frame

	var source := "extends Node\n\n\nfunc _yarn_command_duplicate_discovery() -> void:\n\tpass\n"
	var first := _command_script(source)
	var second := _command_script(source)
	for script in [first, first, second]:
		var node := Node.new()
		node.set_script(script)
		container.add_child(node)

	_runner._auto_discover_commands()

	assert_push_error_count(1)


func test_find_runner_from_a_child():
	_make_runner("Lines")
	var child := Node.new()
	_runner.add_child(child)
	assert_eq(YarnDialogueRunner.find_runner(child), _runner)
