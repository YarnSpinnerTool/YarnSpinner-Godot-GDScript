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
extends Resource
## Provides localised line content for yarn dialogue.
## Handles text lookup, substitution, and markup parsing.

const INVALID_LINE_ID := "<missing>"
const INVALID_LINE_TEXT := "!! ERROR: Missing line!"

var godot_localisation: YarnGodotLocalisation
var _program: YarnProgram

## Maps shadow line IDs to the (line:-prefixed) IDs of the lines they shadow.
var _shadow_lines: Dictionary[String, String] = {}

var _line_parser: YarnLineParser
var _markup_parser: YarnMarkupParser

@export var text_locale_code: String = "":
	set(value):
		text_locale_code = value
		if godot_localisation != null:
			godot_localisation.text_locale_code = value

@export var asset_locale_code: String = "":
	set(value):
		asset_locale_code = value
		if godot_localisation != null:
			godot_localisation.asset_locale_code = value

@export var use_fallback: bool = true:
	set(value):
		use_fallback = value
		if godot_localisation != null:
			godot_localisation.use_fallback = value

@export var fallback_locale_code: String = "":
	set(value):
		fallback_locale_code = value
		if godot_localisation != null:
			godot_localisation.fallback_locale_code = value

## Legacy accessor; prefer get_current_locale()/set_current_locale().
var locale: String:
	get:
		return get_current_locale()
	set(value):
		set_current_locale(value)


func _init() -> void:
	godot_localisation = YarnGodotLocalisation.new()
	godot_localisation.text_locale_code = text_locale_code
	godot_localisation.asset_locale_code = asset_locale_code
	godot_localisation.use_fallback = use_fallback
	godot_localisation.fallback_locale_code = fallback_locale_code
	_line_parser = YarnLineParser.new()
	var builtin_replacer := YarnBuiltInMarkupReplacer.new()
	_line_parser.register_marker_processor("select", builtin_replacer)
	_line_parser.register_marker_processor("plural", builtin_replacer)
	_line_parser.register_marker_processor("ordinal", builtin_replacer)


func set_program(program: YarnProgram) -> void:
	_program = program
	godot_localisation.set_program(program)


func get_localisation() -> YarnGodotLocalisation:
	return godot_localisation


func get_current_locale() -> String:
	return get_localisation().get_current_locale()


func set_current_locale(locale_code: String) -> void:
	get_localisation().set_current_locale(locale_code)


func get_asset_locale() -> String:
	return get_localisation().get_asset_locale()


func get_available_locales() -> PackedStringArray:
	return get_localisation().get_available_locales()


func has_locale(locale_code: String) -> bool:
	return get_localisation().has_locale(locale_code)


## Main entry point for line processing. Fetches localised text,
## applies substitutions, and parses markup.
func get_localised_line(line: YarnLine) -> bool:
	line.metadata = _get_metadata(line.line_id)

	# A shadow line displays another line's content: swap in the source ID
	# before any lookup, so text and assets both come from the source line.
	var source_id := _resolve_source_line_id(line.line_id)
	line.locale_code = get_current_locale()

	if not get_localisation().has_localised_text(source_id):
		push_warning("line provider: localisation %s does not contain an entry for line %s" % [get_current_locale(), line.line_id])
		line.line_id = INVALID_LINE_ID
		line.raw_text = INVALID_LINE_TEXT
		line.substitutions = []
		line.metadata = PackedStringArray()
		line.set_markup_result(YarnMarkupParseResult.new(INVALID_LINE_TEXT))
		return false

	line.raw_text = _get_string(source_id)
	line.set_markup_result(parse_markup(YarnLineParser.expand_substitutions(line.raw_text, line.substitutions), line.locale_code))
	return true


func get_localised_option(option: YarnOption) -> bool:
	option.metadata = _get_metadata(option.line_id)

	var source_id := _resolve_source_line_id(option.line_id)
	option.locale_code = get_current_locale()

	if not get_localisation().has_localised_text(source_id):
		push_warning("line provider: localisation %s does not contain an entry for line %s" % [get_current_locale(), option.line_id])
		option.raw_text = INVALID_LINE_TEXT
		option.substitutions = []
		option.metadata = PackedStringArray()
		option.set_markup_result(YarnMarkupParseResult.new(INVALID_LINE_TEXT))
		return false

	option.raw_text = _get_string(source_id)
	option.set_markup_result(parse_markup(YarnLineParser.expand_substitutions(option.raw_text, option.substitutions), option.locale_code))
	return true


func parse_markup(text: String, locale_code: String) -> YarnMarkupParseResult:
	return _line_parser.parse_string(text, locale_code, true)


func _get_metadata(line_id: String) -> PackedStringArray:
	if _program == null or not _program.line_metadata.has(line_id):
		return PackedStringArray()
	return PackedStringArray(_program.line_metadata[line_id])


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


func resolve_source_line_id(line_id: String) -> String:
	return _resolve_source_line_id(line_id)


func _get_string(line_id: String) -> String:
	return get_localisation().get_localised_text(line_id)


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


func get_markup_parser() -> YarnMarkupParser:
	if _markup_parser == null:
		_markup_parser = YarnMarkupParser.new()
	return _markup_parser


func register_marker_processor(attribute_name: String, processor: YarnAttributeMarkerProcessor) -> void:
	_line_parser.register_marker_processor(attribute_name, processor)


func deregister_marker_processor(attribute_name: String) -> void:
	_line_parser.deregister_marker_processor(attribute_name)


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
