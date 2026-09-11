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

class_name YarnActionDiscovery
extends RefCounted


const REGISTRY_PATH := "res://addons/yarn_spinner/yarn_action_scripts.json"
const REGISTRY_VERSION := 1

static var _scripts: Array[Script] = []
static var _scanned: bool = false
static var _declaration_regex: RegEx


static func get_action_scripts() -> Array[Script]:
	if _scanned:
		return _scripts
	_scanned = true

	var registry := load_registry(REGISTRY_PATH)
	var paths: PackedStringArray = registry.scripts if registry.found else find_action_script_paths()
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script != null:
			_scripts.append(script)

	return _scripts


static func find_action_script_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	var global_classes := ProjectSettings.get_global_class_list()

	var classes := {}
	for class_info in global_classes:
		classes[String(class_info.get("class", ""))] = class_info

	for class_info in global_classes:
		var path: String = class_info.get("path", "")
		if path.is_empty() or not path.ends_with(".gd"):
			continue
		if is_editor_class(String(class_info.get("class", "")), classes):
			continue
		if not ResourceLoader.exists(path):
			continue
		var source := read_script_source(path)
		if not source.is_empty() and not declares_yarn_action(source):
			continue
		paths.append(path)

	return paths


static func build_registry() -> String:
	return JSON.stringify({
		"version": REGISTRY_VERSION,
		"scripts": Array(find_action_script_paths()),
	}, "\t")


static func load_registry(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"found": false, "scripts": PackedStringArray()}

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_warning("yarn spinner: ignoring unreadable command registry at %s" % path)
		return {"found": false, "scripts": PackedStringArray()}

	var registry: Dictionary = json.data
	var scripts: Variant = registry.get("scripts")
	if int(registry.get("version", 0)) != REGISTRY_VERSION or not (scripts is Array):
		push_warning("yarn spinner: ignoring unreadable command registry at %s" % path)
		return {"found": false, "scripts": PackedStringArray()}

	return {"found": true, "scripts": PackedStringArray(scripts)}


static func declares_yarn_action(source: String) -> bool:
	if _declaration_regex == null:
		_declaration_regex = RegEx.create_from_string("(?m)^[ \\t]*(static[ \\t]+)?func[ \\t]+_yarn_(command|function)_")
	return _declaration_regex.search(source) != null


static func is_editor_class(script_class: String, classes: Dictionary) -> bool:
	var current := script_class
	for i in range(64):
		if not classes.has(current):
			return current.begins_with("Editor")
		current = String(classes[current].get("base", ""))
	return false


static func read_script_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
