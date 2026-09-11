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

class_name YarnEffects
extends RefCounted
## reusable animation effects for dialogue presentation.

const DEFAULT_FADE_DURATION := 0.25


static func fade_alpha(
	target: CanvasItem,
	from_alpha: float,
	to_alpha: float,
	duration: float = DEFAULT_FADE_DURATION,
	trans_type: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease_type: Tween.EaseType = Tween.EASE_IN_OUT
) -> Signal:
	if target == null:
		push_error("YarnEffects.fade_alpha: target is null")
		return Signal()

	var current_modulate := target.modulate
	current_modulate.a = from_alpha
	target.modulate = current_modulate

	var tween := target.create_tween()
	tween.set_trans(trans_type)
	tween.set_ease(ease_type)
	tween.tween_property(target, "modulate:a", to_alpha, duration)

	return tween.finished


static func fade_alpha_async(
	target: CanvasItem,
	from_alpha: float,
	to_alpha: float,
	duration: float,
	token: YarnCancellationToken = null
) -> void:
	if target == null:
		push_error("YarnEffects.fade_alpha_async: target is null")
		return

	if duration <= 0.0 or not target.is_inside_tree():
		target.modulate.a = to_alpha
		return

	target.modulate.a = from_alpha
	var elapsed := 0.0
	while (token == null or not token.is_hurry_up_requested) and elapsed < duration:
		await target.get_tree().process_frame
		if not is_instance_valid(target) or not target.is_inside_tree():
			return
		if not target.can_process():
			continue
		elapsed += target.get_process_delta_time()
		target.modulate.a = lerpf(from_alpha, to_alpha, clampf(elapsed / duration, 0.0, 1.0))

	target.modulate.a = to_alpha


static func fade_in(
	target: CanvasItem,
	duration: float = DEFAULT_FADE_DURATION,
	trans_type: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease_type: Tween.EaseType = Tween.EASE_IN_OUT
) -> Signal:
	return fade_alpha(target, 0.0, 1.0, duration, trans_type, ease_type)


static func fade_out(
	target: CanvasItem,
	duration: float = DEFAULT_FADE_DURATION,
	trans_type: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease_type: Tween.EaseType = Tween.EASE_IN_OUT
) -> Signal:
	return fade_alpha(target, 1.0, 0.0, duration, trans_type, ease_type)


static func fade_container(
	container: Control,
	from_alpha: float,
	to_alpha: float,
	duration: float = DEFAULT_FADE_DURATION
) -> Signal:
	return fade_alpha(container, from_alpha, to_alpha, duration)


## typewriter effect - reveals text character by character.
## for pause markup support, use typewriter_with_line() with a YarnPauseEventProcessor.
static func typewriter(
	label: RichTextLabel,
	text: String,
	characters_per_second: float,
	token: YarnCancellationToken = null
) -> Signal:
	if label == null:
		push_error("YarnEffects.typewriter: label is null")
		return Signal()

	label.text = text
	label.visible_ratio = 0.0

	var total_chars := label.get_total_character_count()
	if characters_per_second <= 0 or total_chars == 0 or _is_hurried(token) or not label.is_inside_tree():
		label.visible_ratio = 1.0
		return _next_frame(label)

	var duration := float(total_chars) / characters_per_second

	var tween := label.create_tween()
	tween.tween_property(label, "visible_ratio", 1.0, duration)
	_finish_on_hurry(tween, token, duration)

	return tween.finished


