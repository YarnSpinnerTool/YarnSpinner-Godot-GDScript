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
	CUSTOM,
}

signal dialogue_started()

signal dialogue_completed()

## Emitted when dialogue ends without reaching a natural finish: an explicit
## [method stop_dialogue], a restart via [method start_dialogue], or a VM
## runtime error. Fires immediately before [signal dialogue_completed].
## Teardown (this runner leaving the tree mid-dialogue) emits neither signal.
signal dialogue_cancelled()

signal node_started(node_name: String)

signal node_completed(node_name: String)

## Emitted when a command is not handled by any registered handler.
## If a handler is connected, dialogue pauses until [method signal_content_complete]
## is called. If no handler is connected, an error is logged and dialogue continues.
signal command_unhandled(command_text: String)

## Emitted for every command before dispatch, parsed into name and args.
signal command_received(command_name: String, command_args: Array)

@export_group("Dialogue Setup")

@export var yarn_project: YarnProjectResource:
	set(value):
		if _is_running:
			push_error("dialogue runner: cannot set project while dialogue is running")
			return
		yarn_project = value
		if yarn_project != null and _vm != null:
			_load_program()

@export var start_node: String = "Start"

@export var auto_start: bool = false

## The presenters this runner drives. List them here in the inspector, or
## add them at runtime with [method add_presenter]. Child nodes are NOT
## discovered automatically.
@export var presenters: Array[YarnDialoguePresenter] = []:
	set(value):
		presenters = value
		if _vm != null:
			_presenters.clear()
			_register_listed_presenters()

## If null, an in-memory storage is created automatically.
@export var variable_storage: YarnVariableStorage

@export var line_provider: YarnLineProvider:
	set(value):
		line_provider = value
		if _vm != null and value != null:
			_line_provider = value
			_configure_localisation()
			if _vm.program != null:
				_line_provider.set_program(_vm.program)

@export_group("Dialogue Behaviour")

## Continue dialogue if no presenter selects an option.
@export var allow_option_fallthrough: bool = true

## Seconds before option fallthrough triggers (0 = no timeout).
@export var option_timeout: float = 0.0

## Show the selected option's text as a dialogue line before continuing.
@export var show_selected_option_as_line: bool = false

@export_group("Localisation")

## Prefix for Godot TranslationServer keys (e.g., "YARN_").
@export var translation_prefix: String = "YARN_"

@export_group("Advanced")

## Log detailed VM execution, instruction traces, and command discovery.
@export var verbose_logging: bool = false

@export var saliency_strategy: SaliencyStrategyType = SaliencyStrategyType.RANDOM_BEST_LEAST_RECENT

@export_group("Auto-Discovery")

## RUNTIME setting. Scan the running scene for _yarn_command_* and
## _yarn_function_* methods at startup and register them so Yarn can call
## them. This is what determines whether a command/function actually works
## at play time. (Contrast with YSLS Scan Path below, which only affects the
## editor's .ysls.json and has no effect on what runs.)
@export var auto_discover_commands: bool = true

## RUNTIME setting. Root node whose subtree is scanned for _yarn_command_* /
## _yarn_function_* methods (empty = the current scene root). A method only
## registers if a node carrying its script sits under this root when the scan
## runs. If a command/function errors at runtime, this is the setting to check
## (or register it explicitly with add_command()/add_function()).
@export var discovery_root: NodePath = ^""

@export_group("YSLS Generation")

## EDITOR-ONLY setting. Directory of .gd files to scan when generating the
## .ysls.json used by the VS Code extension (autocomplete and squiggles).
## This does NOT register anything at runtime - a green .ysls.json does not
## mean a command/function is callable. To make it callable, use the
## Discovery Root above or add_command()/add_function(). Defaults to the Yarn
## project's directory; set to "res://" to scan the whole project.
@export_dir var ysls_scan_path: String = ""

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
var _action_sources: Dictionary = {}
var _scene_changed_since_scan: bool = false
## Bumped when a run starts or is cleared. Coroutines handling lines, options
## and commands capture it before awaiting; a mismatch afterwards means their
## run was cancelled (and possibly replaced), so they must not touch the
## current run's state.
var _run_id := 0
var _current_line: YarnLine
var _current_options: Array[YarnOption]
var _waiting_for_content: bool = false
var _current_cancellation_token: YarnCancellationToken
var _current_line_token: YarnCancellationToken
var _current_options_token: YarnCancellationToken
## The active options round'sselection promise select_option routes
## external calls through it so every selection takes the same path.
var _current_selection: YarnPromise
## Bumped for every piece of content the runner presents (lines, option
## lines, options, commands). A presentation join captures it and only
## resumes the VM if it is still current so nothing weird happens if
## force-advancing mid-line via signal_content_complete() which might
## otherwise let the superseded join complete the *next* content early
var _line_epoch := 0
var _line_advancers: Array[Node] = []
var _content_frame := -1
var _completion_promise: YarnPromise
var _stop_requested: bool = false


## Once next content has been requested, a presenter that still hasn't
## finished this many seconds later gets named in a warning (the dialogue is waiting on it!
## I like this being here, even though Unity doesn't do this, as it's helpful.
const STALL_WARNING_SECONDS := 5.0


func _ready() -> void:
	# don't run in editor - @tool is only for the inspector button
	if Engine.is_editor_hint():
		return

	_vm = YarnVirtualMachine.new()
	_library = YarnLibrary.new()
	_library.set_virtual_machine(_vm)
	if line_provider == null:
		line_provider = YarnLineProvider.new()
	_line_provider = line_provider
	_asset_provider = YarnAssetProvider.new()

	_vm.set_library(_library)
	_vm.verbose_logging = verbose_logging

	_bind_vm_signals()

	if variable_storage == null:
		variable_storage = YarnInMemoryVariableStorage.new()
		add_child(variable_storage)

	_vm.variable_storage = variable_storage

	_smart_variable_evaluator = YarnSmartVariableEvaluator.new()
	_smart_variable_evaluator.attach_to_storage(variable_storage)
	variable_storage.smart_variable_evaluator = _smart_variable_evaluator

	_apply_saliency_strategy()
	_library.set_vm_context(_vm.get_effective_saliency_strategy(), variable_storage)
	_configure_localisation()
	_register_builtin_commands()
	_register_global_commands()
	_library.set_target_root(get_tree().root)
	_register_listed_presenters()

	if auto_discover_commands:
		_register_project_commands()
		get_tree().node_added.connect(_on_tree_node_added)
		call_deferred("_auto_discover_commands")

	if yarn_project != null:
		_load_program()

	if auto_start:
		call_deferred("start_dialogue")


