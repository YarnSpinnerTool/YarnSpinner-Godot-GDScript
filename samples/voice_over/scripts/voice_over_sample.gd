# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

extends Control
## main script for the voice over sample using godot's localisation.
## demonstrates voice over with TranslationServer integration.

@onready var dialogue_runner: YarnDialogueRunner = $YarnDialogueRunner
@onready var language_menu: OptionButton = $UI/LanguageMenu
@onready var start_button: Button = $UI/StartButton

## available languages with their locale codes (godot format)
var languages := {
	"English": "en",
	"Deutsch": "de",
	"中文": "zh",
	"Portugues (BR)": "pt_BR"
}


func _ready() -> void:
	# set audio path template for godot localisation
	dialogue_runner.set_audio_path_template("res://samples/voice_over/dialogue/audio/{locale}/")

	# add strings to TranslationServer for each locale
	_setup_translations()

	# populate language menu
	_setup_language_menu()

	# connect signals
	start_button.pressed.connect(_on_start_pressed)
	language_menu.item_selected.connect(_on_language_selected)
	# note: dialogue_completed signal is connected in the scene file

	# set initial locale
	TranslationServer.set_locale("en")


func _setup_translations() -> void:
	# add English strings to TranslationServer
	dialogue_runner.add_strings_to_translation_server("en")

	# for other languages, load from CSV and add to TranslationServer
	#
	# IN A REAL PROJECT, you would use Godot's built-in translation import system:
	#
	# 1. Export your Yarn strings to CSV using:
	#    dialogue_runner.export_strings_to_csv("res://translations/yarn_strings.csv")
	#
	# 2. Send the CSV to translators. They fill in the translated text column.
	#
	# 3. Save translated CSVs with locale suffix (e.g., yarn_strings.de.csv, yarn_strings.zh.csv)
	#    OR use a single CSV with multiple columns (one per language).
	#
	# 4. In Godot, go to Project Settings > Localization > Translations
	#    - Click "Add..." and select your translated CSV files
	#    - Godot will automatically import them as Translation resources
	#
	# 5. The translations are now available via TranslationServer.tr("YARN_line:abc123")
	#    Yarn Spinner's Godot localisation mode uses this automatically.
	#
	# 6. For remaps (audio files per locale), go to Project Settings > Localization > Remaps
	#    - Add your base audio file, then add locale-specific versions
	#    - Godot will automatically load the correct audio based on current locale
	#
	# This sample manually loads CSVs for demonstration purposes only:
	_add_translation_from_csv("res://samples/voice_over/dialogue/VoiceOver-de.csv", "de")
	_add_translation_from_csv("res://samples/voice_over/dialogue/VoiceOver-zh.csv", "zh")
	_add_translation_from_csv("res://samples/voice_over/dialogue/VoiceOver-pt_BR.csv", "pt_BR")


func _add_translation_from_csv(path: String, locale: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open translation file: %s" % path)
		return

	var translation := Translation.new()
	translation.locale = locale

	# skip header
	var _header := file.get_csv_line()

	# read translations
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 2 and not row[0].is_empty():
			var key := "YARN_" + row[0]  # add prefix
			var text := row[1]
			translation.add_message(key, text)

	file.close()

	TranslationServer.add_translation(translation)


func _setup_language_menu() -> void:
	language_menu.clear()
	var idx := 0
	for lang_name in languages:
		language_menu.add_item(lang_name, idx)
		idx += 1


func _on_start_pressed() -> void:
	start_button.visible = false
	language_menu.visible = false
	dialogue_runner.start_dialogue("Start")


func _on_language_selected(index: int) -> void:
	var lang_name := language_menu.get_item_text(index)
	var locale: String = languages[lang_name]
	TranslationServer.set_locale(locale)
	print("Language set to: %s (%s)" % [lang_name, locale])


func _on_dialogue_completed() -> void:
	# show UI again after dialogue ends
	start_button.visible = true
	language_menu.visible = true


func _input(event: InputEvent) -> void:
	# quick language switch with number keys (for testing)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				TranslationServer.set_locale("en")
				print("Switched to English")
			KEY_2:
				TranslationServer.set_locale("de")
				print("Switched to German")
			KEY_3:
				TranslationServer.set_locale("zh")
				print("Switched to Chinese")
			KEY_4:
				TranslationServer.set_locale("pt_BR")
				print("Switched to Portuguese (BR)")
