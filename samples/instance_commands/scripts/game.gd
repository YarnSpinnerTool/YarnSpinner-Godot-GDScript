# Main game script for the instance commands example.
# Demonstrates how to register instance commands so Yarn can call
# methods directly on specific character nodes.

extends Node2D

## Reference to the dialogue runner
@onready var dialogue_runner: YarnDialogueRunner = $YarnDialogueRunner

## Reference to the line presenter
@onready var line_presenter: YarnLinePresenter = $UI/LinePresenter

## Reference to the options presenter
@onready var options_presenter: YarnOptionsPresenter = $UI/OptionsPresenter

## Start button
@onready var start_button: Button = $UI/StartButton


func _ready() -> void:
	# Add presenters to dialogue runner
	dialogue_runner.add_presenter(line_presenter)
	dialogue_runner.add_presenter(options_presenter)

	_setup_yarn_commands()

	# Connect signals
	start_button.pressed.connect(_on_start_pressed)
	dialogue_runner.dialogue_completed.connect(_on_dialogue_completed)


func _setup_yarn_commands() -> void:
	var library := dialogue_runner.get_library()

	# Register instance commands - these are tied to the ExampleCharacter class
	# When Yarn calls <<move mae center>>, it will:
	#   1. Find the node named "mae"
	#   2. Verify it's an ExampleCharacter
	#   3. Call mae._yarn_command_move("center")
	library.register_instance_command("move", ExampleCharacter)
	library.register_instance_command("bounce", ExampleCharacter)  
	library.register_instance_command("set_color", ExampleCharacter)
	library.register_instance_command("face", ExampleCharacter)

	# Set the target root for node lookups
	library.set_target_root(self)

	print("Registered instance commands: move, bounce, set_color, face")


func _on_start_pressed() -> void:
	start_button.visible = false
	dialogue_runner.start_dialogue("Start")


func _on_dialogue_completed() -> void:
	start_button.text = "Restart"
	start_button.visible = true
