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
## Adds a branded Yarn Spinner header to the YarnDialogueRunner inspector.

const YarnNodePickerProperty := preload("res://addons/yarn_spinner/editor/yarn_node_picker_property.gd")


var _edited_object: Object


func _can_handle(object: Object) -> bool:
	return object is YarnDialogueRunner


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
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Logo
	var logo_texture: Texture2D = null
	if ResourceLoader.exists("res://addons/yarn_spinner/icons/YarnSpinnerLogo.png"):
		logo_texture = load("res://addons/yarn_spinner/icons/YarnSpinnerLogo.png")

	if logo_texture:
		var aspect := float(logo_texture.get_height()) / float(logo_texture.get_width())
		var max_logo_width := 500.0
		var min_visible_width := 150.0
		var logo := TextureRect.new()
		logo.texture = logo_texture
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		container.add_child(logo)

		# Responsive logo: shrinks with container, capped at max, hides when tiny
		var _update_logo := func() -> void:
			var available_w := container.size.x
			if available_w < min_visible_width:
				logo.visible = false
				logo.custom_minimum_size = Vector2.ZERO
			else:
				logo.visible = true
				var w := minf(available_w, max_logo_width)
				logo.custom_minimum_size = Vector2(w, w * aspect)
		container.resized.connect(_update_logo)
		container.ready.connect(_update_logo)

	# Links row using RichTextLabel for consistent alignment
	var links_label := RichTextLabel.new()
	links_label.bbcode_enabled = true
	links_label.fit_content = true
	links_label.scroll_active = false
	links_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	links_label.meta_clicked.connect(func(meta: Variant) -> void:
		OS.shell_open(str(meta))
	)

	var link_color := "#4c8962"
	var sep_color := "#4c896280"
	var dot := " [color=%s]\u00b7[/color] " % sep_color

	var parts: Array[String] = []
	var links := [
		["Docs", "https://docs.yarnspinner.dev/"],
		["Samples", "https://github.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript/tree/main/samples"],
		["Discord", "https://discord.com/invite/yarnspinner"],
		["Tell us about your game!", "https://yarnspinner.dev/tell-us"],
	]
	for link in links:
		parts.append("[url=%s][color=%s]%s[/color][/url]" % [link[1], link_color, link[0]])

	links_label.text = "[center]%s[/center]" % dot.join(parts)
	container.add_child(links_label)

	# Bottom separator
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	container.add_child(separator)

	add_custom_control(container)
