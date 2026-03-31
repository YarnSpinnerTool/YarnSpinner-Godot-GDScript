extends GutTest


func test_simple_command():
	var parts := YarnCommandParser.parse("wait 2")
	assert_eq(parts.size(), 2)
	assert_eq(parts[0], "wait")
	assert_eq(parts[1], "2")


func test_quoted_string_argument():
	var parts := YarnCommandParser.parse('say "hello world" character')
	assert_eq(parts.size(), 3)
	assert_eq(parts[0], "say")
	assert_eq(parts[1], "hello world")
	assert_eq(parts[2], "character")


func test_single_quoted_argument():
	var parts := YarnCommandParser.parse("say 'hello world'")
	assert_eq(parts.size(), 2)
	assert_eq(parts[1], "hello world")


func test_escaped_characters():
	var parts := YarnCommandParser.parse('say "hello\\"world"')
	assert_eq(parts[1], 'hello"world')


func test_empty_string():
	var parts := YarnCommandParser.parse("")
	assert_eq(parts.size(), 0)


func test_command_name_only():
	var parts := YarnCommandParser.parse("stop")
	assert_eq(parts.size(), 1)
	assert_eq(parts[0], "stop")


func test_multiple_spaces_between_args():
	var parts := YarnCommandParser.parse("cmd   arg1   arg2")
	assert_eq(parts.size(), 3)
	assert_eq(parts[0], "cmd")
	assert_eq(parts[1], "arg1")
	assert_eq(parts[2], "arg2")


func test_parse_to_dict():
	var result := YarnCommandParser.parse_to_dict("fade_in 1.5 true")
	assert_eq(result.name, "fade_in")
	assert_eq(result.args.size(), 2)
	assert_eq(result.args[0], "1.5")
	assert_eq(result.args[1], "true")


func test_parse_to_dict_empty():
	var result := YarnCommandParser.parse_to_dict("")
	assert_eq(result.name, "")
	assert_eq(result.args.size(), 0)


func test_unterminated_quote():
	var parts := YarnCommandParser.parse('say "hello world')
	assert_eq(parts.size(), 2)
	assert_eq(parts[0], "say")
	assert_eq(parts[1], "hello world")


func test_leading_trailing_whitespace():
	var parts := YarnCommandParser.parse("  wait 2  ")
	assert_eq(parts.size(), 2)
	assert_eq(parts[0], "wait")
	assert_eq(parts[1], "2")
