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

class_name YarnLineProvider
extends RefCounted
## Provides localised line content for yarn dialogue.
## Handles text lookup, substitution, and markup parsing.


var godot_localisation: YarnGodotLocalisation
var _program: YarnProgram

## Fallback mappings when the primary localisation is missing a translation.
var _shadow_lines: Dictionary[String, String] = {}

## Legacy accessor; prefer get_current_locale()/set_current_locale().
var locale: String:
	get:
		return get_current_locale()
	set(value):
		set_current_locale(value)


func _init() -> void:
	godot_localisation = YarnGodotLocalisation.new()


func set_program(program: YarnProgram) -> void:
	_program = program
	godot_localisation.set_program(program)


func get_localisation() -> YarnLocalisation:
	return godot_localisation


func get_current_locale() -> String:
	return get_localisation().get_current_locale()


func set_current_locale(locale_code: String) -> void:
	get_localisation().set_current_locale(locale_code)


func get_available_locales() -> PackedStringArray:
	return get_localisation().get_available_locales()


func has_locale(locale_code: String) -> bool:
	return get_localisation().has_locale(locale_code)


## Main entry point for line processing. Fetches localised text,
## applies substitutions, and parses markup.
func get_localised_line(line: YarnLine) -> void:
	if _program != null and _program.line_metadata.has(line.line_id):
		line.metadata = _program.line_metadata[line.line_id]
		_parse_shadow_metadata(line.line_id, line.metadata)

	line.raw_text = _get_string_with_shadow(line.line_id)
	line.apply_substitutions()
	line.parse_markup()


## Parses #shadow:other_line_id tags from metadata.
func _parse_shadow_metadata(line_id: String, metadata: PackedStringArray) -> void:
	for tag in metadata:
		if tag.begins_with("shadow:"):
			var shadow_id := tag.substr(7)  # length of "shadow:"
			_shadow_lines[line_id] = shadow_id
			return


func get_localised_option(option: YarnOption) -> void:
	option.raw_text = _get_string(option.line_id)
	option.apply_substitutions()


## Tries primary localisation, then shadow line, then returns line_id as fallback.
func _get_string_with_shadow(line_id: String) -> String:
	var text := _get_string(line_id)

	if text.is_empty() and _shadow_lines.has(line_id):
		var shadow_id: String = _shadow_lines[line_id]
		var shadow_text := _get_string(shadow_id)
		if not shadow_text.is_empty():
			return shadow_text

	if text.is_empty():
		return line_id

	return text


## Checks localisation system, then falls back to program string table.
func _get_string(line_id: String) -> String:
	var loc := get_localisation()
	var text := loc.get_localised_text(line_id)

	if not text.is_empty():
		return text

	if _program != null and _program.has_string(line_id):
		return _program.get_string(line_id)

	return ""


func register_shadow_line(line_id: String, shadow_id: String) -> void:
	_shadow_lines[line_id] = shadow_id


func unregister_shadow_line(line_id: String) -> void:
	_shadow_lines.erase(line_id)


func get_localised_audio(line_id: String) -> AudioStream:
	return get_localisation().get_localised_audio(line_id)


func has_localised_audio(line_id: String) -> bool:
	return get_localisation().has_localised_audio(line_id)


func prepare_for_lines(line_ids: PackedStringArray) -> void:
	get_localisation().prepare_for_lines(line_ids)


func clear_shadow_lines() -> void:
	_shadow_lines.clear()


func set_translation_prefix(prefix: String) -> void:
	godot_localisation.translation_prefix = prefix


func get_translation_prefix() -> String:
	return godot_localisation.translation_prefix


## Use {locale} as placeholder, e.g. "res://audio/dialogue/{locale}/"
func set_audio_path_template(template: String) -> void:
	godot_localisation.audio_path_template = template


func export_for_godot_translation(output_path: String) -> Error:
	if _program == null:
		return ERR_INVALID_DATA
	return YarnGodotLocalisation.export_strings_for_translation(_program, output_path, godot_localisation.translation_prefix)


func add_to_translation_server(locale_code: String) -> void:
	if _program != null:
		YarnGodotLocalisation.add_translation_to_server(_program, locale_code, godot_localisation.translation_prefix)


var _markup_parser: YarnMarkupParser


func get_markup_parser() -> YarnMarkupParser:
	if _markup_parser == null:
		_markup_parser = YarnMarkupParser.new()
	return _markup_parser


func register_marker_processor(attribute_name: String, processor: YarnAttributeMarkerProcessor) -> void:
	get_markup_parser().register_marker_processor(attribute_name, processor)


func deregister_marker_processor(attribute_name: String) -> void:
	get_markup_parser().deregister_marker_processor(attribute_name)


func register_bbcode_processor(processor: YarnMarkupAttributeProcessor) -> void:
	get_markup_parser().register_processor(processor)


func unregister_bbcode_processor(processor: YarnMarkupAttributeProcessor) -> void:
	get_markup_parser().unregister_processor(processor)


func get_debug_info() -> String:
	var lines: Array[String] = []
	lines.append("localisation type: GODOT")
	lines.append("")
	lines.append("--- active provider ---")
	lines.append(get_localisation().get_debug_info())
	lines.append("")
	lines.append("shadow lines: %d" % _shadow_lines.size())
	return "\n".join(lines)
