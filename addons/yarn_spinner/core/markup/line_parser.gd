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

const _TOKEN_TYPE_NAMES: Array[String] = [
	"Text",
	"OpenMarker",
	"CloseMarker",
	"CloseSlash",
	"Identifier",
	"Error",
	"Start",
	"End",
	"Equals",
	"StringValue",
	"NumberValue",
	"BooleanValue",
	"InterpolatedValue",
]

static var _implicit_character_regex: RegEx = RegEx.create_from_string("^(?<name>(?:[^:\\\\]|\\\\.)*)(?<suffix>:[\\t\\n\\x{0B}\\f\\r\\x{85}\\p{Z}]*)")
static var _explicit_character_regex: RegEx = RegEx.create_from_string("^[\\t\\n\\x{0B}\\f\\r\\x{85}\\p{Z}]*\\[character")
static var _integer_regex: RegEx = RegEx.create_from_string("^-?[0-9]+$")
static var _float_regex: RegEx = RegEx.create_from_string("^-?([0-9]+\\.?[0-9]*|\\.[0-9]+)$")
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

static var _unicode_letter_digit_regex: RegEx = RegEx.create_from_string("^[\\p{L}\\p{Nd}]$")
static var _unicode_digit_regex: RegEx = RegEx.create_from_string("^\\p{Nd}$")

## check if a character is a Unicode letter or digit.
static func _is_letter_or_digit(c: String) -> bool:
	if c.is_empty():
		return false
	var code := c.unicode_at(0)
	# ASCII fast path
	if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
		return true
	# Unicode letters and digits beyond ASCII
	if code > 127:
		if code > 0xFFFF or (code >= 0xD800 and code <= 0xDFFF):
			return false
		return _unicode_letter_digit_regex.search(c) != null
	return false


static func _is_letter_or_digit_unit(unit: int) -> bool:
	if unit < 0 or unit > 0xFFFF:
		return false
	return _is_letter_or_digit(String.chr(unit))


static func _is_digit_unit(unit: int) -> bool:
	if unit >= 48 and unit <= 57:
		return true
	if unit < 128 or unit > 0xFFFF or (unit >= 0xD800 and unit <= 0xDFFF):
		return false
	return _unicode_digit_regex.search(String.chr(unit)) != null


static func _is_white_space_unit(unit: int) -> bool:
	if unit == 32 or (unit >= 9 and unit <= 13) or unit == 0x85 or unit == 0xA0:
		return true
	if unit < 0x1680:
		return false
	return unit == 0x1680 or (unit >= 0x2000 and unit <= 0x200A) or unit == 0x2028 or unit == 0x2029 or unit == 0x202F or unit == 0x205F or unit == 0x3000


static func _peek_unit(units: PackedInt32Array, reader: int) -> int:
	if reader < units.size():
		return units[reader]
	return -1


static func _is_invariant_float(value: String) -> bool:
	return _float_regex.search(value) != null


static func _try_parse_int32(value: String) -> Variant:
	if _integer_regex.search(value) == null:
		return null
	if value.trim_prefix("-").lstrip("0").length() > 10:
		return null
	var parsed := value.to_int()
	if parsed < -2147483648 or parsed > 2147483647:
		return null
	return parsed


static func _trim_character(value: String, character: String) -> String:
	var start := 0
	var end := value.length()
	while start < end and value[start] == character:
		start += 1
	while end > start and value[end - 1] == character:
		end -= 1
	return value.substr(start, end - start)


