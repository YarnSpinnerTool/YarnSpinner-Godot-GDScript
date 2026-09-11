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
@export var header_list: Array[Dictionary] = []


func add_header(key: String, value: String) -> void:
	header_list.append({"key": key, "value": value})
	if not headers.has(key):
		headers[key] = value


func get_header(key: String) -> String:
	for header in header_list:
		if header["key"] == key:
			return String(header["value"]).strip_edges()
	return String(headers.get(key, "")).strip_edges()


func has_header(key: String) -> bool:
	for header in header_list:
		if header["key"] == key:
			return true
	return headers.has(key)


func get_all_headers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if header_list.is_empty():
		for key in headers:
			result.append({"key": String(key).strip_edges(), "value": String(headers[key]).strip_edges()})
		return result
	for header in header_list:
		result.append({"key": String(header["key"]).strip_edges(), "value": String(header["value"]).strip_edges()})
	return result


func get_tags() -> PackedStringArray:
	var raw := ""
	var found := false
	for header in header_list:
		if header["key"] == "tags":
			raw = header["value"]
			found = true
			break
	if not found:
		raw = headers.get("tags", "")
	if raw.is_empty():
		return PackedStringArray()
	return PackedStringArray(raw.split(" "))
