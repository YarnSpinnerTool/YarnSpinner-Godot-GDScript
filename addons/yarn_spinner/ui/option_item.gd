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

@icon("res://addons/yarn_spinner/icons/option_item.svg")
class_name YarnOptionItem
extends Control
## single option button wrapping a Button with availability state handling.

signal option_selected(option_index: int)

@export var button: Button
## optional; falls back to button text
@export var text_label: Label
@export var unavailable_indicator: Control
@export var show_when_unavailable: bool = true

var option: YarnOption
var option_index: int = -1
var is_available: bool = true


func _ready() -> void:
	if button == null:
		button = _find_child_of_type("Button") as Button
		if button == null:
			# create a button if none exists
			button = Button.new()
			add_child(button)

	if button != null and not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)


func _find_child_of_type(type_name: String) -> Node:
	for child in get_children():
		if child.get_class() == type_name:
			return child
		for grandchild in child.get_children():
			if grandchild.get_class() == type_name:
				return grandchild
	return null


func setup(yarn_option: YarnOption, index: int) -> void:
	option = yarn_option
	option_index = index
	is_available = yarn_option.is_available

	var display_text := yarn_option.text if not yarn_option.text.is_empty() else yarn_option.raw_text
	if text_label != null:
		text_label.text = display_text
	if button != null:
		button.text = display_text

	_update_availability_visual()
	visible = true


func _update_availability_visual() -> void:
	if button != null:
		button.disabled = not is_available

	if unavailable_indicator != null:
		unavailable_indicator.visible = not is_available

	if not show_when_unavailable and not is_available:
		visible = false


func set_available(available: bool) -> void:
	is_available = available
	_update_availability_visual()


func reset() -> void:
	option = null
	option_index = -1
	is_available = true
	visible = false

	if text_label != null:
		text_label.text = ""
	if button != null:
		button.text = ""
		button.disabled = false

	if unavailable_indicator != null:
		unavailable_indicator.visible = false


func grab_focus_if_available() -> void:
	if button != null and is_available and visible:
		button.grab_focus()


func _on_button_pressed() -> void:
	if is_available:
		option_selected.emit(option_index)


func get_button() -> Button:
	return button


func set_text(text: String) -> void:
	if text_label != null:
		text_label.text = text
	if button != null:
		button.text = text
