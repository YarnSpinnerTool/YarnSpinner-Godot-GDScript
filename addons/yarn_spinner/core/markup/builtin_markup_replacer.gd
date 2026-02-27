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

class_name YarnBuiltInMarkupReplacer
extends YarnAttributeMarkerProcessor
## marker processor for built-in select, plural, and ordinal replacement markers.

static var _value_placeholder_regex: RegEx


func _init() -> void:
	if _value_placeholder_regex == null:
		_value_placeholder_regex = RegEx.new()
		_value_placeholder_regex.compile("(?<!\\\\)%")


func process_replacement_marker(
	marker: YarnMarkupAttribute,
	child_builder: Array,
	child_attributes: Array,
	locale_code: String
) -> ReplacementMarkerResult:
	if child_builder == null or child_attributes == null:
		var diags := [MarkupDiagnostic.new("Requested replacement on '%s' but no valid string builder or attributes" % marker.name)]
		return ReplacementMarkerResult.new(diags, 0)

	if child_builder[0].length() > 0 or child_attributes.size() > 0:
		var diags := [MarkupDiagnostic.new("'%s' markup only works on self-closing tags" % marker.name)]
		return ReplacementMarkerResult.new(diags, 0)

	var value_prop := marker.try_get_property("value")
	if value_prop == null:
		var diags := [MarkupDiagnostic.new("no 'value' property found on marker, %s requires this" % marker.name)]
		return ReplacementMarkerResult.new(diags, 0)

	match marker.name:
		"select":
			return ReplacementMarkerResult.new(_select_replace(marker, child_builder, value_prop.to_string_value()), 0)
		"plural", "ordinal":
			match value_prop.type:
				YarnMarkupValue.ValueType.INTEGER:
					return ReplacementMarkerResult.new(_plural_replace(marker, locale_code, child_builder, float(value_prop.integer_value)), 0)
				YarnMarkupValue.ValueType.FLOAT:
					return ReplacementMarkerResult.new(_plural_replace(marker, locale_code, child_builder, value_prop.float_value), 0)
				_:
					var diags := [MarkupDiagnostic.new("Asked to pluralise '%s' but this type doesn't support pluralisation" % value_prop.to_string_value())]
					return ReplacementMarkerResult.new(diags, 0)
		_:
			var diags := [MarkupDiagnostic.new("Asked to perform replacement for %s, a marker we don't handle" % marker.name)]
			return ReplacementMarkerResult.new(diags, 0)


func _select_replace(marker: YarnMarkupAttribute, child_builder: Array, value: String) -> Array:
	var diagnostics: Array = []

	var replacement_prop := marker.try_get_property(value)
	if replacement_prop == null:
		diagnostics.append(MarkupDiagnostic.new("no replacement value for %s was found" % value))
		return diagnostics

	var replacement := replacement_prop.to_string_value()
	replacement = _value_placeholder_regex.sub(replacement, value, true)
	child_builder[0] += replacement

	return diagnostics


func _plural_replace(marker: YarnMarkupAttribute, locale_code: String, child_builder: Array, numeric_value: float) -> Array:
	var diagnostics: Array = []

	var plural_case := _get_plural_case(locale_code, numeric_value, marker.name == "ordinal")
	var plural_case_name := plural_case.to_upper()

	var replacement_value := marker.try_get_property(plural_case_name)
	if replacement_value == null:
		diagnostics.append(MarkupDiagnostic.new("no replacement for %s's plural case of %s was found" % [str(numeric_value), plural_case_name]))
		return diagnostics

	if replacement_value.type != YarnMarkupValue.ValueType.STRING:
		diagnostics.append(MarkupDiagnostic.new("select replacement values are expected to be strings, not %s" % replacement_value.type))

	var input := replacement_value.to_string_value()
	var formatted_value := str(int(numeric_value)) if numeric_value == int(numeric_value) else str(numeric_value)
	child_builder[0] += _value_placeholder_regex.sub(input, formatted_value, true)

	return diagnostics


## get CLDR plural case for a number.
func _get_plural_case(locale_code: String, value: float, is_ordinal: bool) -> String:
	var language_code := locale_code.split("-")[0].split("_")[0].to_lower()

	var abs_value := absf(value)
	var int_value := int(abs_value)

	if is_ordinal:
		return _get_ordinal_plural_case(language_code, int_value)
	else:
		return _get_cardinal_plural_case(language_code, abs_value)


