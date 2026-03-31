extends GutTest


var _parser: YarnMarkupParser


func before_each():
	_parser = YarnMarkupParser.new()


# --- Basic parsing ---

func test_plain_text():
	var result := _parser.parse("Hello, world!")
	assert_eq(result.text, "Hello, world!")
	assert_eq(result.character_name, "")


func test_empty_string():
	var result := _parser.parse("")
	assert_eq(result.text, "")


# --- Character name extraction ---

func test_implicit_character_name():
	var result := _parser.parse("Alice: Hello!")
	assert_eq(result.character_name, "Alice")
	assert_false(result.text.begins_with("Alice:"))


func test_explicit_character_attribute():
	var result := _parser.parse("[character name=\"Bob\"]Bob: [/character]Hi there")
	assert_eq(result.character_name, "Bob")


func test_no_character_name():
	var result := _parser.parse("Just a line with no speaker.")
	assert_eq(result.character_name, "")


# --- Markup processing ---

func test_nested_markup():
	var result := _parser.parse("[b][i]bold italic[/i][/b]")
	assert_true(result.text.contains("bold italic"))


func test_self_closing_tag():
	var result := _parser.parse("before[pause/]after")
	assert_false(result.text.contains("[pause/]"))


func test_escaped_bracket():
	var result := _parser.parse("\\[not a tag\\]")
	assert_true(result.text.contains("[not a tag]"))


# --- parse_to_result ---

func test_parse_to_result_basic():
	var result := _parser.parse_to_result("Hello [b]world[/b]!")
	assert_not_null(result)
	assert_true(result.text.contains("world"))


func test_parse_to_result_character():
	var result := _parser.parse_to_result("Tom: Hey there")
	var char_attr := result.try_get_attribute_with_name("character")
	assert_not_null(char_attr, "character attribute should be detected")
	assert_true(result.text.contains("Hey there"))


func test_parse_to_result_attributes():
	var result := _parser.parse_to_result("[b]bold[/b] text")
	assert_gt(result.attributes.size(), 0)
	assert_eq(result.attributes[0].name, "b")
	assert_eq(result.attributes[0].length, 4)


# --- YarnMarkupParseResult operations ---

func test_text_for_attribute():
	var result := _parser.parse_to_result("[b]hello[/b] world")
	assert_gt(result.attributes.size(), 0, "Should have attributes to test")
	var attr := result.attributes[0]
	assert_gt(attr.length, 0, "Attribute should have non-zero length")
	var attr_text := result.text_for_attribute(attr)
	assert_eq(attr_text, "hello")


func test_delete_range():
	var result := _parser.parse_to_result("[b]hello[/b] world")
	assert_gt(result.attributes.size(), 0, "Should have attributes to test")
	var attr := result.attributes[0]
	assert_gt(attr.length, 0, "Attribute should have non-zero length")
	var new_result := result.delete_range(attr)
	assert_true(new_result.text.length() < result.text.length())
	assert_true(new_result.text.contains("world"))
