extends GutTest

const ASSET_DIR := "user://yarn_localisation_test"
const REMAPS_SETTING := "internationalization/locale/translation_remaps"

var _translations: Array[Translation] = []
var _old_locale := ""
var _old_remaps: Variant = null
var _program: YarnProgram


func before_all():
	DirAccess.make_dir_recursive_absolute(ASSET_DIR)
	_save_wav("a.tres", 11025)
	_save_wav("a_fr.tres", 22050)
	_save_wav("a_de.tres", 44100)
	_save_wav("b.tres", 8000)
	_save_wav("line_c.tres", 8000)


func after_all():
	for file in DirAccess.get_files_at(ASSET_DIR):
		DirAccess.remove_absolute(ASSET_DIR.path_join(file))
	DirAccess.remove_absolute(ASSET_DIR)


func before_each():
	_old_locale = TranslationServer.get_locale()
	_old_remaps = ProjectSettings.get_setting(REMAPS_SETTING, {})
	TranslationServer.set_locale("en")
	_add_translation("fr", {"line:a": "Bonjour"})
	_add_translation("de", {"line:a": "Hallo", "line:b": "Nur Deutsch"})
	_program = YarnProgram.new()
	_program.string_table = {"line:a": "Hello", "line:b": "Base only"}
	ProjectSettings.set_setting(REMAPS_SETTING, {
		ASSET_DIR.path_join("a.tres"): PackedStringArray([
			ASSET_DIR.path_join("a_fr.tres") + ":fr",
			ASSET_DIR.path_join("a_de.tres") + ":de_DE",
		]),
	})


func after_each():
	for translation in _translations:
		TranslationServer.remove_translation(translation)
	_translations.clear()
	TranslationServer.set_locale(_old_locale)
	ProjectSettings.set_setting(REMAPS_SETTING, _old_remaps)


func _add_translation(locale: String, messages: Dictionary) -> void:
	var translation := Translation.new()
	translation.locale = locale
	for line_id in messages:
		translation.add_message("YARN_" + line_id, messages[line_id])
	TranslationServer.add_translation(translation)
	_translations.append(translation)


func _save_wav(file_name: String, mix_rate: int) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = mix_rate
	var data := PackedByteArray()
	data.resize(64)
	wav.data = data
	ResourceSaver.save(wav, ASSET_DIR.path_join(file_name))


func _make_localisation() -> YarnGodotLocalisation:
	var loc := YarnGodotLocalisation.new()
	loc.set_program(_program)
	loc.audio_base_path = ASSET_DIR
	loc.audio_extensions = PackedStringArray([".tres"])
	return loc


func _mix_rate(audio: AudioStream) -> int:
	var wav := audio as AudioStreamWAV
	return wav.mix_rate if wav != null else -1


func test_default_uses_server_locale_then_base_table():
	var loc := _make_localisation()
	assert_eq(loc.get_current_locale(), "en")
	assert_eq(loc.get_localised_text("line:a"), "Hello")
	TranslationServer.set_locale("fr")
	assert_eq(loc.get_localised_text("line:a"), "Bonjour")
	assert_eq(loc.get_localised_text("line:b"), "Base only")


func test_text_locale_does_not_change_server_locale():
	var loc := _make_localisation()
	loc.text_locale_code = "fr"
	assert_eq(loc.get_current_locale(), "fr")
	assert_eq(loc.get_localised_text("line:a"), "Bonjour")
	assert_eq(TranslationServer.get_locale(), "en")
	loc.text_locale_code = "fr_CA"
	assert_eq(loc.get_localised_text("line:a"), "Bonjour")


func test_fallback_disabled_returns_empty():
	var loc := _make_localisation()
	loc.text_locale_code = "fr"
	loc.use_fallback = false
	assert_eq(loc.get_localised_text("line:b"), "")
	assert_false(loc.has_localised_text("line:b"))
	assert_false(loc.fallback_to_program)


func test_fallback_locale():
	var loc := _make_localisation()
	loc.text_locale_code = "fr"
	loc.fallback_locale_code = "de"
	assert_eq(loc.get_localised_text("line:a"), "Bonjour")
	assert_eq(loc.get_localised_text("line:b"), "Nur Deutsch")
	loc.fallback_to_program = true
	assert_eq(loc.fallback_locale_code, "")
	assert_eq(loc.get_localised_text("line:b"), "Base only")


