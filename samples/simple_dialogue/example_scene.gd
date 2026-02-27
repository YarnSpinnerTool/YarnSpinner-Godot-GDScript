# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

extends Node2D
## example scene demonstrating yarn spinner for godot.
## shows basic dialogue setup with built-in presenters.

@onready var dialogue_runner: YarnDialogueRunner = $DialogueRunner


func _ready() -> void:
	# register custom commands
	dialogue_runner.add_command("give_item", _give_item)
	dialogue_runner.add_command("play_music", _play_music)

	# register custom functions
	dialogue_runner.add_function("player_name", _get_player_name, 0)
	dialogue_runner.add_function("has_item", _has_item, 1)

	# connect signals
	dialogue_runner.dialogue_started.connect(_on_dialogue_started)
	dialogue_runner.dialogue_completed.connect(_on_dialogue_completed)
	dialogue_runner.node_started.connect(_on_node_started)
	dialogue_runner.unhandled_command.connect(_on_unhandled_command)


func _input(event: InputEvent) -> void:
	# start dialogue with space if not running
	if event.is_action_pressed("ui_accept") and not dialogue_runner.is_running():
		dialogue_runner.start_dialogue()


# custom command implementations

func _give_item(item_name: String) -> void:
	print("giving item: %s" % item_name)
	# add item to inventory here


func _play_music(track_name: String) -> void:
	print("playing music: %s" % track_name)
	# play music here


# custom function implementations

func _get_player_name() -> String:
	return "Hero"


func _has_item(item_name: String) -> bool:
	# check inventory here
	return false


# signal handlers

func _on_dialogue_started() -> void:
	print("dialogue started")


func _on_dialogue_completed() -> void:
	print("dialogue completed")


func _on_node_started(node_name: String) -> void:
	print("node started: %s" % node_name)


func _on_unhandled_command(command_text: String) -> void:
	print("unhandled command: %s" % command_text)
