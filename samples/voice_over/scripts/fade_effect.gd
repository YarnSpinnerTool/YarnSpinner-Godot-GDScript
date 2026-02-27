# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

class_name FadeEffect
extends ColorRect
## handles screen fade effects for yarn dialogue commands.
## provides set_fade_color, fade_up, and fade_down commands.

## duration for default fades
@export var default_duration: float = 1.0

## the dialogue runner to register commands with
@export var dialogue_runner: YarnDialogueRunner

## singleton instance for static command access
static var _instance: FadeEffect


func _ready() -> void:
	_instance = self

	# start fully transparent
	color = Color(0, 0, 0, 0)

	# auto-find dialogue runner if not set
	if dialogue_runner == null:
		dialogue_runner = _find_dialogue_runner()

	# register commands if dialogue runner is found
	if dialogue_runner != null:
		_register_commands()


## find the dialogue runner in the scene tree
func _find_dialogue_runner() -> YarnDialogueRunner:
	# look for sibling first
	if get_parent() != null:
		for sibling in get_parent().get_children():
			if sibling is YarnDialogueRunner:
				return sibling
	# search recursively from root
	return _find_node_of_type(get_tree().root, "YarnDialogueRunner") as YarnDialogueRunner


func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name or (node.get_script() != null and node.get_script().get_global_name() == type_name):
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found != null:
			return found
	return null


func _register_commands() -> void:
	dialogue_runner.add_command("set_fade_color", _cmd_set_fade_color)
	dialogue_runner.add_command("fade_up", _cmd_fade_up)
	dialogue_runner.add_command("fade_down", _cmd_fade_down)


## command: set fade opacity immediately
func _cmd_set_fade_color(opacity_str: String) -> void:
	var opacity := float(opacity_str)
	color = Color(0, 0, 0, opacity)


## command: fade from black to clear (fade up = reveal scene)
func _cmd_fade_up(duration_str: String = "1.0") -> Signal:
	var duration := float(duration_str) if not duration_str.is_empty() else default_duration
	return _fade(color.a, 0.0, duration)


## command: fade from clear to black (fade down = hide scene)
func _cmd_fade_down(duration_str: String = "1.0") -> Signal:
	var duration := float(duration_str) if not duration_str.is_empty() else default_duration
	return _fade(color.a, 1.0, duration)


## perform a fade animation
func _fade(from: float, to: float, duration: float) -> Signal:
	var tween := create_tween()
	color.a = from
	tween.tween_property(self, "color:a", to, duration)
	return tween.finished


## static method to get the instance
static func get_instance() -> FadeEffect:
	return _instance


## static fade methods for external use
static func fade_up_static(duration: float = 1.0) -> Signal:
	if _instance != null:
		return _instance._fade(_instance.color.a, 0.0, duration)
	return Signal()


static func fade_down_static(duration: float = 1.0) -> Signal:
	if _instance != null:
		return _instance._fade(_instance.color.a, 1.0, duration)
	return Signal()
