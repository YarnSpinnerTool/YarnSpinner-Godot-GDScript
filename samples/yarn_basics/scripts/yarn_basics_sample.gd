# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

extends Node2D
## Yarn Basics Sample - demonstrates all Yarn language features.
##
## This sample shows the Yarn language, not GDScript integration.
## See the bindings samples for command/function registration.


@onready var dialogue_runner: YarnDialogueRunner = $YarnDialogueRunner
@onready var line_presenter: YarnLinePresenter = $UILayer/LinePresenter
@onready var options_presenter: YarnOptionsPresenter = $UILayer/OptionsPresenter
@onready var start_button: Button = $UILayer/UI/StartButton
@onready var restart_button: Button = $UILayer/UI/RestartButton


func _ready() -> void:
	# Add presenters to dialogue runner (they're in UILayer for proper rendering)
	dialogue_runner.add_presenter(line_presenter)
	dialogue_runner.add_presenter(options_presenter)

	# Register custom commands for demonstration
	dialogue_runner.add_command("shake", _shake_camera)

	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	dialogue_runner.dialogue_completed.connect(_on_dialogue_complete)


func _on_start_pressed() -> void:
	start_button.visible = false
	dialogue_runner.start_dialogue("Start")


func _on_restart_pressed() -> void:
	restart_button.visible = false
	# Reset variable storage to start fresh
	dialogue_runner.variable_storage.clear()
	dialogue_runner.start_dialogue("Start")


func _on_dialogue_complete() -> void:
	restart_button.visible = true


## Custom command: <<shake>>
## Shakes the entire UI layer with a flash effect
func _shake_camera(_intensity: String = "1.0") -> void:
	var ui_layer := $UILayer
	var background: ColorRect = $UILayer/Background
	var original_color := background.color

	# Flash white
	background.color = Color.WHITE

	# Massive shake
	var tween := create_tween()
	tween.tween_property(ui_layer, "offset", Vector2(50, 0), 0.03)
	tween.tween_property(ui_layer, "offset", Vector2(-50, 20), 0.03)
	tween.tween_property(ui_layer, "offset", Vector2(40, -20), 0.03)
	tween.tween_property(ui_layer, "offset", Vector2(-30, 15), 0.03)
	tween.tween_property(ui_layer, "offset", Vector2(20, -10), 0.03)
	tween.tween_property(ui_layer, "offset", Vector2(-10, 5), 0.03)
	tween.tween_property(ui_layer, "offset", Vector2.ZERO, 0.05)

	# Fade flash back to original
	var flash_tween := create_tween()
	flash_tween.tween_property(background, "color", original_color, 0.3)