func _enter_tree() -> void:
	# Re-bind VM signal handlers after a re-parent. _exit_tree disconnects
	# them defensively (Unity OnDestroy parity), but _ready only fires the
	# first time a node enters the tree — without this hook, any subsequent
	# add_child to a new parent would leave the runner alive but its VM
	# silent (SHOW_OPTIONS, lines, commands all emitted into the void).
	#
	# On the very first entry _vm doesn't exist yet (it's constructed in
	# _ready, which fires after _enter_tree), so we skip — _ready handles
	# the initial bind in that case.
	_bind_vm_signals()


func _exit_tree() -> void:
	# Clean up signal connections and cancel any in-progress dialogue.
	# Matches Unity's OnDestroy pattern.
	if _vm != null:
		if _vm.line_handler.is_connected(_on_line):
			_vm.line_handler.disconnect(_on_line)
		if _vm.options_handler.is_connected(_on_options):
			_vm.options_handler.disconnect(_on_options)
		if _vm.command_handler.is_connected(_on_command):
			_vm.command_handler.disconnect(_on_command)
		if _vm.node_start_handler.is_connected(_on_node_start):
			_vm.node_start_handler.disconnect(_on_node_start)
		if _vm.node_complete_handler.is_connected(_on_node_complete):
			_vm.node_complete_handler.disconnect(_on_node_complete)
		if _vm.dialogue_complete_handler.is_connected(_on_dialogue_complete):
			_vm.dialogue_complete_handler.disconnect(_on_dialogue_complete)
		if _vm.prepare_for_lines_handler.is_connected(_on_prepare_for_lines):
			_vm.prepare_for_lines_handler.disconnect(_on_prepare_for_lines)

	if is_running():
		# Stop silently. Emitting dialogue_completed here would tell
		# listeners a run finished when the node is just being torn down
		# (scene change, quit) — issue #138. Presenters aren't notified
		# either; they're being freed along with this runner.
		if _vm != null:
			_vm.stop()
		_clear_run_state()
		if _completion_promise != null:
			_completion_promise.settle()


## Bind every VM signal handler. Idempotent — safe to call from both _ready
## (initial setup) and _enter_tree (re-bind after a re-parent).
func _bind_vm_signals() -> void:
	if _vm == null:
		return
	if not _vm.line_handler.is_connected(_on_line):
		_vm.line_handler.connect(_on_line)
	if not _vm.options_handler.is_connected(_on_options):
		_vm.options_handler.connect(_on_options)
	if not _vm.command_handler.is_connected(_on_command):
		_vm.command_handler.connect(_on_command)
	if not _vm.node_start_handler.is_connected(_on_node_start):
		_vm.node_start_handler.connect(_on_node_start)
	if not _vm.node_complete_handler.is_connected(_on_node_complete):
		_vm.node_complete_handler.connect(_on_node_complete)
	if not _vm.dialogue_complete_handler.is_connected(_on_dialogue_complete):
		_vm.dialogue_complete_handler.connect(_on_dialogue_complete)
	if not _vm.prepare_for_lines_handler.is_connected(_on_prepare_for_lines):
		_vm.prepare_for_lines_handler.connect(_on_prepare_for_lines)


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
		SaliencyStrategyType.CUSTOM:
			return

	_vm.set_saliency_strategy(strategy)

	if _library != null and variable_storage != null:
		_library.set_vm_context(strategy, variable_storage)

	if verbose_logging:
		print("dialogue runner: applied saliency strategy: %s" % SaliencyStrategyType.keys()[saliency_strategy])


## Installs a custom [YarnSaliencyStrategy], overriding the built-in chosen by
## the [member saliency_strategy] export. Keeps the VM and the library's
## has-salient-content context in step. The Godot equivalent of Unity's
## DialogueRunner.Dialogue.ContentSaliencyStrategy.
func set_content_saliency_strategy(strategy: YarnSaliencyStrategy) -> void:
	if strategy == null:
		return
	saliency_strategy = SaliencyStrategyType.CUSTOM
	_vm.set_saliency_strategy(strategy)
	if _library != null:
		_library.set_vm_context(strategy, variable_storage)


func _register_listed_presenters() -> void:
	for presenter in presenters:
		if presenter != null and presenter not in _presenters:
			_presenters.append(presenter)
			presenter.dialogue_runner = self

	if _presenters.is_empty():
		# Not an error (presenters can arrive later via add_presenter), but
		# an empty list next to presenter children is almost always a scene
		# that still expects the removed auto-discovery.
		for child in get_children():
			if child is YarnDialoguePresenter:
				push_warning("dialogue runner: the Presenters array is empty, but " +
					"'%s' is a presenter child. Children are not discovered " % child.name +
					"automatically; list it in the Presenters array or call add_presenter().")
				break


## True while options are being presented and no selection has been applied
## yet. Presenters that share an input channel with options UI (e.g a line
## presenter's click-to-continue) should stand down while this is true
func are_options_active() -> bool:
	return not _current_options.is_empty()


func is_presenting_line() -> bool:
	return _current_line_token != null


func get_content_frame() -> int:
	return _content_frame


func register_line_advancer(advancer: Node) -> void:
	if advancer != null and advancer not in _line_advancers:
		_line_advancers.append(advancer)


func unregister_line_advancer(advancer: Node) -> void:
	_line_advancers.erase(advancer)


func has_line_advancer() -> bool:
	for advancer in _line_advancers.duplicate():
		if not is_instance_valid(advancer):
			_line_advancers.erase(advancer)
	return not _line_advancers.is_empty()


