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

@icon("res://addons/yarn_spinner/icons/dialogue_view.svg")
class_name YarnDialogueView
extends CanvasLayer
## complete dialogue view combining line and options presenters.
## provides a ready-to-use dialogue ui with no additional setup.
##
## The visuals come from [member ui_scene] (dialogue_view_ui.tscn by
## default) open that scene in the editor to restyle the panel, fonts and
## colours, or point [member ui_scene] at your own scene. A custom scene
## must contain these scene-unique-named nodes: [code]%Panel[/code],
## [code]%CharacterContainer[/code], [code]%CharacterLabel[/code],
## [code]%TextLabel[/code], [code]%ContinueIndicator[/code] and
## [code]%OptionsContainer[/code].

## The runner this view presents for. Found automatically among ancestors
## when left unset.
@export var dialogue_runner: YarnDialogueRunner

## Node used when THIS VIEW starts dialogue (via [method start_dialogue] or
## [member auto_start]). Leave empty to use the runner's own Start Node
## set it here only to override the runner.
@export var start_node: String = ""

## Starts dialogue as soon as the view is ready. Ignored when the runner's
## own Auto Start is enabled (the runner starts itself; enabling both would
## race). Prefer configuring auto start on the runner.
@export var auto_start: bool = false

## The scene providing this view's visuals. Swap it to reskin the dialogue.
@export var ui_scene: PackedScene = preload("res://addons/yarn_spinner/ui/dialogue_view_ui.tscn")

var line_presenter: YarnLinePresenter
var options_presenter: YarnOptionsPresenter
var _ui: Control
var _text_label: RichTextLabel
var _character_label: Label
var _character_container: Control
var _continue_indicator: Control
var _options_container: Container


func _ready() -> void:
	_instantiate_ui()
	_setup_presenters()

	visible = false

	_register_presenters()


func _instantiate_ui() -> void:
	if ui_scene == null:
		push_error("dialogue view: no ui_scene set")
		return

	_ui = ui_scene.instantiate() as Control
	if _ui == null:
		push_error("dialogue view: ui_scene must have a Control root")
		return
	add_child(_ui)

	_text_label = _ui.get_node_or_null("%TextLabel")
	_character_label = _ui.get_node_or_null("%CharacterLabel")
	_character_container = _ui.get_node_or_null("%CharacterContainer")
	_continue_indicator = _ui.get_node_or_null("%ContinueIndicator")
	_options_container = _ui.get_node_or_null("%OptionsContainer")

	if _text_label == null or _options_container == null:
		push_error("dialogue view: ui_scene is missing required unique-named nodes " +
			"(%TextLabel, %OptionsContainer — see YarnDialogueView docs)")


func _register_presenters() -> void:
	if dialogue_runner == null:
		dialogue_runner = _find_dialogue_runner()

	if dialogue_runner != null:
		dialogue_runner.add_presenter(line_presenter)
		dialogue_runner.add_presenter(options_presenter)
		if not dialogue_runner.dialogue_started.is_connected(_on_dialogue_started):
			dialogue_runner.dialogue_started.connect(_on_dialogue_started)
		if not dialogue_runner.dialogue_completed.is_connected(_on_dialogue_completed):
			dialogue_runner.dialogue_completed.connect(_on_dialogue_completed)
		if dialogue_runner.is_running():
			visible = true

	# The runner's own auto start wins: it starts itself, and starting here
	# too would race it (and trip the runner's already-starting guard).
	if auto_start and dialogue_runner != null and not dialogue_runner.auto_start:
		call_deferred("start_dialogue")


func _find_dialogue_runner() -> YarnDialogueRunner:
	var node := get_parent()
	while node != null:
		if node is YarnDialogueRunner:
			return node
		node = node.get_parent()
	return null


func _on_dialogue_started() -> void:
	visible = true


func _on_dialogue_completed() -> void:
	visible = false


func _setup_presenters() -> void:
	line_presenter = YarnLinePresenter.new()
	line_presenter.text_label = _text_label
	line_presenter.character_label = _character_label
	line_presenter.character_container = _character_container
	line_presenter.continue_indicator = _continue_indicator
	add_child(line_presenter)

	options_presenter = YarnOptionsPresenter.new()
	options_presenter.options_container = _options_container
	add_child(options_presenter)

	line_presenter.line_started.connect(func(_line):
		if _options_container != null:
			_options_container.visible = false
		if _text_label != null:
			_text_label.visible = true)

	options_presenter.options_shown.connect(func(_opts):
		if _text_label != null:
			_text_label.visible = false
		if _options_container != null:
			_options_container.visible = true)


func start_dialogue(node_name: String = "") -> void:
	if dialogue_runner == null:
		push_error("dialogue view: no dialogue runner set")
		return

	visible = true
	if node_name.is_empty():
		# May still be empty, in which case the runner uses its own
		# Start Node the view only overrides when explicitly set.
		node_name = start_node
	dialogue_runner.start_dialogue(node_name)


func stop_dialogue() -> void:
	if dialogue_runner != null:
		dialogue_runner.stop_dialogue()
	visible = false


func _exit_tree() -> void:
	if dialogue_runner != null:
		if dialogue_runner.dialogue_started.is_connected(_on_dialogue_started):
			dialogue_runner.dialogue_started.disconnect(_on_dialogue_started)
		if dialogue_runner.dialogue_completed.is_connected(_on_dialogue_completed):
			dialogue_runner.dialogue_completed.disconnect(_on_dialogue_completed)
		if is_instance_valid(line_presenter):
			dialogue_runner.remove_presenter(line_presenter)
		if is_instance_valid(options_presenter):
			dialogue_runner.remove_presenter(options_presenter)
