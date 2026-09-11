extends GutTest


func test_pause_that_times_out_disconnects_from_the_token():
	var processor := YarnPauseEventProcessor.new()
	processor._pauses[0] = 10.0
	var token := YarnCancellationToken.new()
	var pause := processor.on_character_will_appear(0, null, token)
	assert_false(pause.is_null())
	assert_eq(token.hurry_up_requested.get_connections().size(), 1)

	await wait_for_signal(pause, 2.0)

	assert_eq(token.hurry_up_requested.get_connections().size(), 0)
	assert_eq(processor._active_waits.size(), 0)


func test_hurry_up_ends_a_pause():
	var processor := YarnPauseEventProcessor.new()
	processor._pauses[0] = 10000.0
	var token := YarnCancellationToken.new()
	processor.on_character_will_appear(0, null, token)
	assert_eq(processor._active_waits.size(), 1)

	token.request_hurry_up()

	assert_eq(processor._active_waits.size(), 0)
	assert_eq(token.hurry_up_requested.get_connections().size(), 0)


func test_no_pause_after_hurry_up():
	var processor := YarnPauseEventProcessor.new()
	processor._pauses[0] = 10000.0
	var token := YarnCancellationToken.new()
	token.request_hurry_up()
	assert_true(processor.on_character_will_appear(0, null, token).is_null())
