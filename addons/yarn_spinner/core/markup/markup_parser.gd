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
## supports escaping: \[ and \] for literal brackets, \\ for literal backslash
func parse(text: String) -> Dictionary:
	_character_processor.reset()

	var result := {
		"text": "",
		"character_name": "",
		"attributes": []
	}

	var parse_result := _line_parser.parse_string(text, locale_code, true)

	# convert attributes to BBCode and build output
	var output := ""
	var last_pos := 0

	# sort attributes by position
	var sorted_attrs: Array = parse_result.attributes.duplicate()
	sorted_attrs.sort_custom(func(a, b): return a.position < b.position)

	# track open tags for BBCode conversion
	var open_tags: Array = []

	# process the plain text and insert BBCode tags
	var plain_text := parse_result.text

	# first, extract character name and strip prefix from text
	for attr in sorted_attrs:
		if attr.name == YarnLineParser.CHARACTER_ATTRIBUTE:
			var name_prop: YarnMarkupValue = attr.try_get_property("name")
			if name_prop != null:
				result.character_name = name_prop.string_value
			else:
				result.character_name = parse_result.text_for_attribute(attr).strip_edges().trim_suffix(":")
			_character_processor.character_name = result.character_name
			# remove the "Name: " prefix from parsed text
			if attr.length > 0:
				parse_result = parse_result.delete_range(attr)
				plain_text = parse_result.text
				# re-sort since positions shifted
				sorted_attrs = parse_result.attributes.duplicate()
				sorted_attrs.sort_custom(func(a, b): return a.position < b.position)
			break

	# for BBCode conversion, we process attributes and convert them
	# this is a simplified approach - for full BBCode, use the processors
	output = plain_text

	# apply BBCode processors to known attributes
	var bbcode_output := ""
	var current_pos := 0
	var attr_stack: Array = []

	# build a list of events (opens and closes)
	var events: Array = []
	for attr in sorted_attrs:
		if attr.name == YarnLineParser.CHARACTER_ATTRIBUTE:
			continue  # skip character attribute in BBCode output

		events.append({"type": "open", "pos": attr.position, "attr": attr})
		events.append({"type": "close", "pos": attr.position + attr.length, "attr": attr})

	events.sort_custom(func(a, b):
		if a.pos != b.pos:
			return a.pos < b.pos
		# closes before opens at same position
		return a.type == "close")

	for event in events:
		# add text before this event
		if event.pos > current_pos:
			bbcode_output += plain_text.substr(current_pos, event.pos - current_pos)
			current_pos = event.pos

		if event.type == "open":
			var processor := _find_processor(event.attr.name)
			if processor != null:
				# convert attribute properties to dict for processor
				var props: Dictionary = {}
				for key in event.attr.properties:
					var val: Variant = event.attr.properties[key]
					if val is YarnMarkupValue:
						props[key] = val.to_string_value()
					else:
						props[key] = str(val)

				# get value from first property or name property
				var attr_value := ""
				if event.attr.properties.has(event.attr.name):
					var v: Variant = event.attr.properties[event.attr.name]
					if v is YarnMarkupValue:
						attr_value = v.to_string_value()
					else:
						attr_value = str(v)

				bbcode_output += processor.process_open(attr_value, props)
				attr_stack.append({"attr": event.attr, "processor": processor})
		else:
			# find and close the matching open tag
			for i in range(attr_stack.size() - 1, -1, -1):
				if attr_stack[i].attr == event.attr:
					bbcode_output += attr_stack[i].processor.process_close()
					attr_stack.remove_at(i)
					break

	# add remaining text
	if current_pos < plain_text.length():
		bbcode_output += plain_text.substr(current_pos)

	# close any remaining open tags
	for i in range(attr_stack.size() - 1, -1, -1):
		bbcode_output += attr_stack[i].processor.process_close()

	result.text = bbcode_output if not bbcode_output.is_empty() else plain_text

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

	if result.character_name.is_empty():
		result.character_name = _character_processor.character_name

	return result


## find a processor that handles the given attribute
func _find_processor(attr_name: String) -> YarnMarkupAttributeProcessor:
	for processor in _processors:
		if processor.handles_attribute(attr_name):
			return processor
	return null
