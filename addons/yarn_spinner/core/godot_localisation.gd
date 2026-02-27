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

class_name YarnGodotLocalisation
extends YarnLocalisation
## Localisation provider using Godot's TranslationServer.

var translation_prefix: String = "YARN_"
var fallback_to_program: bool = true
var _program: YarnProgram

## Use {locale} as placeholder, e.g. "res://audio/dialogue/{locale}/"
var audio_path_template: String = ""
var audio_extensions: PackedStringArray = [".ogg", ".wav", ".mp3"]
var _audio_cache: Dictionary[String, AudioStream] = {}
var max_audio_cache_size: int = 50
var _audio_cache_order: Array[String] = []


func get_current_locale() -> String:
	return TranslationServer.get_locale()


func set_current_locale(locale: String) -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale(locale)
	if locale != old_locale:
		locale_changed.emit(locale)


func set_program(program: YarnProgram) -> void:
	_program = program


func get_localised_text(line_id: String) -> String:
	var key := translation_prefix + line_id
	var translated := tr(key)

	# tr() returns key unchanged if not found
	if translated != key:
		return translated

	if fallback_to_program and _program != null and _program.has_string(line_id):
		return _program.get_string(line_id)

	return ""


func has_localised_text(line_id: String) -> bool:
	var key := translation_prefix + line_id
	var translated := tr(key)

	if translated != key:
		return true

	if _program != null and _program.has_string(line_id):
		return true

	return false


func get_available_locales() -> PackedStringArray:
	return TranslationServer.get_loaded_locales()


func has_locale(locale: String) -> bool:
	var loaded := TranslationServer.get_loaded_locales()
	return locale in loaded


func get_localised_audio(line_id: String) -> AudioStream:
	var locale := get_current_locale()
	var cache_key := locale + ":" + line_id

	if _audio_cache.has(cache_key):
		_update_audio_cache_order(cache_key)
		return _audio_cache[cache_key]

	var audio := _load_audio_for_locale(line_id, locale)

	if audio == null:
		var base_locale := locale.split("_")[0]  # godot uses _ not -
		if base_locale != locale:
			audio = _load_audio_for_locale(line_id, base_locale)

	if audio != null:
		_add_to_audio_cache(cache_key, audio)

	return audio


func has_localised_audio(line_id: String) -> bool:
	var locale := get_current_locale()
	var cache_key := locale + ":" + line_id

	if _audio_cache.has(cache_key):
		return true

	var path := _find_audio_path(line_id, locale)
	return not path.is_empty()


func _load_audio_for_locale(line_id: String, locale: String) -> AudioStream:
	var path := _find_audio_path(line_id, locale)
	if path.is_empty():
		return null

	if ResourceLoader.exists(path):
		return load(path) as AudioStream

	return null


func _find_audio_path(line_id: String, locale: String) -> String:
	if audio_path_template.is_empty():
		return ""

	var base_path := audio_path_template.replace("{locale}", locale)
	if not base_path.ends_with("/"):
		base_path += "/"

	# try multiple naming conventions:
	# 1. strip "line:" prefix (most common for yarn spinner)
	# 2. sanitise with underscores
	# 3. original id
	var id_variants: Array[String] = []

	# strip "line:" prefix if present
	if line_id.begins_with("line:"):
		id_variants.append(line_id.substr(5))

	# sanitise: replace colons and slashes with underscores
	var safe_id := line_id.replace(":", "_").replace("/", "_")
	if safe_id not in id_variants:
		id_variants.append(safe_id)

	# original id (in case it's already safe)
	if line_id not in id_variants:
		id_variants.append(line_id)

	# try each variant with each extension
	for variant in id_variants:
		for ext in audio_extensions:
			var path := base_path + variant + ext
			if ResourceLoader.exists(path):
				return path

	return ""


func _add_to_audio_cache(key: String, audio: AudioStream) -> void:
	_audio_cache[key] = audio
	_audio_cache_order.append(key)

	if max_audio_cache_size > 0:
		while _audio_cache.size() > max_audio_cache_size and not _audio_cache_order.is_empty():
			var oldest := _audio_cache_order.pop_front()
			_audio_cache.erase(oldest)


func _update_audio_cache_order(key: String) -> void:
	var idx := _audio_cache_order.find(key)
	if idx >= 0:
		_audio_cache_order.remove_at(idx)
		_audio_cache_order.append(key)


func prepare_for_lines(line_ids: PackedStringArray) -> void:
	for line_id in line_ids:
		if has_localised_audio(line_id):
			get_localised_audio(line_id)


func clear_audio_cache() -> void:
	_audio_cache.clear()
	_audio_cache_order.clear()


static func export_strings_for_translation(program: YarnProgram, output_path: String, prefix: String = "YARN_") -> Error:
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_csv_line(PackedStringArray(["keys", "en"]))

	for line_id: String in program.string_table:
		var text: String = program.string_table[line_id]
		var key := prefix + line_id
		file.store_csv_line(PackedStringArray([key, text]))

	file.close()
	return OK


static func export_as_translation(program: YarnProgram, locale: String, prefix: String = "YARN_") -> Translation:
	var translation := Translation.new()
	translation.locale = locale

	for line_id: String in program.string_table:
		var text: String = program.string_table[line_id]
		var key := prefix + line_id
		translation.add_message(key, text)

	return translation


static func add_translation_to_server(program: YarnProgram, locale: String, prefix: String = "YARN_") -> void:
	var translation := export_as_translation(program, locale, prefix)
	TranslationServer.add_translation(translation)


func get_debug_info() -> String:
	var lines: Array[String] = []
	lines.append("current locale: %s" % get_current_locale())
	lines.append("translation prefix: %s" % translation_prefix)
	lines.append("fallback to program: %s" % str(fallback_to_program))
	lines.append("audio path template: %s" % audio_path_template)
	lines.append("loaded locales: %s" % ", ".join(get_available_locales()))
	lines.append("audio cache size: %d / %d" % [_audio_cache.size(), max_audio_cache_size])
	return "\n".join(lines)
