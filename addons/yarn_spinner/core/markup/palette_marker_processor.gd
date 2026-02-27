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

class_name YarnPaletteMarkerProcessor
extends YarnAttributeMarkerProcessor
## parse-time processor that applies bbcode styling from a YarnMarkupPalette.
## register custom marker names (e.g. [happy], [angry]) mapped to formatting.


## the markup palette defining styles for each marker name.
var palette: YarnMarkupPalette = null
func _init(markup_palette: YarnMarkupPalette = null) -> void:
	palette = markup_palette


func process_replacement_marker(
	marker: YarnMarkupAttribute,
	child_builder: Array,
	child_attributes: Array,
	locale_code: String
) -> ReplacementMarkerResult:
	if palette == null:
		var error := MarkupDiagnostic.new(
			"can't apply palette for marker %s, because a palette was not set" % marker.name
		)
		return ReplacementMarkerResult.new([error], 0)

	var format := palette.palette_for_marker(marker.name)

	if format.get("found", false):
		var children_length: int = child_builder[0].length()
		child_builder[0] = format.start + child_builder[0] + format.end

		# offset child attributes if palette adds visible characters at start
		var marker_offset: int = format.get("marker_offset", 0)
		if marker_offset != 0:
			for i in range(child_attributes.size()):
				var attr: YarnMarkupAttribute = child_attributes[i]
				child_attributes[i] = attr.shift(marker_offset)

		var total_visible: int = format.get("total_visible_character_count", 0)
		var invisible_chars: int = child_builder[0].length() - children_length - total_visible

		return ReplacementMarkerResult.new([], invisible_chars)

	var error := MarkupDiagnostic.new("was unable to find a matching style for %s" % marker.name)
	return ReplacementMarkerResult.new([error], 0)


## registers this processor with a line provider for all markers in the palette.
func register_with_line_provider(line_provider) -> void:
	if palette == null:
		push_warning("cannot register palette processor: no palette set")
		return

	var marker_names := palette.get_all_marker_names()
	for marker_name in marker_names:
		line_provider.register_marker_processor(marker_name, self)


## unregisters this processor from a line provider for all palette markers.
func unregister_from_line_provider(line_provider) -> void:
	if palette == null:
		return

	var marker_names := palette.get_all_marker_names()
	for marker_name in marker_names:
		line_provider.deregister_marker_processor(marker_name)
