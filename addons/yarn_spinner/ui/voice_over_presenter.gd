# ======================================================================== #
#                    Yarn Spinner for Godot (GDScript)                     #
# ======================================================================== #
#                                                                          #
# (C) Yarn Spinner Pty. Ltd.                                               #
#                                                                          #
# Yarn Spinner is a trademark of Secret Lab Pty. Ltd.,                     #
# used under license.                                                      #
#                                                                          #
# This code is subject to the terms of the license defined                 #
# in LICENSE.md.                                                           #
#                                                                          #
# For help, support, and more information, visit:                          #
#   https://yarnspinner.dev                                                #
#   https://docs.yarnspinner.dev                                           #
#                                                                          #
# ======================================================================== #

@icon("res://addons/yarn_spinner/icons/voice_over_presenter.svg")
class_name YarnVoiceOverPresenter
extends YarnDialoguePresenter
## presenter for playing voice over audio associated with dialogue lines.
## syncs audio playback with text display.

signal voice_started(line: YarnLine, audio: AudioStream)
signal voice_finished(line: YarnLine)

@export var audio_player: AudioStreamPlayer
@export var audio_player_2d: AudioStreamPlayer2D
@export var audio_player_3d: AudioStreamPlayer3D
@export var audio_base_path: String = "res://audio/dialogue/"
@export var audio_extension: String = ".ogg"
@export var wait_for_audio: bool = true
@export var interrupt_on_new_line: bool = true
@export var volume_db: float = 0.0
## seconds before starting playback
@export var wait_time_before_start: float = 0.0
## seconds after audio finishes before signaling completion
@export var wait_time_after_complete: float = 0.0
## seconds; 0 = instant stop
@export var fade_out_time_on_interrupt: float = 0.05
## When the voice over finishes, ask the runner to end the line.
@export var end_line_when_voice_complete: bool = true

var _is_playing: bool = false
var _current_line: YarnLine
## bumped whenever the current line changes or dialogue ends, so a superseded
## line's wait timers can tell they are stale after an await.
var _line_generation := 0


func _ready() -> void:
	if audio_player == null and audio_player_2d == null and audio_player_3d == null:
		audio_player = AudioStreamPlayer.new()
		audio_player.bus = "Master"
		add_child(audio_player)


func run_line(line: YarnLine, token: YarnCancellationToken = null) -> void:
	_line_generation += 1
	var generation := _line_generation
	_current_line = line
	_is_playing = false

	if interrupt_on_new_line:
		_stop_audio_immediate()

	var audio := _load_audio_for_line(line)
	if audio == null:
		push_error("voice over presenter: no audio found for line '%s'" % line.line_id)
		if end_line_when_voice_complete:
			# A missing clip in a voice-driven scene should skip the line, not
			# stall it. Deferred so every presenter has started this line
			# before the wind-down request fires.
			_request_line_end.call_deferred(line)
		return

	if wait_time_before_start > 0.0:
		await _wait_unless_next_content(wait_time_before_start, token, generation)
		if generation != _line_generation:
			return

	if not is_inside_tree():
		return

	if wait_for_audio:
		await _play_line_audio(line, audio, token, generation)
	else:
		_play_line_audio(line, audio, token, generation)


func on_dialogue_completed() -> void:
	_line_generation += 1
	_stop_audio_immediate()
	_is_playing = false


