# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

class_name SampleVoicePresenter
extends YarnDialoguePresenter
## voice over presenter for the sample.
## plays localised audio for each line.

## the audio player for voice over
@export var audio_player: AudioStreamPlayer

## whether to wait for audio to finish before allowing continue
@export var wait_for_audio: bool = true

func _ready() -> void:
	if audio_player == null:
		audio_player = AudioStreamPlayer.new()
		add_child(audio_player)


func on_dialogue_started() -> void:
	pass


func on_dialogue_completed() -> void:
	if audio_player != null and audio_player.playing:
		audio_player.stop()


func run_line(line: YarnLine) -> Variant:
	# try to get localised audio
	var audio: AudioStream = dialogue_runner.get_localised_audio(line.line_id)

	if OS.is_debug_build():
		print("VoicePresenter: run_line '%s' audio=%s" % [line.line_id, "found" if audio != null else "NOT FOUND"])

	if audio != null and audio_player != null:
		audio_player.stream = audio
		audio_player.play()

		# connect to cancellation to stop audio if user skips
		if _cancellation_token != null:
			var on_skip := func():
				if audio_player != null and audio_player.playing:
					audio_player.stop()
			_cancellation_token.next_content_requested.connect(on_skip, CONNECT_ONE_SHOT)

	# don't block - audio plays in background while text displays
	return null


func run_options_with_token(_options: Array[YarnOption], _token: YarnCancellationToken) -> int:
	# don't handle options
	return -1


## manually play audio for a line ID
func play_audio(line_id: String) -> void:
	var audio: AudioStream = dialogue_runner.get_localised_audio(line_id)
	if audio != null and audio_player != null:
		audio_player.stream = audio
		audio_player.play()


## stop any playing audio
func stop_audio() -> void:
	if audio_player != null and audio_player.playing:
		audio_player.stop()
