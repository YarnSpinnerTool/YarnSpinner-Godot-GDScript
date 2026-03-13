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

class_name YarnLineParser
extends RefCounted
## parses text and produces markup information.

## property name in replacement attributes that contains the text.
const REPLACEMENT_MARKER_CONTENTS := "contents"

## implicitly-generated character attribute name.
const CHARACTER_ATTRIBUTE := "character"

## 'name' property key on the character attribute.
const CHARACTER_ATTRIBUTE_NAME_PROPERTY := "name"

## property to signify trailing whitespace trimming.
const TRIM_WHITESPACE_PROPERTY := "trimwhitespace"

## attribute to indicate no marker processing.
const NO_MARKUP_ATTRIBUTE := "nomarkup"

## internal property for tracking split attributes
const _INTERNAL_INCREMENT := "_internalIncrementingProperty"

static var _implicit_character_regex: RegEx
static var _explicit_character_regex: RegEx = RegEx.create_from_string("^\\s*\\[character")
enum LexerTokenType {
	TEXT,
	OPEN_MARKER,
	CLOSE_MARKER,
	CLOSE_SLASH,
	IDENTIFIER,
	ERROR,
	START,
	END,
	EQUALS,
	STRING_VALUE,
	NUMBER_VALUE,
	BOOLEAN_VALUE,
	INTERPOLATED_VALUE,
}

enum LexerMode {
	TEXT,
	TAG,
	VALUE,
}

class LexerToken extends RefCounted:
	var type: int = LexerTokenType.TEXT
	var start: int = 0
	var end: int = 0

	func _init(token_type: int = LexerTokenType.TEXT) -> void:
		type = token_type

	func get_range() -> int:
		return end + 1 - start


class TokenStream extends RefCounted:
	var tokens: Array = []
	var iterator: int = 0

	func _init(token_list: Array) -> void:
		tokens = token_list

	func current() -> LexerToken:
		if iterator < 0:
			iterator = 0
			var first := LexerToken.new(LexerTokenType.START)
			return first
		if iterator > tokens.size() - 1:
			iterator = tokens.size() - 1
			var last := LexerToken.new(LexerTokenType.END)
			return last
		return tokens[iterator]

	func next() -> LexerToken:
		iterator += 1
		return current()

	func previous() -> LexerToken:
		iterator -= 1
		return current()

	func consume(number: int) -> void:
		iterator += number

	func peek() -> LexerToken:
		iterator += 1
		var next_token := current()
		iterator -= 1
		return next_token

	func look_ahead(number: int) -> LexerToken:
		iterator += number
		var look := current()
		iterator -= number
		return look

	func compare_pattern(pattern: Array) -> bool:
		var match_result := true
		var current_iterator := iterator
		for token_type in pattern:
			if current().type == token_type:
				iterator += 1
				continue
			match_result = false
			break
		iterator = current_iterator
		return match_result


class MarkupTreeNode extends RefCounted:
	var node_name: String = ""
	var first_token: LexerToken = null
	var children: Array = []  # Array[MarkupTreeNode]
	var properties: Array = []  # Array[YarnMarkupProperty]


class MarkupTextNode extends MarkupTreeNode:
	var text: String = ""


var _marker_processors: Dictionary[String, YarnAttributeMarkerProcessor] = {}
var _internal_incrementing_attribute: int = 1
var _sibling: MarkupTreeNode = null
var _invisible_characters: int = 0

static var _unicode_letter_digit_regex: RegEx

## check if a character is a Unicode letter or digit.
static func _is_letter_or_digit(c: String) -> bool:
	if c.is_empty():
		return false
	var code := c.unicode_at(0)
	# ASCII fast path
	if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
		return true
	# underscore (common in identifiers)
	if code == 95:
		return true
	# Unicode letters and digits beyond ASCII
	if code > 127:
		if _unicode_letter_digit_regex == null:
			_unicode_letter_digit_regex = RegEx.new()
			_unicode_letter_digit_regex.compile("^[\\p{L}\\p{N}]$")
		return _unicode_letter_digit_regex.search(c) != null
	return false


func register_marker_processor(attribute_name: String, processor: YarnAttributeMarkerProcessor) -> void:
	if _marker_processors.has(attribute_name):
		push_error("A marker processor for %s has already been registered" % attribute_name)
		return
	_marker_processors[attribute_name] = processor


