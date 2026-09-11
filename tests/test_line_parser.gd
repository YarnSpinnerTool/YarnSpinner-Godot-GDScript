extends GutTest
## Tests for YarnLineParser: lexer, substitutions, and parsing.


var _parser: YarnLineParser


func before_each():
	_parser = YarnLineParser.new()
	var builtin := YarnBuiltInMarkupReplacer.new()
	_parser.register_marker_processor("select", builtin)
	_parser.register_marker_processor("plural", builtin)
	_parser.register_marker_processor("ordinal", builtin)


# --- Substitution expansion ---

func test_expand_no_placeholders():
	assert_eq(YarnLineParser.expand_substitutions("plain text", []), "plain text")


func test_expand_single():
	assert_eq(YarnLineParser.expand_substitutions("Hi {0}", ["Alice"]), "Hi Alice")


func test_expand_multiple():
	assert_eq(
		YarnLineParser.expand_substitutions("{0} has {1}", ["Alice", "gold"]),
		"Alice has gold"
	)


func test_expand_out_of_range():
	assert_eq(YarnLineParser.expand_substitutions("{0} {1}", ["only_one"]), "only_one {1}")


func test_expand_repeated():
	assert_eq(YarnLineParser.expand_substitutions("{0}{0}", ["x"]), "xx")


# --- Parse string ---

func test_parse_plain():
	var result := _parser.parse_string("Hello world", "en")
	assert_eq(result.text, "Hello world")
	assert_eq(result.attributes.size(), 0)


func test_parse_bold():
	var result := _parser.parse_string("[b]bold[/b] text", "en")
	assert_eq(result.text, "bold text")
	assert_true(result.attributes.size() > 0)
	assert_eq(result.attributes[0].name, "b")
	assert_eq(result.attributes[0].position, 0)
	assert_eq(result.attributes[0].length, 4)


func test_parse_decomposed_accents_match_composed():
	var composed := _parser.parse_string("Zo" + String.chr(0xEB) + ": [b]caf" + String.chr(0xE9) + "[/b] cr" + String.chr(0xE8) + "me", "en")
	var decomposed := _parser.parse_string("Zoe" + String.chr(0x308) + ": [b]cafe" + String.chr(0x301) + "[/b] cre" + String.chr(0x300) + "me", "en")
	assert_eq(decomposed.text, "Zo" + String.chr(0xEB) + ": caf" + String.chr(0xE9) + " cr" + String.chr(0xE8) + "me")
	assert_eq(decomposed.text, composed.text)
	assert_eq(decomposed.get_character_name(), "Zo" + String.chr(0xEB))
	assert_eq(decomposed.attributes.size(), 2)
	assert_eq(decomposed.attributes.size(), composed.attributes.size())
	for index in composed.attributes.size():
		assert_eq(decomposed.attributes[index].name, composed.attributes[index].name)
		assert_eq(decomposed.attributes[index].position, composed.attributes[index].position)
		assert_eq(decomposed.attributes[index].length, composed.attributes[index].length)
		assert_eq(decomposed.attributes[index].source_position, composed.attributes[index].source_position)
	var bold := decomposed.try_get_attribute_with_name("b")
	assert_not_null(bold)
	assert_eq(bold.position, 5)
	assert_eq(bold.length, 4)


func test_parse_nested():
	var result := _parser.parse_string("[b][i]both[/i][/b]", "en")
	assert_eq(result.text, "both")
	assert_eq(result.attributes.size(), 2)


func test_parse_close_all():
	var result := _parser.parse_string("[b]bold[/]", "en")
	assert_eq(result.text, "bold")


func test_parse_self_closing():
	var result := _parser.parse_string("before[pause/]after", "en")
	assert_eq(result.text, "beforeafter")


func test_parse_with_properties():
	var result := _parser.parse_string("[style name=\"fancy\"]text[/style]", "en")
	assert_eq(result.text, "text")
	assert_gt(result.attributes.size(), 0)
	assert_eq(result.attributes[0].name, "style")


func test_parse_implicit_character():
	var result := _parser.parse_string("Alice: Hello!", "en", true)
	var char_attr := result.try_get_attribute_with_name("character")
	assert_not_null(char_attr)


func test_parse_no_implicit_character():
	var result := _parser.parse_string("Alice: Hello!", "en", false)
	var char_attr := result.try_get_attribute_with_name("character")
	assert_null(char_attr)


