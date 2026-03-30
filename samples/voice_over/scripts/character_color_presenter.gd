# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

class_name CharacterColorPresenter
extends YarnDialoguePresenter
## presenter that changes text color based on the speaking character.
## mirrors Unity's CharacterNameColorView.

## character name to color mapping
@export var character_colors: Dictionary = {
	"Tom": Color(0.4, 0.6, 1.0),    # blue-ish
	"Anne": Color(1.0, 0.6, 0.4),   # orange-ish
}

## default color when character not found
@export var default_color: Color = Color.WHITE

## labels to apply the color to
@export var text_labels: Array[Control] = []


func on_dialogue_started() -> void:
	pass


func on_dialogue_completed() -> void:
	pass


func run_line(line: YarnLine, _token: YarnCancellationToken = null) -> Variant:
	var color := default_color

	if not line.character_name.is_empty():
		if character_colors.has(line.character_name):
			color = character_colors[line.character_name]

	# apply color to all configured labels
	for label in text_labels:
		if label != null and is_instance_valid(label):
			if label is Label:
				(label as Label).modulate = color
			elif label is RichTextLabel:
				(label as RichTextLabel).modulate = color

	# don't block - let other presenters handle the line
	return null


func run_options(_options: Array[YarnOption], _token: YarnCancellationToken = null) -> int:
	# don't handle options
	return -1