func deregister_marker_processor(attribute_name: String) -> void:
	_marker_processors.erase(attribute_name)


func _lex_markup(input: String) -> Array:
	var tokens: Array = []

	if input.is_empty():
		var start_token := LexerToken.new(LexerTokenType.START)
		start_token.start = 0
		start_token.end = 0
		var end_token := LexerToken.new(LexerTokenType.END)
		end_token.start = 0
		end_token.end = 0
		tokens.append(start_token)
		tokens.append(end_token)
		return tokens

	var mode := LexerMode.TEXT
	var last := LexerToken.new(LexerTokenType.START)
	last.start = 0
	last.end = 0
	tokens.append(last)

	var current_position := 0
	var i := 0

	while i < input.length():
		var c := input[i]

		if mode == LexerMode.TEXT:
			if c == "[":
				# check for escape sequence
				if last.type == LexerTokenType.TEXT and last.end >= 0 and last.end < input.length():
					var l := input[last.end]
					if l == "\\":
						# escaped bracket, treat as text
						if last.type == LexerTokenType.TEXT:
							last.end = current_position
						else:
							last = LexerToken.new(LexerTokenType.TEXT)
							last.start = current_position
							last.end = current_position
							tokens.append(last)
						current_position += 1
						i += 1
						continue

				last = LexerToken.new(LexerTokenType.OPEN_MARKER)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.TAG
			else:
				if last.type == LexerTokenType.TEXT:
					last.end = current_position
				else:
					last = LexerToken.new(LexerTokenType.TEXT)
					last.start = current_position
					last.end = current_position
					tokens.append(last)

		elif mode == LexerMode.TAG:
			if c == "]":
				last = LexerToken.new(LexerTokenType.CLOSE_MARKER)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.TEXT
			elif c == "/":
				last = LexerToken.new(LexerTokenType.CLOSE_SLASH)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
			elif c == "=":
				last = LexerToken.new(LexerTokenType.EQUALS)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.VALUE
			elif _is_letter_or_digit(c):
				# alphanumeric - identifier (Unicode-aware)
				var start := current_position
				# keep reading while alphanumeric
				while i + 1 < input.length():
					var next_c := input[i + 1]
					if _is_letter_or_digit(next_c):
						i += 1
						current_position += 1
					else:
						break
				last = LexerToken.new(LexerTokenType.IDENTIFIER)
				last.start = start
				last.end = current_position
				tokens.append(last)
			elif not c.strip_edges().is_empty():
				# non-whitespace, non-alphanumeric in tag mode is error
				last = LexerToken.new(LexerTokenType.ERROR)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.TEXT

		elif mode == LexerMode.VALUE:
			# skip whitespace before value
			if c.strip_edges().is_empty():
				current_position += 1
				i += 1
				continue

			if c == "-" or (c.unicode_at(0) >= 48 and c.unicode_at(0) <= 57):
				# number value
				var token := LexerToken.new(LexerTokenType.NUMBER_VALUE)
				token.start = current_position

				# read digits and decimal points
				while i + 1 < input.length():
					var next_c := input[i + 1]
					if next_c.unicode_at(0) >= 48 and next_c.unicode_at(0) <= 57 or next_c == ".":
						i += 1
						current_position += 1
					else:
						break

				# validate as float
				var value_str := input.substr(token.start, current_position + 1 - token.start)
				if value_str.is_valid_float() or value_str.is_valid_int():
					token.end = current_position
					tokens.append(token)
					last = token
				else:
					token.type = LexerTokenType.ERROR
					token.end = current_position
					tokens.append(token)
					last = token

				mode = LexerMode.TAG

			elif c == "\"":
				# quoted string value
				var token := LexerToken.new(LexerTokenType.STRING_VALUE)
				token.start = current_position

				# find closing quote (handling escaped quotes)
				var found_close := false
				while i + 1 < input.length():
					i += 1
					current_position += 1
					if input[i] == "\"" and (i == 0 or input[i - 1] != "\\"):
						found_close = true
						break

				if not found_close:
					token.type = LexerTokenType.ERROR

				token.end = current_position
				tokens.append(token)
				last = token
				mode = LexerMode.TAG

			elif c == "{":
				# interpolated value
				var token := LexerToken.new(LexerTokenType.INTERPOLATED_VALUE)
				token.start = current_position

				var exited := false
				while i + 1 < input.length():
					i += 1
					current_position += 1
					if input[i] == "}":
						exited = true
						break

				if not exited:
					token.type = LexerTokenType.ERROR

				token.end = current_position
				tokens.append(token)
				last = token
				mode = LexerMode.TAG

			else:
				# unquoted string or boolean
				var token := LexerToken.new(LexerTokenType.STRING_VALUE)
				token.start = current_position

				# read alphanumeric characters (Unicode-aware)
				while i + 1 < input.length():
					var next_c := input[i + 1]
					if _is_letter_or_digit(next_c):
						i += 1
						current_position += 1
					else:
						break

				var value_str := input.substr(token.start, current_position + 1 - token.start)
				if value_str.to_lower() == "true" or value_str.to_lower() == "false":
					token.type = LexerTokenType.BOOLEAN_VALUE

				token.end = current_position
				tokens.append(token)
				last = token
				mode = LexerMode.TAG

		current_position += 1
		i += 1

	# add end token
	last = LexerToken.new(LexerTokenType.END)
	last.start = current_position
	last.end = input.length() - 1 if input.length() > 0 else 0
	tokens.append(last)

	return tokens


