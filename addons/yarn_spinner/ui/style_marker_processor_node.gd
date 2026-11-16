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

class_name YarnStyleMarkerProcessorNode
extends Node

@export var dialogue_runner: YarnDialogueRunner
@export var styles: Dictionary[String, Dictionary] = {}

var _processor: YarnStyleMarkerProcessor
var _line_provider: YarnLineProvider


func _ready() -> void:
	_line_provider = await find_line_provider(self, dialogue_runner)
	if _line_provider == null:
		push_warning("style marker processor: no Dialogue Runner found")
		return
	_processor = YarnStyleMarkerProcessor.new()
	for style_name in styles:
		_processor.styles[style_name.to_lower()] = styles[style_name]
	_line_provider.deregister_marker_processor("style")
	_line_provider.register_marker_processor("style", _processor)


func _exit_tree() -> void:
	if _processor != null and _line_provider != null:
		_line_provider.deregister_marker_processor("style")
	_processor = null
	_line_provider = null


static func find_line_provider(from: Node, runner: YarnDialogueRunner) -> YarnLineProvider:
	if runner == null:
		runner = _find_runner(from)
	if runner == null:
		return null
	if not runner.is_node_ready():
		await runner.ready
	return runner.get_line_provider()


static func _find_runner(from: Node) -> YarnDialogueRunner:
	var ancestor := from.get_parent()
	while ancestor != null:
		if ancestor is YarnDialogueRunner:
			return ancestor
		ancestor = ancestor.get_parent()
	if not from.is_inside_tree():
		return null
	return _find_runner_under(from.get_tree().root)


static func _find_runner_under(node: Node) -> YarnDialogueRunner:
	if node is YarnDialogueRunner:
		return node
	for child in node.get_children():
		var found := _find_runner_under(child)
		if found != null:
			return found
	return null
