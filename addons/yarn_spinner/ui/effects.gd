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
	characters_per_second: float
) -> Signal:
	if label == null:
		push_error("YarnEffects.typewriter: label is null")
		return Signal()

	label.text = text
	label.visible_ratio = 0.0

	if characters_per_second <= 0:
		label.visible_ratio = 1.0
		return Signal()

	var total_chars := text.length()
	if total_chars == 0:
		label.visible_ratio = 1.0
		return Signal()

	var duration := float(total_chars) / characters_per_second

	var tween := label.create_tween()
	tween.tween_property(label, "visible_ratio", 1.0, duration)

	return tween.finished


## typewriter with pause support from markup attributes.
static func typewriter_with_line(
	label: RichTextLabel,
	line: YarnLine,
	characters_per_second: float,
	pause_handler: YarnPauseEventProcessor = null
) -> Signal:
	if label == null:
		push_error("YarnEffects.typewriter_with_line: label is null")
		return Signal()

	if line == null:
		push_error("YarnEffects.typewriter_with_line: line is null")
		return Signal()

	var text := line.text
	label.text = text
	label.visible_ratio = 0.0

	if characters_per_second <= 0:
		label.visible_ratio = 1.0
		return Signal()

	var total_chars := text.length()
	if total_chars == 0:
		label.visible_ratio = 1.0
		return Signal()

	if pause_handler != null:
		pause_handler.on_prepare_for_line(line, label)
		pause_handler.on_line_display_begin(line, label)

	var char_delay := 1.0 / characters_per_second
	var tree := label.get_tree()

	for i in range(total_chars):
		if pause_handler != null and pause_handler.has_pause_at(i):
			var pause_duration := pause_handler.get_pause_duration(i)
			if pause_duration > 0 and tree != null:
				await tree.create_timer(pause_duration).timeout

		label.visible_characters = i + 1

		if tree != null:
			await tree.create_timer(char_delay).timeout

	if pause_handler != null:
		pause_handler.on_line_display_complete()

	return Signal()


static func typewriter_words(
	label: RichTextLabel,
	text: String,
	words_per_second: float
) -> Signal:
	if label == null:
		push_error("YarnEffects.typewriter_words: label is null")
		return Signal()

	label.text = text
	label.visible_ratio = 0.0

	if words_per_second <= 0:
		label.visible_ratio = 1.0
		return Signal()

	var words := text.split(" ", false)
	var total_words := words.size()
	if total_words == 0:
		label.visible_ratio = 1.0
		return Signal()

	var duration := float(total_words) / words_per_second

	var tween := label.create_tween()
	tween.tween_property(label, "visible_ratio", 1.0, duration)

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
	var steps := int(duration * frequency)
	var step_duration := duration / steps

	for i in range(steps):
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		var decay := 1.0 - (float(i) / steps)
		tween.tween_property(target, "position", original_pos + offset * decay, step_duration)

	tween.tween_property(target, "position", original_pos, step_duration)

	return tween.finished