func _internal_id_property() -> YarnMarkupProperty:
	var id_property := YarnMarkupProperty.from_int(_INTERNAL_INCREMENT, _internal_incrementing_attribute)
	_internal_incrementing_attribute += 1
	return id_property


func _build_markup_tree_from_tokens(tokens: Array, original: String) -> Dictionary:
	var tree := MarkupTreeNode.new()
	var diagnostics: Array = []

	if tokens == null or tokens.size() < 2:
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Not enough tokens to form a valid tree"))
		return {"tree": tree, "diagnostics": diagnostics}

	if original.is_empty():
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Valid tokens but no original string"))
		return {"tree": tree, "diagnostics": diagnostics}

	if tokens[0].type != LexerTokenType.START or tokens[tokens.size() - 1].type != LexerTokenType.END:
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Token list doesn't start and end correctly"))
		return {"tree": tree, "diagnostics": diagnostics}

	var close_all_pattern := [LexerTokenType.OPEN_MARKER, LexerTokenType.CLOSE_SLASH, LexerTokenType.CLOSE_MARKER]
	var close_open_pattern := [LexerTokenType.OPEN_MARKER, LexerTokenType.CLOSE_SLASH, LexerTokenType.IDENTIFIER, LexerTokenType.CLOSE_MARKER]
	var close_error_pattern := [LexerTokenType.OPEN_MARKER, LexerTokenType.CLOSE_SLASH]
	var open_propertyless_pattern := [LexerTokenType.OPEN_MARKER, LexerTokenType.IDENTIFIER, LexerTokenType.CLOSE_MARKER]
	var number_property_pattern := [LexerTokenType.IDENTIFIER, LexerTokenType.EQUALS, LexerTokenType.NUMBER_VALUE]
	var boolean_property_pattern := [LexerTokenType.IDENTIFIER, LexerTokenType.EQUALS, LexerTokenType.BOOLEAN_VALUE]
	var string_property_pattern := [LexerTokenType.IDENTIFIER, LexerTokenType.EQUALS, LexerTokenType.STRING_VALUE]
	var interpolated_property_pattern := [LexerTokenType.IDENTIFIER, LexerTokenType.EQUALS, LexerTokenType.INTERPOLATED_VALUE]
	var self_closing_pattern := [LexerTokenType.CLOSE_SLASH, LexerTokenType.CLOSE_MARKER]

	var stream := TokenStream.new(tokens)
	var open_nodes: Array = [tree]
	var unmatched_closes: Array = []

	while stream.current().type != LexerTokenType.END:
		var token_type := stream.current().type

		match token_type:
			LexerTokenType.START:
				pass

			LexerTokenType.END:
				_clean_up_unmatched_closes(open_nodes, unmatched_closes, diagnostics)

			LexerTokenType.TEXT:
				if unmatched_closes.size() > 0:
					_clean_up_unmatched_closes(open_nodes, unmatched_closes, diagnostics)

				var text := original.substr(stream.current().start, stream.current().end + 1 - stream.current().start)
				var node := MarkupTextNode.new()
				node.text = text
				node.first_token = stream.current()
				open_nodes.back().children.append(node)

			LexerTokenType.OPEN_MARKER:
				if stream.compare_pattern(close_all_pattern):
					# close all marker [/]
					stream.consume(2)
					while open_nodes.size() > 1:
						var markup_node: MarkupTreeNode = open_nodes.pop_back()
						if not markup_node.node_name.is_empty():
							unmatched_closes.erase(markup_node.node_name)

					for remaining in unmatched_closes:
						diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("asked to close %s but no corresponding opening" % remaining))
					unmatched_closes.clear()

				elif stream.compare_pattern(close_open_pattern):
					# close specific marker [/name]
					var close_id_token := stream.look_ahead(2)
					var close_id := original.substr(close_id_token.start, close_id_token.get_range())
					stream.consume(3)

					if open_nodes.size() == 1:
						diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Asked to close %s, but no open marker for it" % close_id, close_id_token.start))
					else:
						if close_id == open_nodes.back().node_name:
							open_nodes.pop_back()
						else:
							unmatched_closes.append(close_id)

				elif stream.compare_pattern(close_error_pattern):
					diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Invalid token following close", stream.current().start))

				else:
					# regular open marker
					if stream.peek().type != LexerTokenType.IDENTIFIER:
						diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Invalid token following open marker", stream.peek().start))
					else:
						if unmatched_closes.size() > 0:
							_clean_up_unmatched_closes(open_nodes, unmatched_closes, diagnostics)

						var id_token := stream.peek()
						var id := original.substr(id_token.start, id_token.get_range())

						# check for nomarkup
						if stream.compare_pattern(open_propertyless_pattern) and id == NO_MARKUP_ATTRIBUTE:
							var token_start := stream.current()
							var first_token_after := stream.look_ahead(3)

							var nm: MarkupTreeNode = null
							while stream.current().type != LexerTokenType.END:
								if stream.compare_pattern(close_open_pattern):
									var nm_id_token := stream.look_ahead(2)
									if original.substr(nm_id_token.start, nm_id_token.get_range()) == NO_MARKUP_ATTRIBUTE:
										var text_node := MarkupTextNode.new()
										text_node.text = original.substr(first_token_after.start, stream.current().start - first_token_after.start)
										nm = MarkupTreeNode.new()
										nm.node_name = NO_MARKUP_ATTRIBUTE
										nm.children.append(text_node)
										nm.first_token = token_start
										stream.consume(3)
										break
								stream.next()

							if nm == null:
								diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("entered nomarkup mode but no exit token", token_start.start))
							else:
								open_nodes.back().children.append(nm)

						elif stream.compare_pattern(open_propertyless_pattern):
							# simple marker [name]
							var marker := MarkupTreeNode.new()
							marker.node_name = id
							marker.first_token = stream.current()
							open_nodes.back().children.append(marker)
							open_nodes.append(marker)
							stream.consume(2)

						else:
							# marker with properties
							var marker := MarkupTreeNode.new()
							marker.node_name = id
							marker.first_token = stream.current()
							open_nodes.back().children.append(marker)
							open_nodes.append(marker)

							if stream.look_ahead(2).type != LexerTokenType.EQUALS:
								stream.consume(1)

			LexerTokenType.IDENTIFIER:
				# property definition
				var id := original.substr(stream.current().start, stream.current().get_range())

				if stream.compare_pattern(number_property_pattern):
					var value_token := stream.look_ahead(2)
					var value_str := original.substr(value_token.start, value_token.get_range())
					if not value_str.contains(".") and value_str.is_valid_int():
						open_nodes.back().properties.append(YarnMarkupProperty.from_int(id, value_str.to_int()))
					else:
						open_nodes.back().properties.append(YarnMarkupProperty.from_float(id, value_str.to_float()))
					stream.consume(2)

				elif stream.compare_pattern(boolean_property_pattern):
					var value_token := stream.look_ahead(2)
					var value_str := original.substr(value_token.start, value_token.get_range())
					open_nodes.back().properties.append(YarnMarkupProperty.from_bool(id, value_str.to_lower() == "true"))
					stream.consume(2)

				elif stream.compare_pattern(string_property_pattern):
					var value_token := stream.look_ahead(2)
					var value_str := original.substr(value_token.start, value_token.get_range())
					# remove quotes and handle escapes
					if value_str.begins_with("\"") and value_str.ends_with("\""):
						value_str = value_str.substr(1, value_str.length() - 2).replace("\\", "")
					open_nodes.back().properties.append(YarnMarkupProperty.from_string(id, value_str))
					stream.consume(2)

				elif stream.compare_pattern(interpolated_property_pattern):
					var value_token := stream.look_ahead(2)
					var value_str := original.substr(value_token.start, value_token.get_range())
					value_str = value_str.trim_prefix("{").trim_suffix("}")
					open_nodes.back().properties.append(YarnMarkupProperty.from_string(id, value_str))
					stream.consume(2)

				else:
					diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Expected property and value", stream.peek().start))

			LexerTokenType.CLOSE_SLASH:
				# self-closing marker
				if stream.compare_pattern(self_closing_pattern):
					var top: MarkupTreeNode = open_nodes.pop_back()
					# add trimwhitespace property if not present
					var found := false
					for prop in top.properties:
						if prop.name == TRIM_WHITESPACE_PROPERTY:
							found = true
							break
					if not found:
						top.properties.append(YarnMarkupProperty.from_bool(TRIM_WHITESPACE_PROPERTY, true))
					stream.consume(1)
				else:
					diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Unexpected closing slash", stream.current().start))

		stream.next()

	# clean up remaining unmatched closes
	if unmatched_closes.size() > 0:
		_clean_up_unmatched_closes(open_nodes, unmatched_closes, diagnostics)

	# check for unclosed attributes
	if open_nodes.size() > 1:
		var line := "parsing finished with unclosed attributes: "
		for node in open_nodes:
			if node.node_name.is_empty():
				line += " NULL"
			else:
				line += " [" + node.node_name + "]"
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new(line))

	return {"tree": tree, "diagnostics": diagnostics}


