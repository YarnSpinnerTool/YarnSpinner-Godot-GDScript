extends GutTest


func _text(codes: Array) -> String:
	var result := ""
	for code in codes:
		result += String.chr(code)
	return result


func _nfc(codes: Array) -> String:
	return YarnUnicodeNormalization.nfc(_text(codes))


func test_decomposed_e_acute_composes():
	assert_eq(_nfc([0x65, 0x301]), _text([0xE9]))
	assert_eq(YarnUnicodeNormalization.nfc("Cafe" + String.chr(0x301) + " au lait"), "Caf" + String.chr(0xE9) + " au lait")


func test_composed_e_acute_is_unchanged():
	assert_eq(_nfc([0xE9]), _text([0xE9]))
	assert_eq(YarnUnicodeNormalization.nfc("Caf" + String.chr(0xE9)), "Caf" + String.chr(0xE9))


func test_ascii_fast_path_returns_input():
	var line := "Alice: Hello there! [b]Welcome[/b] to the {0} tavern."
	assert_eq(YarnUnicodeNormalization.nfc(line), line)
	assert_eq(YarnUnicodeNormalization.nfc(""), "")


func test_text_without_combining_characters_is_unchanged():
	var line := _text([0x41F, 0x440, 0x438, 0x432, 0x435, 0x442, 0x20, 0x4F60, 0x597D, 0x20, 0x1F600])
	assert_eq(YarnUnicodeNormalization.nfc(line), line)


func test_hangul_jamo_compose_to_syllables():
	assert_eq(_nfc([0x1100, 0x1161]), _text([0xAC00]))
	assert_eq(_nfc([0x1100, 0x1161, 0x11A8]), _text([0xAC01]))
	assert_eq(_nfc([0xAC00, 0x11A8]), _text([0xAC01]))
	assert_eq(_nfc([0x1112, 0x1161, 0x11AB, 0x1100, 0x1173, 0x11AF]), _text([0xD55C, 0xAE00]))


func test_hangul_blocked_and_complete_syllables():
	assert_eq(_nfc([0xAC01, 0x11A8]), _text([0xAC01, 0x11A8]))
	assert_eq(_nfc([0x1100, 0x301, 0x1161]), _text([0x1100, 0x301, 0x1161]))


func test_composition_exclusions_stay_decomposed():
	assert_eq(_nfc([0x958]), _text([0x915, 0x93C]))
	assert_eq(_nfc([0x915, 0x93C]), _text([0x915, 0x93C]))
	assert_eq(_nfc([0x1D15E]), _text([0x1D157, 0x1D165]))


func test_singletons_are_replaced():
	assert_eq(_nfc([0x212B]), _text([0xC5]))
	assert_eq(_nfc([0x2126]), _text([0x3A9]))


func test_non_starter_decomposition():
	assert_eq(_nfc([0x344]), _text([0x308, 0x301]))


func test_blocked_composition():
	assert_eq(_nfc([0x61, 0x300, 0x301]), _text([0xE0, 0x301]))
	assert_eq(_nfc([0x61, 0x301, 0x301]), _text([0xE1, 0x301]))
	assert_eq(_nfc([0xB47, 0x301, 0xB3E]), _text([0xB47, 0x301, 0xB3E]))


func test_unblocked_composition_across_lower_class_mark():
	assert_eq(_nfc([0x61, 0x323, 0x302]), _text([0x1EAD]))
	assert_eq(_nfc([0xB47, 0xB3E]), _text([0xB4B]))


func test_combining_marks_are_reordered():
	assert_eq(_nfc([0x71, 0x301, 0x323]), _text([0x71, 0x323, 0x301]))
	assert_eq(_nfc([0x61, 0x302, 0x323]), _text([0x1EAD]))
	assert_eq(_nfc([0x61, 0x302, 0x323, 0x301]), _text([0x1EAD, 0x301]))


func test_leading_combining_marks_are_kept():
	assert_eq(_nfc([0x301, 0x65]), _text([0x301, 0x65]))
	assert_eq(_nfc([0x301, 0x323]), _text([0x323, 0x301]))


func test_first_use_from_several_threads_is_safe():
	YarnUnicodeNormalization._loaded = false
	var input := _text([0x43, 0x61, 0x66, 0x65, 0x301])
	var threads: Array[Thread] = []
	for i in range(8):
		var thread := Thread.new()
		threads.append(thread)
		thread.start(func() -> String: return YarnUnicodeNormalization.nfc(input))
	for thread in threads:
		assert_eq(thread.wait_to_finish(), _text([0x43, 0x61, 0x66, 0xE9]))


func test_normalisation_is_idempotent():
	var once := _nfc([0x5A, 0x6F, 0x65, 0x308, 0x20, 0x1100, 0x1161, 0x11A8, 0x20, 0x212B, 0x20, 0x61, 0x302, 0x323])
	assert_eq(once, _text([0x5A, 0x6F, 0xEB, 0x20, 0xAC01, 0x20, 0xC5, 0x20, 0x1EAD]))
	assert_eq(YarnUnicodeNormalization.nfc(once), once)