static func find_runner(node: Node) -> YarnDialogueRunner:
	var current := node
	while current != null:
		if current is YarnDialogueRunner:
			return current
		current = current.get_parent()
	var tree: SceneTree = null
	if node != null and node.is_inside_tree():
		tree = node.get_tree()
	else:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return _find_runner_in(tree.root)


static func _find_runner_in(node: Node) -> YarnDialogueRunner:
	if node is YarnDialogueRunner:
		return node
	for child in node.get_children():
		var found := _find_runner_in(child)
		if found != null:
			return found
	return null


func _on_tree_node_added(_node: Node) -> void:
	_scene_changed_since_scan = true


func _dispatch_command_with_discovery(command_text: String) -> Dictionary:
	var result: Dictionary = await _library.dispatch_command(command_text, self)
	if result.status == YarnLibrary.CommandDispatchStatus.NOT_FOUND and auto_discover_commands and _scene_changed_since_scan and is_inside_tree():
		_auto_discover_commands()
		result = await _library.dispatch_command(command_text, self)
	return result


func _report_duplicate_action(kind: String, yarn_name: String, script: Script) -> void:
	if _action_sources.get(kind + ":" + yarn_name) == script:
		return
	push_error("dialogue runner: failed to register %s '%s' from %s: a %s by this name has already been registered" % [kind, yarn_name, script.resource_path, kind])


func _auto_discover_commands() -> void:
	if not is_inside_tree():
		return
	_scene_changed_since_scan = false
	var root: Node = null
	if not discovery_root.is_empty():
		root = get_node_or_null(discovery_root)
	if root == null:
		root = get_tree().current_scene
	if root == null:
		# No current scene (runner used standalone): scan what we can reach.
		root = owner if owner != null else self

	var registered_scripts: Dictionary = {}
	_scan_node_for_commands(root, registered_scripts)

	if verbose_logging and not registered_scripts.is_empty():
		print("dialogue runner: auto-discovered commands from %d scripts" % registered_scripts.size())


func _register_project_commands() -> void:
	# Autoload singletons are the idiomatic Godot home for global commands (the
	# counterpart of Unity's static [YarnCommand] methods). Scan them first so a
	# singleton method wins the name, and register each as a global command bound
	# to the singleton - a singleton is unambiguous, so no target is needed and
	# <<command args>> works directly.
	var registered_scripts: Dictionary = {}
	_scan_singletons_for_commands(registered_scripts)

	for script in YarnActionDiscovery.get_action_scripts():
		if registered_scripts.has(script):
			continue
		registered_scripts[script] = true
		_register_script_actions(script)


## Registers _yarn_command_*/_yarn_function_* methods found on autoload
## singletons as GLOBAL definitions bound to the singleton instance. Because a
## singleton is unique, both static and non-static methods bind directly (no
## target resolution), matching how Unity treats static commands as global.
func _scan_singletons_for_commands(registered_scripts: Dictionary) -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return

	for setting in ProjectSettings.get_property_list():
		var setting_name: String = setting.get("name", "")
		if not setting_name.begins_with("autoload/"):
			continue
		var autoload_name := setting_name.substr("autoload/".length())
		var singleton := tree.root.get_node_or_null(NodePath(autoload_name))
		if singleton == null:
			continue

		var script := singleton.get_script() as Script
		if script == null or registered_scripts.has(script):
			continue
		registered_scripts[script] = true

		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if method_name.begins_with("_yarn_command_"):
				var yarn_name := method_name.substr(14)
				if _library.has_command(yarn_name) or _library.has_instance_command(yarn_name):
					_report_duplicate_action("command", yarn_name, script)
				else:
					_action_sources["command:" + yarn_name] = script
					_library.register_command(yarn_name, Callable(singleton, method_name))
					if verbose_logging:
						print("dialogue runner: registered global command '%s' on autoload '%s'" % [yarn_name, autoload_name])
			elif method_name.begins_with("_yarn_function_"):
				var yarn_name := method_name.substr(15)
				if _library.has_function(yarn_name):
					_report_duplicate_action("function", yarn_name, script)
				else:
					_action_sources["function:" + yarn_name] = script
					_library.register_function(yarn_name, Callable(singleton, method_name))


func _scan_node_for_commands(node: Node, registered_scripts: Dictionary) -> void:
	var script := node.get_script() as Script
	if script != null and not registered_scripts.has(script):
		if _register_script_actions(script):
			registered_scripts[script] = true

	for child in node.get_children():
		_scan_node_for_commands(child, registered_scripts)


func _register_script_actions(script: Script) -> bool:
	var found_actions := false

	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		var is_static: bool = (method.get("flags", 0) & METHOD_FLAG_STATIC) != 0

		if method_name.begins_with("_yarn_command_"):
			var yarn_name := method_name.substr(14)  # remove "_yarn_command_"
			found_actions = true

			if _library.has_command(yarn_name) or _library.has_instance_command(yarn_name):
				_report_duplicate_action("command", yarn_name, script)
				continue

			_action_sources["command:" + yarn_name] = script
			if is_static:
				# Static commands are global — no target node needed.
				# Call via the class directly: <<foo args>>
				_library.register_command(yarn_name, Callable(script, method_name))
			else:
				# Instance commands resolve a target node at dispatch:
				# <<foo targetNode args>>
				_library.register_instance_command(yarn_name, script)

			if verbose_logging:
				var script_class := _get_script_class_name(script)
				var kind := "static command" if is_static else "instance command"
				print("dialogue runner: auto-registered %s '%s' on %s" % [kind, yarn_name, script_class])

		elif method_name.begins_with("_yarn_function_"):
			var yarn_name := method_name.substr(15)  # remove "_yarn_function_"
			found_actions = true

			if _library.has_function(yarn_name):
				_report_duplicate_action("function", yarn_name, script)
				continue

			if not is_static:
				push_error("dialogue runner: function '%s' in %s must be static to be registered as a Yarn function" % [yarn_name, script.resource_path])
				continue

			_action_sources["function:" + yarn_name] = script
			_library.register_function(yarn_name, Callable(script, method_name))

			if verbose_logging:
				print("dialogue runner: auto-registered function '%s' from %s" % [yarn_name, script.resource_path])

	return found_actions


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

	var program := yarn_project.get_program()
	_vm.program = program
	_line_provider.set_program(program)
	_library.set_program(program)
	variable_storage.set_program(program)

	if _smart_variable_evaluator != null:
		_smart_variable_evaluator.set_program_context(program, _library)