## clean up unmatched closes using adoption agency algorithm
func _clean_up_unmatched_closes(open_nodes: Array, unmatched_close_names: Array, errors: Array) -> void:
	var orphans: Array = []

	while unmatched_close_names.size() > 0 and open_nodes.size() > 1:
		var top: MarkupTreeNode = open_nodes.pop_back()

		# add internal ID if not already present
		var found := false
		for prop in top.properties:
			if prop.name == _INTERNAL_INCREMENT:
				found = true
				break
		if not found:
			top.properties.append(_internal_id_property())

		if not top.node_name.is_empty() and not unmatched_close_names.has(top.node_name):
			orphans.push_front(top)
		else:
			unmatched_close_names.erase(top.node_name)

	# report remaining unmatched closes
	if unmatched_close_names.size() > 0:
		for unmatched in unmatched_close_names:
			errors.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("asked to close %s but no corresponding opening" % unmatched))
		unmatched_close_names.clear()
		return

	# reparent orphans
	for template in orphans:
		var clone := MarkupTreeNode.new()
		clone.node_name = template.node_name
		clone.properties = template.properties.duplicate()
		clone.first_token = template.first_token
		open_nodes.back().children.append(clone)
		open_nodes.append(clone)


func _walk_and_process_tree(root: MarkupTreeNode, builder: Array, attributes: Array, locale_code: String, diagnostics: Array, offset: int = 0) -> void:
	_sibling = null
	_invisible_characters = 0
	_walk_tree(root, builder, attributes, locale_code, diagnostics, offset)