func _play_line_audio(line: YarnLine, audio: AudioStream, token: YarnCancellationToken, generation: int) -> void:
	var player := _play_audio(audio)
	if player == null:
		return
	_is_playing = true
	voice_started.emit(line, audio)

	var tree := get_tree()
	while not _is_player_stopped(player) and not _is_next_content_requested(token):
		await tree.process_frame
		if generation != _line_generation or not is_inside_tree():
			return

	if _is_next_content_requested(token) and not _is_player_stopped(player):
		var start_volume: float = player.get(&"volume_linear")
		if fade_out_time_on_interrupt > 0.0:
			var elapsed := 0.0
			var last_ticks := Time.get_ticks_usec()
			while elapsed < fade_out_time_on_interrupt:
				await tree.process_frame
				if generation != _line_generation or not is_inside_tree() or not is_instance_valid(player):
					return
				var now := Time.get_ticks_usec()
				if can_process():
					elapsed += (now - last_ticks) / 1000000.0
				last_ticks = now
				player.set(&"volume_linear", lerpf(start_volume, 0.0, clampf(elapsed / fade_out_time_on_interrupt, 0.0, 1.0)))
		player.call(&"stop")
		player.set(&"volume_linear", start_volume)
	else:
		player.call(&"stop")

	_is_playing = false
	voice_finished.emit(line)

	if not _is_next_content_requested(token) and wait_time_after_complete > 0.0:
		await _wait_unless_next_content(wait_time_after_complete, token, generation)
		if generation != _line_generation:
			return

	if end_line_when_voice_complete:
		# Route through the line's source so wrapper presenters (e.g. the
		# Interruption add-on) can intercept; falls back to the runner.
		_request_line_end(line)


func _wait_unless_next_content(seconds: float, token: YarnCancellationToken, generation: int) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var remaining := seconds
	while remaining > 0.0 and not _is_next_content_requested(token):
		await tree.process_frame
		if generation != _line_generation or not is_inside_tree():
			return
		if not can_process():
			continue
		remaining -= get_process_delta_time()


func _is_next_content_requested(token: YarnCancellationToken) -> bool:
	return token != null and token.is_next_content_requested


func _is_player_stopped(player: Node) -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return true
	if not player.can_process() or player.get(&"stream_paused"):
		return false
	return not player.get(&"playing")


func _load_audio_for_line(line: YarnLine) -> AudioStream:
	# Prefer the runner's audio lookup (set via set_audio_base_path;
	# localised by Godot's translation remaps on load) so set_locale()
	# swaps voice as well as text. It has its own cache.
	# A shadow line plays its source line's audio, so resolve the ID first.
	var source_line_id := line.line_id
	if dialogue_runner != null:
		var provider := dialogue_runner.get_line_provider()
		if provider != null:
			var shadow_source := provider.get_shadow_line_source(line.line_id)
			if not shadow_source.is_empty():
				source_line_id = shadow_source
		var localised: AudioStream = dialogue_runner.get_localised_audio(source_line_id)
		if localised != null:
			return localised

	var path := _get_audio_path(source_line_id)
	if ResourceLoader.exists(path):
		return load(path) as AudioStream

	return null


func _get_audio_path(line_id: String) -> String:
	# Strip the "line:" prefix first: audio files are conventionally named
	# after the bare id (tutorial-tom-01.wav for line:tutorial-tom-01),
	# matching the localisation resolver's lookup order.
	var filename := line_id.trim_prefix("line:").replace(":", "_").replace("/", "_")
	return audio_base_path.path_join(filename + audio_extension)


func _play_audio(audio: AudioStream) -> Node:
	if audio_player != null:
		audio_player.stream = audio
		audio_player.volume_db = volume_db
		audio_player.play()
		return audio_player
	elif audio_player_2d != null:
		audio_player_2d.stream = audio
		audio_player_2d.volume_db = volume_db
		audio_player_2d.play()
		return audio_player_2d
	elif audio_player_3d != null:
		audio_player_3d.stream = audio
		audio_player_3d.volume_db = volume_db
		audio_player_3d.play()
		return audio_player_3d
	return null


func _stop_audio_immediate() -> void:
	if audio_player != null:
		audio_player.stop()
		audio_player.volume_db = volume_db
	if audio_player_2d != null:
		audio_player_2d.stop()
		audio_player_2d.volume_db = volume_db
	if audio_player_3d != null:
		audio_player_3d.stop()
		audio_player_3d.volume_db = volume_db
