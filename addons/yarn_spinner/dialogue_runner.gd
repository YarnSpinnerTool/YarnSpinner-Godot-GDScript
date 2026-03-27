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

@tool
@icon("res://addons/yarn_spinner/icons/dialogue_runner.svg")
class_name YarnDialogueRunner
extends Node
## main controller for yarn spinner dialogue.
## manages the virtual machine, presenters, and dialogue flow.


enum SaliencyStrategyType {
	RANDOM_BEST_LEAST_RECENT, ## random among best complexity, preferring least recently seen
	BEST_LEAST_RECENT,        ## highest complexity, preferring least recently seen
	BEST,                     ## highest complexity score
	FIRST,                    ## first matching candidate
	RANDOM,                   ## random selection
}

signal dialogue_started()

signal dialogue_completed()

signal node_started(node_name: String)

signal node_completed(node_name: String)

signal unhandled_command(command_text: String)

## emitted for every command before dispatch, parsed into name and args
signal command_received(command_name: String, command_args: Array)

@export var yarn_project: YarnProjectResource:
	set(value):
		yarn_project = value
		if yarn_project != null and _vm != null:
			_load_program()

@export var start_node: String = "Start"

@export var auto_start: bool = false

## if null, an in-memory storage is created automatically
@export var variable_storage: YarnVariableStorage

## continue dialogue if no presenter selects an option
@export var allow_option_fallthrough: bool = false

## seconds before option fallthrough triggers (0 = no timeout)
@export var option_timeout: float = 0.0

## show selected option's text as a line before continuing
@export var run_selected_option_as_line: bool = false

## log detailed VM execution, instruction traces, and command discovery to the output console
@export var verbose_logging: bool = false

@export var saliency_strategy: SaliencyStrategyType = SaliencyStrategyType.RANDOM_BEST_LEAST_RECENT

## prefix for Godot TranslationServer keys (e.g., "YARN_")
@export var translation_prefix: String = "YARN_"

@export_group("Auto-Discovery")

## scan scene for _yarn_command_* methods at startup
@export var auto_discover_commands: bool = true

## root node for command scanning (empty = scene root)
@export var discovery_root: NodePath = ^""

@export_group("YSLS Generation")

## directory to scan for _yarn_command_* and _yarn_function_* methods
@export_dir var ysls_scan_path: String = "res://"

@export_tool_button("Regenerate YSLS", "Reload") var _regenerate_ysls_button = _regenerate_ysls_pressed

var _presenters: Array[YarnDialoguePresenter] = []
var _content_complete_pending: bool = false
var _vm: YarnVirtualMachine
var _library: YarnLibrary
var _line_provider: YarnLineProvider
var _asset_provider: YarnAssetProvider
var _smart_variable_evaluator: YarnSmartVariableEvaluator
var _is_running: bool = false
var _is_starting: bool = false
var _current_line: YarnLine
var _current_options: Array[YarnOption]
var _waiting_for_content: bool = false
var _current_cancellation_token: YarnCancellationToken


func _ready() -> void:
	# don't run in editor - @tool is only for the inspector button
	if Engine.is_editor_hint():
		return

	_vm = YarnVirtualMachine.new()
	_library = YarnLibrary.new()
	_line_provider = YarnLineProvider.new()
	_asset_provider = YarnAssetProvider.new()

	_vm.set_library(_library)
	_vm.verbose_logging = verbose_logging

	_vm.line_handler.connect(_on_line)
	_vm.options_handler.connect(_on_options)
	_vm.command_handler.connect(_on_command)
	_vm.node_start_handler.connect(_on_node_start)
	_vm.node_complete_handler.connect(_on_node_complete)
	_vm.dialogue_complete_handler.connect(_on_dialogue_complete)
	_vm.prepare_for_lines_handler.connect(_on_prepare_for_lines)

	if variable_storage == null:
		variable_storage = YarnInMemoryVariableStorage.new()
		add_child(variable_storage)

	_vm.variable_storage = variable_storage

	_smart_variable_evaluator = YarnSmartVariableEvaluator.new()
	_smart_variable_evaluator.attach_to_storage(variable_storage)
	variable_storage.smart_variable_evaluator = _smart_variable_evaluator

	var visited_func := func(n: String) -> bool:
		return _vm.has_visited_node(n)
	var visited_count_func := func(n: String) -> float:
		return float(_vm.get_visit_count(n))
	_library.register_function("visited", visited_func, 1)
	_library.register_function("visited_count", visited_count_func, 1)

	_apply_saliency_strategy()
	_library.set_vm_context(_vm.saliency_strategy, variable_storage)
	_configure_localisation()
	_register_builtin_commands()
	_library.set_target_root(get_tree().root)
	_discover_presenters()

	if auto_discover_commands:
		call_deferred("_auto_discover_commands")

	if yarn_project != null:
		_load_program()

	if auto_start:
		call_deferred("start_dialogue")