static func create_with_builtin_replacers() -> YarnLineParser:
	var parser := YarnLineParser.new()
	var builtin_replacer := YarnBuiltInMarkupReplacer.new()
	parser.register_marker_processor("select", builtin_replacer)
	parser.register_marker_processor("plural", builtin_replacer)
	parser.register_marker_processor("ordinal", builtin_replacer)
	return parser


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

	input = YarnUnicodeNormalization.nfc(input)

	var units := PackedInt32Array()
	var unit_to_character := PackedInt32Array()
	for index in range(input.length()):
		var code := input.unicode_at(index)
		if code > 0xFFFF:
			code -= 0x10000
			units.append(0xD800 + (code >> 10))
			units.append(0xDC00 + (code & 0x3FF))
			unit_to_character.append(index)
			unit_to_character.append(index)
		else:
			units.append(code)
			unit_to_character.append(index)
	unit_to_character.append(input.length())
	var unit_count := units.size()

	var mode := LexerMode.TEXT
	var last := LexerToken.new(LexerTokenType.START)
	last.start = 0
	last.end = 0
	tokens.append(last)

	var current_position := 0
	var reader := 0

	while reader < unit_count:
		var c := units[reader]
		reader += 1

		if mode == LexerMode.TEXT:
			var is_text := c != 91
			if not is_text and last.type == LexerTokenType.TEXT and units[last.end] == 92:
				is_text = true

			if is_text:
				if last.type == LexerTokenType.TEXT:
					last.end = current_position
				else:
					last = LexerToken.new(LexerTokenType.TEXT)
					last.start = current_position
					last.end = current_position
					tokens.append(last)
			else:
				last = LexerToken.new(LexerTokenType.OPEN_MARKER)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.TAG

		elif mode == LexerMode.TAG:
			if c == 93:
				last = LexerToken.new(LexerTokenType.CLOSE_MARKER)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.TEXT
			elif c == 47:
				last = LexerToken.new(LexerTokenType.CLOSE_SLASH)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
			elif c == 61:
				last = LexerToken.new(LexerTokenType.EQUALS)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.VALUE
			elif _is_letter_or_digit_unit(c):
				var start := current_position
				var peek := _peek_unit(units, reader)
				while _is_letter_or_digit_unit(peek) or peek == 95 or peek == 124:
					reader += 1
					current_position += 1
					peek = _peek_unit(units, reader)
				last = LexerToken.new(LexerTokenType.IDENTIFIER)
				last.start = start
				last.end = current_position
				tokens.append(last)
			elif not _is_white_space_unit(c):
				last = LexerToken.new(LexerTokenType.ERROR)
				last.start = current_position
				last.end = current_position
				tokens.append(last)
				mode = LexerMode.TEXT

		elif mode == LexerMode.VALUE:
			if _is_white_space_unit(c):
				current_position += 1
				continue

			if _is_digit_unit(c) or c == 45:
				var token := LexerToken.new(LexerTokenType.NUMBER_VALUE)
				token.start = current_position

				var next_unit := _peek_unit(units, reader)
				if _is_digit_unit(next_unit) or next_unit == 46:
					while reader < unit_count:
						reader += 1
						current_position += 1
						if reader >= unit_count:
							token.type = LexerTokenType.ERROR
							break
						next_unit = units[reader]
						if not (_is_digit_unit(next_unit) or next_unit == 46):
							break

				var first_character := unit_to_character[token.start]
				var value_str := input.substr(first_character, unit_to_character[current_position] + 1 - first_character)
				if not _is_invariant_float(value_str):
					token.type = LexerTokenType.ERROR
				token.end = current_position
				tokens.append(token)
				last = token
				mode = LexerMode.TAG

			elif c == 34:
				var token := LexerToken.new(LexerTokenType.STRING_VALUE)
				token.start = current_position

				if reader < unit_count:
					var next_quote := -1
					var first_quote := -1
					for index in range(current_position + 1, unit_count):
						if units[index] != 34:
							continue
						if first_quote == -1:
							first_quote = index
						if units[index - 1] != 92:
							next_quote = index
							break
					if next_quote == -1:
						next_quote = first_quote

					if next_quote == -1:
						token.type = LexerTokenType.ERROR
					else:
						var length := next_quote - current_position
						reader += length
						current_position += length
				else:
					token.type = LexerTokenType.ERROR

				token.end = current_position
				tokens.append(token)
				last = token
				mode = LexerMode.TAG

			elif c == 123:
				var token := LexerToken.new(LexerTokenType.INTERPOLATED_VALUE)
				token.start = current_position

				var exited := false
				while reader < unit_count:
					current_position += 1
					var read_unit := units[reader]
					reader += 1
					if read_unit == 125:
						exited = true
						break

				if not exited:
					token.type = LexerTokenType.ERROR

				token.end = current_position
				tokens.append(token)
				last = token
				mode = LexerMode.TAG

			else:
				var token := LexerToken.new(LexerTokenType.STRING_VALUE)
				token.start = current_position

				if _is_letter_or_digit_unit(_peek_unit(units, reader)):
					while reader < unit_count:
						reader += 1
						current_position += 1
						if not _is_letter_or_digit_unit(_peek_unit(units, reader)):
							break

				var first_character := unit_to_character[token.start]
				var value_str := input.substr(first_character, unit_to_character[current_position] + 1 - first_character)
				if value_str == "true" or value_str == "True" or value_str == "false" or value_str == "False":
					token.type = LexerTokenType.BOOLEAN_VALUE

				token.end = current_position
				tokens.append(token)
				last = token
				mode = LexerMode.TAG

		current_position += 1

	last = LexerToken.new(LexerTokenType.END)
	last.start = current_position
	last.end = unit_count - 1
	tokens.append(last)

	for token in tokens:
		token.start = unit_to_character[token.start]
		token.end = unit_to_character[token.end]

	return tokens


