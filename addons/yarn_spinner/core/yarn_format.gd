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

class_name YarnFormat
extends RefCounted

const _INDEX_LIMIT := 1000000
const _WIDTH_LIMIT := 1000000
const _CUSTOM_FORMAT_PRECISION := 7
const _ROUND_TRIP_DIGITS := 9
const _NO_FIRST_DIGIT := 0x7FFFFFFF
const _GROUP_SEPARATOR := ","
const _DECIMAL_SEPARATOR := "."
const _CURRENCY_SYMBOL := "¤"
const _PER_MILLE_SYMBOL := "‰"

const _ERR_BAD_SPECIFIER := "Format specifier was invalid."
const _ERR_UNCLOSED := "Input string was not in a correct format. Format item ends prematurely at offset %d."
const _ERR_EXPECTED_DIGIT := "Input string was not in a correct format. Expected an ASCII digit at offset %d."
const _ERR_UNEXPECTED_CLOSE := "Input string was not in a correct format. Unexpected closing brace without a corresponding opening brace at offset %d."
const _ERR_INDEX := "Index (zero based) must be greater than or equal to zero and less than the size of the argument list."

const _C_NUL := 0
const _C_SPACE := 32
const _C_DOUBLE_QUOTE := 34
const _C_HASH := 35
const _C_PERCENT := 37
const _C_QUOTE := 39
const _C_PLUS := 43
const _C_COMMA := 44
const _C_MINUS := 45
const _C_DOT := 46
const _C_ZERO := 48
const _C_NINE := 57
const _C_COLON := 58
const _C_SEMICOLON := 59
const _C_UPPER_E := 69
const _C_BACKSLASH := 92
const _C_LOWER_E := 101
const _C_OPEN_BRACE := 123
const _C_CLOSE_BRACE := 125
const _C_PER_MILLE := 0x2030


static func format(format_string: String, argument: Variant) -> Dictionary:
	var result := ""
	var length := format_string.length()
	var pos := 0

	while pos < length:
		var literal_end := pos
		while literal_end < length:
			var lc := format_string.unicode_at(literal_end)
			if lc == _C_OPEN_BRACE or lc == _C_CLOSE_BRACE:
				break
			literal_end += 1
		result += format_string.substr(pos, literal_end - pos)
		pos = literal_end
		if pos >= length:
			break

		var brace := format_string.unicode_at(pos)
		pos += 1
		if pos >= length:
			return _fail(_ERR_UNCLOSED % pos)
		var ch := format_string.unicode_at(pos)
		if ch == brace:
			result += String.chr(ch)
			pos += 1
			continue
		if brace != _C_OPEN_BRACE:
			return _fail(_ERR_UNEXPECTED_CLOSE % pos)

		var index := ch - _C_ZERO
		if index < 0 or index > 9:
			return _fail(_ERR_EXPECTED_DIGIT % pos)

		var width := 0
		var left_justify := false
		var item_format := ""

		pos += 1
		if pos >= length:
			return _fail(_ERR_UNCLOSED % pos)
		ch = format_string.unicode_at(pos)

		if ch != _C_CLOSE_BRACE:
			while _is_digit(ch) and index < _INDEX_LIMIT:
				index = index * 10 + ch - _C_ZERO
				pos += 1
				if pos >= length:
					return _fail(_ERR_UNCLOSED % pos)
				ch = format_string.unicode_at(pos)

			while ch == _C_SPACE:
				pos += 1
				if pos >= length:
					return _fail(_ERR_UNCLOSED % pos)
				ch = format_string.unicode_at(pos)

			if ch == _C_COMMA:
				pos += 1
				if pos >= length:
					return _fail(_ERR_UNCLOSED % pos)
				ch = format_string.unicode_at(pos)
				while ch == _C_SPACE:
					pos += 1
					if pos >= length:
						return _fail(_ERR_UNCLOSED % pos)
					ch = format_string.unicode_at(pos)

				if ch == _C_MINUS:
					left_justify = true
					pos += 1
					if pos >= length:
						return _fail(_ERR_UNCLOSED % pos)
					ch = format_string.unicode_at(pos)

				width = ch - _C_ZERO
				if width < 0 or width > 9:
					return _fail(_ERR_EXPECTED_DIGIT % pos)
				pos += 1
				if pos >= length:
					return _fail(_ERR_UNCLOSED % pos)
				ch = format_string.unicode_at(pos)
				while _is_digit(ch) and width < _WIDTH_LIMIT:
					width = width * 10 + ch - _C_ZERO
					pos += 1
					if pos >= length:
						return _fail(_ERR_UNCLOSED % pos)
					ch = format_string.unicode_at(pos)

				while ch == _C_SPACE:
					pos += 1
					if pos >= length:
						return _fail(_ERR_UNCLOSED % pos)
					ch = format_string.unicode_at(pos)

			if ch != _C_CLOSE_BRACE:
				if ch != _C_COLON:
					return _fail(_ERR_UNCLOSED % pos)
				var format_start := pos + 1
				while true:
					pos += 1
					if pos >= length:
						return _fail(_ERR_UNCLOSED % pos)
					ch = format_string.unicode_at(pos)
					if ch == _C_CLOSE_BRACE:
						break
					if ch == _C_OPEN_BRACE:
						return _fail(_ERR_UNCLOSED % pos)
				item_format = format_string.substr(format_start, pos - format_start)

		pos += 1
		if index != 0:
			return _fail(_ERR_INDEX)

		var formatted := _format_argument(argument, item_format)
		if not formatted.ok:
			return formatted

		var text: String = formatted.text
		var padding := width - text.length()
		if padding > 0 and not left_justify:
			result += " ".repeat(padding)
		result += text
		if padding > 0 and left_justify:
			result += " ".repeat(padding)

	return _succeed(result)


