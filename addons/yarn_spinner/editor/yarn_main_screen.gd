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
extends Control
## Yarn Spinner main editor screen (the "Yarn Spinner" tab in the editor's top bar).
##
## Hosts the .yarn script editor with a project file list and a per-file node
## outline, plus a collapsible Commands & Functions palette. Replaces the former
## "Yarn" and "Yarn Commands" bottom-panel docks.

const YarnCommandsPanel := preload("res://addons/yarn_spinner/editor/yarn_commands_panel.gd")
const YarnSyntaxHighlighter := preload("res://addons/yarn_spinner/editor/yarn_syntax_highlighter.gd")
const YarnProjectImporter := preload("res://addons/yarn_spinner/editor/yarn_project_importer.gd")
const DOCS_URL := "https://docs.yarnspinner.dev"
const EDITOR_URL := "https://yarnspinner.dev/editor"
const NEW_FILE_TEMPLATE := "title: Start\n---\n\n===\n"

# --- editor state ---
var _current_path: String = ""
var _is_dirty: bool = false
var _pending_path: String = ""
var _pending_home: bool = false

# --- toolbar ---
var _welcome_button: Button
var _save_button: Button
var _reload_button: Button
var _commands_toggle: Button
var _samples_button: Button
var _path_label: Label

# --- samples view ---
var _samples_panel: Control
var _samples_grid: GridContainer

# --- file list / node outline ---
var _file_filter: LineEdit
var _file_tree: Tree
var _node_filter: LineEdit
var _node_list: ItemList
## Files grouped by .yarnproject: [{ name: String, project_path: String, files: [res:// paths] }, ...].
## A trailing "(Unassociated)" group collects .yarn files not matched by any project.
var _project_groups: Array = []

# --- editor / commands ---
var _code_edit: CodeEdit
var _empty_state: Control
var _body_split: VSplitContainer
var _commands_panel: Control
var _confirm_dialog: ConfirmationDialog
var _new_file_dialog: FileDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	root.add_child(_build_toolbar())

	_body_split = VSplitContainer.new()
	_body_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_body_split)

	# editor area: [ files + nodes ] | [ code edit ]
	var editor_split := HSplitContainer.new()
	editor_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_split.add_child(editor_split)

	editor_split.add_child(_build_sidebar())
	editor_split.add_child(_build_editor_area())

	# folded-by-default commands palette
	_commands_panel = YarnCommandsPanel.new()
	_commands_panel.custom_minimum_size = Vector2(0, 180)
	_commands_panel.visible = false
	_body_split.add_child(_commands_panel)

	# samples browser: a full-body list shown in place of the editor
	_samples_panel = _build_samples_panel()
	_samples_panel.visible = false
	root.add_child(_samples_panel)

	_build_dialogs()

	_refresh_file_list()
	_update_ui()


# -------------------------------------------------------------------------- #
#  UI construction
# -------------------------------------------------------------------------- #

func _build_toolbar() -> Control:
	var toolbar := HBoxContainer.new()

	_welcome_button = Button.new()
	_welcome_button.text = "Welcome"
	_welcome_button.icon = _editor_icon("ArrowLeft")
	_welcome_button.tooltip_text = "Return to the Yarn Spinner welcome screen"
	_welcome_button.pressed.connect(_go_home)
	toolbar.add_child(_welcome_button)

	toolbar.add_child(VSeparator.new())

	var new_button := Button.new()
	new_button.text = "New"
	new_button.icon = _editor_icon("New")
	new_button.tooltip_text = "Create a new .yarn file"
	new_button.pressed.connect(_on_new_pressed)
	toolbar.add_child(new_button)

	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.icon = _editor_icon("Save")
	_save_button.tooltip_text = "Save the current file (Ctrl+S)"
	_save_button.pressed.connect(_save_file)
	toolbar.add_child(_save_button)

	_reload_button = Button.new()
	_reload_button.text = "Reload"
	_reload_button.icon = _editor_icon("Reload")
	_reload_button.tooltip_text = "Reload the current file from disk"
	_reload_button.pressed.connect(_reload_file)
	toolbar.add_child(_reload_button)

	toolbar.add_child(VSeparator.new())

	_path_label = Label.new()
	_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child(_path_label)

	_commands_toggle = Button.new()
	_commands_toggle.text = "Commands"
	_commands_toggle.icon = _editor_icon("MemberMethod")
	_commands_toggle.toggle_mode = true
	_commands_toggle.tooltip_text = "Show the Commands & Functions palette"
	_commands_toggle.toggled.connect(_on_commands_toggled)
	toolbar.add_child(_commands_toggle)

	_samples_button = Button.new()
	_samples_button.text = "Samples"
	_samples_button.icon = _editor_icon("PlayScene")
	_samples_button.toggle_mode = true
	_samples_button.tooltip_text = "Browse and run the Yarn Spinner samples"
	_samples_button.toggled.connect(_on_samples_toggled)
	toolbar.add_child(_samples_button)

	var docs_button := Button.new()
	docs_button.text = "Docs"
	docs_button.icon = _editor_icon("ExternalLink")
	docs_button.tooltip_text = DOCS_URL
	docs_button.pressed.connect(func() -> void: OS.shell_open(DOCS_URL))
	toolbar.add_child(docs_button)

	return toolbar