func _configure_localisation() -> void:
	_line_provider.set_translation_prefix(translation_prefix)


func _apply_saliency_strategy() -> void:
	var strategy: YarnSaliencyStrategy
	match saliency_strategy:
		SaliencyStrategyType.RANDOM_BEST_LEAST_RECENT:
			strategy = YarnSaliencyStrategy.YarnRandomBestLeastRecentlyViewedSaliencyStrategy.new()
		SaliencyStrategyType.BEST_LEAST_RECENT:
			strategy = YarnSaliencyStrategy.YarnBestLeastRecentlyViewedSaliencyStrategy.new()
		SaliencyStrategyType.BEST:
			strategy = YarnSaliencyStrategy.YarnBestSaliencyStrategy.new()
		SaliencyStrategyType.FIRST:
			strategy = YarnSaliencyStrategy.YarnFirstSaliencyStrategy.new()
		SaliencyStrategyType.RANDOM:
			strategy = YarnSaliencyStrategy.YarnRandomSaliencyStrategy.new()
		_:
			strategy = YarnSaliencyStrategy.YarnFirstSaliencyStrategy.new()

	_vm.set_saliency_strategy(strategy)

	if _library != null and variable_storage != null:
		_library.set_vm_context(strategy, variable_storage)

	if verbose_logging:
		print("dialogue runner: applied saliency strategy: %s" % SaliencyStrategyType.keys()[saliency_strategy])


func _discover_presenters() -> void:
	for child in get_children():
		if child is YarnDialoguePresenter:
			if child not in _presenters:
				_presenters.append(child)
				child.dialogue_runner = self


func _auto_discover_commands() -> void:
	var root: Node = self
	if not discovery_root.is_empty():
		root = get_node_or_null(discovery_root)
	if root == null:
		root = get_tree().current_scene

	if root == null:
		return

	var registered_scripts: Dictionary = {}

	_scan_node_for_commands(root, registered_scripts)

	if verbose_logging and not registered_scripts.is_empty():
		print("dialogue runner: auto-discovered commands from %d scripts" % registered_scripts.size())


func _scan_node_for_commands(node: Node, registered_scripts: Dictionary) -> void:
	var script := node.get_script() as Script
	if script != null and not registered_scripts.has(script):
		var methods := script.get_script_method_list()
		var found_commands := false

		for method in methods:
			var method_name: String = method["name"]
			if method_name.begins_with("_yarn_command_"):
				var yarn_name := method_name.substr(14)  # remove "_yarn_command_"

				if not _library.has_command(yarn_name) and not _library.has_instance_command(yarn_name):
					_library.register_instance_command(yarn_name, script)

					found_commands = true

					if verbose_logging:
						var script_class := _get_script_class_name(script)
						print("dialogue runner: auto-registered command '%s' on %s" % [yarn_name, script_class])

			elif method_name.begins_with("_yarn_function_"):
				var yarn_name := method_name.substr(15)  # remove "_yarn_function_"

				if not _library.has_function(yarn_name):
					var param_count: int = method.get("args", []).size()
					_library.register_function(yarn_name, Callable(node, method_name), param_count)

					if verbose_logging:
						print("dialogue runner: auto-registered function '%s' from %s" % [yarn_name, node.name])

		if found_commands:
			registered_scripts[script] = true

	for child in node.get_children():
		_scan_node_for_commands(child, registered_scripts)


