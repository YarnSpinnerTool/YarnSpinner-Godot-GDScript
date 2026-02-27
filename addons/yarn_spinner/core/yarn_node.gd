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

class_name YarnNode
extends Resource
## represents a single node in a yarn program.
## contains the instructions to execute and metadata headers.

@export var node_name: String = ""
@export var instructions: Array[YarnInstruction] = []
@export var headers: Dictionary = {}  # Dictionary[String, String]


func get_header(key: String) -> String:
	return headers.get(key, "")


func has_header(key: String) -> bool:
	return headers.has(key)


func get_tags() -> PackedStringArray:
	var tags_header := get_header("tags")
	if tags_header.is_empty():
		return PackedStringArray()
	return PackedStringArray(tags_header.split(" "))