## typewriter with pause support from markup attributes.
static func typewriter_with_line(
	label: RichTextLabel,
	line: YarnLine,
	characters_per_second: float,
	pause_handler: YarnPauseEventProcessor = null,
	token: YarnCancellationToken = null
) -> Signal:
	if label == null:
		push_error("YarnEffects.typewriter_with_line: label is null")
		return Signal()

	if line == null:
		push_error("YarnEffects.typewriter_with_line: line is null")
		return Signal()

	var line_typewriter := YarnTypewriter.LetterTypewriter.new()
	line_typewriter.characters_per_second = characters_per_second
	line_typewriter.text_element = label
	if pause_handler != null:
		line_typewriter.action_markup_handlers = [pause_handler]

	var markup := line.get_markup_result_without_character_name()
	var display_text := line.get_bbcode_text()
	line_typewriter.prepare_for_content(markup, display_text)

	if not label.is_inside_tree():
		label.visible_characters = -1
		return Signal()

	var done := YarnPromise.new()
	_run_line_typewriter(line_typewriter, markup, display_text, token, done)
	return done.completed


static func typewriter_words(
	label: RichTextLabel,
	text: String,
	words_per_second: float,
	token: YarnCancellationToken = null
) -> Signal:
	if label == null:
		push_error("YarnEffects.typewriter_words: label is null")
		return Signal()

	label.text = text

	var boundaries := YarnTypewriter.word_boundaries(label.get_parsed_text())
	if words_per_second <= 0 or boundaries.is_empty() or _is_hurried(token) or not label.is_inside_tree():
		label.visible_characters = -1
		return _next_frame(label)

	label.visible_characters = boundaries[0]

	var seconds_per_word := 1.0 / words_per_second
	var tween := label.create_tween()
	for index in range(1, boundaries.size()):
		tween.tween_interval(seconds_per_word)
		tween.tween_callback(label.set.bind("visible_characters", boundaries[index]))
	tween.tween_callback(label.set.bind("visible_characters", -1))
	_finish_on_hurry(tween, token, seconds_per_word * boundaries.size())

	return tween.finished


static func punch_scale(
	target: Control,
	punch_scale: float = 1.2,
	duration: float = 0.1
) -> Signal:
	if target == null:
		return Signal()

	var original_scale := target.scale
	var tween := target.create_tween()
	tween.tween_property(target, "scale", original_scale * punch_scale, duration * 0.5)
	tween.tween_property(target, "scale", original_scale, duration * 0.5)
	return tween.finished


static func shake(
	target: Control,
	intensity: float = 5.0,
	duration: float = 0.3,
	frequency: float = 30.0
) -> Signal:
	if target == null:
		return Signal()

	var original_pos := target.position
	var tween := target.create_tween()
	var steps := maxi(int(duration * frequency), 1)
	var step_duration := maxf(duration, 0.0) / steps

	for i in range(steps):
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		var decay := 1.0 - (float(i) / steps)
		tween.tween_property(target, "position", original_pos + offset * decay, step_duration)

	tween.tween_property(target, "position", original_pos, step_duration)

	return tween.finished


static func _run_line_typewriter(
	line_typewriter: YarnTypewriter,
	markup: YarnMarkupParseResult,
	display_text: String,
	token: YarnCancellationToken,
	done: YarnPromise
) -> void:
	var tree := line_typewriter.text_element.get_tree()
	var start_frame := Engine.get_process_frames()
	await line_typewriter.run_typewriter(markup, display_text, token)
	if Engine.get_process_frames() == start_frame and tree != null:
		await tree.process_frame
	done.settle()


static func _is_hurried(token: YarnCancellationToken) -> bool:
	return token != null and token.is_hurry_up_requested


static func _next_frame(node: Node) -> Signal:
	if node.is_inside_tree():
		return node.get_tree().process_frame
	return Signal()


static func _finish_on_hurry(tween: Tween, token: YarnCancellationToken, duration: float) -> void:
	if token == null:
		return
	var finish := func() -> void:
		if tween.is_valid() and tween.is_running():
			tween.custom_step(duration + 1.0)
	var release := func() -> void:
		if token.hurry_up_requested.is_connected(finish):
			token.hurry_up_requested.disconnect(finish)
	token.hurry_up_requested.connect(finish, CONNECT_ONE_SHOT)
	tween.finished.connect(release, CONNECT_ONE_SHOT)