func test_parse_explicit_character_overrides_implicit():
	var result := _parser.parse_string("[character name=\"Bob\"]Bob: [/character]Hello!", "en", true)
	var char_attr := result.try_get_attribute_with_name("character")
	assert_not_null(char_attr)
	var name_prop := char_attr.try_get_property("name")
	assert_not_null(name_prop)
	assert_eq(name_prop.string_value, "Bob")


func test_parse_nomarkup():
	var result := _parser.parse_string("[nomarkup][b]not bold[/b][/nomarkup]", "en")
	assert_true(result.text.contains("[b]"))


func test_parse_escaped_bracket():
	var result := _parser.parse_string("\\[not a tag\\]", "en")
	assert_true(result.text.contains("[not a tag]"))


func test_parse_empty_string():
	var result := _parser.parse_string("", "en")
	assert_eq(result.text, "")
	assert_eq(result.attributes.size(), 0)


# --- Attribute positions ---

func test_attribute_position_after_text():
	var result := _parser.parse_string("hello [b]world[/b]", "en")
	assert_gt(result.attributes.size(), 0)
	assert_eq(result.attributes[0].position, 6)
	assert_eq(result.attributes[0].length, 5)


func test_multiple_attributes_positions():
	var result := _parser.parse_string("[b]first[/b] [i]second[/i]", "en")
	assert_eq(result.attributes.size(), 2)
	assert_eq(result.attributes[0].name, "b")
	assert_eq(result.attributes[0].position, 0)
	assert_eq(result.attributes[0].length, 5)
	assert_eq(result.attributes[1].name, "i")
	assert_eq(result.attributes[1].position, 6)
	assert_eq(result.attributes[1].length, 6)


# --- Unicode ---

func test_unicode_text():
	var result := _parser.parse_string("こんにちは世界", "ja")
	assert_eq(result.text, "こんにちは世界")


func test_unicode_with_markup():
	var result := _parser.parse_string("[b]こんにちは[/b]世界", "ja")
	assert_eq(result.text, "こんにちは世界")


# --- Adjacent self-closing tags ---

func test_adjacent_self_closing():
	var result := _parser.parse_string("a[pause/][pause/]b", "en")
	assert_eq(result.text, "ab")


func _parse(input: String, add_implicit_character: bool = true) -> Dictionary:
	return _parser.parse_string_and_include_markup_diagnostics(input, "en", add_implicit_character)


func _assert_parse_error(input: String) -> void:
	var result := _parse(input)
	assert_gt(result.diagnostics.size(), 0, "expected diagnostics for %s" % input)
	assert_eq(result.markup.text, input)
	assert_eq(result.markup.attributes.size(), 0)


func test_identifier_allows_underscore_and_pipe_after_first_character():
	var result := _parse("[a_b|c]x[/a_b|c]")
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(result.markup.text, "x")
	assert_eq(result.markup.attributes[0].name, "a_b|c")


func test_identifier_with_pipe_must_be_closed_by_full_name():
	_assert_parse_error("[a|b]x[/a]")


func test_identifier_cannot_start_with_underscore():
	_assert_parse_error("[_x/]y")


func test_identifier_rejects_characters_outside_bmp():
	_assert_parse_error("[\U020000]x[/\U020000]")


func test_identifier_rejects_non_decimal_digits():
	_assert_parse_error("[a²]x[/a²]")


func test_unquoted_value_stops_at_underscore():
	var result := _parse("[a=foo_bar]x[/a]")
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(result.markup.text, "bar]x")
	var attribute: YarnMarkupAttribute = result.markup.attributes[0]
	assert_eq(attribute.length, 5)
	assert_eq(attribute.try_get_string_property("a"), "foo")


func test_non_ascii_digit_value_is_error():
	_assert_parse_error("[a p=٣]x[/a]")


func test_invalid_name_is_error():
	_assert_parse_error("[wave!]x[/wave]")
	var result := _parse("[invalid.name]normal text[/invalid.name]")
	var found := false
	for diagnostic in result.diagnostics:
		if diagnostic.message.begins_with("Error parsing markup, invalid name:"):
			found = true
			assert_eq(diagnostic.column, 1)
	assert_true(found)


func test_single_unmatched_close_at_end_of_line_is_error():
	_assert_parse_error("[a][b]x[/a][/b]")


func test_multiple_unmatched_closes_at_end_of_line_are_rebalanced():
	var result := _parse("start[a]ab[b]bc[c]cb[/b][/c][/a]")
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(result.markup.text, "startabbccb")
	assert_eq(result.markup.attributes.size(), 3)


