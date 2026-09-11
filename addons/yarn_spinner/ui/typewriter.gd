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

class_name YarnTypewriter
extends Resource

var action_markup_handlers: Array = []
var text_element: RichTextLabel


func prepare_for_content(line: YarnMarkupParseResult, display_text: String) -> void:
	if text_element == null or not is_instance_valid(text_element):
		return
	text_element.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	text_element.visible_characters = 0
	text_element.text = display_text
	for handler in action_markup_handlers:
		if handler != null and handler.has_method("on_prepare_for_line"):
			handler.on_prepare_for_line(line, text_element)


func run_typewriter(line: YarnMarkupParseResult, display_text: String, token: YarnCancellationToken) -> void:
	var label := text_element
	if label == null or not is_instance_valid(label):
		push_warning("typewriter: can't show text, because no text element was provided")
	else:
		label.visible_characters = 0
		label.text = display_text

		for handler in action_markup_handlers:
			if handler != null and handler.has_method("on_line_display_begin"):
				handler.on_line_display_begin(line, label)

		var character_count := label.get_total_character_count()
		var seconds_per_unit := _get_seconds_per_unit()
		var uses_words := _uses_word_boundaries()
		var boundaries := word_boundaries(label.get_parsed_text()) if uses_words else PackedInt32Array()
		var next_boundary := 0
		var accumulated := seconds_per_unit

		for i in range(character_count):
			if not is_instance_valid(label):
				break

			var gate := true
			if uses_words:
				gate = next_boundary < boundaries.size() and i == boundaries[next_boundary]
				if gate:
					next_boundary += 1

			if gate and seconds_per_unit > 0.0:
				while not _is_hurried(token) and accumulated < seconds_per_unit:
					if not is_instance_valid(label) or not label.is_inside_tree():
						break
					var before := Time.get_ticks_usec()
					await label.get_tree().process_frame
					if not is_instance_valid(label):
						break
					if not label.can_process():
						continue
					accumulated += float(Time.get_ticks_usec() - before) / 1_000_000.0
				if uses_words:
					accumulated -= seconds_per_unit

			for handler in action_markup_handlers:
				if handler != null and handler.has_method("on_character_will_appear"):
					var result: Variant = handler.on_character_will_appear(i, line, token)
					if result is Signal and not (result as Signal).is_null() and not _is_hurried(token):
						await result

			if not is_instance_valid(label):
				break
			label.visible_characters = i + 1

			if not uses_words:
				accumulated -= seconds_per_unit

		if is_instance_valid(label):
			label.visible_characters = -1

	for handler in action_markup_handlers:
		if handler != null and handler.has_method("on_line_display_complete"):
			handler.on_line_display_complete()


func content_will_dismiss() -> void:
	for handler in action_markup_handlers:
		if handler != null and handler.has_method("on_line_will_dismiss"):
			handler.on_line_will_dismiss()


func content_did_dismiss() -> void:
	if text_element != null and is_instance_valid(text_element):
		text_element.visible_characters = 0


func _get_seconds_per_unit() -> float:
	return 0.0


func _uses_word_boundaries() -> bool:
	return false


static func _is_hurried(token: YarnCancellationToken) -> bool:
	return token != null and token.is_hurry_up_requested


static func word_boundaries(text: String) -> PackedInt32Array:
	var boundaries := PackedInt32Array()
	var in_word := false
	for i in range(text.length()):
		if _is_word_character(text.unicode_at(i)):
			in_word = true
		elif in_word:
			boundaries.append(i)
			in_word = false
	if in_word:
		boundaries.append(text.length())
	return boundaries


static func _is_word_character(code: int) -> bool:
	if code == 0x2D or code == 0xAD or code == 0x2010 or code == 0x2011:
		return true
	if code >= 0x30 and code <= 0x39:
		return true
	var server := TextServerManager.get_primary_interface()
	return server != null and server.is_valid_letter(code)


class InstantTypewriter extends YarnTypewriter:
	pass


class LetterTypewriter extends YarnTypewriter:
	var characters_per_second: float = 0.0

	func _get_seconds_per_unit() -> float:
		if characters_per_second > 0.0:
			return 1.0 / characters_per_second
		return 0.0


class WordTypewriter extends YarnTypewriter:
	var words_per_second: float = 0.0

	func _get_seconds_per_unit() -> float:
		if words_per_second > 0.0:
			return 1.0 / words_per_second
		return 0.0

	func _uses_word_boundaries() -> bool:
		return true