func _build_sidebar() -> Control:
	var sidebar := VSplitContainer.new()
	sidebar.custom_minimum_size = Vector2(240, 0)

	# Yarn Projects (groups) → their .yarn scripts
	var files_box := VBoxContainer.new()
	files_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var files_header := Label.new()
	files_header.text = "Yarn Projects"
	files_header.theme_type_variation = "HeaderSmall"
	files_box.add_child(files_header)

	_file_filter = LineEdit.new()
	_file_filter.placeholder_text = "Filter files..."
	_file_filter.clear_button_enabled = true
	_file_filter.right_icon = _editor_icon("Search")
	_file_filter.text_changed.connect(func(_t: String) -> void: _rebuild_file_list())
	files_box.add_child(_file_filter)

	_file_tree = Tree.new()
	_file_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_file_tree.hide_root = true
	_file_tree.allow_reselect = true
	_file_tree.allow_rmb_select = false
	_file_tree.item_selected.connect(_on_file_tree_selected)
	files_box.add_child(_file_tree)
	sidebar.add_child(files_box)

	# Nodes
	var nodes_box := VBoxContainer.new()
	nodes_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nodes_header := Label.new()
	nodes_header.text = "Nodes"
	nodes_header.theme_type_variation = "HeaderSmall"
	nodes_box.add_child(nodes_header)

	_node_filter = LineEdit.new()
	_node_filter.placeholder_text = "Filter nodes..."
	_node_filter.clear_button_enabled = true
	_node_filter.right_icon = _editor_icon("Search")
	_node_filter.text_changed.connect(func(_t: String) -> void: _refresh_node_outline())
	nodes_box.add_child(_node_filter)

	_node_list = ItemList.new()
	_node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_node_list.allow_reselect = true
	_node_list.item_selected.connect(_on_node_selected)
	nodes_box.add_child(_node_list)
	sidebar.add_child(nodes_box)

	return sidebar


func _build_code_edit() -> CodeEdit:
	var code := CodeEdit.new()
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.gutters_draw_line_numbers = true
	code.draw_tabs = true
	code.minimap_draw = true
	code.highlight_current_line = true
	code.highlight_all_occurrences = true
	code.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code.placeholder_text = "Select a .yarn file from the list, or create a new one."
	code.syntax_highlighter = YarnSyntaxHighlighter.new()
	code.text_changed.connect(_on_text_changed)

	# Match the editor's source-code font when available.
	var theme := EditorInterface.get_editor_theme()
	if theme and theme.has_font("source", "EditorFonts"):
		code.add_theme_font_override("font", theme.get_font("source", "EditorFonts"))
		code.add_theme_font_size_override("font_size", theme.get_font_size("source_size", "EditorFonts"))
	return code


## Wraps the CodeEdit and the empty-state callout (the "get the standalone
## editor" card) in the same slot so toggling between them keeps the layout.
func _build_editor_area() -> Control:
	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_code_edit = _build_code_edit()
	_code_edit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(_code_edit)

	_empty_state = _build_empty_state()
	_empty_state.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(_empty_state)

	return wrapper