func test_close_marker_diagnostic_column():
	var result := _parse("normal line [/a]")
	assert_eq(result.diagnostics.size(), 1)
	assert_true(result.diagnostics[0].message.begins_with("Asked to close \"a\""))
	assert_eq(result.diagnostics[0].column, 14)


func test_property_value_types_and_strings():
	var cases := [
		["[a p=\"string\"]s[/a]", YarnMarkupValue.ValueType.STRING, "string"],
		["[a p=\"str\\\"ing\"]s[/a]", YarnMarkupValue.ValueType.STRING, "str\"ing"],
		["[a p=string]s[/a]", YarnMarkupValue.ValueType.STRING, "string"],
		["[a p=42]s[/a]", YarnMarkupValue.ValueType.INTEGER, "42"],
		["[a p=13.37]s[/a]", YarnMarkupValue.ValueType.FLOAT, "13.37"],
		["[a p=true]s[/a]", YarnMarkupValue.ValueType.BOOL, "True"],
		["[a p=false]s[/a]", YarnMarkupValue.ValueType.BOOL, "False"],
		["[a p={$someValue}]s[/a]", YarnMarkupValue.ValueType.STRING, "$someValue"],
		["[p=-1 /]", YarnMarkupValue.ValueType.INTEGER, "-1"],
		["[p=-1.1 /]", YarnMarkupValue.ValueType.FLOAT, "-1.1"],
		["[p=True]s[/p]", YarnMarkupValue.ValueType.BOOL, "True"],
		["[p=False]s[/p]", YarnMarkupValue.ValueType.BOOL, "False"],
		["[a p=TRUE]s[/a]", YarnMarkupValue.ValueType.STRING, "TRUE"],
		["[a p=1.0]s[/a]", YarnMarkupValue.ValueType.FLOAT, "1"],
		["[a p=-0.0]s[/a]", YarnMarkupValue.ValueType.FLOAT, "-0"],
		["[a p=0.00001]s[/a]", YarnMarkupValue.ValueType.FLOAT, "1E-05"],
		["[a p=-.5]s[/a]", YarnMarkupValue.ValueType.FLOAT, "-0.5"],
		["[a p=2147483647]s[/a]", YarnMarkupValue.ValueType.INTEGER, "2147483647"],
		["[a p=99999999999]s[/a]", YarnMarkupValue.ValueType.FLOAT, "1E+11"],
		["[a p=\"\\\"hi\\\"\"]s[/a]", YarnMarkupValue.ValueType.STRING, "hi"],
		["[a p=\"foo\\\"]s[/a]", YarnMarkupValue.ValueType.STRING, "foo"],
	]
	for test_case in cases:
		var result := _parse(test_case[0])
		assert_eq(result.diagnostics.size(), 0, test_case[0])
		assert_eq(result.markup.attributes.size(), 1, test_case[0])
		if result.markup.attributes.size() != 1:
			continue
		var value: YarnMarkupValue = result.markup.attributes[0].try_get_property("p")
		assert_eq(value.type, test_case[1], test_case[0])
		assert_eq(value.to_string_value(), test_case[2], test_case[0])


func test_interpolated_value_trims_all_braces():
	var result := _parse("[a p={{$x}}]s[/a]")
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(result.markup.text, "]s")
	assert_eq(result.markup.attributes[0].try_get_string_property("p"), "$x")


func test_self_closing_trims_unicode_whitespace():
	assert_eq(_parse("A [a/]　B").markup.text, "A B")
	assert_eq(_parse("A [a/] B").markup.text, "A B")
	assert_eq(_parse("A [a/]​B").markup.text, "A ​B")


func test_non_breaking_space_separates_tag_parts():
	var result := _parse("[a b=1]x[/a]")
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(result.markup.attributes[0].try_get_int_property("b"), 1)


func test_implicit_character_consumes_unicode_whitespace():
	var result := _parse("Mae: Wow")
	var character: YarnMarkupAttribute = result.markup.try_get_attribute_with_name("character")
	assert_not_null(character)
	assert_eq(character.length, 5)


func test_duplicate_property_names_are_error():
	_assert_parse_error("[a b=1 b=2]x[/a]")
	_assert_parse_error("[a trimwhitespace=false trimwhitespace=true/] x")


func test_closing_more_markers_than_open_is_error():
	_assert_parse_error("[/ /]x")
