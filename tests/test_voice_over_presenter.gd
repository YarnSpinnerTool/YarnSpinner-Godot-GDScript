extends GutTest

const ASSET_DIR := "user://yarn_voice_over_test"


class FakeSource:
	extends RefCounted
	var calls := 0

	func request_line_cancellation(_line: YarnLine) -> void:
		calls += 1


var _presenter: YarnVoiceOverPresenter
var _source: FakeSource


func before_all():
	DirAccess.make_dir_recursive_absolute(ASSET_DIR)
	_save_wav("short.tres", 0.2)
	_save_wav("long.tres", 3.0)


func after_all():
	for file in DirAccess.get_files_at(ASSET_DIR):
		DirAccess.remove_absolute(ASSET_DIR.path_join(file))
	DirAccess.remove_absolute(ASSET_DIR)


func before_each():
	_presenter = YarnVoiceOverPresenter.new()
	_presenter.audio_base_path = ASSET_DIR
	_presenter.audio_extension = ".tres"
	add_child_autofree(_presenter)
	_source = FakeSource.new()


func _save_wav(file_name: String, seconds: float) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 11025
	var data := PackedByteArray()
	data.resize(int(11025 * seconds))
	data.fill(128)
	wav.data = data
	ResourceSaver.save(wav, ASSET_DIR.path_join(file_name))


func _make_line(line_id: String) -> YarnLine:
	var line := YarnLine.new()
	line.line_id = line_id
	line.source = _source
	return line


func _start(line: YarnLine, token: YarnCancellationToken) -> Array:
	var state := [false]
	var run := func():
		await _presenter.run_line(line, token)
		state[0] = true
	run.call()
	return state


func _seconds_since(start_usec: int) -> float:
	return (Time.get_ticks_usec() - start_usec) / 1000000.0


func test_fade_default_matches_unity():
	assert_almost_eq(_presenter.fade_out_time_on_interrupt, 0.05, 0.0001)


func test_natural_completion_requests_line_end():
	var token := YarnCancellationToken.new()
	var started := Time.get_ticks_usec()
	var state := _start(_make_line("line:short"), token)
	assert_false(state[0])
	await wait_until(func(): return state[0], 3.0)
	assert_true(state[0])
	assert_gt(_seconds_since(started), 0.15)
	assert_eq(_source.calls, 1)


func test_interruption_fades_linearly_and_restores_volume():
	_presenter.fade_out_time_on_interrupt = 0.4
	var token := YarnCancellationToken.new()
	var state := _start(_make_line("line:long"), token)
	await wait_seconds(0.2)
	assert_true(_presenter.audio_player.playing)
	token.request_next_content()
	var started := Time.get_ticks_usec()
	await wait_seconds(0.2)
	var mid_volume := _presenter.audio_player.volume_linear
	assert_between(mid_volume, 0.25, 0.75)
	assert_false(state[0])
	await wait_until(func(): return state[0], 2.0)
	var elapsed := _seconds_since(started)
	assert_between(elapsed, 0.35, 0.8)
	assert_false(_presenter.audio_player.playing)
	assert_almost_eq(_presenter.audio_player.volume_linear, 1.0, 0.001)
	assert_eq(_source.calls, 1)


func test_wait_before_start_is_interruptible():
	_presenter.wait_time_before_start = 5.0
	var token := YarnCancellationToken.new()
	var state := _start(_make_line("line:long"), token)
	await wait_seconds(0.1)
	assert_false(_presenter.audio_player.playing)
	token.request_next_content()
	var started := Time.get_ticks_usec()
	await wait_until(func(): return state[0], 2.0)
	assert_true(state[0])
	assert_lt(_seconds_since(started), 0.5)
	assert_eq(_source.calls, 1)


func test_wait_after_complete_is_interruptible():
	_presenter.wait_time_after_complete = 5.0
	var token := YarnCancellationToken.new()
	var state := _start(_make_line("line:short"), token)
	await wait_seconds(0.5)
	assert_false(_presenter.audio_player.playing)
	assert_false(state[0])
	assert_eq(_source.calls, 0)
	token.request_next_content()
	var started := Time.get_ticks_usec()
	await wait_until(func(): return state[0], 2.0)
	assert_true(state[0])
	assert_lt(_seconds_since(started), 0.3)
	assert_eq(_source.calls, 1)


func test_wait_after_complete_runs_when_not_interrupted():
	_presenter.wait_time_after_complete = 0.4
	var token := YarnCancellationToken.new()
	var started := Time.get_ticks_usec()
	var state := _start(_make_line("line:short"), token)
	await wait_until(func(): return state[0], 3.0)
	assert_gt(_seconds_since(started), 0.55)
	assert_eq(_source.calls, 1)


func test_wait_after_complete_skipped_when_interrupted():
	_presenter.wait_time_after_complete = 5.0
	var token := YarnCancellationToken.new()
	var state := _start(_make_line("line:long"), token)
	await wait_seconds(0.2)
	token.request_next_content()
	var started := Time.get_ticks_usec()
	await wait_until(func(): return state[0], 2.0)
	assert_true(state[0])
	assert_lt(_seconds_since(started), 0.5)
	assert_eq(_source.calls, 1)


func test_no_line_end_when_disabled():
	_presenter.end_line_when_voice_complete = false
	var state := _start(_make_line("line:short"), YarnCancellationToken.new())
	await wait_until(func(): return state[0], 3.0)
	assert_true(state[0])
	assert_eq(_source.calls, 0)


func test_dialogue_completed_stops_audio():
	var token := YarnCancellationToken.new()
	var state := _start(_make_line("line:long"), token)
	await wait_seconds(0.1)
	assert_true(_presenter.audio_player.playing)
	_presenter.on_dialogue_completed()
	assert_false(_presenter.audio_player.playing)
	await wait_until(func(): return state[0], 1.0)
	assert_true(state[0])
	assert_eq(_source.calls, 0)