func _get_script_class_name(script: Script) -> String:
	var global_classes := ProjectSettings.get_global_class_list()
	for class_info in global_classes:
		if class_info.get("path", "") == script.resource_path:
			return class_info.get("class", "")
	if not script.resource_path.is_empty():
		return script.resource_path.get_file().get_basename().to_pascal_case()
	return "unknown"


func _load_program() -> void:
	if yarn_project == null:
		return

	_vm.program = yarn_project.get_program()
	_line_provider.set_program(_vm.program)
	_library.set_program(_vm.program)
	variable_storage.set_program(_vm.program)

	if _smart_variable_evaluator != null:
		_smart_variable_evaluator.set_program_context(_vm.program, _library)

	if variable_storage.has_method("load_initial_values_from_program"):
		variable_storage.load_initial_values_from_program(_vm.program)


## if dialogue is already running, it will be stopped first.
func start_dialogue(node_name: String = "") -> void:
	if _is_starting:
		push_warning("dialogue runner: start_dialogue called while already starting, ignoring")
		return
	_is_starting = true

	if node_name.is_empty():
		node_name = start_node

	if _vm.program == null:
		push_error("dialogue runner: no program loaded")
		_is_starting = false
		return

	if _is_running:
		if verbose_logging:
			print("dialogue runner: stopping existing dialogue before starting new one")
		await stop_dialogue()

	_is_running = true
	_is_starting = false
	_content_complete_pending = false
	dialogue_started.emit()

	# duplicate to prevent mutation during async iteration
	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		if not _is_running:
			return
		await _safe_notify_presenter(presenter, "on_dialogue_started")

	if _is_running and _vm.set_node(node_name):
		_continue_dialogue()


func stop_dialogue() -> void:
	if not _is_running:
		return

	_vm.stop()
	_is_running = false
	_content_complete_pending = false
	_waiting_for_content = false

	if _current_cancellation_token != null:
		_current_cancellation_token.request_next_content()
		_current_cancellation_token = null

	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		if is_instance_valid(presenter):
			await _safe_notify_presenter(presenter, "on_dialogue_completed")

	dialogue_completed.emit()


func is_running() -> bool:
	return _is_running


func get_current_node_name() -> String:
	if _vm == null:
		return ""
	return _vm.get_current_node_name()


func has_visited_node(node_name: String) -> bool:
	if _vm == null:
		return false
	return _vm.has_visited_node(node_name)


func get_visit_count(node_name: String) -> int:
	if _vm == null:
		return 0
	return _vm.get_visit_count(node_name)


func reset_visit_tracking() -> void:
	if _vm != null:
		_vm.reset_visit_tracking()


func get_all_node_names() -> PackedStringArray:
	if _vm == null or _vm.program == null:
		return PackedStringArray()
	return _vm.program.get_node_names()


## named has_yarn_node to avoid conflict with Node.has_node()
func has_yarn_node(node_name: String) -> bool:
	if _vm == null or _vm.program == null:
		return false
	return _vm.program.has_node(node_name)


func get_header_value(node_name: String, header_name: String) -> String:
	if _vm == null:
		return ""
	return _vm.get_header_value(node_name, header_name)


func get_headers(node_name: String) -> Dictionary:
	if _vm == null:
		return {}
	return _vm.get_headers(node_name)


func get_string_id_for_node(node_name: String) -> String:
	if _vm == null:
		return ""
	return _vm.get_string_id_for_node(node_name)


func is_node_group(node_name: String) -> bool:
	if _vm == null:
		return false
	return _vm.is_node_group(node_name)


func has_salient_content(node_group_name: String) -> bool:
	if _vm == null:
		return false
	return _vm.has_salient_content(node_group_name)


func get_saliency_options_for_node_group(node_group_name: String) -> Array:
	if _vm == null:
		return []
	return _vm.get_saliency_options_for_node_group(node_group_name)


