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

@icon("res://addons/yarn_spinner/icons/option_item.svg")
class_name YarnOptionButton
extends Button
## option button for dialogue choices: plain grey text that turns white
## with a dot indicator while focused. hovering focuses the button.

## shown while the button has focus.
@export var selection_indicator: Control

@export var text_label: RichTextLabel

var _base_minimum_size: Vector2


func _ready() -> void:
	focus_entered.connect(_update_indicator)
	focus_exited.connect(_update_indicator)
	mouse_entered.connect(_on_mouse_entered)
	draw.connect(_sync_text_label_colour)
	_base_minimum_size = custom_minimum_size
	if text_label != null:
		text_label.minimum_size_changed.connect(_sync_minimum_size)
	_sync_text_label_font()
	_update_indicator()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_sync_text_label_font()


func set_option_text(bbcode: String, plain_text: String, struck_through: bool = false) -> void:
	if text_label == null:
		text = plain_text
		return
	text = ""
	text_label.text = "[s]%s[/s]" % bbcode if struck_through else bbcode
	_sync_text_label_colour()


func _sync_minimum_size() -> void:
	if text_label == null or not text_label.fit_content:
		return
	var wanted := text_label.get_combined_minimum_size() + get_theme_stylebox("normal").get_minimum_size()
	custom_minimum_size = Vector2(maxf(_base_minimum_size.x, wanted.x), maxf(_base_minimum_size.y, wanted.y))


func get_option_text() -> String:
	if text_label != null:
		return text_label.get_parsed_text()
	return text


func _on_mouse_entered() -> void:
	if not disabled:
		grab_focus()


func _update_indicator() -> void:
	if selection_indicator != null:
		selection_indicator.visible = has_focus()


func _sync_text_label_colour() -> void:
	if text_label == null:
		return
	var colour := _current_font_colour()
	if text_label.get_theme_color("default_color") != colour:
		text_label.add_theme_color_override("default_color", colour)


func _current_font_colour() -> Color:
	if disabled:
		return get_theme_color("font_disabled_color")
	match get_draw_mode():
		DRAW_PRESSED:
			return get_theme_color("font_pressed_color")
		DRAW_HOVER:
			return get_theme_color("font_hover_color")
		DRAW_HOVER_PRESSED:
			return get_theme_color("font_hover_pressed_color")
	if has_focus():
		return get_theme_color("font_focus_color")
	return get_theme_color("font_color")


func _sync_text_label_font() -> void:
	if text_label == null:
		return
	var font_size := get_theme_font_size("font_size")
	for size_name in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		text_label.add_theme_font_size_override(size_name, font_size)
	if not has_theme_font_override("font"):
		return
	var font := get_theme_font("font")
	text_label.add_theme_font_override("normal_font", font)
	text_label.add_theme_font_override("bold_font", _font_variation(font, true, false))
	text_label.add_theme_font_override("italics_font", _font_variation(font, false, true))
	text_label.add_theme_font_override("bold_italics_font", _font_variation(font, true, true))


static func _font_variation(font: Font, bold: bool, italic: bool) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font
	if bold:
		variation.variation_embolden = 0.8
	if italic:
		variation.variation_transform = Transform2D(Vector2(1.0, 0.2), Vector2(0.0, 1.0), Vector2.ZERO)
	return variation
