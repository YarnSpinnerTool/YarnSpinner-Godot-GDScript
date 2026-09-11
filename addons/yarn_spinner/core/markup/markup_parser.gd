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

class_name YarnMarkupParser
extends RefCounted
## parses yarn spinner markup and transforms it using registered processors.
## uses YarnLineParser internally with a backwards-compatible API.

const BBCODE_TAG_START := "\uE000"
const BBCODE_TAG_END := "\uE001"

var _line_parser: YarnLineParser
var _processors: Array[YarnMarkupAttributeProcessor] = []
var _character_processor: YarnCharacterMarkupProcessor
var _style_processor: YarnStyleMarkupProcessor
var _palette_processor: YarnPaletteMarkupProcessor
var locale_code: String = "en"


func _init() -> void:
	_line_parser = YarnLineParser.new()

	var builtin_replacer := YarnBuiltInMarkupReplacer.new()
	_line_parser.register_marker_processor("select", builtin_replacer)
	_line_parser.register_marker_processor("plural", builtin_replacer)
	_line_parser.register_marker_processor("ordinal", builtin_replacer)

	# pause is a regular self-closing attribute read at display time by PauseEventProcessor
	_character_processor = YarnCharacterMarkupProcessor.new()
	_style_processor = YarnStyleMarkupProcessor.new()
	_palette_processor = YarnPaletteMarkupProcessor.new()

	_processors.append(_character_processor)
	_processors.append(_style_processor)
	_processors.append(_palette_processor)

	# Inline style shortcuts: [b]/[i]/[u]/[s]/[code] map directly to BBCode tags
	# of the same name for RichTextLabel rendering.
	for tag in ["b", "i", "u", "s", "code"]:
		_processors.append(_InlineStyleProcessor.new(tag))

	# [link="..."]text[/link] becomes [url=...]text[/url] — clickable when the
	# RichTextLabel handles meta_clicked.
	_processors.append(_LinkProcessor.new())


static func bbcode_tag(tag: String) -> String:
	return BBCODE_TAG_START + tag + BBCODE_TAG_END


static func brackets_to_tags(bbcode: String) -> String:
	return bbcode.replace("[", BBCODE_TAG_START).replace("]", BBCODE_TAG_END)


static func escape_text(text: String) -> String:
	var output := ""
	for character in text:
		match character:
			"[":
				output += "[lb]"
			"]":
				output += "[rb]"
			BBCODE_TAG_START:
				output += "["
			BBCODE_TAG_END:
				output += "]"
			_:
				output += character
	return output


static func strip_bbcode_tags(text: String) -> String:
	var output := ""
	var in_tag := false
	for character in text:
		if character == BBCODE_TAG_START:
			in_tag = true
		elif character == BBCODE_TAG_END:
			in_tag = false
		elif not in_tag:
			output += character
	return output


func register_processor(processor: YarnMarkupAttributeProcessor) -> void:
	_processors.append(processor)


func unregister_processor(processor: YarnMarkupAttributeProcessor) -> void:
	_processors.erase(processor)


func register_marker_processor(attribute_name: String, processor: YarnAttributeMarkerProcessor) -> void:
	_line_parser.register_marker_processor(attribute_name, processor)


func deregister_marker_processor(attribute_name: String) -> void:
	_line_parser.deregister_marker_processor(attribute_name)


func get_style_processor() -> YarnStyleMarkupProcessor:
	return _style_processor


func get_palette_processor() -> YarnPaletteMarkupProcessor:
	return _palette_processor


## parse markup and return a YarnMarkupParseResult.
func parse_to_result(text: String, add_implicit_character: bool = true) -> YarnMarkupParseResult:
	return _line_parser.parse_string(text, locale_code, add_implicit_character)


## parse markup in text and return processed result (backwards-compatible API)
## returns a dictionary with:
##   - text: the processed text with BBCode
##   - character_name: extracted character name (empty if none)
##   - attributes: array of parsed attribute info
## supports escaping: \[ and \] for literal brackets
func parse(text: String) -> Dictionary:
	var result := {
		"text": "",
		"character_name": "",
		"attributes": []
	}

	var parse_result := _line_parser.parse_string(text, locale_code, true)
	result.character_name = parse_result.get_character_name()

	var display_result := parse_result.without_character_name()
	result.text = convert_to_bbcode(display_result)

	var sorted_attrs: Array = display_result.attributes.duplicate()
	sorted_attrs.sort_custom(func(a, b): return a.position < b.position)

	# convert attributes to legacy format
	for attr in sorted_attrs:
		var legacy_attr := {
			"name": attr.name,
			"value": "",
			"position": attr.position,
			"source_position": attr.source_position,
			"length": attr.length,
		}
		# get first property value as the attribute value
		if attr.properties.size() > 0:
			for key in attr.properties:
				var val: Variant = attr.properties[key]
				if val is YarnMarkupValue:
					legacy_attr.value = val.to_string_value()
				else:
					legacy_attr.value = str(val)
				break
		result.attributes.append(legacy_attr)

	return result