## cannot be called while dialogue is running.
func set_project(project: YarnProjectResource) -> void:
	if _is_running:
		push_error("dialogue runner: cannot set project while dialogue is running")
		return
	yarn_project = project
	_load_program()


func get_variable_storage() -> YarnVariableStorage:
	return variable_storage


func get_smart_variable_evaluator() -> YarnSmartVariableEvaluator:
	return _smart_variable_evaluator




func get_line_provider() -> YarnLineProvider:
	return _line_provider


func get_presenters() -> Array[YarnDialoguePresenter]:
	return _presenters.duplicate()


## may be null if no content is being presented.
func get_cancellation_token() -> YarnCancellationToken:
	return _current_cancellation_token


func get_library() -> YarnLibrary:
	return _library


func add_function(func_name: String, callable: Callable, param_count: int = -1) -> void:
	if func_name.is_empty():
		push_error("dialogue runner: function name cannot be empty")
		return
	if not callable.is_valid():
		push_error("dialogue runner: invalid callable for function '%s'" % func_name)
		return
	_library.register_function(func_name, callable, param_count)


func remove_function(func_name: String) -> void:
	if func_name.is_empty():
		return
	_library.unregister_function(func_name)


func add_command(command_name: String, callable: Callable) -> void:
	if command_name.is_empty():
		push_error("dialogue runner: command name cannot be empty")
		return
	if not callable.is_valid():
		push_error("dialogue runner: invalid callable for command '%s'" % command_name)
		return
	_library.register_command(command_name, callable)


func remove_command(command_name: String) -> void:
	if command_name.is_empty():
		return
	_library.unregister_command(command_name)


## enables "target.method" syntax in yarn commands.
func add_command_target(target_name: String, target: Node) -> void:
	if target_name.is_empty():
		push_error("dialogue runner: target name cannot be empty")
		return
	if target == null:
		push_error("dialogue runner: target node cannot be null for '%s'" % target_name)
		return
	_library.register_command_target(target_name, target)


func remove_command_target(target_name: String) -> void:
	if target_name.is_empty():
		return
	_library.unregister_command_target(target_name)


func add_presenter(presenter: YarnDialoguePresenter) -> void:
	if presenter == null:
		push_error("dialogue runner: presenter cannot be null")
		return
	if presenter not in _presenters:
		_presenters.append(presenter)
		presenter.dialogue_runner = self


func remove_presenter(presenter: YarnDialoguePresenter) -> void:
	if presenter == null:
		return
	_presenters.erase(presenter)


func signal_content_complete() -> void:
	if _waiting_for_content and not _content_complete_pending:
		_waiting_for_content = false
		_content_complete_pending = true
		_vm.signal_content_complete()
		call_deferred("_continue_dialogue_safe")


func select_option(option_index: int) -> void:
	if option_index < 0 or option_index >= _current_options.size():
		push_error("dialogue runner: invalid option index %d (have %d options)" % [option_index, _current_options.size()])
		return

	var selected_option: YarnOption = _current_options[option_index]

	_vm.set_selected_option(option_index)
	_current_options.clear()

	if run_selected_option_as_line and selected_option != null:
		await _run_option_as_line(selected_option)

	call_deferred("_continue_dialogue")


func _run_option_as_line(option: YarnOption) -> void:
	var line := YarnLine.new()
	line.line_id = option.line_id
	line.raw_text = option.raw_text
	line.substitutions = option.substitutions

	if _line_provider != null:
		_line_provider.get_localised_line(line)

	if verbose_logging:
		print("dialogue runner: running selected option as line: %s" % line.get_plain_text())

	_waiting_for_content = true
	_current_cancellation_token = YarnCancellationToken.new()

	var presenters_copy := _presenters.duplicate()

	var completion_signals: Array[Signal] = []
	for presenter in presenters_copy:
		if not _is_running:
			return
		presenter._cancellation_token = _current_cancellation_token
		var result: Variant = presenter.run_line(line)
		if result is Signal:
			completion_signals.append(result)

	for sig: Signal in completion_signals:
		if not _is_running:
			return
		await sig


func get_locale() -> String:
	return _line_provider.get_current_locale()


