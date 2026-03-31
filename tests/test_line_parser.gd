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
