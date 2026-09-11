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
extends RefCounted
## Yarn Spinner's localisation, built upon on Godot's own systems so
## text through [TranslationServer] (keys are teh line id with
## [member translation_prefix] prepended), audio through translation
## remaps (Project Settings > Localization > Remaps)
## by [ResourceLoader]. There is no separate Yarn localisation backend anymore.
## It's not really needed by Godot!

## Emitted when the locale is changed through [method set_current_locale].
signal locale_changed(locale: String)

const _TRANSLATION_REMAPS_SETTING := "internationalization/locale/translation_remaps"

var translation_prefix: String = "YARN_"
var text_locale_code: String = ""
var asset_locale_code: String = ""
var use_fallback: bool = true:
	set(value):
		if use_fallback != value:
			use_fallback = value
			clear_audio_cache()
var fallback_locale_code: String = "":
	set(value):
		if fallback_locale_code != value:
			fallback_locale_code = value
			clear_audio_cache()
var fallback_to_program: bool:
	get:
		return use_fallback
	set(value):
		use_fallback = value
		fallback_locale_code = ""
var _program: YarnProgram

## Folder containing the BASE-language voice files, named after the line id
## without its "line:" prefix (line:tutorial-tom-01 -> tutorial-tom-01.wav).
## Localised variants are provided by Godot translation remaps.
var audio_base_path: String = ""
var audio_extensions: PackedStringArray = [".ogg", ".wav", ".mp3"]
var _audio_cache: Dictionary[String, AudioStream] = {}
var max_audio_cache_size: int = 50
var _audio_cache_order: Array[String] = []
var _pending_audio_loads: Dictionary[String, String] = {}


func get_current_locale() -> String:
	if not text_locale_code.is_empty():
		return text_locale_code
	return TranslationServer.get_locale()


func get_asset_locale() -> String:
	if not asset_locale_code.is_empty():
		return asset_locale_code
	return get_current_locale()


func set_current_locale(locale: String) -> void:
	var old_locale := TranslationServer.get_locale()
	TranslationServer.set_locale(locale)
	if locale != old_locale:
		locale_changed.emit(locale)


func set_program(program: YarnProgram) -> void:
	_program = program


func get_localised_text(line_id: String) -> String:
	var key := translation_prefix + line_id
	var translated := _translate_for_locale(key, get_current_locale())
	if not translated.is_empty():
		return translated

	if not use_fallback:
		return ""

	if not fallback_locale_code.is_empty():
		return _translate_for_locale(key, fallback_locale_code)

	if _program != null and _program.has_string(line_id):
		return _program.get_string(line_id)

	return ""


func has_localised_text(line_id: String) -> bool:
	return not get_localised_text(line_id).is_empty()


func _translate_for_locale(key: String, locale: String) -> String:
	if locale.is_empty():
		return ""
	var best := ""
	var best_score := 0
	for translation: Translation in TranslationServer.get_translations():
		if translation == null:
			continue
		var score := TranslationServer.compare_locales(locale, translation.locale)
		if score <= 0 or score < best_score:
			continue
		var message := String(translation.get_message(key))
		if message.is_empty():
			continue
		best = message
		best_score = score
		if score == 10:
			break
	if not best.is_empty() and TranslationServer.is_pseudolocalization_enabled():
		return String(TranslationServer.pseudolocalize(best))
	return best


func get_available_locales() -> PackedStringArray:
	return TranslationServer.get_loaded_locales()


func has_locale(locale: String) -> bool:
	var loaded := TranslationServer.get_loaded_locales()
	return locale in loaded


func get_localised_audio(line_id: String) -> AudioStream:
	var locale := get_asset_locale()
	var cache_key := locale + ":" + line_id

	if _audio_cache.has(cache_key):
		_update_audio_cache_order(cache_key)
		return _audio_cache[cache_key]

	var path := _resolve_audio_path(line_id, locale)
	if path.is_empty():
		return null

	var audio: AudioStream = null
	if _pending_audio_loads.has(path):
		var requested_key: String = _pending_audio_loads[path]
		_pending_audio_loads.erase(path)
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var pending_audio := ResourceLoader.load_threaded_get(path) as AudioStream
			if requested_key == cache_key:
				audio = pending_audio

	if audio == null:
		# CACHE_MODE_IGNORE: Godot caches a remapped resource under its
		# ORIGINAL path so after a locale switch a plain load() would
		# return the previous locale's audio. The per-locale cache in
		# get_localised_audio does the caching instead
		audio = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream

	if audio != null:
		_add_to_audio_cache(cache_key, audio)

	return audio


func has_localised_audio(line_id: String) -> bool:
	var locale := get_asset_locale()
	var cache_key := locale + ":" + line_id

	if _audio_cache.has(cache_key):
		return true

	return not _resolve_audio_path(line_id, locale).is_empty()


