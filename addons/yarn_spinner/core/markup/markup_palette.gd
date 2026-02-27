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

class_name YarnMarkupPalette
extends Resource
## a collection of marker names and formatting styles for the palette processor.
## supports basic markers (colour, bold, italic, etc.) and custom markers
## (arbitrary start/end tag strings).


## simple formatting with colour, bold, italic, underline, strikethrough.
class BasicMarker extends RefCounted:
	var marker: String = ""
	var custom_color: bool = false
	var color: Color = Color.WHITE
	var boldened: bool = false
	var italicised: bool = false
	var underlined: bool = false
	var strikedthrough: bool = false
	func _init(
		marker_name: String = "",
		use_color: bool = false,
		marker_color: Color = Color.WHITE,
		bold: bool = false,
		italic: bool = false,
		underline: bool = false,
		strikethrough: bool = false
	) -> void:
		marker = marker_name
		custom_color = use_color
		color = marker_color
		boldened = bold
		italicised = italic
		underlined = underline
		strikedthrough = strikethrough


## arbitrary start/end tag strings for complex formatting effects.
class CustomMarker extends RefCounted:
	var marker: String = ""
	var start: String = ""
	var end: String = ""
	## visible characters added at start (for attribute position adjustment).
	var marker_offset: int = 0
	## total visible characters added by start and end combined.
	var total_visible_character_count: int = 0
	func _init(
		marker_name: String = "",
		start_tags: String = "",
		end_tags: String = "",
		offset: int = 0,
		visible_chars: int = 0
	) -> void:
		marker = marker_name
		start = start_tags
		end = end_tags
		marker_offset = offset
		total_visible_character_count = visible_chars


## basic markers stored as dictionaries for inspector editing.
@export var basic_markers: Array[Dictionary] = []

## custom markers stored as dictionaries for inspector editing.
@export var custom_markers: Array[Dictionary] = []

var _basic_markers_cache: Array[BasicMarker] = []
var _custom_markers_cache: Array[CustomMarker] = []
var _cache_built: bool = false


## builds internal caches from exported dictionary arrays (called lazily).
func _build_cache() -> void:
	if _cache_built:
		return

	_basic_markers_cache.clear()
	for dict in basic_markers:
		var bm := BasicMarker.new(
			dict.get("marker", ""),
			dict.get("custom_color", false),
			dict.get("color", Color.WHITE),
			dict.get("boldened", false),
			dict.get("italicised", false),
			dict.get("underlined", false),
			dict.get("strikedthrough", false)
		)
		_basic_markers_cache.append(bm)

	_custom_markers_cache.clear()
	for dict in custom_markers:
		var cm := CustomMarker.new(
			dict.get("marker", ""),
			dict.get("start", ""),
			dict.get("end", ""),
			dict.get("marker_offset", 0),
			dict.get("total_visible_character_count", 0)
		)
		_custom_markers_cache.append(cm)

	_cache_built = true


## returns {"found": bool, "color": Color} for a marker name.
func color_for_marker(marker_name: String) -> Dictionary:
	_build_cache()

	for item in _basic_markers_cache:
		if item.marker == marker_name:
			return {"found": true, "color": item.color}

	return {"found": false, "color": Color.BLACK}


## returns formatting as start/end tags for a marker name.
## basic markers are converted to bbcode; custom markers return as-is.
func palette_for_marker(marker_name: String) -> Dictionary:
	_build_cache()

	for item in _basic_markers_cache:
		if item.marker == marker_name:
			var front := ""
			var back := ""

			# closing tags are prepended so they nest properly
			if item.custom_color:
				front += "[color=#%s]" % item.color.to_html(false)
				back = "[/color]" + back
			if item.boldened:
				front += "[b]"
				back = "[/b]" + back
			if item.italicised:
				front += "[i]"
				back = "[/i]" + back
			if item.underlined:
				front += "[u]"
				back = "[/u]" + back
			if item.strikedthrough:
				front += "[s]"
				back = "[/s]" + back

			return {
				"found": true,
				"marker": item.marker,
				"start": front,
				"end": back,
				"marker_offset": 0,
				"total_visible_character_count": 0
			}

	for item in _custom_markers_cache:
		if item.marker == marker_name:
			return {
				"found": true,
				"marker": item.marker,
				"start": item.start,
				"end": item.end,
				"marker_offset": item.marker_offset,
				"total_visible_character_count": item.total_visible_character_count
			}

	return {"found": false}


## adds a basic marker at runtime (added to both cache and exported array).
func add_basic_marker(
	marker_name: String,
	use_color: bool = false,
	marker_color: Color = Color.WHITE,
	bold: bool = false,
	italic: bool = false,
	underline: bool = false,
	strikethrough: bool = false
) -> void:
	var bm := BasicMarker.new(marker_name, use_color, marker_color, bold, italic, underline, strikethrough)
	_basic_markers_cache.append(bm)

	basic_markers.append({
		"marker": marker_name,
		"custom_color": use_color,
		"color": marker_color,
		"boldened": bold,
		"italicised": italic,
		"underlined": underline,
		"strikedthrough": strikethrough
	})


## adds a custom marker at runtime (added to both cache and exported array).
func add_custom_marker(
	marker_name: String,
	start_tags: String,
	end_tags: String,
	offset: int = 0,
	visible_chars: int = 0
) -> void:
	var cm := CustomMarker.new(marker_name, start_tags, end_tags, offset, visible_chars)
	_custom_markers_cache.append(cm)

	custom_markers.append({
		"marker": marker_name,
		"start": start_tags,
		"end": end_tags,
		"marker_offset": offset,
		"total_visible_character_count": visible_chars
	})


## returns all marker names defined in this palette.
func get_all_marker_names() -> Array[String]:
	_build_cache()

	var names: Array[String] = []
	for item in _basic_markers_cache:
		names.append(item.marker)
	for item in _custom_markers_cache:
		names.append(item.marker)
	return names


## clears the internal cache, forcing rebuild on next access.
func invalidate_cache() -> void:
	_cache_built = false
	_basic_markers_cache.clear()
	_custom_markers_cache.clear()
