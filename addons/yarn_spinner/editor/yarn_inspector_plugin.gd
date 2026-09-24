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
extends EditorInspectorPlugin
## Adds a branded Yarn Spinner header to the YarnDialogueRunner, Yarn script,
## and .ysls.json inspectors.

const YarnNodePickerProperty := preload("res://addons/yarn_spinner/editor/yarn_node_picker_property.gd")
const YarnInspectorHeader := preload("res://addons/yarn_spinner/editor/yarn_inspector_header.gd")


var _edited_object: Object


func _can_handle(object: Object) -> bool:
	if object is YarnDialogueRunner or object is YarnScriptResource:
		return true
	return object is JSON and (object as JSON).resource_path.ends_with(".ysls.json")


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name == "yarn_project":
		_edited_object = object
	if name == "start_node":
		# Insert the browse button right before start_node (i.e. after yarn_project)
		var button := Button.new()
		button.text = "Select Project File..."
		button.tooltip_text = "Browse for a .yarnproject file"
		button.pressed.connect(_on_browse_project)
		add_custom_control(button)
		var picker := YarnNodePickerProperty.new()
		add_property_editor("start_node", picker)
		return true
	return false


func _on_browse_project() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.yarnproject", "Yarn Project")
	dialog.title = "Select Yarn Project"

	if _edited_object and _edited_object.get("yarn_project") is Resource:
		var res_path: String = _edited_object.get("yarn_project").resource_path
		if not res_path.is_empty():
			dialog.current_dir = res_path.get_base_dir()

	dialog.file_selected.connect(func(path: String) -> void:
		var resource := load(path)
		if resource != null and _edited_object:
			_edited_object.set("yarn_project", resource)
			# Notify the inspector to refresh
			EditorInterface.get_inspector().edit(_edited_object)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
	)

	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _parse_begin(object: Object) -> void:
	add_custom_control(YarnInspectorHeader.create())
