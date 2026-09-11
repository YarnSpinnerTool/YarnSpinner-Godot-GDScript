extends GutTest


const LINE_TEXT := "Bea: You have [plural value={0} one=\"% apple\" other=\"% apples\"/] and [ordinal value={1} one=\"%st\" two=\"%nd\" few=\"%rd\" other=\"%th\"/] place."
const OPTION_TEXT := "[plural value={0} one=\"% pear\" other=\"% pears\"/]"


func _line_text() -> String:
	var line := YarnLine.new()
	line.raw_text = LINE_TEXT
	line.substitutions = ["3", "2"] as Array[String]
	line.locale_code = "en"
	return line.text


func _option_text() -> String:
	var option := YarnOption.new()
	option.raw_text = OPTION_TEXT
	option.substitutions = ["1"] as Array[String]
	option.locale_code = "en"
	return option.text


func _count_mismatches(expected_line: String, expected_option: String, expected_crc: int) -> int:
	var mismatches := 0
	for i in range(50):
		if _line_text() != expected_line:
			mismatches += 1
		if _option_text() != expected_option:
			mismatches += 1
		if YarnVariableStorage.crc32("Hello Yarn") != expected_crc:
			mismatches += 1
		if YarnCldrPluralRules.get_cardinal_case("ru", 2.0) != "few":
			mismatches += 1
		if YarnCldrPluralRules.get_ordinal_case("en", 2.0) != "two":
			mismatches += 1
	return mismatches


func test_lines_options_and_shared_tables_work_from_several_threads():
	var expected_line := _line_text()
	var expected_option := _option_text()
	var expected_crc := YarnVariableStorage.crc32("Hello Yarn")
	assert_eq(expected_line, "Bea: You have 3 apples and 2nd place.")
	assert_eq(expected_option, "1 pear")

	YarnCldrPluralRules._cardinal_dispatch_ready = false
	YarnCldrPluralRules._ordinal_dispatch_ready = false
	YarnVariableStorage._crc32_ready = false

	var threads: Array[Thread] = []
	for i in range(8):
		var thread := Thread.new()
		threads.append(thread)
		thread.start(_count_mismatches.bind(expected_line, expected_option, expected_crc))
	var mismatches := 0
	for thread in threads:
		mismatches += int(thread.wait_to_finish())

	assert_eq(mismatches, 0)
