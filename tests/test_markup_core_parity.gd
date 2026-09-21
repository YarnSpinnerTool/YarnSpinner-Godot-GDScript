extends GutTest


var _parser: YarnLineParser


func before_each():
	_parser = YarnLineParser.new()


func _from_codepoints(codepoints: Array) -> String:
	var packed := PackedInt32Array()
	for code in codepoints:
		packed.append(code)
	return packed.to_byte_array().get_string_from_utf32()


func _cases() -> Array:
	var acute := _from_codepoints([0x301])
	var smiley := _from_codepoints([0x1F642])
	return [
		{
			"input": "this is line without markup",
			"text": "this is line without markup",
			"implicit_character": false,
			"attributes": [],
		},
		{
			"input": "[a]this is line with basic markup[/a]",
			"text": "this is line with basic markup",
			"implicit_character": false,
			"attributes": [["a", 0, 30]],
		},
		{
			"input": "[a]this is line with [b]nested basic[/b] markup[/a]",
			"text": "this is line with nested basic markup",
			"implicit_character": false,
			"attributes": [["a", 0, 37], ["b", 18, 12]],
		},
		{
			"input": "this is a[nomarkup] line with [b]nomarkup hiding[/b] markup[/nomarkup] elements",
			"text": "this is a line with [b]nomarkup hiding[/b] markup elements",
			"implicit_character": false,
			"attributes": [["nomarkup", 9, 40]],
		},
		{
			"input": "[a]This is [b]some [c]markup[/b] with[/c] closing tag issues inside a valid tag[/a]",
			"text": "This is some markup with closing tag issues inside a valid tag",
			"implicit_character": false,
			"attributes": [["a", 0, 62], ["b", 8, 11], ["c", 13, 11]],
		},
		{
			"input": "this is a line with non-replacement[a/]  markup",
			"text": "this is a line with non-replacement markup",
			"implicit_character": false,
			"attributes": [["a", 35, 0]],
		},
		{
			"input": "this is a line with \\[markup=false var = 12]two [markup2]markup[/] inside of it",
			"text": "this is a line with [markup=false var = 12]two markup inside of it",
			"implicit_character": false,
			"attributes": [["markup2", 47, 6]],
		},
		{
			"input": "Mae: hello there",
			"text": "Mae: hello there",
			"implicit_character": true,
			"attributes": [["character", 0, 5]],
		},
		{
			"input": "[a]xx[b]yy[/a]zz[/b]",
			"text": "xxyyzz",
			"implicit_character": false,
			"attributes": [["a", 0, 4], ["b", 2, 4]],
		},
		{
			"input": "start [markup=-1 /] end",
			"text": "start end",
			"implicit_character": false,
			"attributes": [["markup", 6, 0]],
		},
		{
			"input": _from_codepoints([0xE1]) + " [a]S[/a]",
			"text": _from_codepoints([0xE1]) + " S",
			"implicit_character": false,
			"attributes": [["a", 2, 1]],
		},
		{
			"input": "cafe" + acute + " [a]S[/a]",
			"text": _from_codepoints([0x63, 0x61, 0x66, 0xE9]) + " S",
			"implicit_character": false,
			"attributes": [["a", 5, 1]],
		},
	]


func test_astral_characters_are_one_position_each_unlike_utf16_runtimes():
	var smiley := _from_codepoints([0x1F642])
	var result := _parser.parse_string("emoji " + smiley + " [a]tail[/a]", "en", false)

	assert_eq(result.text, "emoji " + smiley + " tail")
	assert_eq(result.attributes.size(), 1)
	assert_eq(
		result.attributes[0].position,
		8,
		"Godot strings index by code point, so the emoji counts once here and "
		+ "twice in the C# and Unreal runtimes, which index by UTF-16 unit"
	)


func test_core_markup_parity(case_data = use_parameters(_cases())):
	var result := _parser.parse_string(
		case_data.input, "en", case_data.implicit_character
	)

	assert_eq(result.text, case_data.text, "text for `%s`" % case_data.input)
	assert_eq(
		result.attributes.size(),
		(case_data.attributes as Array).size(),
		"attribute count for `%s`" % case_data.input
	)

	for expected in case_data.attributes:
		var found: YarnMarkupAttribute = null
		for attribute in result.attributes:
			if attribute.name == expected[0]:
				found = attribute
				break
		if found == null:
			fail_test("`%s` is missing the [%s] attribute" % [case_data.input, expected[0]])
			continue
		assert_eq(
			found.position, expected[1], "[%s] position in `%s`" % [expected[0], case_data.input]
		)
		assert_eq(
			found.length, expected[2], "[%s] length in `%s`" % [expected[0], case_data.input]
		)