## Centered card shown when no .yarn file is open — promotes the standalone
## Yarn Spinner Editor (autocomplete / live errors / rename / node graph).
func _build_empty_state() -> Control:
	var scale := EditorInterface.get_editor_scale()
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(int(440 * scale), 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(32 * scale))
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(14 * scale))
	margin.add_child(box)

	var logo := TextureRect.new()
	if ResourceLoader.exists("res://addons/yarn_spinner/icons/YarnSpinnerLogo.png"):
		logo.texture = load("res://addons/yarn_spinner/icons/YarnSpinnerLogo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, int(128 * scale))
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(logo)

	var headline := Label.new()
	headline.text = "The best editing experience for Yarn Spinner"
	headline.theme_type_variation = "HeaderMedium"
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(headline)

	var body := Label.new()
	body.text = "Autocomplete, live error checking, project-wide rename, and visual node-graph editing — in the standalone Yarn Spinner Editor."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.modulate = Color(1, 1, 1, 0.75)
	box.add_child(body)

	var button_row := CenterContainer.new()
	box.add_child(button_row)

	var button := Button.new()
	button.text = "Get it at yarnspinner.dev/editor"
	button.icon = _editor_icon("ExternalLink")
	button.tooltip_text = EDITOR_URL
	button.pressed.connect(func() -> void: OS.shell_open(EDITOR_URL))
	button_row.add_child(button)

	return center


func _build_dialogs() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Unsaved Changes"
	_confirm_dialog.ok_button_text = "Save"
	_confirm_dialog.add_button("Discard", true, "discard")
	_confirm_dialog.confirmed.connect(_on_confirm_save)
	_confirm_dialog.custom_action.connect(_on_confirm_action)
	_confirm_dialog.canceled.connect(_on_confirm_cancel)
	add_child(_confirm_dialog)

	_new_file_dialog = FileDialog.new()
	_new_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_new_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_new_file_dialog.filters = PackedStringArray(["*.yarn ; Yarn Scripts"])
	_new_file_dialog.current_file = "Dialogue.yarn"
	_new_file_dialog.title = "Create Yarn Script"
	_new_file_dialog.file_selected.connect(_on_new_file_selected)
	add_child(_new_file_dialog)


# -------------------------------------------------------------------------- #
#  Public API (called by the plugin)
# -------------------------------------------------------------------------- #

## Open `path` in the editor, loading it from disk. Used by the plugin's _edit().
func edit_file(path: String) -> void:
	if _code_edit == null or path.is_empty():
		return
	# Leave the samples browser if it's open, so the file is actually visible.
	if _samples_button and _samples_button.button_pressed:
		_samples_button.button_pressed = false
	_current_path = path
	_reload_file()
	if not _path_is_known(path):
		_refresh_file_list()
	_select_current_in_file_list()


## Called by the plugin when the tab becomes visible, so the file list stays fresh.
func notify_shown() -> void:
	_refresh_file_list()


# -------------------------------------------------------------------------- #
#  File list (grouped by .yarnproject)
# -------------------------------------------------------------------------- #

func _refresh_file_list() -> void:
	_project_groups.clear()

	var all_yarn := _find_yarn_files("res://")
	var claimed := {}

	# One group per .yarnproject, using its parsed `sourceFiles` globs.
	for project_path in _find_yarn_projects("res://"):
		var abs_project := ProjectSettings.globalize_path(project_path)
		var sources := YarnProjectImporter.parse_project_sources(abs_project, abs_project.get_base_dir())
		var files: Array[String] = []
		for abs in sources:
			var res_path := ProjectSettings.localize_path(abs)
			files.append(res_path)
			claimed[res_path] = true
		files.sort()
		_project_groups.append({
			"name": project_path.get_file().get_basename(),
			"project_path": project_path,
			"files": files,
		})

	# Anything not claimed by any project lands in a trailing "(Unassociated)" group.
	var orphans: Array[String] = []
	for f in all_yarn:
		if not claimed.has(f):
			orphans.append(f)
	if not orphans.is_empty():
		orphans.sort()
		_project_groups.append({
			"name": "(Unassociated)",
			"project_path": "",
			"files": orphans,
		})

	_rebuild_file_list()


const _TREE_KIND_GROUP := "group"
const _TREE_KIND_FILE := "file"


func _rebuild_file_list() -> void:
	if _file_tree == null:
		return
	_file_tree.clear()
	var root := _file_tree.create_item()
	var filter := _file_filter.text.to_lower()

	# Yarn-branded icons make it unambiguous which rows are projects vs scripts.
	# The source SVGs are 256x256 so we cap their rendered width to a tab-sized
	# icon (Godot does not auto-scale TreeItem icons).
	var project_icon: Texture2D = load("res://addons/yarn_spinner/icons/yarn_project.svg")
	var script_icon: Texture2D = load("res://addons/yarn_spinner/icons/yarn_script.svg")
	var orphan_icon: Texture2D = _editor_icon("Folder")
	var icon_w := int(round(16.0 * EditorInterface.get_editor_scale()))

	for group in _project_groups:
		var matched: Array[String] = []
		for path in group.files:
			if filter.is_empty() or path.get_file().to_lower().contains(filter):
				matched.append(path)
		if matched.is_empty():
			continue

		var is_orphan_group: bool = group.project_path == ""
		var header := _file_tree.create_item(root)
		var header_label: String = "Unassociated" if is_orphan_group else group.name
		header.set_text(0, "%s  (%d)" % [header_label, matched.size()])
		header.set_selectable(0, false)
		header.set_metadata(0, {"kind": _TREE_KIND_GROUP})
		if is_orphan_group:
			header.set_icon(0, orphan_icon)
			header.set_icon_modulate(0, Color(1, 1, 1, 0.6))
		else:
			header.set_icon(0, project_icon)
			header.set_icon_max_width(0, icon_w)
			header.set_tooltip_text(0, "Yarn Project — %s" % group.project_path)

		for path in matched:
			var item := _file_tree.create_item(header)
			item.set_text(0, path.get_file())
			item.set_tooltip_text(0, path)
			item.set_icon(0, script_icon)
			item.set_icon_max_width(0, icon_w)
			item.set_metadata(0, {"kind": _TREE_KIND_FILE, "path": path})

	_select_current_in_file_list()


func _select_current_in_file_list() -> void:
	if _file_tree == null:
		return
	var found := _find_tree_item_for(_current_path)
	if found:
		found.select(0)
		_file_tree.scroll_to_item(found)
	else:
		_file_tree.deselect_all()


func _find_tree_item_for(path: String) -> TreeItem:
	if _file_tree == null or _file_tree.get_root() == null or path.is_empty():
		return null
	var group := _file_tree.get_root().get_first_child()
	while group:
		var item := group.get_first_child()
		while item:
			var meta = item.get_metadata(0)
			if meta is Dictionary and meta.get("path", "") == path:
				return item
			item = item.get_next()
		group = group.get_next()
	return null


func _on_file_tree_selected() -> void:
	var item := _file_tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if not (meta is Dictionary) or meta.get("kind", "") != _TREE_KIND_FILE:
		return
	var path: String = meta["path"]
	if path == _current_path:
		return
	if _is_dirty:
		_pending_path = path
		_confirm_dialog.dialog_text = "Save changes to \"%s\" before switching files?" % _current_path.get_file()
		_confirm_dialog.popup_centered()
	else:
		edit_file(path)


func _path_is_known(path: String) -> bool:
	for group in _project_groups:
		if group.files.has(path):
			return true
	return false


# -------------------------------------------------------------------------- #
#  Node outline
# -------------------------------------------------------------------------- #

func _refresh_node_outline() -> void:
	if _node_list == null:
		return
	var previous := ""
	if _node_list.is_anything_selected():
		previous = _node_list.get_item_text(_node_list.get_selected_items()[0])
	_node_list.clear()

	var filter := _node_filter.text.to_lower() if _node_filter else ""
	var lines := _code_edit.text.split("\n")
	var in_header := true
	for i in lines.size():
		var stripped := lines[i].strip_edges()
		if stripped == "---":
			in_header = false
		elif stripped == "===":
			in_header = true
		elif in_header and stripped.begins_with("title:"):
			var node_name := stripped.substr(6).strip_edges()
			if not filter.is_empty() and not node_name.to_lower().contains(filter):
				continue
			var idx := _node_list.add_item(node_name, _editor_icon("Active"))
			_node_list.set_item_metadata(idx, i)
			if node_name == previous:
				_node_list.select(idx)


func _on_node_selected(index: int) -> void:
	var line: int = _node_list.get_item_metadata(index)
	_code_edit.set_caret_line(line)
	_code_edit.set_caret_column(0)
	_code_edit.center_viewport_to_caret()
	_code_edit.grab_focus()


# -------------------------------------------------------------------------- #
#  Load / save
# -------------------------------------------------------------------------- #

func _reload_file() -> void:
	if _code_edit == null or _current_path.is_empty():
		if _code_edit:
			_code_edit.text = ""
		_refresh_node_outline()
		_update_ui()
		return

	var file := FileAccess.open(_current_path, FileAccess.READ)
	if file == null:
		push_error("YarnEditor: failed to open %s: %s" % [_current_path, error_string(FileAccess.get_open_error())])
		return
	_code_edit.text = file.get_as_text()
	file.close()
	_is_dirty = false
	_refresh_node_outline()
	_update_ui()


func _save_file() -> void:
	if _current_path.is_empty():
		return
	var file := FileAccess.open(_current_path, FileAccess.WRITE)
	if file == null:
		push_error("YarnEditor: failed to save %s: %s" % [_current_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(_code_edit.text)
	file.close()
	_is_dirty = false
	_update_ui()
	EditorInterface.get_resource_filesystem().scan()
	print("YarnEditor: saved %s" % _current_path)


func _on_text_changed() -> void:
	_is_dirty = true
	_refresh_node_outline()
	_update_ui()


func _update_ui() -> void:
	if _path_label == null:
		return
	var display := _current_path.get_file() if not _current_path.is_empty() else "No file open"
	if _is_dirty:
		display += " (*)"
	_path_label.text = display
	_save_button.disabled = not _is_dirty
	_reload_button.disabled = _current_path.is_empty()
	_code_edit.editable = not _current_path.is_empty()

	# Show the "Yarn Spinner Editor" callout only when nothing is being edited.
	var no_file := _current_path.is_empty()
	if _empty_state:
		_empty_state.visible = no_file
	_code_edit.visible = not no_file
	if _welcome_button:
		_welcome_button.disabled = no_file


# -------------------------------------------------------------------------- #
#  Confirm-on-switch
# -------------------------------------------------------------------------- #

func _on_confirm_save() -> void:
	_save_file()
	_open_pending()


func _on_confirm_action(action: StringName) -> void:
	if action == &"discard":
		_is_dirty = false
		_confirm_dialog.hide()
		_open_pending()


func _on_confirm_cancel() -> void:
	_pending_path = ""
	_pending_home = false
	_select_current_in_file_list()


func _open_pending() -> void:
	if _pending_home:
		_pending_home = false
		_pending_path = ""
		_do_go_home()
		return
	if _pending_path.is_empty():
		return
	var path := _pending_path
	_pending_path = ""
	edit_file(path)


## Return to the empty-state callout. Prompts to save first if there are
## unsaved changes (re-using the file-switch confirm dialog).
func _go_home() -> void:
	if _current_path.is_empty():
		return
	if _is_dirty:
		_pending_home = true
		_pending_path = ""
		_confirm_dialog.dialog_text = "Save changes to \"%s\" before leaving?" % _current_path.get_file()
		_confirm_dialog.popup_centered()
	else:
		_do_go_home()


func _do_go_home() -> void:
	_current_path = ""
	_is_dirty = false
	_code_edit.text = ""
	_refresh_node_outline()
	_select_current_in_file_list()
	_update_ui()


# -------------------------------------------------------------------------- #
#  Commands palette (collapsible)
# -------------------------------------------------------------------------- #

func _on_commands_toggled(pressed: bool) -> void:
	_commands_panel.visible = pressed
	if pressed:
		_commands_panel._refresh()
		_position_commands_split.call_deferred()


func _position_commands_split() -> void:
	if _body_split.size.y > 320:
		_body_split.split_offset = int(_body_split.size.y) - 240


# -------------------------------------------------------------------------- #
#  Samples browser
# -------------------------------------------------------------------------- #

const SAMPLES_DOCS_URL := "https://yarnspinner.dev/docs/godot/samples"

const SAMPLE_CARD_WIDTH := 268.0
const SAMPLE_THUMB_HEIGHT := 150.0
const SAMPLE_THUMB_OVERRIDES := ["thumbnail.png", "thumbnail.jpg", "screenshot.png", "screenshot.jpg"]

## The order samples appear in the gallery: a learning path from first steps
## through core features, presentation, voice, and finally saliency. Folders
## not listed here sort after these, alphabetically.
const SAMPLE_ORDER := [
	"welcome",
	"yarn_basics",
	"simple_3d",
	"feature_tour",
	"commands_and_functions",
	"instance_commands",
	"inline_events",
	"node_internals",
	"replacement_markup",
	"themed_line_presenter",
	"options_that_timeout",
	"phone_chat",
	"background-chatter",
	"voice_over",
	"voice_over_3d",
	"basic-saliency",
	"custom-saliency",
	"advanced_saliency",
]

## One-line blurbs shown on each sample card, keyed by folder name.
const SAMPLE_DESCRIPTIONS := {
	"advanced_saliency": "Set the cast, the room and the scenario, then watch saliency stage the right scene.",
	"background-chatter": "Ambient NPC conversations play out around you, each line floating above its speaker.",
	"basic-saliency": "Characters change what they say with the day and time, using node and line groups.",
	"commands_and_functions": "Drive your game from Yarn with custom commands, and read game state back with functions.",
	"custom-saliency": "Write your own saliency strategy to decide which content gets chosen.",
	"feature_tour": "A guided, room-by-room walk through every major Yarn Spinner feature.",
	"inline_events": "Fire game events like movement and emotions from right inside a line of dialogue.",
	"instance_commands": "Commands that target a specific object instance in the scene.",
	"node_internals": "Peek at node titles, headers and metadata from the running dialogue.",
	"options_that_timeout": "Options that expire if the player takes too long to choose.",
	"phone_chat": "A texting conversation told in chat bubbles, typing indicator and all.",
	"replacement_markup": "Custom markup that swaps text for icons and richly styled spans.",
	"simple_3d": "The smallest possible 3D scene that runs a single Yarn line.",
	"themed_line_presenter": "Restyle the built-in line presenter to match the look of your game.",
	"voice_over_3d": "Recorded voice-over synced to lines in a 3D scene.",
	"voice_over": "Play recorded voice-over alongside each spoken line.",
	"welcome": "A friendly starting point that introduces the basics of Yarn Spinner.",
	"yarn_basics": "The fundamentals: nodes, lines, options and jumps.",
}

# A small rotating palette so placeholder thumbnails feel intentional, not blank.
const SAMPLE_ACCENTS := [
	Color("e36588"), Color("6794d9"), Color("8bc34a"), Color("ffb74d"),
	Color("ba68c8"), Color("4dd0e1"), Color("f06292"), Color("9ccc65"),
]


func _build_samples_panel() -> Control:
	var scale := EditorInterface.get_editor_scale()

	var panel := MarginContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		panel.add_theme_constant_override("margin_" + side, int(16 * scale))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(4 * scale))
	panel.add_child(box)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", int(12 * scale))
	box.add_child(header_row)

	var header := Label.new()
	header.text = "Samples"
	header.theme_type_variation = "HeaderLarge"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)

	var docs_link := LinkButton.new()
	docs_link.text = "Samples documentation"
	docs_link.uri = SAMPLES_DOCS_URL
	docs_link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	docs_link.tooltip_text = SAMPLES_DOCS_URL
	docs_link.size_flags_vertical = Control.SIZE_SHRINK_END
	header_row.add_child(docs_link)

	var hint := Label.new()
	hint.text = "Run a sample to see Yarn Spinner in action, or open its scene to see how it's built."
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, int(8 * scale))
	box.add_child(spacer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_samples_grid = GridContainer.new()
	_samples_grid.columns = 4
	_samples_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_samples_grid.add_theme_constant_override("h_separation", int(14 * scale))
	_samples_grid.add_theme_constant_override("v_separation", int(14 * scale))
	_samples_grid.resized.connect(_update_samples_columns)
	scroll.add_child(_samples_grid)

	return panel


## Keeps cards filling each row: 4 columns when four fit at their minimum width,
## otherwise 3. Cards stretch to share the row, so there's never a ragged edge.
func _update_samples_columns() -> void:
	if _samples_grid == null:
		return
	var scale := EditorInterface.get_editor_scale()
	var min_card := 190.0 * scale
	var sep := 14.0 * scale
	var cols := 4 if _samples_grid.size.x >= 4.0 * min_card + 3.0 * sep else 3
	if _samples_grid.columns != cols:
		_samples_grid.columns = cols


func _on_samples_toggled(pressed: bool) -> void:
	if _samples_panel == null:
		return
	_samples_panel.visible = pressed
	_body_split.visible = not pressed
	if pressed:
		_refresh_samples()


func _refresh_samples() -> void:
	if _samples_grid == null:
		return
	for child in _samples_grid.get_children():
		child.queue_free()

	var samples := _find_samples()
	if samples.is_empty():
		var empty := Label.new()
		empty.text = "No samples found under res://samples/."
		empty.modulate = Color(1, 1, 1, 0.6)
		_samples_grid.add_child(empty)
		return

	for i in samples.size():
		_samples_grid.add_child(_build_sample_card(samples[i], i))
	_update_samples_columns.call_deferred()


func _build_sample_card(sample: Dictionary, index: int) -> Control:
	var scale := EditorInterface.get_editor_scale()
	var accent: Color = SAMPLE_ACCENTS[index % SAMPLE_ACCENTS.size()]

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(int(190 * scale), 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _sample_card_style(false))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(func() -> void:
		card.add_theme_stylebox_override("panel", _sample_card_style(true)))
	card.mouse_exited.connect(func() -> void:
		card.add_theme_stylebox_override("panel", _sample_card_style(false)))

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)

	# Thumbnail: a real scene preview when we can get one, an accent placeholder until then.
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0, int(SAMPLE_THUMB_HEIGHT * scale))
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	thumb.clip_contents = true
	thumb.texture = _sample_placeholder(sample.name, accent)
	# Grow the thumbnail's height with its width so it keeps a 16:9 feel.
	thumb.resized.connect(func() -> void:
		var h := int(thumb.size.x * SAMPLE_THUMB_HEIGHT / SAMPLE_CARD_WIDTH)
		if absi(int(thumb.custom_minimum_size.y) - h) > 1:
			thumb.custom_minimum_size.y = h)
	body.add_child(thumb)
	_request_sample_thumbnail(sample, thumb)

	var text_margin := MarginContainer.new()
	for side in ["left", "right"]:
		text_margin.add_theme_constant_override("margin_" + side, int(12 * scale))
	text_margin.add_theme_constant_override("margin_top", int(10 * scale))
	text_margin.add_theme_constant_override("margin_bottom", int(12 * scale))
	# Fill the card so the description absorbs spare height and the buttons sit
	# on the bottom edge, keeping every row's buttons aligned.
	text_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(text_margin)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", int(4 * scale))
	text_margin.add_child(text)

	var name_label := Label.new()
	name_label.text = sample.name
	name_label.theme_type_variation = "HeaderSmall"
	text.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = SAMPLE_DESCRIPTIONS.get(sample.folder, sample.scene.trim_prefix("res://samples/"))
	desc_label.modulate = Color(1, 1, 1, 0.6)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(0, int(52 * scale))
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.add_child(desc_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(6 * scale))
	text.add_child(buttons)

	var card_docs := LinkButton.new()
	card_docs.text = "Docs"
	card_docs.uri = SAMPLES_DOCS_URL + "/" + sample.folder.replace("_", "-")
	card_docs.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	card_docs.tooltip_text = card_docs.uri
	card_docs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_docs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_child(card_docs)

	var open_button := Button.new()
	open_button.text = "Open"
	open_button.icon = _editor_icon("Load")
	open_button.tooltip_text = "Open this sample's scene in the editor"
	open_button.pressed.connect(_open_sample.bind(sample.scene))
	buttons.add_child(open_button)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.icon = _editor_icon("Play")
	play_button.tooltip_text = "Run this sample"
	play_button.pressed.connect(_play_sample.bind(sample.scene))
	buttons.add_child(play_button)

	return card