func convert_to_bbcode(parse_result: YarnMarkupParseResult) -> String:
	_character_processor.reset()

	var plain_text := parse_result.text
	var events: Array[Dictionary] = []
	var order := 0
	for attr in parse_result.attributes:
		if attr.name == YarnLineParser.CHARACTER_ATTRIBUTE or attr.length <= 0:
			continue
		if _find_processor(attr.name) == null:
			continue
		events.append({"open": true, "pos": attr.position, "attr": attr, "order": order})
		events.append({"open": false, "pos": attr.position + attr.length, "attr": attr, "order": order})
		order += 1

	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.pos != b.pos:
			return a.pos < b.pos
		if a.open != b.open:
			return not a.open
		if a.open:
			if a.attr.length != b.attr.length:
				return a.attr.length > b.attr.length
			return a.order < b.order
		return a.order > b.order)

	var output := ""
	var current_pos := 0
	var stack: Array[Dictionary] = []

	for event in events:
		if event.pos > current_pos:
			output += escape_text(plain_text.substr(current_pos, event.pos - current_pos))
			current_pos = event.pos

		if event.open:
			var processor := _find_processor(event.attr.name)
			output += processor.process_open(_attribute_value(event.attr), _attribute_properties(event.attr))
			stack.append({"attr": event.attr, "processor": processor})
			continue

		var index := -1
		for i in range(stack.size() - 1, -1, -1):
			if stack[i].attr == event.attr:
				index = i
				break
		if index == -1:
			continue

		var reopen: Array[Dictionary] = []
		for i in range(stack.size() - 1, index, -1):
			output += stack[i].processor.process_close()
			reopen.push_front(stack[i])
		output += stack[index].processor.process_close()
		stack.resize(index)
		for entry in reopen:
			output += entry.processor.process_open(_attribute_value(entry.attr), _attribute_properties(entry.attr))
			stack.append(entry)

	if current_pos < plain_text.length():
		output += escape_text(plain_text.substr(current_pos))

	for i in range(stack.size() - 1, -1, -1):
		output += stack[i].processor.process_close()

	return output


func _attribute_value(attr: YarnMarkupAttribute) -> String:
	if attr.properties.has(attr.name):
		var value: Variant = attr.properties[attr.name]
		if value is YarnMarkupValue:
			return value.to_string_value()
		return str(value)
	return ""


func _attribute_properties(attr: YarnMarkupAttribute) -> Dictionary:
	var props: Dictionary = {}
	for key in attr.properties:
		var value: Variant = attr.properties[key]
		if value is YarnMarkupValue:
			props[key] = value.to_string_value()
		else:
			props[key] = str(value)
	return props


## find a processor that handles the given attribute
func _find_processor(attr_name: String) -> YarnMarkupAttributeProcessor:
	for processor in _processors:
		if processor.handles_attribute(attr_name):
			return processor
	return null


# Built-in passthrough for [b]/[i]/[u]/[s]/[code] — yarn attribute name matches
# the Godot BBCode tag exactly, so we just emit it directly.
class _InlineStyleProcessor extends YarnMarkupAttributeProcessor:
	func _init(name: String) -> void:
		attribute_name = name

	func process_open(_attribute_value: String, _properties: Dictionary) -> String:
		return "[%s]" % attribute_name

	func process_close() -> String:
		return "[/%s]" % attribute_name


# [link="value"]text[/link] -> [url=value]text[/url].
# Tracks a per-instance stack so process_close emits the matching BBCode only
# when the corresponding open actually emitted a [url=...] tag.
class _LinkProcessor extends YarnMarkupAttributeProcessor:
	var _emitted_url_stack: Array[bool] = []

	func _init() -> void:
		attribute_name = "link"

	func process_open(attribute_value: String, _properties: Dictionary) -> String:
		var has_url := not attribute_value.is_empty()
		_emitted_url_stack.push_back(has_url)
		if not has_url:
			return ""
		return "[url=%s]" % attribute_value

	func process_close() -> String:
		if _emitted_url_stack.is_empty():
			return ""
		if _emitted_url_stack.pop_back():
			return "[/url]"
		return ""