func set_locale(locale_code: String) -> void:
	_line_provider.set_current_locale(locale_code)


func get_available_locales() -> PackedStringArray:
	return _line_provider.get_available_locales()


func has_locale(locale_code: String) -> bool:
	return _line_provider.has_locale(locale_code)


## use {locale} placeholder, e.g., "res://audio/dialogue/{locale}/"
func set_audio_path_template(template: String) -> void:
	_line_provider.set_audio_path_template(template)


func export_for_godot_translation(output_path: String) -> Error:
	return _line_provider.export_for_godot_translation(output_path)


func add_strings_to_translation_server(locale_code: String) -> void:
	_line_provider.add_to_translation_server(locale_code)


func get_localised_audio(line_id: String) -> AudioStream:
	return _line_provider.get_localised_audio(line_id)


func has_localised_audio(line_id: String) -> bool:
	return _line_provider.has_localised_audio(line_id)


func get_localisation_debug_info() -> String:
	return _line_provider.get_debug_info()


func request_hurry_up() -> void:
	if _current_cancellation_token != null:
		_current_cancellation_token.request_hurry_up()
	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		if is_instance_valid(presenter):
			presenter.request_hurry_up()


func request_next_content() -> void:
	if _current_cancellation_token != null:
		_current_cancellation_token.request_next_content()
	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		if is_instance_valid(presenter):
			presenter.request_next()


func _continue_dialogue() -> void:
	if not _is_running:
		return
	_vm.continue_dialogue()

	if _vm.has_error():
		push_error("dialogue runner: VM encountered an error, stopping dialogue")
		stop_dialogue()


func _continue_dialogue_safe() -> void:
	_content_complete_pending = false
	_continue_dialogue()


func _on_line(line: YarnLine) -> void:
	if not _is_running:
		return

	_current_line = line

	if _line_provider != null:
		_line_provider.get_localised_line(line)

	_waiting_for_content = true

	_current_cancellation_token = YarnCancellationToken.new()
	var presenters_copy := _presenters.duplicate()

	var completion_signals: Array[Signal] = []
	for presenter in presenters_copy:
		if not _is_running:
			return
		presenter._cancellation_token = _current_cancellation_token
		var result: Variant = presenter.run_line(line)
		if result is Signal:
			completion_signals.append(result)

	for sig: Signal in completion_signals:
		if not _is_running:
			return
		await sig

	if _is_running:
		signal_content_complete()


func _on_options(options: Array[YarnOption]) -> void:
	if not _is_running:
		return

	_current_options = options

	if _line_provider != null:
		for option in options:
			_line_provider.get_localised_option(option)

	_current_cancellation_token = YarnCancellationToken.new()
	var presenters_copy := _presenters.duplicate()

	var timeout_triggered := false
	if option_timeout > 0.0:
		_start_option_timeout(option_timeout, func():
			timeout_triggered = true
			if _current_cancellation_token != null:
				_current_cancellation_token.request_next_content())

	var selected_option_index := -1
	for presenter in presenters_copy:
		if not _is_running or timeout_triggered:
			break
		presenter._cancellation_token = _current_cancellation_token
		var result: int = await presenter.run_options_with_token(options, _current_cancellation_token)
		if result >= 0 and selected_option_index < 0:
			selected_option_index = result
			break

	if not _is_running:
		return

	if selected_option_index >= 0:
		await select_option(selected_option_index)
		return

	if allow_option_fallthrough or timeout_triggered:
		push_warning("dialogue runner: no presenter handled options, using fallthrough")
		_vm.set_selected_option(YarnVirtualMachine.NO_OPTION_SELECTED)
		_current_options.clear()
		call_deferred("_continue_dialogue")
	else:
		push_error("dialogue runner: no presenter handled options and fallthrough disabled")
		stop_dialogue()


func _start_option_timeout(timeout: float, on_timeout: Callable) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(timeout).timeout
	if _is_running and not _current_options.is_empty():
		on_timeout.call()


