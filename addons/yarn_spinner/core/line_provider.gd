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

## Maps shadow line IDs to the (line:-prefixed) IDs of the lines they shadow.
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


func get_localisation() -> YarnGodotLocalisation:
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

	# A shadow line displays another line's content: swap in the source ID
	# before any lookup, so text and assets both come from the source line.
	var source_id := _resolve_source_line_id(line.line_id)

	line.raw_text = _get_string(source_id)
	if line.raw_text.is_empty():
		push_warning("line provider: no text found for line '%s' in locale '%s'" % [line.line_id, get_current_locale()])
		line.raw_text = line.line_id
	line.locale_code = get_current_locale()
	line.apply_substitutions()
	line.parse_markup()


## Returns the ID of the line this line shadows (with its "line:" prefix),
## or "" if it is not a shadow line. A #shadow:some_id tag is compiled to
## "shadow:some_id" metadata; the source line's string table key is
## "line:some_id".
func get_shadow_line_source(line_id: String) -> String:
	if _shadow_lines.has(line_id):
		return _shadow_lines[line_id]
	if _program != null and _program.line_metadata.has(line_id):
		_parse_shadow_metadata(line_id, _program.line_metadata[line_id])
	return _shadow_lines.get(line_id, "")


## Parses #shadow:other_line_id tags from metadata.
func _parse_shadow_metadata(line_id: String, metadata: PackedStringArray) -> void:
	for tag in metadata:
		if tag.begins_with("shadow:"):
			_shadow_lines[line_id] = "line:" + tag.substr(7)  # length of "shadow:"
			return


## The ID whose content a line should display: the shadow source for a
## shadow line, otherwise the line's own ID.
func _resolve_source_line_id(line_id: String) -> String:
	var source := get_shadow_line_source(line_id)
	return line_id if source.is_empty() else source


func get_localised_option(option: YarnOption) -> void:
	option.raw_text = _get_string(_resolve_source_line_id(option.line_id))
	option.locale_code = get_current_locale()
	option.apply_substitutions()


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
	return get_localisation().get_localised_audio(_resolve_source_line_id(line_id))


func has_localised_audio(line_id: String) -> bool:
	return get_localisation().has_localised_audio(_resolve_source_line_id(line_id))


func prepare_for_lines(line_ids: PackedStringArray) -> void:
	var resolved := PackedStringArray()
	for line_id in line_ids:
		resolved.append(_resolve_source_line_id(line_id))
	get_localisation().prepare_for_lines(resolved)


func clear_shadow_lines() -> void:
	_shadow_lines.clear()


func set_translation_prefix(prefix: String) -> void:
	godot_localisation.translation_prefix = prefix


func get_translation_prefix() -> String:
	return godot_localisation.translation_prefix


## Folder of the base-language voice files; localised variants come from
## Godot translation remaps.
func set_audio_base_path(path: String) -> void:
	godot_localisation.audio_base_path = path


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
	lines.append(get_localisation().get_debug_info())
	lines.append("")
	lines.append("shadow lines: %d" % _shadow_lines.size())
	return "\n".join(lines)