## if dialogue is already running, it will be stopped first.
func start_dialogue(node_name: String = "") -> void:
	if _is_starting:
		push_warning("dialogue runner: start_dialogue called while already starting, ignoring")
		return

	if node_name.is_empty():
		node_name = start_node

	if yarn_project == null:
		push_error("dialogue runner: can't start dialogue: no yarn project has been configured")
		return

	if _vm.program == null:
		push_error("dialogue runner: can't start dialogue: the yarn project doesn't contain a valid program (possibly due to errors in the yarn scripts?)")
		return

	_is_starting = true

	while _vm.is_continuing():
		await (Engine.get_main_loop() as SceneTree).process_frame

	if _is_running:
		if verbose_logging:
			print("dialogue runner: stopping existing dialogue before starting new one")
		await stop_dialogue()

	if not _vm.program.has_node(node_name):
		push_error("dialogue runner: can't start dialogue: no node named '%s' has been loaded" % node_name)
		_is_starting = false
		return

	_is_running = true
	_run_id += 1
	var run := _run_id
	_content_complete_pending = false
	_stop_requested = false
	_completion_promise = YarnPromise.new()

	if not _vm.set_node(node_name):
		_is_running = false
		_is_starting = false
		_completion_promise.settle()
		return

	_apply_saliency_strategy()
	_is_starting = false

	if run != _run_id or not _is_running:
		return

	dialogue_started.emit()

	await _notify_presenters_together("on_dialogue_started")

	if run != _run_id or not _is_running:
		return

	_continue_dialogue()


func stop_dialogue() -> void:
	if not _is_running:
		return

	var completion := _completion_promise
	_stop_requested = true
	_cancel_current_content()
	_vm.stop()
	if completion != null:
		await completion.wait()


func _cancel_current_content() -> void:
	if _current_line_token != null:
		_current_line_token.request_next_content()
	if _current_options_token != null:
		_current_options_token.request_next_content()


## Reset per-run state without emitting any signals.
func _clear_run_state() -> void:
	_is_running = false
	_run_id += 1
	_content_complete_pending = false
	_waiting_for_content = false
	_current_options.clear()
	_current_selection = null
	_cancel_current_content()
	_current_line_token = null
	_current_options_token = null
	_current_cancellation_token = null


## Shared tail for every non-teardown end of dialogue: presenters are
## notified, then signals fire. Cancelled ends (explicit stop, restart,
## VM error) emit dialogue_cancelled before dialogue_completed.
func _finish_dialogue(was_cancelled: bool) -> void:
	# If a presenter callback restarts dialogue mid-loop stop notifying:
	# the remaining presenters now belong to the new run and resetting them
	# (ie generation bumps, visibility clears) would kill its first line. The
	# old run's completion signals are also skipped the new run's start
	# has already fired, and emitting completed after it would invert order
	var run := _run_id
	await _notify_presenters_together("on_dialogue_completed")
	if _run_id != run:
		return

	if was_cancelled:
		dialogue_cancelled.emit()
	dialogue_completed.emit()


func _notify_presenters_together(method: String) -> void:
	var promises: Array[YarnPromise] = []
	for presenter in _presenters.duplicate():
		if not is_instance_valid(presenter):
			continue
		var promise := YarnPromise.new()
		promises.append(promise)
		_run_presenter_notification(presenter, method, promise)
	for promise in promises:
		await promise.wait()


func _run_presenter_notification(presenter: Variant, method: String, promise: YarnPromise) -> void:
	if not is_instance_valid(presenter):
		promise.settle()
		return
	var on_exit := func() -> void:
		promise.settle()
	presenter.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	await _safe_notify_presenter(presenter, method)
	promise.settle()
	if is_instance_valid(presenter) and presenter.tree_exiting.is_connected(on_exit):
		presenter.tree_exiting.disconnect(on_exit)


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


func has_header(node_name: String, header_name: String) -> bool:
	if _vm == null:
		return false
	return _vm.has_header(node_name, header_name)


func get_headers(node_name: String) -> Dictionary:
	if _vm == null:
		return {}
	return _vm.get_headers(node_name)


func get_all_headers(node_name: String) -> Array[Dictionary]:
	if _vm == null:
		return []
	return _vm.get_all_headers(node_name)


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


## Internal — prefer add_command(), add_function() etc. on the DialogueRunner.
func get_library() -> YarnLibrary:
	return _library


func add_function(func_name: String, callable: Callable, param_count: int = -1) -> void:
	_library.register_function(func_name, callable, param_count)


func remove_function(func_name: String) -> void:
	if not _library.has_function(func_name):
		push_error("dialogue runner: cannot remove function %s: no function with that name exists in the library" % func_name)
		return
	_library.unregister_function(func_name)


func add_command(command_name: String, callable: Callable) -> void:
	_library.register_command(command_name, callable)


func remove_command(command_name: String) -> void:
	if not _library.has_command(command_name) and not _library.has_instance_command(command_name):
		push_error("dialogue runner: can't remove command %s, because no command with this name is currently registered" % command_name)
		return
	_library.unregister_command(command_name)
	_library.unregister_instance_command(command_name)


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


## Called by a presenter (via [member YarnLine.source]) when it wants the
## currently-running line to end. Wrapper presenters (e.g. the Interruption
## add-on) may substitute themselves as the source and intercept this call.
##
## Mirrors Yarn Spinner for Unity's
## [code]IRequestLineCancellation.RequestLineCancellation[/code], which calls
## [code]RequestNextLine()[/code]. The cancellation token fires, waking
## presenters parked on [method YarnCancellationToken.wait_for_next_content].
## The line actually ends when all presenters have finished... the token is
## the request, the presenters' completion is teh "proof"
func request_line_cancellation(_line: YarnLine) -> void:
	request_next_content()