func _on_command(command_text: String) -> void:
	_waiting_for_content = true

	var _parsed := YarnCommandParser.parse(command_text)
	if not _parsed.is_empty():
		command_received.emit(_parsed[0], _parsed.slice(1))

	var result := _library.dispatch_command(command_text, self)

	if not result.handled:
		if await _handle_builtin_command(command_text):
			signal_content_complete()
			return

		unhandled_command.emit(command_text)
		signal_content_complete()
		return

	if result.is_async:
		var async_result: Variant = result.result
		if async_result is Signal:
			await async_result
		elif async_result is Object and async_result != null:
			await async_result

	if not _is_running:
		return

	signal_content_complete()


func _handle_builtin_command(command_text: String) -> bool:
	var parts := YarnCommandParser.parse(command_text)
	if parts.is_empty():
		return false

	var command := parts[0].to_lower()

	match command:
		"stop":
			stop_dialogue()
			return true
		_:
			return false


func _on_node_start(node_name: String) -> void:
	node_started.emit(node_name)

	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		_safe_call_presenter(presenter, "on_node_started", [node_name])


func _on_node_complete(node_name: String) -> void:
	node_completed.emit(node_name)

	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		_safe_call_presenter(presenter, "on_node_completed", [node_name])


func _on_dialogue_complete() -> void:
	_is_running = false

	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		await _safe_notify_presenter(presenter, "on_dialogue_completed")

	dialogue_completed.emit()


func _on_prepare_for_lines(line_ids: PackedStringArray) -> void:
	if _asset_provider != null:
		_asset_provider.preload_assets(line_ids)

	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		_safe_call_presenter(presenter, "prepare_for_lines", [line_ids])


func _safe_notify_presenter(presenter: YarnDialoguePresenter, method: String) -> void:
	if not is_instance_valid(presenter):
		return

	if not presenter.has_method(method):
		return

	var result: Variant = presenter.call(method)
	if result is Signal:
		await result


func _safe_call_presenter(presenter: YarnDialoguePresenter, method: String, args: Array) -> void:
	if not is_instance_valid(presenter):
		return

	if not presenter.has_method(method):
		return

	presenter.callv(method, args)


func get_asset_provider() -> YarnAssetProvider:
	return _asset_provider


## keys: text, character_name, line_id, metadata. empty dict if no line is active.
func get_current_line_as_dict() -> Dictionary:
	if _current_line == null:
		return {}
	return {
		"text": _current_line.get_plain_text(),
		"character_name": _current_line.character_name,
		"line_id": _current_line.line_id,
		"metadata": Array(_current_line.metadata),
	}


## each element keys: text, option_index, is_available, line_id, metadata.
func get_current_options_as_array() -> Array:
	if _current_options.is_empty():
		return []
	var arr: Array = []
	for option in _current_options:
		arr.append({
			"text": option.get_plain_text(),
			"option_index": option.option_index,
			"is_available": option.is_available,
			"line_id": option.line_id,
			"metadata": Array(option.metadata),
		})
	return arr


func _register_builtin_commands() -> void:
	_library.register_command("wait", _cmd_wait)


func _cmd_wait(duration_str: String = "1.0") -> Signal:
	var duration := float(duration_str) if duration_str.is_valid_float() else 1.0
	return get_tree().create_timer(duration).timeout


func _regenerate_ysls_pressed() -> void:
	regenerate_ysls()


## regenerates the .ysls.json file next to the yarn project for VS Code integration.
func regenerate_ysls() -> void:
	if yarn_project == null:
		push_error("dialogue runner: cannot regenerate ysls - no yarn project assigned")
		return

	var project_path := yarn_project.resource_path
	if project_path.is_empty():
		push_error("dialogue runner: cannot regenerate ysls - yarn project has no path")
		return

	var generator := YarnYSLSGenerator.new()

	generator.scan_directory(ysls_scan_path)

	if _library != null:
		generator.scan_library(_library)

	var err := generator.save_ysls_for_project(project_path)
	if err == OK:
		print("dialogue runner: regenerated ysls for %s" % project_path)
	else:
		push_error("dialogue runner: failed to regenerate ysls: %s" % error_string(err))