## CLDR cardinal plural case (covers top 20 languages).
func _get_cardinal_plural_case(language: String, value: float) -> String:
	var int_value := int(value)
	var has_decimal := value != float(int_value)

	match language:
		# Germanic: one for 1, other for everything else
		"en", "de", "nl", "sv", "da", "no", "nb", "nn", "af", "fy":
			if int_value == 1 and not has_decimal:
				return "one"
			return "other"

		# French/Portuguese: one for 0-1 (compact integer), other for rest
		"fr", "pt":
			if value >= 0.0 and value < 2.0:
				return "one"
			return "other"

		# Spanish/Italian: one for 1 only
		"es", "it", "ca", "eu", "gl":
			if int_value == 1 and not has_decimal:
				return "one"
			return "other"

		# Russian/Ukrainian: one/few/many
		"ru", "uk":
			if has_decimal:
				return "other"
			var mod10 := int_value % 10
			var mod100 := int_value % 100
			if mod10 == 1 and mod100 != 11:
				return "one"
			if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
				return "few"
			if mod10 == 0 or (mod10 >= 5 and mod10 <= 9) or (mod100 >= 11 and mod100 <= 14):
				return "many"
			return "other"

		# Polish: one/few/many
		"pl":
			if has_decimal:
				return "other"
			if int_value == 1:
				return "one"
			var mod10 := int_value % 10
			var mod100 := int_value % 100
			if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
				return "few"
			if int_value != 1 and (mod10 >= 0 and mod10 <= 1) or (mod10 >= 5 and mod10 <= 9) or (mod100 >= 12 and mod100 <= 14):
				return "many"
			return "other"

		# Czech/Slovak: one/few/many
		"cs", "sk":
			if has_decimal:
				return "many"
			if int_value == 1:
				return "one"
			if int_value >= 2 and int_value <= 4:
				return "few"
			return "other"

		# Romanian: one/few/other
		"ro":
			if has_decimal:
				return "other"
			if int_value == 1:
				return "one"
			var mod100 := int_value % 100
			if int_value == 0 or (mod100 >= 2 and mod100 <= 19):
				return "few"
			return "other"

		# Croatian/Serbian/Bosnian: one/few/other (same as Russian)
		"hr", "sr", "bs":
			if has_decimal:
				return "other"
			var mod10 := int_value % 10
			var mod100 := int_value % 100
			if mod10 == 1 and mod100 != 11:
				return "one"
			if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
				return "few"
			return "other"

		# Hungarian/Turkish/Finnish: one for 1, other for rest
		"hu", "tr", "fi", "et":
			if int_value == 1 and not has_decimal:
				return "one"
			return "other"

		# Arabic: zero/one/two/few/many/other
		"ar":
			if int_value == 0:
				return "zero"
			if int_value == 1:
				return "one"
			if int_value == 2:
				return "two"
			var mod100 := int_value % 100
			if mod100 >= 3 and mod100 <= 10:
				return "few"
			if mod100 >= 11 and mod100 <= 99:
				return "many"
			return "other"

		# Hebrew: one/two/other
		"he", "iw":
			if int_value == 1 and not has_decimal:
				return "one"
			if int_value == 2 and not has_decimal:
				return "two"
			return "other"

		# East Asian: no plural forms
		"ja", "ko", "zh", "vi", "th", "id", "ms":
			return "other"

		_:
			# default: one for 1, other for everything else
			if int_value == 1 and not has_decimal:
				return "one"
			return "other"


## CLDR ordinal plural case.
func _get_ordinal_plural_case(language: String, value: int) -> String:
	match language:
		"en":
			var mod10 := value % 10
			var mod100 := value % 100
			if mod10 == 1 and mod100 != 11:
				return "one"
			if mod10 == 2 and mod100 != 12:
				return "two"
			if mod10 == 3 and mod100 != 13:
				return "few"
			return "other"

		"fr":
			if value == 1:
				return "one"
			return "other"

		"it":
			# Italian ordinals: many for 8 and 11, other for rest
			if value == 11 or value == 8 or value == 80 or value == 800:
				return "many"
			return "other"

		"de", "nl", "sv", "da", "no", "nb", "nn":
			# Germanic (non-English): other for all
			return "other"

		"es", "pt", "ca", "gl":
			# Romance languages
			return "other"

		"ru", "uk":
			# Russian/Ukrainian: other for all ordinals
			return "other"

		"pl":
			# Polish: other for all ordinals
			return "other"

		"hu":
			# Hungarian: one/other
			if value == 1 or value == 5:
				return "one"
			return "other"

		_:
			# default: other for all ordinals
			return "other"
