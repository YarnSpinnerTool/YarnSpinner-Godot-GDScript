extends GutTest


func _make_line(raw: String, subs: Array[String] = []) -> YarnLine:
	var line := YarnLine.new()
	line.raw_text = raw
	line.substitutions = subs
	return line


func test_plain_text():
	var line := _make_line("Hello, world!")
	assert_eq(line.text, "Hello, world!")
	assert_eq(line.character_name, "")


func test_substitution_single():
	var line := _make_line("Hello, {0}!", ["Alice"])
	assert_eq(line.text, "Hello, Alice!")


func test_substitution_multiple():
	var line := _make_line("{0} gave {1} gold to {2}.", ["Alice", "50", "Bob"])
	assert_eq(line.text, "Alice gave 50 gold to Bob.")


func test_substitution_repeated_placeholder():
	var line := _make_line("{0} and {0} again", ["hey"])
	assert_eq(line.text, "hey and hey again")


func test_no_substitutions_leaves_placeholders():
	var line := _make_line("Hello {0}!")
	assert_eq(line.text, "Hello {0}!")


func test_character_name_colon_syntax():
	var line := _make_line("Alice: Hello there!")
	assert_eq(line.character_name, "Alice")
	assert_eq(line.text, "Hello there!")


func test_character_name_explicit_markup():
	var line := _make_line("[character name=\"Bob\"]Bob: [/character]Hey!")
	assert_eq(line.character_name, "Bob")
	assert_true(line.text.contains("Hey!"))


func test_text_without_character_name():
	var line := _make_line("Bob: How are you?")
	assert_eq(line.text_without_character_name, "How are you?")


func test_lazy_computation_only_once():
	var line := _make_line("Alice: Hello!")
	var _first := line.text
	line.raw_text = "Bob: Different!"
	assert_eq(line.text, "Hello!")
	assert_eq(line.character_name, "Alice")


func test_invalidate_recomputes():
	var line := _make_line("Alice: Hello!")
	var _first := line.text
	line.raw_text = "Bob: Different!"
	line.invalidate()
	assert_eq(line.text, "Different!")
	assert_eq(line.character_name, "Bob")


func test_text_setter_bypasses_lazy():
	var line := _make_line("Alice: Hello!")
	line.text = "Overridden"
	assert_eq(line.text, "Overridden")


func test_markup_attributes_populated():
	var line := _make_line("[b]bold text[/b] normal")
	var _text := line.text
	assert_gt(line.markup_attributes.size(), 0, "Should have at least one markup attribute")
	assert_eq(line.markup_attributes[0].name, "b")


func test_escaped_colon_not_character():
	var line := _make_line("Time\\: 3pm")
	assert_eq(line.character_name, "")


func test_try_get_attribute_returns_null_for_missing():
	var line := _make_line("plain text")
	assert_null(line.try_get_attribute("nonexistent"))


func test_text_for_attribute_empty_length():
	var line := _make_line("hello")
	var attr := YarnMarkupAttribute.new(0, 0, 0, "test", [])
	assert_eq(line.text_for_attribute(attr), "")


func test_text_for_attribute_out_of_bounds():
	var line := _make_line("hi")
	var attr := YarnMarkupAttribute.new(0, 0, 99, "test", [])
	assert_eq(line.text_for_attribute(attr), "")


func test_get_bbcode_text():
	var line := _make_line("Alice: [b]Hello![/b]")
	var bbcode := line.get_bbcode_text()
	assert_true(bbcode is String)
	assert_false(bbcode.is_empty())