func signal_content_complete() -> void:
	if not _waiting_for_content:
		return
	# Always clear the flag even if a previous deferred continuation is still
	# queued — `_continue_dialogue_safe` reads `_waiting_for_content` to decide
	# whether new content has started, and a stale `true` here would make it
	# bail forever once the previous defer fires.
	_waiting_for_content = false

	# Wake up presenters that are passively waiting on the current line's
	# cancellation token (e.g. SubtitlePresenter's
	# `WaitUntilCanceled(token.NextContentToken)` pattern). Mirrors the Unity
	# runner, which cancels NextContentToken when a line is signalled done.
	if _current_line_token != null:
		_current_line_token.request_next_content()

	if _content_complete_pending:
		# Previous defer is queued; it will resume the VM. Don't queue another.
		return
	if _vm.current_state == _vm.ExecutionState.WAITING_FOR_INPUT or _vm.current_state == _vm.ExecutionState.STOPPED:
		return
	_content_complete_pending = true
	_vm.signal_content_complete()
	call_deferred("_continue_dialogue_safe")


func select_option(option_index: int) -> void:
	# Route external calls through the active options round when one is in
	# flight the same path a presenter selection takes so a direct call
	# cannot leave the options join armed against a stale selection promise.
	if _current_selection != null and not _current_selection.is_settled:
		if option_index < 0 or option_index >= _current_options.size():
			push_error("dialogue runner: invalid option index %d (have %d options)" % [option_index, _current_options.size()])
			return
		_current_selection.settle(option_index)
		return
	await _apply_selected_option(option_index)


func _apply_selected_option(option_index: int) -> void:
	if option_index < 0 or option_index >= _current_options.size():
		push_error("dialogue runner: invalid option index %d (have %d options)" % [option_index, _current_options.size()])
		return

	var selected_option: YarnOption = _current_options[option_index]
	_current_options.clear()

	# Present the option BEFORE resuming the VM. set_selected_option
	# flips the VM back to RUNNING, and when a presenter selects
	# synchronously (inside the SHOW_OPTIONS emission) the VM's instruction
	# loop is still on the stack resuming first would let it steamrol
	# straight past the echo line.
	if show_selected_option_as_line and selected_option != null:
		var run := _run_id
		await _run_option_as_line(selected_option)
		if run != _run_id:
			return

	_vm.set_selected_option(option_index)

	# Use the guarded continueasthe VM may already be suspended on the next
	# piece of content by the time this deferred fires the unsafe variant
	# would force SUSPENDED back to RUNNING and steamroll that content.
	call_deferred("_continue_dialogue_safe")


func _run_option_as_line(option: YarnOption) -> void:
	var line := YarnLine.new()
	line.line_id = option.line_id
	line.raw_text = option.raw_text
	line.substitutions = option.substitutions
	line.metadata = option.metadata
	line.locale_code = option.locale_code
	line.set_markup_result(option.get_markup_result())

	if verbose_logging:
		print("dialogue runner: running selected option as line: %s" % line.get_plain_text())

	var run := _run_id
	_line_epoch += 1
	_waiting_for_content = true
	var token := YarnCancellationToken.new()
	_current_line_token = token
	_current_cancellation_token = token
	_content_frame = Engine.get_process_frames()

	# Mark ourselves as the source the presenters should route end-of-line
	# requests through. Wrapper presenters (e.g. the Interruption add-on) may
	# substitute themselves as the source before dispatching to children.
	line.source = self

	var promises := _start_line_presenters(line, run, token)

	for promise in promises:
		if run != _run_id:
			return
		await promise.wait()
		if run != _run_id:
			return

	# The option line is done; fire its token so presenter sub-coroutines
	# parked on it (and the stall watchdog) wind down. select_option resumes
	# the VM itself, so signal_content_complete is not called here which
	# means the waiting flag must be cleared here instead, or the deferred
	# _continue_dialogue_safe bails forever and the dialogue hangs.
	_waiting_for_content = false
	token.request_next_content()
	if _current_line_token == token:
		_current_line_token = null


func get_locale() -> String:
	return _line_provider.get_current_locale()


func set_locale(locale_code: String) -> void:
	_line_provider.set_current_locale(locale_code)


func get_available_locales() -> PackedStringArray:
	return _line_provider.get_available_locales()


func has_locale(locale_code: String) -> bool:
	return _line_provider.has_locale(locale_code)


## use {locale} placeholder, e.g., "res://audio/dialogue/{locale}/"
## Points voice-over lookup at the folder of BASE-language audio files
## (named after the line id: line:tutorial-tom-01 -> tutorial-tom-01.wav).
## Localised audio comes from Godot's translation remaps (Project Settings >
## Localization > Remaps), applied automatically when the file loads! MAGIC
func set_audio_base_path(path: String) -> void:
	_line_provider.set_audio_base_path(path)


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


## Asks the current content to hurry (skip animation, keep it on screen).
## Delivered through the cancellation token, which presenters watch.
func request_hurry_up() -> void:
	if _current_line_token != null:
		_current_line_token.request_hurry_up()


## Asks the current content to finish and advance. Delivered through the
## cancellation token: presenters watching it dismiss their content and
## return, and the runner advances once all of them have returned.
func request_next_content() -> void:
	if _current_line_token != null:
		_current_line_token.request_next_content()


func request_next_line() -> void:
	request_next_content()


func request_hurry_up_option() -> void:
	if _current_options_token != null:
		_current_options_token.request_hurry_up()