static func _succeed(text: String) -> Dictionary:
	return {"ok": true, "text": text, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "text": "", "error": message}


static func _is_digit(c: int) -> bool:
	return c >= _C_ZERO and c <= _C_NINE


static func _is_ascii_letter(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


static func _format_argument(argument: Variant, item_format: String) -> Dictionary:
	match typeof(argument):
		TYPE_NIL:
			return _succeed("")
		TYPE_BOOL:
			return _succeed("True" if argument else "False")
		TYPE_STRING, TYPE_STRING_NAME:
			return _succeed(String(argument))
		TYPE_INT, TYPE_FLOAT:
			return _format_single(YarnNumber.to_f32(float(argument)), item_format)
	return _succeed(str(argument))


static func _format_single(value: float, item_format: String) -> Dictionary:
	if is_nan(value):
		return _succeed("NaN")
	if is_inf(value):
		return _succeed("Infinity" if value > 0.0 else "-Infinity")

	var spec := _parse_format_specifier(item_format)
	if not spec.ok:
		return _fail(_ERR_BAD_SPECIFIER)
	var kind: int = spec.kind
	var precision: int = spec.precision

	var bits := _single_bits(value)
	var negative := ((bits >> 31) & 1) == 1
	var biased_exponent := (bits >> 23) & 0xFF
	var mantissa := bits & 0x7FFFFF
	var exponent := -149
	if biased_exponent != 0:
		mantissa |= 1 << 23
		exponent = biased_exponent - 150

	if kind == _C_NUL:
		precision = _CUSTOM_FORMAT_PRECISION

	var max_digits := precision
	var significant := true
	match _upper(kind):
		_C_NUL:
			pass
		67:
			if precision == -1:
				precision = 2
			significant = false
		_C_UPPER_E:
			if precision == -1:
				precision = 6
			precision += 1
		70, 78:
			if precision == -1:
				precision = 2
			significant = false
		71:
			if precision == 0:
				precision = -1
		80:
			if precision == -1:
				precision = 2
			precision += 2
			significant = false
		82:
			precision = -1
		_:
			return _fail(_ERR_BAD_SPECIFIER)

	var number := {"digits": "", "scale": 0, "negative": negative}
	if mantissa != 0:
		var generated: Dictionary
		if precision == -1:
			generated = _shortest_digits(mantissa, exponent)
		else:
			generated = _counted_digits(mantissa, exponent, precision, significant)
		number.digits = generated.digits
		number.scale = generated.scale

	if kind == _C_NUL:
		return _succeed(_number_to_string_format(number, item_format))

	if precision == -1:
		max_digits = maxi(number.digits.length(), _ROUND_TRIP_DIGITS)
	return _succeed(_number_to_string(number, kind, max_digits))


static func _upper(c: int) -> int:
	if c >= 97 and c <= 122:
		return c - 32
	return c


static func _parse_format_specifier(item_format: String) -> Dictionary:
	var length := item_format.length()
	var c := 0
	if length > 0:
		c = item_format.unicode_at(0)
		if _is_ascii_letter(c):
			if length == 1:
				return {"ok": true, "kind": c, "precision": -1}
			var n := 0
			var i := 1
			while i < length and _is_digit(item_format.unicode_at(i)):
				if n >= 100000000:
					return {"ok": false, "kind": c, "precision": -1}
				n = n * 10 + item_format.unicode_at(i) - _C_ZERO
				i += 1
			if i >= length or item_format.unicode_at(i) == _C_NUL:
				return {"ok": true, "kind": c, "precision": n}
	if length == 0 or c == _C_NUL:
		return {"ok": true, "kind": 71, "precision": -1}
	return {"ok": true, "kind": _C_NUL, "precision": -1}


static func _single_bits(value: float) -> int:
	var arr := PackedFloat32Array([value])
	return arr.to_byte_array().decode_u32(0)


static func _big_multiply_small(big: PackedByteArray, factor: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(big.size() + 12)
	var carry := 0
	var n := big.size()
	for i in n:
		var t := big[i] * factor + carry
		out[i] = t % 10
		carry = t / 10
	while carry > 0:
		out[n] = carry % 10
		carry /= 10
		n += 1
	out.resize(n)
	return out


static func _exact_decimal(value: int, power_of_two: int) -> Dictionary:
	var big := PackedByteArray()
	var v := value
	while v > 0:
		big.append(v % 10)
		v /= 10
	var frac := 0
	if power_of_two >= 0:
		var remaining := power_of_two
		while remaining > 0:
			var step := mini(remaining, 30)
			big = _big_multiply_small(big, 1 << step)
			remaining -= step
	else:
		var remaining := -power_of_two
		frac = remaining
		while remaining > 0:
			var step := mini(remaining, 13)
			big = _big_multiply_small(big, int(pow(5.0, step)))
			remaining -= step
	return {"big": big, "frac": frac}


static func _big_endian(big: PackedByteArray, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	out.fill(0)
	var n := big.size()
	for i in n:
		out[size - 1 - i] = big[i]
	return out


static func _strip_trailing_zeros(digits: String) -> String:
	var end := digits.length()
	while end > 0 and digits.unicode_at(end - 1) == _C_ZERO:
		end -= 1
	return digits.substr(0, end)


static func _round_up_digits(digits: String, scale: int) -> Dictionary:
	var i := digits.length() - 1
	while i >= 0 and digits.unicode_at(i) == _C_NINE:
		i -= 1
	if i < 0:
		return {"digits": "1", "scale": scale + 1}
	return {"digits": digits.substr(0, i) + String.chr(digits.unicode_at(i) + 1), "scale": scale}


static func _counted_digits(mantissa: int, exponent: int, cutoff: int, significant: bool) -> Dictionary:
	var exact := _exact_decimal(mantissa, exponent)
	var big: PackedByteArray = exact.big
	var all_digits := ""
	for i in range(big.size() - 1, -1, -1):
		all_digits += String.chr(_C_ZERO + big[i])
	var decimal_exponent: int = all_digits.length() - 1 - exact.frac
	var digits := _strip_trailing_zeros(all_digits)

	var cutoff_exponent := -cutoff
	if significant:
		cutoff_exponent = decimal_exponent + 1 - cutoff

	if decimal_exponent < cutoff_exponent:
		var first := digits.unicode_at(0) - _C_ZERO
		if first > 5 or (first == 5 and digits.length() > 1):
			return {"digits": "1", "scale": decimal_exponent + 2}
		return {"digits": digits.substr(0, 1), "scale": decimal_exponent + 1}

	var count := decimal_exponent - cutoff_exponent + 1
	if digits.length() <= count:
		return {"digits": digits, "scale": decimal_exponent + 1}

	var head := digits.substr(0, count)
	var next := digits.unicode_at(count) - _C_ZERO
	var round_up := next > 5 or (next == 5 and digits.length() > count + 1)
	if next == 5 and digits.length() == count + 1:
		round_up = (head.unicode_at(count - 1) - _C_ZERO) % 2 == 1

	if round_up:
		var rounded := _round_up_digits(head, decimal_exponent + 1)
		return {"digits": _strip_trailing_zeros(rounded.digits), "scale": rounded.scale}
	return {"digits": _strip_trailing_zeros(head), "scale": decimal_exponent + 1}


static func _compare_prefix(value: PackedByteArray, bound: PackedByteArray, index: int) -> int:
	for i in index + 1:
		if value[i] != bound[i]:
			return 1 if value[i] > bound[i] else -1
	for i in range(index + 1, bound.size()):
		if bound[i] != 0:
			return -1
	return 0


static func _compare_prefix_plus_one(value: PackedByteArray, bound: PackedByteArray, index: int) -> int:
	var prefix := value.slice(0, index + 1)
	var i := index
	while i >= 0 and prefix[i] == 9:
		prefix[i] = 0
		i -= 1
	if i < 0:
		return 1
	prefix[i] += 1
	return _compare_prefix(prefix, bound, index)


static func _shortest_digits(mantissa: int, exponent: int) -> Dictionary:
	var power := exponent - 2
	var low_offset := 1 if mantissa == (1 << 23) else 2
	var exact_value := _exact_decimal(4 * mantissa, power)
	var exact_low := _exact_decimal(4 * mantissa - low_offset, power)
	var exact_high := _exact_decimal(4 * mantissa + 2, power)
	var size: int = exact_high.big.size()
	var frac: int = exact_value.frac
	var value := _big_endian(exact_value.big, size)
	var low_bound := _big_endian(exact_low.big, size)
	var high_bound := _big_endian(exact_high.big, size)
	var even := mantissa % 2 == 0

	var first := 0
	while value[first] == 0:
		first += 1
	var decimal_exponent := size - 1 - first - frac

	var digits := ""
	var index := first
	var low := false
	var high := false
	while true:
		var cmp_low := _compare_prefix(value, low_bound, index)
		var cmp_high := _compare_prefix_plus_one(value, high_bound, index)
		low = cmp_low >= 0 if even else cmp_low > 0
		high = cmp_high <= 0 if even else cmp_high < 0
		if low or high or index == size - 1:
			break
		digits += String.chr(_C_ZERO + value[index])
		index += 1

	var output_digit := value[index]
	var round_down := low
	if low == high:
		var compare := -1
		if index + 1 < size:
			var next := value[index + 1]
			if next > 5:
				compare = 1
			elif next == 5:
				compare = 0
				for i in range(index + 2, size):
					if value[i] != 0:
						compare = 1
						break
		round_down = compare < 0
		if compare == 0:
			round_down = output_digit % 2 == 0

	if round_down:
		digits += String.chr(_C_ZERO + output_digit)
	elif output_digit == 9:
		var rounded := _round_up_digits(digits + "9", decimal_exponent + 1)
		return {"digits": _strip_trailing_zeros(rounded.digits), "scale": rounded.scale}
	else:
		digits += String.chr(_C_ZERO + output_digit + 1)
	return {"digits": _strip_trailing_zeros(digits), "scale": decimal_exponent + 1}


static func _round_number(number: Dictionary, pos: int, correctly_rounded: bool) -> void:
	var digits: String = number.digits
	var n := digits.length()
	var i := clampi(pos, 0, n)
	if i == pos and i < n and not correctly_rounded and digits.unicode_at(i) >= _C_ZERO + 5:
		while i > 0 and digits.unicode_at(i - 1) == _C_NINE:
			i -= 1
		if i > 0:
			digits = digits.substr(0, i - 1) + String.chr(digits.unicode_at(i - 1) + 1)
		else:
			number.scale += 1
			digits = "1"
	else:
		while i > 0 and digits.unicode_at(i - 1) == _C_ZERO:
			i -= 1
		digits = digits.substr(0, i)
	if digits.is_empty():
		number.scale = 0
	number.digits = digits


static func _number_to_string(number: Dictionary, kind: int, max_digits: int) -> String:
	var sign := "-" if number.negative else ""
	match _upper(kind):
		67:
			if max_digits < 0:
				max_digits = 2
			_round_number(number, number.scale + max_digits, true)
			var body := _CURRENCY_SYMBOL + _format_fixed(number, max_digits, true)
			return "(" + body + ")" if number.negative else body
		70:
			if max_digits < 0:
				max_digits = 2
			_round_number(number, number.scale + max_digits, true)
			return sign + _format_fixed(number, max_digits, false)
		78:
			if max_digits < 0:
				max_digits = 2
			_round_number(number, number.scale + max_digits, true)
			return sign + _format_fixed(number, max_digits, true)
		_C_UPPER_E:
			if max_digits < 0:
				max_digits = 6
			max_digits += 1
			_round_number(number, max_digits, true)
			return sign + _format_scientific(number, max_digits, String.chr(kind))
		71, 82:
			if max_digits < 1:
				max_digits = number.digits.length()
			_round_number(number, max_digits, true)
			var exp_char := "E" if kind == 71 or kind == 82 else "e"
			return sign + _format_general(number, max_digits, exp_char)
		80:
			if max_digits < 0:
				max_digits = 2
			number.scale += 2
			_round_number(number, number.scale + max_digits, true)
			return sign + _format_fixed(number, max_digits, true) + " %"
	return ""


static func _group_integer(integer: String) -> String:
	var grouped := ""
	var end := integer.length()
	while end > 3:
		grouped = _GROUP_SEPARATOR + integer.substr(end - 3, 3) + grouped
		end -= 3
	return integer.substr(0, end) + grouped


static func _format_fixed(number: Dictionary, max_digits: int, grouped: bool) -> String:
	var digits: String = number.digits
	var scale: int = number.scale
	var n := digits.length()
	var cursor := 0
	var out := "0"
	if scale > 0:
		cursor = mini(scale, n)
		var integer := digits.substr(0, cursor) + "0".repeat(scale - cursor)
		out = _group_integer(integer) if grouped else integer
	if max_digits > 0:
		out += _DECIMAL_SEPARATOR
		var remaining := max_digits
		if scale < 0:
			var zeros := mini(-scale, remaining)
			out += "0".repeat(zeros)
			remaining -= zeros
		var fraction := digits.substr(cursor, remaining) if cursor < n else ""
		out += fraction + "0".repeat(remaining - fraction.length())
	return out


static func _format_scientific(number: Dictionary, max_digits: int, exp_char: String) -> String:
	var digits: String = number.digits
	var out := digits.substr(0, 1) if not digits.is_empty() else "0"
	if max_digits != 1:
		out += _DECIMAL_SEPARATOR
	var rest := digits.substr(1, max_digits - 1) if digits.length() > 1 else ""
	out += rest + "0".repeat(max_digits - 1 - rest.length())
	var e: int = 0 if digits.is_empty() else number.scale - 1
	return out + _format_exponent(e, exp_char, 3, true)


static func _format_general(number: Dictionary, max_digits: int, exp_char: String) -> String:
	var digits: String = number.digits
	var scale: int = number.scale
	var n := digits.length()
	var dig_pos := scale
	var scientific := false
	if dig_pos > max_digits or dig_pos < -3:
		dig_pos = 1
		scientific = true

	var out := "0"
	var cursor := 0
	if dig_pos > 0:
		cursor = mini(dig_pos, n)
		out = digits.substr(0, cursor) + "0".repeat(dig_pos - cursor)
		dig_pos = 0

	if cursor < n or dig_pos < 0:
		out += _DECIMAL_SEPARATOR + "0".repeat(maxi(-dig_pos, 0)) + digits.substr(cursor)

	if scientific:
		out += _format_exponent(scale - 1, exp_char, 2, true)
	return out


static func _format_exponent(value: int, exp_char: String, min_digits: int, positive_sign: bool) -> String:
	var out := exp_char
	if value < 0:
		out += "-"
		value = -value
	elif positive_sign:
		out += "+"
	var text := str(value)
	if text.length() < min_digits:
		text = "0".repeat(min_digits - text.length()) + text
	return out + text


static func _find_section(item_format: String, section: int) -> int:
	if section == 0:
		return 0
	var length := item_format.length()
	var src := 0
	while true:
		if src >= length:
			return 0
		var ch := item_format.unicode_at(src)
		src += 1
		match ch:
			_C_QUOTE, _C_DOUBLE_QUOTE:
				while src < length and item_format.unicode_at(src) != _C_NUL:
					var quoted := item_format.unicode_at(src)
					src += 1
					if quoted == ch:
						break
			_C_BACKSLASH:
				if src < length and item_format.unicode_at(src) != _C_NUL:
					src += 1
			_C_SEMICOLON:
				section -= 1
				if section == 0:
					if src < length and item_format.unicode_at(src) != _C_NUL and item_format.unicode_at(src) != _C_SEMICOLON:
						return src
					return 0
			_C_NUL:
				return 0
	return 0


static func _char_at(text: String, index: int) -> int:
	if index < text.length():
		return text.unicode_at(index)
	return _C_NUL


static func _number_to_string_format(number: Dictionary, item_format: String) -> String:
	var length := item_format.length()
	var initial_section := 0
	if number.digits.is_empty():
		initial_section = 2
	elif number.negative:
		initial_section = 1
	var section := _find_section(item_format, initial_section)

	var digit_count := 0
	var decimal_pos := -1
	var first_digit := _NO_FIRST_DIGIT
	var last_digit := 0
	var scientific := false
	var thousand_pos := -1
	var thousand_count := 0
	var thousand_seps := false
	var scale_adjust := 0
	var src := 0

	while true:
		digit_count = 0
		decimal_pos = -1
		first_digit = _NO_FIRST_DIGIT
		last_digit = 0
		scientific = false
		thousand_pos = -1
		thousand_seps = false
		scale_adjust = 0
		src = section

		while src < length:
			var ch := item_format.unicode_at(src)
			src += 1
			if ch == _C_NUL or ch == _C_SEMICOLON:
				break
			match ch:
				_C_HASH:
					digit_count += 1
				_C_ZERO:
					if first_digit == _NO_FIRST_DIGIT:
						first_digit = digit_count
					digit_count += 1
					last_digit = digit_count
				_C_DOT:
					if decimal_pos < 0:
						decimal_pos = digit_count
				_C_COMMA:
					if digit_count > 0 and decimal_pos < 0:
						if thousand_pos >= 0 and thousand_pos == digit_count:
							thousand_count += 1
						else:
							if thousand_pos >= 0:
								thousand_seps = true
							thousand_pos = digit_count
							thousand_count = 1
				_C_PERCENT:
					scale_adjust += 2
				_C_PER_MILLE:
					scale_adjust += 3
				_C_QUOTE, _C_DOUBLE_QUOTE:
					while src < length and item_format.unicode_at(src) != _C_NUL:
						var quoted := item_format.unicode_at(src)
						src += 1
						if quoted == ch:
							break
				_C_BACKSLASH:
					if src < length and item_format.unicode_at(src) != _C_NUL:
						src += 1
				_C_UPPER_E, _C_LOWER_E:
					var next := _char_at(item_format, src)
					var after := _char_at(item_format, src + 1)
					if next == _C_ZERO or ((next == _C_PLUS or next == _C_MINUS) and after == _C_ZERO):
						src += 1
						while src < length and item_format.unicode_at(src) == _C_ZERO:
							src += 1
						scientific = true

		if decimal_pos < 0:
			decimal_pos = digit_count

		if thousand_pos >= 0:
			if thousand_pos == decimal_pos:
				scale_adjust -= thousand_count * 3
			else:
				thousand_seps = true

		if not number.digits.is_empty():
			number.scale += scale_adjust
			var pos: int = digit_count if scientific else number.scale + digit_count - decimal_pos
			_round_number(number, pos, false)
			if number.digits.is_empty():
				var zero_section := _find_section(item_format, 2)
				if zero_section != section:
					section = zero_section
					continue
		else:
			number.scale = 0
		break

	var digits: String = number.digits
	var digit_length := digits.length()
	var scale: int = number.scale

	first_digit = decimal_pos - first_digit if first_digit < decimal_pos else 0
	last_digit = decimal_pos - last_digit if last_digit > decimal_pos else 0

	var dig_pos := decimal_pos
	var adjust := 0
	if not scientific:
		dig_pos = maxi(scale, decimal_pos)
		adjust = scale - decimal_pos

	var separator_positions: Array[int] = []
	if thousand_seps:
		var total_digits := dig_pos + (adjust if adjust < 0 else 0)
		var num_digits := maxi(first_digit, total_digits)
		var group_total := 3
		while num_digits > group_total:
			separator_positions.append(group_total)
			group_total += 3
	var separator_index := separator_positions.size() - 1

	var out := ""
	if number.negative and section == 0 and scale != 0:
		out = "-"

	var decimal_written := false
	var cursor := 0
	src = section

	while src < length:
		var ch := item_format.unicode_at(src)
		src += 1
		if ch == _C_NUL or ch == _C_SEMICOLON:
			break

		if adjust > 0 and (ch == _C_HASH or ch == _C_ZERO or ch == _C_DOT):
			while adjust > 0:
				if cursor < digit_length:
					out += digits.substr(cursor, 1)
					cursor += 1
				else:
					out += "0"
				if thousand_seps and dig_pos > 1 and separator_index >= 0 and dig_pos == separator_positions[separator_index] + 1:
					out += _GROUP_SEPARATOR
					separator_index -= 1
				dig_pos -= 1
				adjust -= 1

		match ch:
			_C_HASH, _C_ZERO:
				var emitted := ""
				if adjust < 0:
					adjust += 1
					if dig_pos <= first_digit:
						emitted = "0"
				elif cursor < digit_length:
					emitted = digits.substr(cursor, 1)
					cursor += 1
				elif dig_pos > last_digit:
					emitted = "0"
				if not emitted.is_empty():
					out += emitted
					if thousand_seps and dig_pos > 1 and separator_index >= 0 and dig_pos == separator_positions[separator_index] + 1:
						out += _GROUP_SEPARATOR
						separator_index -= 1
				dig_pos -= 1
			_C_DOT:
				if dig_pos == 0 and not decimal_written:
					if last_digit < 0 or (decimal_pos < digit_count and cursor < digit_length):
						out += _DECIMAL_SEPARATOR
						decimal_written = true
			_C_PER_MILLE:
				out += _PER_MILLE_SYMBOL
			_C_PERCENT:
				out += "%"
			_C_COMMA:
				pass
			_C_QUOTE, _C_DOUBLE_QUOTE:
				while src < length and item_format.unicode_at(src) != _C_NUL and item_format.unicode_at(src) != ch:
					out += item_format.substr(src, 1)
					src += 1
				if src < length and item_format.unicode_at(src) != _C_NUL:
					src += 1
			_C_BACKSLASH:
				if src < length and item_format.unicode_at(src) != _C_NUL:
					out += item_format.substr(src, 1)
					src += 1
			_C_UPPER_E, _C_LOWER_E:
				var next := _char_at(item_format, src)
				var after := _char_at(item_format, src + 1)
				if scientific:
					var positive_sign := false
					var min_digits := 0
					if next == _C_ZERO:
						min_digits = 1
					elif next == _C_PLUS and after == _C_ZERO:
						positive_sign = true
					elif not (next == _C_MINUS and after == _C_ZERO):
						out += String.chr(ch)
						continue
					src += 1
					while src < length and item_format.unicode_at(src) == _C_ZERO:
						src += 1
						min_digits += 1
					min_digits = mini(min_digits, 10)
					var exp_value := 0 if digits.is_empty() else scale - decimal_pos
					out += _format_exponent(exp_value, String.chr(ch), min_digits, positive_sign)
					scientific = false
				else:
					out += String.chr(ch)
					if src < length:
						if next == _C_PLUS or next == _C_MINUS:
							out += String.chr(next)
							src += 1
						while src < length and item_format.unicode_at(src) == _C_ZERO:
							out += "0"
							src += 1
			_:
				out += String.chr(ch)

	if number.negative and section == 0 and scale == 0 and not out.is_empty():
		out = "-" + out
	return out