func _internal_id_property() -> YarnMarkupProperty:
	var id_property := YarnMarkupProperty.from_int(_INTERNAL_INCREMENT, _internal_incrementing_attribute)
	_internal_incrementing_attribute += 1
	return id_property


func _build_markup_tree_from_tokens(tokens: Array, original: String) -> Dictionary:
	var tree := MarkupTreeNode.new()
	var diagnostics: Array = []

	if tokens == null or tokens.size() < 2:
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("There are not enough tokens to form a valid tree."))
		return {"tree": tree, "diagnostics": diagnostics}

	if original.is_empty():
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("There is a valid list of tokens but no original string."))
		return {"tree": tree, "diagnostics": diagnostics}

	if tokens[0].type != LexerTokenType.START or tokens[tokens.size() - 1].type != LexerTokenType.END:
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Token list doesn't start and end with the correct tokens."))
		return {"tree": tree, "diagnostics": diagnostics}

	original = YarnUnicodeNormalization.nfc(original)

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
		if open_nodes.is_empty():
			diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Markup closed more attributes than were open.", stream.current().start))
			break

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
						diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("asked to close \"%s\" markup but there is no corresponding opening. Is [/%s] a typo?" % [remaining, remaining], stream.current().start))
					unmatched_closes.clear()

				elif stream.compare_pattern(close_open_pattern):
					# close specific marker [/name]
					var close_id_token := stream.look_ahead(2)
					var close_id := original.substr(close_id_token.start, close_id_token.get_range())
					stream.consume(3)

					if open_nodes.size() == 1:
						diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Asked to close \"%s\", but we don't have an open marker for it." % close_id, close_id_token.start))
					else:
						if close_id == open_nodes.back().node_name:
							open_nodes.pop_back()
						else:
							unmatched_closes.append(close_id)

				elif stream.compare_pattern(close_error_pattern):
					diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Error parsing markup, detected invalid token %s, following a close." % _TOKEN_TYPE_NAMES[stream.look_ahead(2).type], stream.current().start))

				else:
					# regular open marker
					if stream.peek().type != LexerTokenType.IDENTIFIER:
						diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Error parsing markup, detected invalid token %s, following an open marker." % _TOKEN_TYPE_NAMES[stream.peek().type], stream.peek().start))
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
								diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("we entered nomarkup mode but didn't find an exit token", token_start.start))
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

						elif stream.look_ahead(2).type == LexerTokenType.ERROR:
							var invalid_name := original.substr(id_token.start, stream.look_ahead(2).end - id_token.start)
							diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Error parsing markup, invalid name: \"%s\"" % invalid_name, id_token.start))
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
					var int_value: Variant = _try_parse_int32(value_str)
					if int_value != null:
						open_nodes.back().properties.append(YarnMarkupProperty.from_int(id, int_value))
					elif _is_invariant_float(value_str):
						open_nodes.back().properties.append(YarnMarkupProperty.from_float(id, YarnNumber.to_f32(value_str.to_float())))
					else:
						diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("failed to convert the value %s into a valid property" % value_str, value_token.start))

				elif stream.compare_pattern(boolean_property_pattern):
					var value_token := stream.look_ahead(2)
					var value_str := original.substr(value_token.start, value_token.get_range())
					open_nodes.back().properties.append(YarnMarkupProperty.from_bool(id, value_str.to_lower() == "true"))

				elif stream.compare_pattern(string_property_pattern):
					var value_token := stream.look_ahead(2)
					var value_str := original.substr(value_token.start, value_token.get_range())
					if value_str.begins_with("\"") and value_str.ends_with("\""):
						value_str = _trim_character(value_str.replace("\\", ""), "\"")
					open_nodes.back().properties.append(YarnMarkupProperty.from_string(id, value_str))

				elif stream.compare_pattern(interpolated_property_pattern):
					var value_token := stream.look_ahead(2)
					var value_str := original.substr(value_token.start, value_token.get_range())
					value_str = _trim_character(_trim_character(value_str, "{"), "}")
					open_nodes.back().properties.append(YarnMarkupProperty.from_string(id, value_str))

				else:
					var peek_token := stream.peek()
					var look_token := stream.look_ahead(2)
					var found := "%s %s %s" % [id, original.substr(peek_token.start, peek_token.get_range()), original.substr(look_token.start, look_token.get_range())]
					diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Expected to find a property and it's value, but instead found \"%s\"." % found, stream.peek().start))

				stream.consume(2)

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
					diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("Encountered an unexpected closing slash", stream.current().start))

		stream.next()

	if unmatched_closes.size() > 1:
		_clean_up_unmatched_closes(open_nodes, unmatched_closes, diagnostics)

	# check for unclosed attributes
	if open_nodes.size() > 1:
		var node_names := PackedStringArray()
		for index in range(open_nodes.size() - 1, -1, -1):
			var node: MarkupTreeNode = open_nodes[index]
			if not node.node_name.is_empty():
				node_names.append("[" + node.node_name + "]")
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("parsing finished with unclosed attributes still on the stack: " + ", ".join(node_names)))

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
			errors.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("asked to close \"%s\" markup but there is no corresponding opening. Is [/%s] a typo?" % [unmatched, unmatched]))
		unmatched_close_names.clear()
		return

	# reparent orphans
	for template in orphans:
		var clone := MarkupTreeNode.new()
		clone.node_name = template.node_name
		clone.properties = template.properties
		clone.first_token = template.first_token
		open_nodes.back().children.append(clone)
		open_nodes.append(clone)


