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

extends Node
## yarn spinner singleton providing global access and utilities.
## autoloaded as "YarnSpinner" when the plugin is enabled.

const VERSION := "1.0.0"

var _global_commands: Dictionary[String, Callable] = {}
var _global_functions: Dictionary[String, Dictionary] = {}
var _saliency_strategies: Dictionary[String, YarnSaliencyStrategy] = {}


func _ready() -> void:
	_register_default_saliency_strategies()


func register_command(command_name: String, callable: Callable) -> void:
	_global_commands[command_name] = callable


func unregister_command(command_name: String) -> void:
	_global_commands.erase(command_name)


func register_function(func_name: String, callable: Callable, param_count: int = -1) -> void:
	_global_functions[func_name] = {
		"callable": callable,
		"param_count": param_count
	}


func unregister_function(func_name: String) -> void:
	_global_functions.erase(func_name)


func get_global_commands() -> Dictionary:
	return _global_commands.duplicate()


func get_global_functions() -> Dictionary:
	return _global_functions.duplicate()


func register_saliency_strategy(name: String, strategy: YarnSaliencyStrategy) -> void:
	_saliency_strategies[name] = strategy


func get_saliency_strategy(name: String) -> YarnSaliencyStrategy:
	return _saliency_strategies.get(name)


func _register_default_saliency_strategies() -> void:
	register_saliency_strategy("first", YarnSaliencyStrategy.YarnFirstSaliencyStrategy.new())
	register_saliency_strategy("random", YarnSaliencyStrategy.YarnRandomSaliencyStrategy.new())
	register_saliency_strategy("best", YarnSaliencyStrategy.YarnBestSaliencyStrategy.new())
	register_saliency_strategy("best_least_recently_viewed", YarnSaliencyStrategy.YarnBestLeastRecentlyViewedSaliencyStrategy.new())
	register_saliency_strategy("random_best_least_recently_viewed", YarnSaliencyStrategy.YarnRandomBestLeastRecentlyViewedSaliencyStrategy.new())


func create_dialogue_runner(project: YarnProjectResource = null) -> YarnDialogueRunner:
	var runner := YarnDialogueRunner.new()
	if project != null:
		runner.yarn_project = project

	for cmd_name in _global_commands:
		runner.add_command(cmd_name, _global_commands[cmd_name])

	for func_name in _global_functions:
		var info: Dictionary = _global_functions[func_name]
		runner.add_function(func_name, info.callable, info.param_count)

	return runner


## Utility: parse a yarn command string into name and arguments.
## [br][br]
## Returns: [code]{"name": "command_name", "args": ["arg1", "arg2"]}[/code]
## [br][br]
## Supports quoted arguments with spaces: [code]<<give "magic sword">>[/code]
func parse_command(command_text: String) -> Dictionary:
	return YarnCommandParser.parse_to_dict(command_text)
