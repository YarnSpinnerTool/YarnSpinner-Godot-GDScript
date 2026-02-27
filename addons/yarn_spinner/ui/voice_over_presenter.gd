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
@export var fade_out_time_on_interrupt: float = 0.0
@export var end_line_when_voice_complete: bool = false

var _is_playing: bool = false
var _fade_tween: Tween
var _current_line: YarnLine
signal _voice_complete
## line_id -> AudioStream
var _audio_cache: Dictionary[String, AudioStream] = {}
## 0 = unlimited
@export var max_cache_size: int = 50
var _cache_access_order: Array[String] = []


func _ready() -> void:
	if audio_player == null and audio_player_2d == null and audio_player_3d == null:
		audio_player = AudioStreamPlayer.new()
		audio_player.bus = "Master"
		add_child(audio_player)


func run_line(line: YarnLine) -> Variant:
	_current_line = line
	_is_playing = false

	if interrupt_on_new_line:
		_stop_audio_immediate()

	var audio := _load_audio_for_line(line)
	if audio == null:
		return null

	_is_playing = true

	if wait_time_before_start > 0.0 and is_inside_tree():
		await get_tree().create_timer(wait_time_before_start).timeout
		if not _is_playing:
			return null

	_play_audio(audio)
	voice_started.emit(line, audio)

	if wait_for_audio:
		return _voice_complete
	else:
		return null


func on_dialogue_completed() -> void:
	_stop_audio_immediate()
	_is_playing = false


func request_hurry_up() -> void:
	pass


func request_next() -> void:
	if _is_playing:
		_is_playing = false
		_stop_audio_with_fade()
		_voice_complete.emit()
		voice_finished.emit(_current_line)


func prepare_for_lines(line_ids: PackedStringArray) -> void:
	for line_id in line_ids:
		if not _audio_cache.has(line_id):
			var path := _get_audio_path(line_id)
			if ResourceLoader.exists(path):
				_add_to_cache(line_id, load(path))


func _load_audio_for_line(line: YarnLine) -> AudioStream:
	if _audio_cache.has(line.line_id):
		_update_cache_access(line.line_id)
		return _audio_cache[line.line_id]

	var path := _get_audio_path(line.line_id)
	if ResourceLoader.exists(path):
		var audio := load(path) as AudioStream
		_add_to_cache(line.line_id, audio)
		return audio

	return null


func _add_to_cache(line_id: String, audio: AudioStream) -> void:
	if max_cache_size > 0:
		while _audio_cache.size() >= max_cache_size and not _cache_access_order.is_empty():
			var oldest := _cache_access_order.pop_front()
			_audio_cache.erase(oldest)

	_audio_cache[line_id] = audio
	_update_cache_access(line_id)


func _update_cache_access(line_id: String) -> void:
	var idx := _cache_access_order.find(line_id)
	if idx >= 0:
		_cache_access_order.remove_at(idx)
	_cache_access_order.append(line_id)


func _get_audio_path(line_id: String) -> String:
	var filename := line_id.replace(":", "_").replace("/", "_")
	return audio_base_path.path_join(filename + audio_extension)


func _play_audio(audio: AudioStream) -> void:
	if audio_player != null:
		audio_player.stream = audio
		audio_player.volume_db = volume_db
		if not audio_player.finished.is_connected(_on_audio_finished):
			audio_player.finished.connect(_on_audio_finished)
		audio_player.play()
	elif audio_player_2d != null:
		audio_player_2d.stream = audio
		audio_player_2d.volume_db = volume_db
		if not audio_player_2d.finished.is_connected(_on_audio_finished):
			audio_player_2d.finished.connect(_on_audio_finished)
		audio_player_2d.play()
	elif audio_player_3d != null:
		audio_player_3d.stream = audio
		audio_player_3d.volume_db = volume_db
		if not audio_player_3d.finished.is_connected(_on_audio_finished):
			audio_player_3d.finished.connect(_on_audio_finished)
		audio_player_3d.play()


func _stop_audio_immediate() -> void:
	_kill_fade_tween()
	if audio_player != null and audio_player.playing:
		audio_player.stop()
		audio_player.volume_db = volume_db
	if audio_player_2d != null and audio_player_2d.playing:
		audio_player_2d.stop()
		audio_player_2d.volume_db = volume_db
	if audio_player_3d != null and audio_player_3d.playing:
		audio_player_3d.stop()
		audio_player_3d.volume_db = volume_db


func _stop_audio_with_fade() -> void:
	if fade_out_time_on_interrupt <= 0.0:
		_stop_audio_immediate()
		return

	_kill_fade_tween()

	var active_player: Node = _get_active_player()
	if active_player == null:
		return

	_fade_tween = create_tween()
	_fade_tween.tween_property(active_player, "volume_db", -80.0, fade_out_time_on_interrupt)
	_fade_tween.finished.connect(func():
		_stop_audio_immediate()
	, CONNECT_ONE_SHOT)


func _get_active_player() -> Node:
	if audio_player != null and audio_player.playing:
		return audio_player
	if audio_player_2d != null and audio_player_2d.playing:
		return audio_player_2d
	if audio_player_3d != null and audio_player_3d.playing:
		return audio_player_3d
	return null


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
		_fade_tween = null


func _on_audio_finished() -> void:
	if not _is_playing:
		return

	_is_playing = false

	if wait_time_after_complete > 0.0 and is_inside_tree():
		await get_tree().create_timer(wait_time_after_complete).timeout

	voice_finished.emit(_current_line)
	_voice_complete.emit()

	if end_line_when_voice_complete and dialogue_runner != null:
		dialogue_runner.signal_content_complete()


func clear_cache() -> void:
	_audio_cache.clear()
	_cache_access_order.clear()


func set_audio_for_line(line_id: String, audio: AudioStream) -> void:
	_audio_cache[line_id] = audio


func _exit_tree() -> void:
	if audio_player != null and audio_player.finished.is_connected(_on_audio_finished):
		audio_player.finished.disconnect(_on_audio_finished)
	if audio_player_2d != null and audio_player_2d.finished.is_connected(_on_audio_finished):
		audio_player_2d.finished.disconnect(_on_audio_finished)
	if audio_player_3d != null and audio_player_3d.finished.is_connected(_on_audio_finished):
		audio_player_3d.finished.disconnect(_on_audio_finished)
