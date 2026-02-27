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

class_name YarnLocalisation
extends RefCounted
## Base class for yarn spinner localisation providers.

enum Type {
	GODOT,
}

signal locale_changed(new_locale: String)


func get_current_locale() -> String:
	return ""


func set_current_locale(_locale: String) -> void:
	pass


func get_localised_text(_line_id: String) -> String:
	return ""


func has_localised_text(_line_id: String) -> bool:
	return false


func get_available_locales() -> PackedStringArray:
	return PackedStringArray()


func has_locale(_locale: String) -> bool:
	return false


func prepare_for_lines(_line_ids: PackedStringArray) -> void:
	pass


func get_localised_audio(_line_id: String) -> AudioStream:
	return null


func has_localised_audio(_line_id: String) -> bool:
	return false