## Loads the baselanguage file andGodot's translation remaps substitute the
## current locale's variant during load; other locales resolve the remap here.
func _resolve_audio_path(line_id: String, locale: String) -> String:
	var base_path := _find_audio_path(line_id)
	if base_path.is_empty():
		return ""

	var is_current_locale := locale == TranslationServer.get_locale()
	var remapped := _find_remap_target(base_path, locale)
	if not remapped.is_empty():
		return base_path if is_current_locale else remapped

	if not use_fallback:
		return ""

	if not fallback_locale_code.is_empty():
		return _find_remap_target(base_path, fallback_locale_code)

	if is_current_locale:
		return base_path
	return _get_unremapped_path(base_path)


func _find_remap_target(path: String, locale: String) -> String:
	if locale.is_empty():
		return ""
	var remaps: Variant = ProjectSettings.get_setting(_TRANSLATION_REMAPS_SETTING, {})
	if not remaps is Dictionary or remaps.is_empty():
		return ""

	var entries: Variant = null
	if remaps.has(path):
		entries = remaps[path]
	else:
		for key: Variant in remaps:
			if _to_resource_path(String(key)).simplify_path() == path.simplify_path():
				entries = remaps[key]
				break
	if entries == null:
		return ""

	var best := ""
	var best_score := 0
	for entry: Variant in entries:
		var remap := String(entry)
		var split := remap.rfind(":")
		if split < 0:
			continue
		var score := TranslationServer.compare_locales(locale, remap.substr(split + 1).strip_edges())
		if score <= 0 or score < best_score:
			continue
		var target := _to_resource_path(remap.left(split))
		if target.is_empty() or not ResourceLoader.exists(target):
			continue
		best = target
		best_score = score
		if score == 10:
			break
	return best


func _to_resource_path(path: String) -> String:
	if not path.begins_with("uid://"):
		return path
	var id := ResourceUID.text_to_id(path)
	if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
		return ""
	return ResourceUID.get_id_path(id)


func _get_unremapped_path(path: String) -> String:
	if _find_remap_target(path, TranslationServer.get_locale()).is_empty():
		return path
	var import_config := ConfigFile.new()
	if import_config.load(path + ".import") != OK:
		return path
	var imported_path := String(import_config.get_value("remap", "path", ""))
	if imported_path.is_empty() or not FileAccess.file_exists(imported_path):
		return path
	return imported_path


func _find_audio_path(line_id: String) -> String:
	if audio_base_path.is_empty():
		return ""

	var base_path := audio_base_path
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
	if _audio_cache.has(key):
		_audio_cache[key] = audio
		_update_audio_cache_order(key)
		return

	_audio_cache[key] = audio
	_audio_cache_order.append(key)

	if max_audio_cache_size > 0:
		while _audio_cache.size() > max_audio_cache_size and not _audio_cache_order.is_empty():
			var oldest: Variant = _audio_cache_order.pop_front()
			_audio_cache.erase(oldest)


func _update_audio_cache_order(key: String) -> void:
	var idx := _audio_cache_order.find(key)
	if idx >= 0:
		_audio_cache_order.remove_at(idx)
		_audio_cache_order.append(key)


func prepare_for_lines(line_ids: PackedStringArray) -> void:
	_poll_pending_audio_loads()
	var locale := get_asset_locale()
	for line_id in line_ids:
		var cache_key := locale + ":" + line_id
		if _audio_cache.has(cache_key):
			continue
		var path := _resolve_audio_path(line_id, locale)
		if path.is_empty() or _pending_audio_loads.has(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_IGNORE) == OK:
			_pending_audio_loads[path] = cache_key


func _poll_pending_audio_loads() -> void:
	for path: String in _pending_audio_loads.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var cache_key: String = _pending_audio_loads[path]
		_pending_audio_loads.erase(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			continue
		var audio := ResourceLoader.load_threaded_get(path) as AudioStream
		if audio != null and not cache_key.is_empty() and not _audio_cache.has(cache_key):
			_add_to_audio_cache(cache_key, audio)


func clear_audio_cache() -> void:
	_audio_cache.clear()
	_audio_cache_order.clear()
	for path: String in _pending_audio_loads.keys():
		_pending_audio_loads[path] = ""
	_poll_pending_audio_loads()


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
	lines.append("asset locale: %s" % get_asset_locale())
	lines.append("translation prefix: %s" % translation_prefix)
	lines.append("use fallback: %s" % str(use_fallback))
	lines.append("fallback locale: %s" % fallback_locale_code)
	lines.append("audio base path: %s" % audio_base_path)
	lines.append("loaded locales: %s" % ", ".join(get_available_locales()))
	lines.append("audio cache size: %d / %d" % [_audio_cache.size(), max_audio_cache_size])
	return "\n".join(lines)