func _walk_tree(root: MarkupTreeNode, builder: Array, attributes: Array, locale_code: String, diagnostics: Array, offset: int = 0) -> void:
	if root is MarkupTextNode:
		var line: String = root.text

		# check for whitespace trimming from older sibling
		if _sibling != null:
			for prop in _sibling.properties:
				if prop.name == TRIM_WHITESPACE_PROPERTY:
					if prop.value.bool_value == true:
						if line.length() > 0 and line[0] in [" ", "\t", "\n", "\r"]:
							line = line.substr(1)
					break

		# handle escape sequences
		line = line.replace("\\[", "[")
		line = line.replace("\\]", "]")

		builder[0] += line
		_sibling = root
		return

	# process children
	var child_builder: Array = [""]
	var child_attributes: Array = []
	for child in root.children:
		_walk_tree(child, child_builder, child_attributes, locale_code, diagnostics, builder[0].length() + offset)

	# if root node, just add children and return
	if root.node_name.is_empty():
		builder[0] += child_builder[0]
		attributes.append_array(child_attributes)
		return

	# check for replacement marker processor
	if _marker_processors.has(root.node_name):
		var rewriter: YarnAttributeMarkerProcessor = _marker_processors[root.node_name]
		var attribute := YarnMarkupAttribute.new(
			builder[0].length() + offset,
			root.first_token.start if root.first_token else -1,
			child_builder[0].length(),
			root.node_name,
			root.properties
		)
		var result := rewriter.process_replacement_marker(attribute, child_builder, child_attributes, locale_code)
		diagnostics.append_array(result.diagnostics)
		_invisible_characters += result.invisible_characters
	else:
		# not a replacement marker, add as attribute
		var attribute := YarnMarkupAttribute.new(
			builder[0].length() - _invisible_characters + offset,
			root.first_token.start if root.first_token else -1,
			child_builder[0].length(),
			root.node_name,
			root.properties
		)
		attributes.append(attribute)
		_sibling = root

	builder[0] += child_builder[0]
	attributes.append_array(child_attributes)


