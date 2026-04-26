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
	assert_eq(result.text, "[b][i]bold italic[/i][/b]")


func test_self_closing_tag():
	var result := _parser.parse("before[pause/]after")
	assert_eq(result.text, "beforeafter")


func test_escaped_bracket():
	var result := _parser.parse("\\[not a tag\\]")
	assert_eq(result.text, "[not a tag]")


# --- Inline style shortcuts (regression: previously dropped silently) ---

func test_bold_shortcut():
	var result := _parser.parse("Hello [b]bold[/b] world")
	assert_eq(result.text, "Hello [b]bold[/b] world")


func test_italic_shortcut():
	var result := _parser.parse("Hello [i]italic[/i] world")
	assert_eq(result.text, "Hello [i]italic[/i] world")


func test_underline_shortcut():
	var result := _parser.parse("Hello [u]under[/u] world")
	assert_eq(result.text, "Hello [u]under[/u] world")


func test_strikethrough_shortcut():
	var result := _parser.parse("Hello [s]strike[/s] world")
	assert_eq(result.text, "Hello [s]strike[/s] world")


func test_code_shortcut():
	var result := _parser.parse("call [code]foo()[/code] please")
	assert_eq(result.text, "call [code]foo()[/code] please")


func test_link_with_url():
	# Uses a protocol-less URL because the line parser currently treats any
	# leading "X:" as a character prefix even inside markup attribute values
	# (separate bug — tracked but not fixed here). The welcome sample yarn
	# uses the same protocol-less form.
	var result := _parser.parse("see [link=\"yarnspinner.dev\"]docs[/link]")
	assert_eq(result.text, "see [url=yarnspinner.dev]docs[/url]")


func test_link_with_extra_properties():
	# Extra attribute properties (e.g. external=true) shouldn't break emission.
	var result := _parser.parse("[link=\"a\" external=true]x[/link]")
	assert_eq(result.text, "[url=a]x[/url]")


func test_link_without_url_stripped():
	# An empty link value emits no BBCode rather than an unbalanced [/url].
	var result := _parser.parse("[link]bare[/link]")
	assert_eq(result.text, "bare")


func test_style_long_form():
	# Long-form [style=bold] still works alongside the shortcut.
	var result := _parser.parse("[style=bold]thick[/style]")
	assert_eq(result.text, "[b]thick[/b]")


func test_color_palette():
	# Named palette colours map to hex.
	var result := _parser.parse("[color=red]hot[/color]")
	assert_eq(result.text, "[color=#ff0000]hot[/color]")


func test_character_prefix_with_markup():
	# Welcome sample regression: implicit "Name: " prefix is stripped and the
	# remaining markup is emitted as BBCode.
	var result := _parser.parse("Capsley: Hello [b]world[/b]")
	assert_eq(result.character_name, "Capsley")
	assert_eq(result.text, "Hello [b]world[/b]")


# --- parse_to_result ---

func test_parse_to_result_basic():
	# parse_to_result returns the structured result with markup stripped from
	# .text and tracked as attributes — no BBCode emission at this layer.
	var result := _parser.parse_to_result("Hello [b]world[/b]!")
	assert_not_null(result)
	assert_eq(result.text, "Hello world!")


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
