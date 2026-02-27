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

@tool
extends VBoxContainer
## Simple text editor for .yarn files.
## Embeds in the editor as a bottom panel.

var _current_path: String = ""
var _is_dirty: bool = false

var _toolbar: HBoxContainer
var _path_label: Label
var _save_button: Button
var _reload_button: Button
var _code_edit: CodeEdit


func _ready() -> void:
	_toolbar = HBoxContainer.new()
	add_child(_toolbar)

	_path_label = Label.new()
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.text = "No file"
	_toolbar.add_child(_path_label)

	_reload_button = Button.new()
	_reload_button.text = "Reload"
	_reload_button.pressed.connect(_on_reload_pressed)
	_toolbar.add_child(_reload_button)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(_on_save_pressed)
	_toolbar.add_child(_save_button)

	_code_edit = CodeEdit.new()
	_code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code_edit.gutters_draw_line_numbers = true
	_code_edit.draw_tabs = true
	_code_edit.minimap_draw = true
	_code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code_edit.placeholder_text = "Double-click a .yarn file to edit it here..."
	_code_edit.text_changed.connect(_on_text_changed)
	add_child(_code_edit)

	_update_ui()


func edit_file(path: String) -> void:
	if _code_edit == null:
		return

	if _is_dirty and path != _current_path:
		# TODO: prompt to save
		pass

	_current_path = path
	_reload_file()
	_update_ui()


func _reload_file() -> void:
	if _code_edit == null:
		return

	if _current_path.is_empty():
		_code_edit.text = ""
		return

	var file := FileAccess.open(_current_path, FileAccess.READ)
	if file == null:
		push_error("YarnEditor: Failed to open %s: %s" % [_current_path, error_string(FileAccess.get_open_error())])
		return

	_code_edit.text = file.get_as_text()
	file.close()
	_is_dirty = false
	_update_ui()


func _save_file() -> void:
	if _current_path.is_empty():
		return

	var file := FileAccess.open(_current_path, FileAccess.WRITE)
	if file == null:
		push_error("YarnEditor: Failed to save %s: %s" % [_current_path, error_string(FileAccess.get_open_error())])
		return

	file.store_string(_code_edit.text)
	file.close()
	_is_dirty = false
	_update_ui()

	EditorInterface.get_resource_filesystem().scan()
	print("YarnEditor: Saved %s" % _current_path)


func _update_ui() -> void:
	if _path_label == null:
		return

	var display_path := _current_path.get_file() if not _current_path.is_empty() else "No file"
	if _is_dirty:
		display_path += " (*)"
	_path_label.text = display_path

	_save_button.disabled = not _is_dirty
	_reload_button.disabled = _current_path.is_empty()


func _on_text_changed() -> void:
	_is_dirty = true
	_update_ui()


func _on_save_pressed() -> void:
	_save_file()


func _on_reload_pressed() -> void:
	_reload_file()


func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.keycode == KEY_S:
			if not _current_path.is_empty():
				_save_file()
				accept_event()