func _walk_and_process_tree(root: MarkupTreeNode, builder: Array, attributes: Array, locale_code: String, diagnostics: Array, offset: int = 0) -> void:
	_sibling = null
	_invisible_characters = 0
	_walk_tree(root, builder, attributes, locale_code, diagnostics, offset)


static func _duplicate_property_name(properties: Array) -> String:
	var seen: Dictionary = {}
	for prop in properties:
		if seen.has(prop.name):
			return prop.name
		seen[prop.name] = true
	return ""


func _walk_tree(root: MarkupTreeNode, builder: Array, attributes: Array, locale_code: String, diagnostics: Array, offset: int = 0) -> void:
	if root is MarkupTextNode:
		var line: String = root.text

		# check for whitespace trimming from older sibling
		if _sibling != null:
			for prop in _sibling.properties:
				if prop.name == TRIM_WHITESPACE_PROPERTY:
					if prop.value.bool_value == true:
						if line.length() > 0 and _is_white_space_unit(line.unicode_at(0)):
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

	var duplicate_name := _duplicate_property_name(root.properties)
	if not duplicate_name.is_empty():
		diagnostics.append(YarnAttributeMarkerProcessor.MarkupDiagnostic.new("An item with the same key has already been added. Key: %s" % duplicate_name, root.first_token.start if root.first_token else -1))
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
	for diagnostic in result.diagnostics:
		push_warning("markup: %s" % diagnostic._to_string())
	return result.markup


func parse_string_and_include_markup_diagnostics(input: String, locale_code: String, add_implicit_character: bool = true) -> Dictionary:
	return _parse_string_with_diagnostics(input, locale_code, true, true, add_implicit_character)


func _parse_string_with_diagnostics(input: String, locale_code: String, squish: bool = true, sort: bool = true, add_implicit_character: bool = true) -> Dictionary:
	if input == null:
		push_error("Input is null")
		return {"markup": YarnMarkupParseResult.new(), "diagnostics": []}

	input = YarnUnicodeNormalization.nfc(input)

	# Implicit character detection: inject [character] markup before parsing,
	# so the character attribute goes through the full markup pipeline
	# (matching the canonical C# LineParser behaviour)
	if add_implicit_character and not _explicit_character_regex.search(input):
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
		var value: Variant = substitutions[i]
		text = text.replace("{%d}" % i, "" if value == null else str(value))

	return text
