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

class_name YarnNumber
extends RefCounted
## Yarn numbers are 32-bit floats. Godot floats are 64-bit doubles, so
## every number needs to be snapped to float32 width and displayed with
## float32 shortest-round-trip formatting to match the other runtimes.


## Rounds a double to the nearest representable 32-bit float value.
static func to_f32(v: float) -> float:
	var arr := PackedFloat32Array()
	arr.resize(1)
	arr[0] = v
	return arr[0]


## Formats a number for dialogue display: the shortest
## decimal that round-trips back to the same float32 value, in plain
## decimal notation for magnitudes in [0.0001, 1e9), scientific otherwise.
static func to_display_string(v: float) -> String:
	v = to_f32(v)

	if is_nan(v):
		return "NaN"
	if is_inf(v):
		return "Infinity" if v > 0.0 else "-Infinity"
	if v == 0.0:
		return "-0" if _is_negative_zero(v) else "0"

	var negative := v < 0.0
	var abs_v := absf(v)
	var exponent := _magnitude(abs_v)

	var digits := ""
	var digit_exponent := exponent
	for d in range(1, 10):
		var found := _digits_for_precision(abs_v, d, exponent)
		var candidate: float = float(found.digits) * pow(10.0, found.exponent - (d - 1))
		digits = found.digits
		digit_exponent = found.exponent
		if to_f32(candidate) == abs_v:
			break

	# Plain vs scientific is decided from the decimal exponent of the
	# rounded digits (not the raw double), since a float32 value near the
	# 0.0001 boundary can sit a hair below it in double precision even
	# though its shortest decimal representation is exactly "0.0001".
	var is_plain := digit_exponent >= -4 and digit_exponent < 9
	var body: String
	if is_plain:
		body = _format_plain(digits, digit_exponent)
	else:
		body = _format_scientific(digits, digit_exponent)

	return ("-" if negative else "") + body


static func _is_negative_zero(v: float) -> bool:
	return v == 0.0 and (1.0 / v) < 0.0


## Base-10 exponent E such that abs_v / 10^E lies in [1, 10).
static func _magnitude(abs_v: float) -> int:
	var exponent := int(floor(log(abs_v) / log(10.0)))
	if abs_v / pow(10.0, exponent) >= 10.0:
		exponent += 1
	elif abs_v / pow(10.0, exponent) < 1.0:
		exponent -= 1
	return exponent


## Rounds abs_v to exactly d significant digits, returning {digits, exponent}
## where digits is a d-character decimal string and exponent is the power
## of ten of its leading digit (adjusted for any rounding carry).
static func _digits_for_precision(abs_v: float, d: int, exponent: int) -> Dictionary:
	var scale := d - 1 - exponent
	var scaled: float = abs_v * pow(10.0, scale) if scale >= 0 else abs_v / pow(10.0, -scale)
	var rounded := round(scaled)
	var e := exponent
	var digit_str := str(int(rounded))

	while digit_str.length() > d:
		rounded = round(rounded / 10.0)
		e += 1
		digit_str = str(int(rounded))

	return {"digits": digit_str, "exponent": e}


static func _format_plain(digits: String, exponent: int) -> String:
	var point_pos := exponent + 1
	var d := digits.length()

	if point_pos <= 0:
		return "0." + "0".repeat(-point_pos) + digits
	if point_pos >= d:
		return digits + "0".repeat(point_pos - d)
	return digits.substr(0, point_pos) + "." + digits.substr(point_pos)


static func _format_scientific(digits: String, exponent: int) -> String:
	var mantissa := digits[0]
	if digits.length() > 1:
		mantissa += "." + digits.substr(1)
	return mantissa + "E" + _format_exponent(exponent)


static func _format_exponent(exponent: int) -> String:
	var sign := "+" if exponent >= 0 else "-"
	var digits := str(absi(exponent))
	if digits.length() < 2:
		digits = "0" + digits
	return sign + digits
