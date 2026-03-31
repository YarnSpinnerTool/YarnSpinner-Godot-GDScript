extends GutTest


func test_request_hurry_up():
	var token := YarnCancellationToken.new()
	token.request_hurry_up()
	assert_true(token.is_hurry_up_requested)
	assert_true(token.is_cancelled)
	assert_eq(token.cancellation_mode, YarnCancellationToken.CancellationMode.HURRY_UP)


func test_request_next_content():
	var token := YarnCancellationToken.new()
	token.request_next_content()
	assert_true(token.is_next_content_requested)
	assert_true(token.is_cancelled)
	assert_eq(token.cancellation_mode, YarnCancellationToken.CancellationMode.NEXT_CONTENT)


func test_hurry_up_then_next_content():
	var token := YarnCancellationToken.new()
	token.request_hurry_up()
	token.request_next_content()
	assert_true(token.is_hurry_up_requested)
	assert_true(token.is_next_content_requested)
	assert_eq(token.cancellation_mode, YarnCancellationToken.CancellationMode.NEXT_CONTENT)


func test_escalate_to_next_content():
	var token := YarnCancellationToken.new()
	token.request_hurry_up()
	token.escalate_to_next_content()
	assert_true(token.is_next_content_requested)
	assert_eq(token.cancellation_mode, YarnCancellationToken.CancellationMode.NEXT_CONTENT)


func test_escalate_does_nothing_without_hurry_up():
	var token := YarnCancellationToken.new()
	token.escalate_to_next_content()
	assert_false(token.is_next_content_requested)
	assert_eq(token.cancellation_mode, YarnCancellationToken.CancellationMode.NONE)


func test_should_skip():
	var token := YarnCancellationToken.new()
	assert_false(token.should_skip())
	token.request_next_content()
	assert_true(token.should_skip())


func test_should_hurry():
	var token := YarnCancellationToken.new()
	assert_false(token.should_hurry())
	token.request_hurry_up()
	assert_true(token.should_hurry())
	token.request_next_content()
	assert_false(token.should_hurry(), "hurry should be false once escalated to next_content")
	assert_true(token.should_skip())


func test_hurry_up_signal_emitted():
	var token := YarnCancellationToken.new()
	var received := []
	token.hurry_up_requested.connect(func(): received.append(true))
	token.request_hurry_up()
	assert_eq(received.size(), 1)


func test_next_content_signal_emitted():
	var token := YarnCancellationToken.new()
	var received := []
	token.next_content_requested.connect(func(): received.append(true))
	token.request_next_content()
	assert_eq(received.size(), 1)


func test_cancellation_requested_signal():
	var token := YarnCancellationToken.new()
	var modes := []
	token.cancellation_requested.connect(func(mode): modes.append(mode))
	token.request_hurry_up()
	token.request_next_content()
	assert_eq(modes.size(), 2)
	assert_eq(modes[0], YarnCancellationToken.CancellationMode.HURRY_UP)
	assert_eq(modes[1], YarnCancellationToken.CancellationMode.NEXT_CONTENT)


func test_idempotent_hurry_up():
	var token := YarnCancellationToken.new()
	var counter := [0]
	token.hurry_up_requested.connect(func(): counter[0] += 1)
	token.request_hurry_up()
	token.request_hurry_up()
	assert_eq(counter[0], 1, "Signal should only fire once")


func test_idempotent_next_content():
	var token := YarnCancellationToken.new()
	var counter := [0]
	token.next_content_requested.connect(func(): counter[0] += 1)
	token.request_next_content()
	token.request_next_content()
	assert_eq(counter[0], 1, "Signal should only fire once")


func test_wait_for_cancellation_already_cancelled():
	var token := YarnCancellationToken.new()
	token.request_hurry_up()
	# Should return immediately since already cancelled
	var mode := token.cancellation_mode
	assert_eq(mode, YarnCancellationToken.CancellationMode.HURRY_UP)
