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

class_name YarnMarkupParseResult
extends RefCounted
## the result of parsing a line of marked-up text.
## contains plain text (markup tags removed) and attributes describing positions.


## the plain text with all markup tags removed.
var text: String = ""


## the markup attributes found in this parse result.
var attributes: Array[YarnMarkupAttribute] = []
func _init(parsed_text: String = "", parsed_attributes: Array[YarnMarkupAttribute] = []) -> void:
	text = parsed_text
	attributes = parsed_attributes


## returns the first attribute with the specified name, or null if not found.
func try_get_attribute_with_name(attr_name: String) -> YarnMarkupAttribute:
	for attr in attributes:
		if attr.name == attr_name:
			return attr
	return null


## returns the substring of text covered by an attribute.
func text_for_attribute(attr: YarnMarkupAttribute) -> String:
	if attr.length == 0:
		return ""

	if text.is_empty():
		push_error("markup parse result does not contain any text")
		return ""

	if text.length() < attr.position + attr.length:
		push_error("attribute represents a range not representable by this text")
		return ""

	return text.substr(attr.position, attr.length)


## deletes an attribute's text range and returns a new parse result with
## remaining attributes adjusted for the removed text.
func delete_range(attr_to_delete: YarnMarkupAttribute) -> YarnMarkupParseResult:
	var new_attributes: Array[YarnMarkupAttribute] = []

	# zero-length: just remove from attribute list, no text changes
	if attr_to_delete.length == 0:
		for a in attributes:
			if a != attr_to_delete:
				new_attributes.append(a)
		return YarnMarkupParseResult.new(text, new_attributes)

	var deletion_start := attr_to_delete.position
	var deletion_end := attr_to_delete.position + attr_to_delete.length
	var edited_text := text.substr(0, attr_to_delete.position) + text.substr(attr_to_delete.position + attr_to_delete.length)

	for existing_attr in attributes:
		if existing_attr == attr_to_delete:
			continue

		var attr: YarnMarkupAttribute = existing_attr as YarnMarkupAttribute
		if attr == null:
			continue

		var start: int = attr.position
		var end: int = attr.position + attr.length
		var edited_attr: YarnMarkupAttribute = attr

		if start <= deletion_start:
			if end <= deletion_start:
				# entirely before deletion
				pass

			elif end <= deletion_end:
				# starts before deletion, ends inside it - truncate
				edited_attr = attr.shift(0)
				edited_attr.length = deletion_start - start

				if attr.length > 0 and edited_attr.length <= 0:
					continue

			else:
				# spans across deletion - shrink by deletion length
				edited_attr = attr.shift(0)
				edited_attr.length -= attr_to_delete.length

		elif start >= deletion_end:
			# entirely after deletion - shift back
			edited_attr = attr.shift(-attr_to_delete.length)

		elif start >= deletion_start and end <= deletion_end:
			# entirely inside deletion - remove
			continue

		elif start >= deletion_start and end > deletion_end:
			# starts inside deletion, ends after - move and shrink
			var overlap_length: int = deletion_end - start
			edited_attr = attr.shift(0)
			edited_attr.position = deletion_start
			edited_attr.length = attr.length - overlap_length

		new_attributes.append(edited_attr)

	return YarnMarkupParseResult.new(edited_text, new_attributes)