static func _squish_split_attributes(attributes: Array) -> void:
	var removals: Array = []
	var merged: Dictionary = {}

	for i in range(attributes.size()):
		var attribute: YarnMarkupAttribute = attributes[i]
		var value := attribute.try_get_property(_INTERNAL_INCREMENT)
		if value != null:
			var id := value.integer_value
			if merged.has(id):
				var existing: YarnMarkupAttribute = merged[id]
				if existing.position > attribute.position:
					existing.position = attribute.position
				existing.length += attribute.length
				merged[id] = existing
			else:
				merged[id] = attribute
			removals.append(i)

	# remove split attributes (reverse order)
	removals.sort()
	for i in range(removals.size() - 1, -1, -1):
		attributes.remove_at(removals[i])

	# add merged attributes back
	for id in merged:
		attributes.append(merged[id])


## parse a string and produce a markup parse result.
func parse_string(input: String, locale_code: String, add_implicit_character: bool = true) -> YarnMarkupParseResult:
	var result := _parse_string_with_diagnostics(input, locale_code, true, true, add_implicit_character)
	return result.markup


func _parse_string_with_diagnostics(input: String, locale_code: String, squish: bool = true, sort: bool = true, add_implicit_character: bool = true) -> Dictionary:
	if input == null:
		push_error("Input is null")
		return {"markup": YarnMarkupParseResult.new(), "diagnostics": []}

	# Implicit character detection: inject [character] markup before parsing,
	# so the character attribute goes through the full markup pipeline
	# (matching the canonical C# LineParser behaviour)
	if add_implicit_character and not _explicit_character_regex.search(input):
		if _implicit_character_regex == null:
			_implicit_character_regex = RegEx.new()
			_implicit_character_regex.compile("^(?<name>(?:[^:\\\\]|\\\\.)*)(?<suffix>:\\s*)")

		var match_result := _implicit_character_regex.search(input)
		if match_result:
			var char_name := match_result.get_string("name")
			var char_suffix := match_result.get_string("suffix")
			input = "[character name=\"" + char_name + "\"]" + char_name + char_suffix + "[/character]" + input.substr(match_result.get_end())

	# unescape \: to : now that character detection is done
	input = input.replace("\\:", ":")

	var tokens := _lex_markup(input)
	var parse_result := _build_markup_tree_from_tokens(tokens, input)

	# if parsing errors, return input as-is
	if parse_result.diagnostics.size() > 0:
		var error_markup := YarnMarkupParseResult.new(input)
		return {"markup": error_markup, "diagnostics": parse_result.diagnostics}

	var builder: Array = [""]
	var attributes: Array[YarnMarkupAttribute] = []
	var diagnostics: Array = []

	_walk_and_process_tree(parse_result.tree, builder, attributes, locale_code, diagnostics)

	if squish:
		_squish_split_attributes(attributes)

	var final_text: String = builder[0]

	if sort:
		attributes.sort_custom(func(a, b): return a.source_position < b.source_position)

	# if there were processing errors, return input as-is
	if diagnostics.size() > 0:
		final_text = input
		attributes.clear()

	var markup := YarnMarkupParseResult.new(final_text, attributes)
	return {"markup": markup, "diagnostics": diagnostics}


static func expand_substitutions(text: String, substitutions: Array) -> String:
	if substitutions == null or substitutions.is_empty():
		return text
	if text == null:
		push_error("Text is null, cannot apply substitutions")
		return ""

	for i in range(substitutions.size()):
		text = text.replace("{%d}" % i, str(substitutions[i]))

	return text
