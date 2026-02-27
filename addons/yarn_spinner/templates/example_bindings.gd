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

extends Node
## Example YarnBindingLoader usage. Delete this file -- it's just for reference.


# === Inspector-based setup (recommended) ===
#
# 1. Add a YarnBindingLoader node to your scene as a sibling of YarnDialogueRunner
#
# 2. In the Inspector, add bindings to the "Bindings" array:
#
#    Binding 0:
#      Yarn Name: shake_camera
#      Type: COMMAND
#      Target Node: ../Camera2D
#      Method Name: shake
#      Description: Shakes the camera with given intensity
#
#    Binding 1:
#      Yarn Name: has_item
#      Type: FUNCTION
#      Target Node: ../Player
#      Method Name: check_inventory
#      Parameter Count: 1
#      Description: Returns true if player has the specified item
#
# 3. The loader auto-registers when the scene loads.


# === Programmatic setup ===

@onready var binding_loader: YarnBindingLoader = $YarnBindingLoader

func _ready() -> void:
	binding_loader.add_binding(
		"shake_camera",
		YarnCommandBinding.Type.COMMAND,
		$Camera2D,
		"shake"
	)

	binding_loader.add_binding(
		"has_item",
		YarnCommandBinding.Type.FUNCTION,
		$Player,
		"check_inventory",
		1
	)

	print(binding_loader.get_debug_info())


# === Example target methods ===

# Example Camera2D methods:
#
# func shake(intensity: String, duration: String = "0.5") -> void:
#     var tween := create_tween()
#     tween.tween_property(self, "offset", Vector2(float(intensity) * 10, 0), 0.05)
#     tween.tween_property(self, "offset", Vector2.ZERO, float(duration))
#
# # Async command -- returning a Signal makes dialogue wait for completion
# func shake_and_wait(intensity: String) -> Signal:
#     var tween := create_tween()
#     tween.tween_property(self, "offset", Vector2(float(intensity) * 10, 0), 0.1)
#     tween.tween_property(self, "offset", Vector2.ZERO, 0.4)
#     return tween.finished


# Example Player methods:
#
# var inventory: Array[String] = []
#
# func check_inventory(item_name: String) -> bool:
#     return item_name in inventory
#
# func add_to_inventory(item_name: String) -> void:
#     inventory.append(item_name)


# === Using in Yarn ===
#
# title: Example
# ---
# <<shake_camera 0.5>>
# The ground trembles beneath you.
#
# <<if has_item("key")>>
#     You use the key to unlock the door.
# <<else>>
#     The door is locked. You need a key.
# <<endif>>
# ===
