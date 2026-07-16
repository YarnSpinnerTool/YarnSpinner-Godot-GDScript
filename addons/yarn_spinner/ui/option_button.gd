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
class_name YarnOptionButton
extends Button
## option button matching Unity's Option Item prefab: plain grey text that
## turns white with a dot indicator while focused. hovering focuses the
## button, mirroring Unity's pointer-enter selection.

## shown while the button has focus (Unity's Selection Indicator image).
@export var selection_indicator: Control


func _ready() -> void:
	focus_entered.connect(_update_indicator)
	focus_exited.connect(_update_indicator)
	mouse_entered.connect(_on_mouse_entered)
	_update_indicator()


func _on_mouse_entered() -> void:
	if not disabled:
		grab_focus()


func _update_indicator() -> void:
	if selection_indicator != null:
		selection_indicator.visible = has_focus()
