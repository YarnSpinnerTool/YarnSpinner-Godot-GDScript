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

@export var dialogue_runner: YarnDialogueRunner
@export var start_node: String = "Start"
@export var auto_start: bool = false

var line_presenter: YarnLinePresenter
var options_presenter: YarnOptionsPresenter
var _panel: PanelContainer
var _text_label: RichTextLabel
var _character_label: Label
var _character_container: HBoxContainer
var _continue_indicator: Label
var _options_container: VBoxContainer


func _ready() -> void:
	_build_ui()
	_setup_presenters()

	visible = false

	_register_presenters()


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

	if auto_start and dialogue_runner != null:
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


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -200
	_panel.custom_minimum_size = Vector2(0, 200)
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_character_container = HBoxContainer.new()
	vbox.add_child(_character_container)

	_character_label = Label.new()
	_character_label.add_theme_font_size_override("font_size", 20)
	_character_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_character_container.add_child(_character_label)

	_character_container.visible = false

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 18)
	vbox.add_child(_text_label)

	_continue_indicator = Label.new()
	_continue_indicator.text = "▼"
	_continue_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_indicator.visible = false
	vbox.add_child(_continue_indicator)

	_options_container = VBoxContainer.new()
	_options_container.add_theme_constant_override("separation", 5)
	_options_container.visible = false
	vbox.add_child(_options_container)


func _setup_presenters() -> void:
	line_presenter = YarnLinePresenter.new()
	line_presenter.text_label = _text_label
	line_presenter.character_label = _character_label
	line_presenter.character_container = _character_container
	line_presenter.continue_indicator = _continue_indicator
	line_presenter.characters_per_second = 40.0
	add_child(line_presenter)

	options_presenter = YarnOptionsPresenter.new()
	options_presenter.options_container = _options_container
	add_child(options_presenter)

	line_presenter.line_started.connect(func(_line):
		_options_container.visible = false
		_text_label.visible = true)

	options_presenter.options_shown.connect(func(_opts):
		_text_label.visible = false
		_options_container.visible = true)


func start_dialogue(node_name: String = "") -> void:
	if dialogue_runner == null:
		push_error("dialogue view: no dialogue runner set")
		return

	visible = true
	if node_name.is_empty():
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