func _sample_card_style(hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var base := Color(0.16, 0.17, 0.21)
	var theme := EditorInterface.get_editor_theme()
	if theme and theme.has_color("base_color", "Editor"):
		base = theme.get_color("base_color", "Editor")
	sb.bg_color = base.lightened(0.07) if hovered else base.lightened(0.02)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(0)
	sb.border_color = Color(1, 1, 1, 0.12) if hovered else Color(1, 1, 1, 0.05)
	sb.set_border_width_all(1)
	return sb


## Builds a tidy accent gradient with the sample's initial, used until (or unless)
## a real scene preview is available.
func _sample_placeholder(display_name: String, accent: Color) -> Texture2D:
	var w := 268
	var h := 150
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var top := accent.darkened(0.35)
	var bottom := accent.darkened(0.6)
	for y in h:
		var row := top.lerp(bottom, float(y) / float(h - 1))
		for x in w:
			img.set_pixel(x, y, row)
	return ImageTexture.create_from_image(img)


## Uses the sample's bundled screenshot (thumbnail.png / screenshot.png). Falls
## back to the accent placeholder set by the caller when none is present.
func _request_sample_thumbnail(sample: Dictionary, target: TextureRect) -> void:
	var folder_path := "res://samples".path_join(sample.folder)
	for name in SAMPLE_THUMB_OVERRIDES:
		var candidate := folder_path.path_join(name)
		if ResourceLoader.exists(candidate):
			var tex := load(candidate)
			if tex is Texture2D:
				target.texture = tex
				return


func _play_sample(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("YarnEditor: sample scene not found: %s" % scene_path)
		return
	EditorInterface.play_custom_scene(scene_path)


func _open_sample(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		return
	EditorInterface.open_scene_from_path(scene_path)
	# Opening leaves us on the Yarn Spinner tab; switch to the scene editor so
	# the opened scene is actually visible.
	_show_opened_scene.call_deferred()


func _show_opened_scene() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root is CanvasItem:
		EditorInterface.set_main_screen_editor("2D")
	else:
		EditorInterface.set_main_screen_editor("3D")


## Finds each sample folder under res://samples/ (excluding shared) and its
## entry scene, returning [{ name, scene }] in [constant SAMPLE_ORDER] order.
func _find_samples() -> Array:
	var samples: Array = []
	var base := "res://samples"
	var dir := DirAccess.open(base)
	if dir == null:
		return samples
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and not entry.begins_with(".") and entry != "shared":
			var scene := _find_sample_scene(base.path_join(entry), entry)
			if not scene.is_empty():
				samples.append({"name": entry.replace("-", "_").capitalize(), "scene": scene, "folder": entry})
		entry = dir.get_next()
	dir.list_dir_end()
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia := SAMPLE_ORDER.find(a.folder)
		var ib := SAMPLE_ORDER.find(b.folder)
		if ia < 0 and ib < 0:
			return a.name < b.name
		if ia < 0 or ib < 0:
			return ib < 0
		return ia < ib)
	return samples


## Picks the entry scene for a sample: a scene named after the folder (with an
## optional "_sample" suffix, in the folder or a scenes/ subfolder), else the
## first .tscn found in the folder or its scenes/ subfolder.
func _find_sample_scene(dir_path: String, folder: String) -> String:
	var candidates := [
		dir_path.path_join(folder + ".tscn"),
		dir_path.path_join("scenes").path_join(folder + ".tscn"),
		dir_path.path_join(folder + "_sample.tscn"),
		dir_path.path_join("scenes").path_join(folder + "_sample.tscn"),
	]
	for candidate in candidates:
		if ResourceLoader.exists(candidate):
			return candidate
	var found := _first_tscn(dir_path)
	if not found.is_empty():
		return found
	return _first_tscn(dir_path.path_join("scenes"))


func _first_tscn(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	var found: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.ends_with(".tscn"):
			found.append(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found[0] if not found.is_empty() else ""


# -------------------------------------------------------------------------- #
#  New file
# -------------------------------------------------------------------------- #

func _on_new_pressed() -> void:
	_new_file_dialog.popup_centered(Vector2i(700, 480))


func _on_new_file_selected(path: String) -> void:
	if not path.ends_with(".yarn"):
		path += ".yarn"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("YarnEditor: failed to create %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(NEW_FILE_TEMPLATE)
	file.close()
	EditorInterface.get_resource_filesystem().scan()
	edit_file(path)


# -------------------------------------------------------------------------- #
#  Helpers
# -------------------------------------------------------------------------- #

func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
		if not _current_path.is_empty():
			_save_file()
			accept_event()


func _editor_icon(icon_name: String) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	if theme and theme.has_icon(icon_name, "EditorIcons"):
		return theme.get_icon(icon_name, "EditorIcons")
	return null


func _find_yarn_files(root: String) -> PackedStringArray:
	var results := PackedStringArray()
	_find_yarn_files_recursive(root, results)
	results.sort()
	return results


func _find_yarn_files_recursive(dir_path: String, results: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != "addons":
				_find_yarn_files_recursive(full_path, results)
		elif file_name.ends_with(".yarn"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()


func _find_yarn_projects(root: String) -> PackedStringArray:
	var results := PackedStringArray()
	_find_yarn_projects_recursive(root, results)
	results.sort()
	return results


func _find_yarn_projects_recursive(dir_path: String, results: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != "addons":
				_find_yarn_projects_recursive(full_path, results)
		elif file_name.ends_with(".yarnproject"):
			results.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
