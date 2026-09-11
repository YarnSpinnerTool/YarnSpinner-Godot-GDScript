extends GutTest


func _label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.size = Vector2(400, 100)
	add_child_autofree(label)
	return label


func test_letter_typewriter_reveals_everything():
	var label := _label()
	var finished := YarnEffects.typewriter(label, "Hello there.", 200.0)
	assert_eq(label.visible_ratio, 0.0)
	assert_true(await wait_for_signal(finished, 2.0))
	assert_eq(label.visible_ratio, 1.0)


func test_hurry_up_finishes_the_letter_typewriter():
	var label := _label()
	var token := YarnCancellationToken.new()
	var finished := YarnEffects.typewriter(label, "Hello there, traveller.", 1.0, token)
	var done := [false]
	finished.connect(func() -> void: done[0] = true)

	token.request_hurry_up()

	assert_true(done[0])
	assert_eq(label.visible_ratio, 1.0)
	assert_eq(token.hurry_up_requested.get_connections().size(), 0)


func test_instant_typewriter_can_still_be_awaited():
	var label := _label()
	var finished := YarnEffects.typewriter(label, "Hello", 0.0)
	assert_false(finished.is_null())
	await finished
	assert_eq(label.visible_ratio, 1.0)


func test_word_typewriter_reveals_whole_words():
	var label := _label()
	var finished := YarnEffects.typewriter_words(label, "one two three", 5.0)
	assert_eq(label.visible_characters, 3)
	await wait_seconds(0.3)
	assert_eq(label.visible_characters, 7)
	assert_true(await wait_for_signal(finished, 2.0))
	assert_eq(label.visible_characters, -1)


func test_hurry_up_finishes_the_word_typewriter():
	var label := _label()
	var token := YarnCancellationToken.new()
	var finished := YarnEffects.typewriter_words(label, "one two three four", 0.5, token)
	var done := [false]
	finished.connect(func() -> void: done[0] = true)

	token.request_hurry_up()

	assert_true(done[0])
	assert_eq(label.visible_characters, -1)


func test_line_typewriter_pauses_and_can_be_hurried():
	var label := _label()
	var line := YarnLine.new()
	line.raw_text = "Hi [pause=5000/]there"
	line.locale_code = "en"
	var token := YarnCancellationToken.new()
	var finished := YarnEffects.typewriter_with_line(label, line, 200.0, YarnPauseEventProcessor.new(), token)
	var done := [false]
	finished.connect(func(_value: Variant = null) -> void: done[0] = true)

	for i in range(20):
		await get_tree().process_frame
	assert_false(done[0])
	assert_ne(label.visible_characters, -1)

	token.request_hurry_up()
	if not done[0]:
		assert_true(await wait_for_signal(finished, 2.0))
	assert_eq(label.visible_characters, -1)
	assert_eq(label.get_parsed_text(), "Hi there")


func test_line_typewriter_result_can_be_awaited_when_instant():
	var label := _label()
	var line := YarnLine.new()
	line.raw_text = "Hello"
	line.locale_code = "en"
	var finished := YarnEffects.typewriter_with_line(label, line, 0.0)
	assert_false(finished.is_null())
	assert_true(await wait_for_signal(finished, 1.0))
	assert_eq(label.visible_characters, -1)


func test_short_shake_does_not_divide_by_zero():
	var target := Control.new()
	add_child_autofree(target)
	target.position = Vector2(10, 20)
	var finished := YarnEffects.shake(target, 5.0, 0.01, 30.0)
	assert_true(await wait_for_signal(finished, 1.0))
	assert_eq(target.position, Vector2(10, 20))