func test_asset_locale_defaults_to_text_locale():
	var loc := _make_localisation()
	loc.text_locale_code = "fr"
	assert_eq(loc.get_asset_locale(), "fr")
	assert_eq(_mix_rate(loc.get_localised_audio("line:a")), 22050)
	loc.asset_locale_code = "de"
	assert_eq(loc.get_asset_locale(), "de")
	assert_eq(_mix_rate(loc.get_localised_audio("line:a")), 44100)
	assert_eq(loc.get_current_locale(), "fr")


func test_asset_remap_language_match():
	var loc := _make_localisation()
	loc.asset_locale_code = "fr_CA"
	assert_eq(_mix_rate(loc.get_localised_audio("line:a")), 22050)


func test_asset_fallback_rules():
	var loc := _make_localisation()
	loc.asset_locale_code = "es"
	assert_eq(_mix_rate(loc.get_localised_audio("line:a")), 11025)
	loc.fallback_locale_code = "fr"
	assert_eq(_mix_rate(loc.get_localised_audio("line:a")), 22050)
	loc.use_fallback = false
	assert_null(loc.get_localised_audio("line:a"))
	assert_false(loc.has_localised_audio("line:a"))


func test_threaded_preload_is_collected_by_get():
	var loc := _make_localisation()
	loc.asset_locale_code = "de"
	loc.prepare_for_lines(PackedStringArray(["line:a"]))
	assert_eq(loc._pending_audio_loads.size(), 1)
	assert_eq(_mix_rate(loc.get_localised_audio("line:a")), 44100)
	assert_eq(loc._pending_audio_loads.size(), 0)
	assert_true(loc._audio_cache.has("de:line:a"))


func test_threaded_preload_is_harvested_by_next_prepare():
	var loc := _make_localisation()
	loc.asset_locale_code = "fr"
	loc.prepare_for_lines(PackedStringArray(["line:a"]))
	var path := ASSET_DIR.path_join("a_fr.tres")
	await wait_until(func(): return ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS, 5.0)
	loc.prepare_for_lines(PackedStringArray())
	assert_eq(loc._pending_audio_loads.size(), 0)
	assert_eq(_mix_rate(loc._audio_cache.get("fr:line:a")), 22050)


func test_asset_provider_uses_localisation_naming():
	var provider := YarnAssetProvider.new()
	provider.audio_base_path = ASSET_DIR
	provider.audio_extensions = PackedStringArray([".tres"])
	provider.use_threaded_loading = false
	assert_eq(_mix_rate(provider.get_audio("line:b")), 8000)
	assert_eq(_mix_rate(provider.get_audio("line:c")), 8000)
	assert_null(provider.get_audio("line:missing"))


func test_asset_provider_preload_is_harvested():
	var provider := YarnAssetProvider.new()
	provider.audio_base_path = ASSET_DIR
	provider.audio_extensions = PackedStringArray([".tres"])
	provider.image_extensions = PackedStringArray()
	provider.preload_assets(PackedStringArray(["line:b"]))
	assert_eq(provider.get_cache_stats().pending_loads, 1)
	var path := ASSET_DIR.path_join("b.tres")
	await wait_until(func(): return ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS, 5.0)
	provider.preload_assets(PackedStringArray())
	assert_eq(provider.get_cache_stats().pending_loads, 0)
	assert_eq(provider.get_cache_stats().audio_cache_size, 1)

	provider.preload_assets(PackedStringArray(["line:c"]))
	var path_c := ASSET_DIR.path_join("line_c.tres")
	await wait_until(func(): return ResourceLoader.load_threaded_get_status(path_c) != ResourceLoader.THREAD_LOAD_IN_PROGRESS, 5.0)
	provider.clear()
	assert_eq(provider.get_cache_stats().pending_loads, 0)
	assert_eq(provider.get_cache_stats().total_cached, 0)
	assert_eq(ResourceLoader.load_threaded_get_status(path_c), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