func save_state_to_persistent_storage(save_file_name: String) -> bool:
	if variable_storage == null:
		push_error("dialogue runner: can't save variables: variable storage is not set")
		return false

	var typed := variable_storage.get_all_variables_typed()
	var floats: Dictionary = typed.get("floats", {})
	var strings: Dictionary = typed.get("strings", {})
	var bools: Dictionary = typed.get("bools", {})
	var data := {
		"floatKeys": floats.keys(),
		"floatValues": floats.values(),
		"stringKeys": strings.keys(),
		"stringValues": strings.values(),
		"boolKeys": bools.keys(),
		"boolValues": bools.values(),
	}

	var path := "user://".path_join(save_file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("dialogue runner: failed to save state to %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "    "))
	file.close()
	return true


func load_state_from_persistent_storage(save_file_name: String) -> bool:
	if variable_storage == null:
		push_warning("dialogue runner: can't load state from persistent storage: variable storage is not set")
		return false

	var path := "user://".path_join(save_file_name)
	if not FileAccess.file_exists(path):
		push_error("dialogue runner: failed to load save state at %s: the file does not exist" % path)
		return false

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("dialogue runner: failed to load save state at %s: the file is not valid JSON" % path)
		return false

	var data: Dictionary = parsed
	var sections := [
		["floatKeys", "floatValues", "numeric"],
		["stringKeys", "stringValues", "string"],
		["boolKeys", "boolValues", "boolean"],
	]
	var results: Array[Dictionary] = []
	for section in sections:
		var keys: Variant = data.get(section[0])
		var values: Variant = data.get(section[1])
		if not keys is Array or not values is Array:
			push_error("dialogue runner: failed to load save state at %s: provided JSON string was not able to extract %s variables" % [path, section[2]])
			return false
		if (keys as Array).size() != (values as Array).size():
			push_error("dialogue runner: failed to load save state at %s: number of keys and values of %s variables does not match" % [path, section[2]])
			return false
		var entries := {}
		for i in range((keys as Array).size()):
			entries[String(keys[i])] = values[i]
		results.append(entries)

	for key in results[0]:
		results[0][key] = float(results[0][key])
	for key in results[1]:
		results[1][key] = String(results[1][key])
	for key in results[2]:
		results[2][key] = bool(results[2][key])

	variable_storage.set_all_variables_typed(results[0], results[1], results[2], true)
	return true


func _continue_dialogue() -> void:
	if not _is_running:
		return
	_vm.continue_dialogue()

	if _vm.has_error():
		push_error("dialogue runner: VM encountered an error, stopping dialogue")
		stop_dialogue()


func _continue_dialogue_safe() -> void:
	_content_complete_pending = false
	if _vm.current_state == _vm.ExecutionState.WAITING_FOR_INPUT:
		return
	if _vm.current_state == _vm.ExecutionState.STOPPED:
		return
	# If a line/command is currently awaiting its presenter's completion or
	# its returned signal, don't force the VM forward — vm.continue_dialogue
	# would unconditionally set state to RUNNING and steamroll over the
	# pending await. The await will resume on its own and call
	# signal_content_complete, which queues a fresh deferred continuation.
	#
	# This guards both async commands (where the await is on the returned
	# Signal/coroutine) AND lines/sync commands where a new RUN_LINE has
	# started while the previous completion's deferred call was queued.
	if _waiting_for_content:
		return
	_continue_dialogue()


func _on_line(line: YarnLine) -> void:
	if not _is_running:
		return

	var run := _run_id
	_line_epoch += 1
	var epoch := _line_epoch
	_current_line = line

	if _line_provider != null:
		var requested_id := line.line_id
		if not _line_provider.get_localised_line(line):
			push_error("dialogue runner: failed to get a localised line for %s!" % requested_id)

	_waiting_for_content = true

	var token := YarnCancellationToken.new()
	_current_line_token = token
	_current_cancellation_token = token
	_content_frame = Engine.get_process_frames()

	# Mark ourselves as the source the presenters should route end-of-line
	# requests through. Wrapper presenters (e.g. the Interruption add-on) may
	# substitute themselves as the source before dispatching to children.
	line.source = self

	var promises := _start_line_presenters(line, run, token)

	for promise in promises:
		if run != _run_id:
			return
		await promise.wait()
		if run != _run_id:
			return

	if _current_line_token == token:
		_current_line_token = null

	# Only the join for the current content may resume the VM if user code
	# force-advanced mid-line via signal_content_complete, this join is
	# superseded and must stay silent! SILENT!
	if _is_running and epoch == _line_epoch:
		signal_content_complete()


## Starts run_line on every presenter concurrently one detached wrapper
## coroutine per presenter, all launched in the same same frame and returns one
## promise per presenter, settled when that presenter has fully finished the
## line. Also arms the warn-only stall watchdog for the batch!
func _start_line_presenters(line: YarnLine, run: int, token: YarnCancellationToken) -> Array[YarnPromise]:
	var promises: Array[YarnPromise] = []
	# Freed presenters must be skipped before the call: the wrapper's typed
	# parameter rejects a freed object outright, which would abort the call
	# and strand an unsettled promise. `started` stays index-aligned with
	# `promises` for the watchdog.
	var started: Array[YarnDialoguePresenter] = []
	for presenter in _presenters.duplicate():
		if run != _run_id:
			break
		if not is_instance_valid(presenter) or _is_presenter_disabled(presenter):
			continue
		var promise := YarnPromise.new()
		promises.append(promise)
		started.append(presenter)
		_run_presenter_line(presenter, line, token, promise)
	_watch_presentation_stall(token, started, promises, "line")
	return promises


func _is_presenter_disabled(presenter: Node) -> bool:
	return presenter.process_mode == Node.PROCESS_MODE_DISABLED


## Runs one presenter's run_line and settles its promise when the presenter
## has returned the whole presenter system: run_line comes back when
## the presenter is finished with the line, awaiting internally for
## anything that takes time
func _run_presenter_line(presenter: YarnDialoguePresenter, line: YarnLine,
		token: YarnCancellationToken, promise: YarnPromise) -> void:
	if not is_instance_valid(presenter):
		promise.settle()
		return
	# A presenter freeed or removed from the tree mid-line can never resume
	# its coroutine... count it as finished so the join cannot hang on it
	# (settle() latches.. so this is a noop when the presenter finished
	# normally first)
	var on_exit := func() -> void:
		promise.settle()
	presenter.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	await presenter.run_line(line, token)
	promise.settle()
	if is_instance_valid(presenter) and presenter.tree_exiting.is_connected(on_exit):
		presenter.tree_exiting.disconnect(on_exit)


## Warn-only stall diagnostic! Once next content has been requested, every
## presenter is implicitly promising to finish promptly nothing can
## enforce that, so if a promise is still unsettled STALL_WARNING_SECONDS
## later, name the presenter: a forgotten return otherwise presents as a
## silent hang. Never advances teh dialogue
func _watch_presentation_stall(token: YarnCancellationToken,
		presenters: Array[YarnDialoguePresenter], promises: Array[YarnPromise],
		what: String) -> void:
	if token == null:
		return
	var run := _run_id
	await token.wait_for_next_content()
	if run != _run_id or not is_inside_tree():
		return
	var any_pending := false
	for promise in promises:
		if not promise.is_settled:
			any_pending = true
			break
	if not any_pending:
		return
	await YarnAsync.wait(self, STALL_WARNING_SECONDS)
	if run != _run_id:
		return
	for i in promises.size():
		if promises[i].is_settled:
			continue
		var who := "a freed presenter"
		if i < presenters.size() and is_instance_valid(presenters[i]):
			who = str(presenters[i].name)
			var presenter_script: Script = presenters[i].get_script()
			if presenter_script != null and not presenter_script.resource_path.is_empty():
				who += " (%s)" % presenter_script.resource_path
		push_warning(("dialogue runner: %s presenter %s has not finished %.0f seconds " +
			"after next content was requested. Once the cancellation token fires, " +
			"run_line/run_options must wrap up and return — dialogue is waiting " +
			"on it.") % [what, who, STALL_WARNING_SECONDS])


func _on_options(options: Array[YarnOption]) -> void:
	if not _is_running:
		return

	var run := _run_id
	_current_options = options

	if _line_provider != null:
		for i in range(options.size()):
			var option := options[i]
			if not _line_provider.get_localised_option(option):
				push_error("dialogue runner: failed to get a localised line for line %s (option %d)!" % [option.line_id, i + 1])
			option.source = self

	var token := YarnCancellationToken.new()
	_current_options_token = token
	_current_cancellation_token = token
	_content_frame = Engine.get_process_frames()
	var presenters_copy := _presenters.duplicate()

	# The first presenter to produce a valid selection settles this promise
	# (settle() latches, so later selections are no-ops ). It settles with -1
	# when every presenter finished without selecting, or on timeout.
	var selection := YarnPromise.new()
	_current_selection = selection
	var done_promises: Array[YarnPromise] = []

	var timed_out := [false]
	if option_timeout > 0.0:
		_start_option_timeout(option_timeout, func():
			timed_out[0] = true
			token.request_next_content()
			selection.settle(-1))

	# Start all presenters concurrently (matching Unity's WhenAll pattern!).
	# Freed presenters skipped before the call see _start_line_presenters.
	var started: Array[YarnDialoguePresenter] = []
	for presenter in presenters_copy:
		if run != _run_id:
			return
		if not is_instance_valid(presenter):
			continue
		var done := YarnPromise.new()
		done_promises.append(done)
		started.append(presenter)
		_run_presenter_options(presenter, options, token, selection, done)

	_watch_options_completion(done_promises, selection)
	_watch_presentation_stall(token, started, done_promises, "options")

	var selected_value: Variant = await selection.wait()
	if run != _run_id or not _is_running:
		return
	_current_selection = null
	if _current_options_token == token:
		_current_options_token = null

	var selected_option_index := -1
	if selected_value is int:
		selected_option_index = int(selected_value)

	if selected_option_index >= 0:
		# Ask the remaining presenters to wind down per the token contract
		# they must finish once this fires!
		token.request_next_content()
		await _apply_selected_option(selected_option_index)
		return

	if allow_option_fallthrough or timed_out[0]:
		token.request_next_content()
		_vm.set_selected_option(YarnVirtualMachine.NO_OPTION_SELECTED)
		_current_options.clear()
		# Guarded continue for the same reason as select_option: a synchronous
		# fallthrough happens inside the SHOW_OPTIONS emission and the VM may
		# already be suspended on the next piece of content.
		call_deferred("_continue_dialogue_safe")
	else:
		push_error("yarn spinner: no presenter handled the dialogue options and " +
			"'Allow Option Fallthrough' is disabled. Either:\n" +
			"  - Connect an options presenter (YarnOptionsPresenter) to the dialogue runner\n" +
			"  - Enable 'Allow Option Fallthrough' in the dialogue runner inspector\n" +
			"  - Set 'Option Timeout' to a non-zero value\n" +
			"Dialogue has been stopped.")
		stop_dialogue()


func _start_option_timeout(timeout: float, on_timeout: Callable) -> void:
	if not is_inside_tree():
		return
	var run := _run_id
	await YarnAsync.wait(self, timeout)
	if run == _run_id and _is_running and not _current_options.is_empty():
		on_timeout.call()


## Runs one presenter's run_options and settles [param done] when it has
## returned (same contract as run_line). A valid selection (>= 0) also
## settles the shared [param selection] promise first one wins.
func _run_presenter_options(presenter: YarnDialoguePresenter, options: Array[YarnOption],
		token: YarnCancellationToken, selection: YarnPromise, done: YarnPromise) -> void:
	if not is_instance_valid(presenter):
		done.settle()
		return
	# See _run_presenter_line: a presenter that leaves the tree counts as
	# finished, so the options round cannot hang on it.
	var on_exit := func() -> void:
		done.settle()
	presenter.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	var result: Variant = await presenter.run_options(options, token)
	if result is int and int(result) >= 0:
		selection.settle(int(result))
	done.settle()
	if is_instance_valid(presenter) and presenter.tree_exiting.is_connected(on_exit):
		presenter.tree_exiting.disconnect(on_exit)


## Settles [param selection] with -1 once every presenter has finished
## without selecting, so options with no willing presenter fall through
## instead of hanging. A real selection wins tehrace!
func _watch_options_completion(done_promises: Array[YarnPromise], selection: YarnPromise) -> void:
	var run := _run_id
	for done in done_promises:
		await done.wait()
		if run != _run_id:
			return
	selection.settle(-1)


func _on_command(command_text: String) -> void:
	var run := _run_id
	_waiting_for_content = true
	# A superseded line join must not complete this command (see _line_epoch)
	# and symmetrically, if this command is force-advanced past while its
	# async work is still running, the stale completion below must not end
	# whatever content is presenting by then.
	_line_epoch += 1
	var epoch := _line_epoch

	var _parsed := YarnCommandParser.parse(command_text)
	if not _parsed.is_empty():
		command_received.emit(_parsed[0], _parsed.slice(1))

	# Awaited: coroutine command handlers (like the built-in <<wait>>) run
	# to completion inside dispatch. The epoch captured above guards the
	# completion below against content that advanced past us meanwhile.
	var result := await _dispatch_command_with_discovery(command_text)

	if result.status == YarnLibrary.CommandDispatchStatus.NOT_FOUND:
		if await _handle_builtin_command(command_text):
			if run == _run_id and epoch == _line_epoch:
				signal_content_complete()
			return

		if command_unhandled.get_connections().size() > 0:
			command_unhandled.emit(command_text)
			return

		push_error(("yarn spinner: no command \"%s\" was found. It is not registered at " +
			"runtime - attach its script to a node under the DialogueRunner's discovery " +
			"root, make it static, or register it with runner.add_command(). A valid " +
			".ysls.json does not register it. Dialogue will continue.") % (_parsed[0] if not _parsed.is_empty() else command_text))
		if run == _run_id and epoch == _line_epoch:
			signal_content_complete()
		return

	if not result.handled:
		match result.status:
			YarnLibrary.CommandDispatchStatus.TARGET_NOT_FOUND, YarnLibrary.CommandDispatchStatus.TARGET_MISSING_COMPONENT:
				push_error(("yarn spinner: can't call command <<%s>>: %s. A _yarn_command_ on a " +
					"non-static method is an instance command, so its first argument must be a " +
					"target node name (<<cmd TargetNode args>>). For a global command, make the " +
					"method static or register it with runner.add_command().") % [command_text, result.error])
			_:
				push_error("yarn spinner: can't call command <<%s>>: %s" % [command_text, result.error])
		if run == _run_id and epoch == _line_epoch:
			signal_content_complete()
		return

	if result.is_async:
		var async_result: Variant = result.result
		if async_result is Signal:
			await async_result
		elif async_result is Object and async_result != null:
			# Coroutine functions called via Callable.callv return a
			# GDScriptFunctionState. The state has a `completed` signal that
			# fires when the coroutine runs to its end.
			if async_result.has_signal("completed"):
				await async_result.completed
			else:
				await async_result

	if run != _run_id or not _is_running or epoch != _line_epoch:
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
		if is_instance_valid(presenter) and not _is_presenter_disabled(presenter):
			_safe_call_presenter(presenter, "on_node_started", [node_name])


func _on_node_complete(node_name: String) -> void:
	node_completed.emit(node_name)

	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		if is_instance_valid(presenter) and not _is_presenter_disabled(presenter):
			_safe_call_presenter(presenter, "on_node_completed", [node_name])


func _on_dialogue_complete() -> void:
	if not _is_running:
		return
	# A VM error ends the run to avoid a soft-lock (GDScript has no
	# exceptions to surface it), but it isn't a natural finish — flag it
	# as cancelled so listeners can tell the difference.
	var was_cancelled := _stop_requested or (_vm != null and _vm.has_error())
	var completion := _completion_promise
	_clear_run_state()
	await _finish_dialogue(was_cancelled)
	if completion != null:
		completion.settle()


func _on_prepare_for_lines(line_ids: PackedStringArray) -> void:
	if _line_provider != null:
		_line_provider.prepare_for_lines(line_ids)

	if _asset_provider != null:
		var resolved := PackedStringArray()
		for line_id in line_ids:
			resolved.append(_line_provider.resolve_source_line_id(line_id) if _line_provider != null else line_id)
		_asset_provider.preload_assets(resolved)

	var presenters_copy := _presenters.duplicate()
	for presenter in presenters_copy:
		_safe_call_presenter(presenter, "prepare_for_lines", [line_ids])


# Deliberately untyped parameter: a typed YarnDialoguePresenter argument
# would make the CALL itself error on a freed object, before this guard runs!
func _safe_notify_presenter(presenter: Variant, method: String) -> void:
	if not is_instance_valid(presenter):
		return

	if not presenter.has_method(method):
		return

	var result: Variant = presenter.call(method)
	if result is Signal:
		await result
	elif result is Object and result != null and result.has_signal("completed"):
		# Coroutine overrides called via call() return a function state;
		# wait for it the same way _on_command waits for async commands.
		await result.completed


# Untyped for the same reason as _safe_notify_presenter.
func _safe_call_presenter(presenter: Variant, method: String, args: Array) -> void:
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
	if not _library.has_command("wait"):
		_library.register_command("wait", _cmd_wait)


func _register_global_commands() -> void:
	# Pull commands and functions registered on the YarnSpinner autoload
	# singleton (via YarnSpinner.register_command / register_function).
	var ys := Engine.get_singleton("YarnSpinner") if Engine.has_singleton("YarnSpinner") else null
	if ys == null:
		# Try autoload path
		ys = get_node_or_null("/root/YarnSpinner")
	if ys == null:
		return

	if ys.has_method("get_global_commands"):
		var cmds: Dictionary = ys.get_global_commands()
		for cmd_name in cmds:
			if not _library.has_command(cmd_name):
				_library.register_command(cmd_name, cmds[cmd_name])

	if ys.has_method("get_global_functions"):
		var funcs: Dictionary = ys.get_global_functions()
		for func_name in funcs:
			if not _library.has_function(func_name):
				var info: Dictionary = funcs[func_name]
				_library.register_function(func_name, info.get("callable"), info.get("param_count", -1))


func _cmd_wait(duration: float) -> void:
	# Pause-respecting <<wait>> must not keep elapsing under a pause menu lol
	# Fixed this thanks to Leonardo.
	await YarnAsync.wait(self, duration)


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

	# Default to nearest ancestor with scripts if no scan path configured
	var scan_root := ysls_scan_path if not ysls_scan_path.is_empty() else YarnYSLSGenerator.find_scan_root(project_path)
	generator.scan_directory(scan_root)

	if _library != null:
		generator.scan_library(_library)

	var err := generator.save_ysls_for_project(project_path)
	if err == OK:
		print("dialogue runner: regenerated ysls for %s" % project_path)
	else:
		push_error("dialogue runner: failed to regenerate ysls: %s" % error_string(err))
