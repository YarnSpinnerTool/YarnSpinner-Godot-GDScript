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

class_name YarnCldrPluralRules
extends RefCounted
## Unicode CLDR plural rules (cardinal and ordinal) for the `plural` and
## `ordinal` markup replacement markers.
##
## Each locale resolves to one of six plural cases: "zero", "one", "two",
## "few", "many", or "other". "other" is the only case guaranteed to exist
## for every locale, and is also the fallback for locales this file doesn't
## know about.
##
## CLDR rules are written in terms of a handful of operands derived from
## the number being pluralised:
##   n - the absolute value of the number
##   i - the integer digits of n
##   v - the number of visible fraction digits, with trailing zeros
##   f - the visible fraction digits, with trailing zeros, as an integer
##   t - the visible fraction digits, without trailing zeros, as an integer
##
## LIMITATION: a Godot float carries no record of how it was authored, so
## trailing zeros in the fraction (e.g. whether a value was written as
## "1.50" or "1.5") can never be recovered. This implementation derives the
## fraction operands from the number's shortest round-trip invariant string,
## as the reference implementation does, which makes v and w (fraction
## digits without trailing zeros) identical, and likewise f and t identical.


## Returns the CLDR operand set for a number.
static func get_operands(value: float) -> Dictionary:
	var magnitude := absf(value)
	var fraction_text := _invariant_fraction_text(magnitude)
	var f := _fraction_value(magnitude, fraction_text)
	return {
		"n": magnitude,
		"i": _integer_value(magnitude),
		"v": fraction_text.length(),
		"f": f,
		"t": f,
	}


## Normalises a locale/language code: lowercase, region and script stripped.
static func normalise_language(language_code: String) -> String:
	return language_code.split("-")[0].split("_")[0].to_lower()


## Returns the CLDR cardinal plural case ("zero", "one", "two", "few",
## "many", or "other") for the given language and number.
static func get_cardinal_case(language_code: String, value: float) -> String:
	var rule := _resolve_rule(_cardinal_dispatch(), language_code)
	if not rule.is_valid():
		return "other"
	return rule.call(get_operands(value))


## Returns the CLDR ordinal plural case ("zero", "one", "two", "few",
## "many", or "other") for the given language and number.
static func get_ordinal_case(language_code: String, value: float) -> String:
	var rule := _resolve_rule(_ordinal_dispatch(), language_code)
	if not rule.is_valid():
		return "other"
	return rule.call(get_operands(value))


static func _resolve_rule(dispatch: Dictionary, language_code: String) -> Callable:
	var parts := language_code.replace("-", "_").split("_")
	for index in range(1, parts.size()):
		parts[index] = parts[index].to_upper()
	parts[0] = parts[0].to_lower()
	var full_code := "_".join(parts)
	if dispatch.has(full_code):
		return dispatch[full_code]
	return dispatch.get(normalise_language(language_code), Callable())


static func _integer_value(value: float) -> int:
	if is_nan(value):
		return 0
	return int(clampf(value, -2147483648.0, 2147483647.0))


static func _shortest_digits(value: float) -> Array:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, absf(value))
	var bits := bytes.decode_s64(0)
	var frac_len := maxi(_fraction_bit_count(bits), _fraction_bit_count(bits - 1))
	frac_len = maxi(frac_len, _fraction_bit_count(bits + 1))
	var exact := _scaled_digits(bits, frac_len)
	var low := _add_digits(exact, _scaled_digits(bits - 1, frac_len))
	var high := _add_digits(exact, _scaled_digits(bits + 1, frac_len))
	var inclusive := bits & 1 == 0
	var candidate := exact
	for keep in range(1, exact.length()):
		var drop := exact.length() - keep
		var rounded := _round_digits(exact, drop)
		if _round_trips(rounded, low, high, inclusive):
			candidate = rounded
			break
		rounded = _add_digits(rounded, "1" + "0".repeat(drop))
		if _round_trips(rounded, low, high, inclusive):
			candidate = rounded
			break
	return [candidate.rstrip("0"), candidate.length() - frac_len]


static func _decompose(bits: int) -> Array:
	var biased := (bits >> 52) & 0x7ff
	var mantissa := bits & 0xfffffffffffff
	var exponent := -1074
	if biased != 0:
		mantissa |= 1 << 52
		exponent = biased - 1075
	while mantissa != 0 and mantissa & 1 == 0 and exponent < 0:
		mantissa >>= 1
		exponent += 1
	return [mantissa, exponent]


static func _fraction_bit_count(bits: int) -> int:
	return maxi(0, -int(_decompose(bits)[1]))


static func _scaled_digits(bits: int, frac_len: int) -> String:
	var parts := _decompose(bits)
	var digits := str(parts[0])
	var twos: int = parts[1] + frac_len
	var fives := frac_len
	while twos > 0:
		var step := mini(twos, 30)
		digits = _multiply_digits(digits, 1 << step)
		twos -= step
	while fives > 0:
		var step := mini(fives, 13)
		digits = _multiply_digits(digits, int(pow(5, step)))
		fives -= step
	return digits


static func _multiply_digits(digits: String, factor: int) -> String:
	if digits == "0":
		return digits
	var out := PackedByteArray()
	var carry := 0
	for index in range(digits.length() - 1, -1, -1):
		var product := (digits.unicode_at(index) - 48) * factor + carry
		out.append(48 + product % 10)
		carry = floori(product / 10.0)
	while carry > 0:
		out.append(48 + carry % 10)
		carry = floori(carry / 10.0)
	out.reverse()
	return out.get_string_from_ascii()


static func _add_digits(a: String, b: String) -> String:
	var size := maxi(a.length(), b.length()) + 1
	var out := PackedByteArray()
	out.resize(size)
	var carry := 0
	for index in range(size):
		var sum := carry
		if index < a.length():
			sum += a.unicode_at(a.length() - 1 - index) - 48
		if index < b.length():
			sum += b.unicode_at(b.length() - 1 - index) - 48
		out[size - 1 - index] = 48 + sum % 10
		carry = 1 if sum >= 10 else 0
	var digits := out.get_string_from_ascii().lstrip("0")
	return "0" if digits.is_empty() else digits


static func _compare_digits(a: String, b: String) -> int:
	if a.length() != b.length():
		return -1 if a.length() < b.length() else 1
	if a == b:
		return 0
	return -1 if a < b else 1


static func _round_digits(exact: String, drop: int) -> String:
	var kept := exact.substr(0, exact.length() - drop)
	var rest := exact.substr(exact.length() - drop)
	var half := "5" + "0".repeat(drop - 1)
	if rest > half or (rest == half and (kept.unicode_at(kept.length() - 1) - 48) % 2 == 1):
		kept = _add_digits(kept, "1")
	return kept + "0".repeat(drop)


static func _round_trips(candidate: String, low: String, high: String, inclusive: bool) -> bool:
	var doubled := _add_digits(candidate, candidate)
	var against_low := _compare_digits(doubled, low)
	if against_low < 0 or (against_low == 0 and not inclusive):
		return false
	var against_high := _compare_digits(doubled, high)
	return against_high < 0 or (against_high == 0 and inclusive)


static func _invariant_fraction_text(value: float) -> String:
	if is_nan(value) or is_inf(value) or (absf(value) < 1e17 and value == floorf(value)):
		return ""
	var shortest := _shortest_digits(value)
	var digits: String = shortest[0]
	var scale: int = shortest[1]
	if scale > 17 or scale < -3:
		if digits.length() == 1:
			return ""
		var exponent := scale - 1
		return "%sE%s%02d" % [digits.substr(1), "-" if exponent < 0 else "+", absi(exponent)]
	if scale <= 0:
		return "0".repeat(-scale) + digits
	return digits.substr(scale)


static func _fraction_value(value: float, fraction_text: String) -> int:
	if fraction_text.is_empty():
		return 0
	if fraction_text.is_valid_int() and fraction_text.to_int() <= 2147483647:
		return fraction_text.to_int()
	var is_float32 := value == YarnNumber.to_f32(value)
	var shortest := _display_digits(value) if is_float32 else _shortest_digits(value)
	var digits: String = shortest[0]
	var scale: int = shortest[1]
	if scale >= digits.length():
		return 0
	return digits.substr(maxi(scale, 0)).to_int()


static func _display_digits(value: float) -> Array:
	var body := YarnNumber.to_display_string(value).trim_prefix("-")
	var exponent := 0
	var e_index := body.find("E")
	if e_index != -1:
		exponent = body.substr(e_index + 1).trim_prefix("+").to_int()
		body = body.substr(0, e_index)
	var point := body.find(".")
	return [body.replace(".", ""), (body.length() if point == -1 else point) + exponent]


# ---------------------------------------------------------------------- #
# Cardinal rule groups
# ---------------------------------------------------------------------- #

static func _c_hi(o: Dictionary) -> String:
	var n: float = o.n
	var i: int = o.i
	if i == 0 or n == 1.0:
		return "one"
	return "other"


static func _c_hy(o: Dictionary) -> String:
	var i: int = o.i
	if i == 0 or i == 1:
		return "one"
	return "other"


static func _c_en(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	if i == 1 and v == 0:
		return "one"
	return "other"


static func _c_si(o: Dictionary) -> String:
	var n: float = o.n
	var i: int = o.i
	var f: int = o.f
	if n == 0.0 or n == 1.0 or (i == 0 and f == 1):
		return "one"
	return "other"


static func _c_ak(o: Dictionary) -> String:
	var n: float = o.n
	if floorf(n) == n and n >= 0.0 and n <= 1.0:
		return "one"
	return "other"


static func _c_tzm(o: Dictionary) -> String:
	var n: float = o.n
	if (floorf(n) == n and n >= 0.0 and n <= 1.0) or (floorf(n) == n and n >= 11.0 and n <= 99.0):
		return "one"
	return "other"


static func _c_tr(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	return "other"


static func _c_da(o: Dictionary) -> String:
	var n: float = o.n
	var i: int = o.i
	var t: int = o.t
	if n == 1.0 or (t != 0 and i == 0) or i == 1:
		return "one"
	return "other"


static func _c_is(o: Dictionary) -> String:
	var i: int = o.i
	var t: int = o.t
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	var t_mod10 := t % 10
	var t_mod100 := t % 100
	if (t == 0 and i_mod10 == 1 and i_mod100 != 11) or (t_mod10 == 1 and t_mod100 != 11):
		return "one"
	return "other"


static func _c_mk(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var f: int = o.f
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	var f_mod10 := f % 10
	var f_mod100 := f % 100
	if (v == 0 and i_mod10 == 1 and i_mod100 != 11) or (f_mod10 == 1 and f_mod100 != 11):
		return "one"
	return "other"


static func _c_fil(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var f: int = o.f
	var i_mod10 := i % 10
	var f_mod10 := f % 10
	if (v == 0 and i == 1) or i == 2 or i == 3 \
			or (v == 0 and not (i_mod10 == 4 or i_mod10 == 6 or i_mod10 == 9)) \
			or (v != 0 and not (f_mod10 == 4 or f_mod10 == 6 or f_mod10 == 9)):
		return "one"
	return "other"


static func _c_lv(o: Dictionary) -> String:
	var n: float = o.n
	var v: int = o.v
	var f: int = o.f
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	var f_mod10 := f % 10
	var f_mod100 := f % 100
	if n_mod10 == 0.0 or (floorf(n_mod100) == n_mod100 and n_mod100 >= 11.0 and n_mod100 <= 19.0) \
			or (v == 2 and f_mod100 >= 11 and f_mod100 <= 19):
		return "zero"
	if (n_mod10 == 1.0 and n_mod100 != 11.0) or (v == 2 and f_mod10 == 1 and f_mod100 != 11) \
			or (v != 2 and f_mod10 == 1):
		return "one"
	return "other"


static func _c_lag(o: Dictionary) -> String:
	var n: float = o.n
	var i: int = o.i
	if n == 0.0:
		return "zero"
	if i == 0 or (i == 1 and n != 0.0):
		return "one"
	return "other"


static func _c_ksh(o: Dictionary) -> String:
	var n: float = o.n
	if n == 0.0:
		return "zero"
	if n == 1.0:
		return "one"
	return "other"


static func _c_he(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	if (i == 1 and v == 0) or (i == 0 and v != 0):
		return "one"
	if i == 2 and v == 0:
		return "two"
	return "other"


static func _c_se(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	return "other"


static func _c_shi(o: Dictionary) -> String:
	var n: float = o.n
	var i: int = o.i
	if i == 0 or n == 1.0:
		return "one"
	if floorf(n) == n and n >= 2.0 and n <= 10.0:
		return "few"
	return "other"


static func _c_ro(o: Dictionary) -> String:
	var n: float = o.n
	var i: int = o.i
	var v: int = o.v
	var n_mod100 := fmod(n, 100.0)
	if i == 1 and v == 0:
		return "one"
	if v != 0 or n == 0.0 or (n != 1.0 and floorf(n_mod100) == n_mod100 and n_mod100 >= 1.0 and n_mod100 <= 19.0):
		return "few"
	return "other"


static func _c_bs(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var f: int = o.f
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	var f_mod10 := f % 10
	var f_mod100 := f % 100
	if (v == 0 and i_mod10 == 1 and i_mod100 != 11) or (f_mod10 == 1 and f_mod100 != 11):
		return "one"
	if (v == 0 and i_mod10 >= 2 and i_mod10 <= 4 and not (i_mod100 >= 12 and i_mod100 <= 14)) \
			or (f_mod10 >= 2 and f_mod10 <= 4 and not (f_mod100 >= 12 and f_mod100 <= 14)):
		return "few"
	return "other"


static func _c_fr(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var i_mod1000000 := i % 1000000
	if i == 0 or i == 1:
		return "one"
	if i != 0 and i_mod1000000 == 0 and v == 0:
		return "many"
	return "other"


static func _c_pt(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var i_mod1000000 := i % 1000000
	if i >= 0 and i <= 1:
		return "one"
	if i != 0 and i_mod1000000 == 0 and v == 0:
		return "many"
	return "other"


static func _c_it(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var i_mod1000000 := i % 1000000
	if i == 1 and v == 0:
		return "one"
	if i != 0 and i_mod1000000 == 0 and v == 0:
		return "many"
	return "other"


static func _c_es(o: Dictionary) -> String:
	var n: float = o.n
	var i: int = o.i
	var v: int = o.v
	var i_mod1000000 := i % 1000000
	if n == 1.0:
		return "one"
	if i != 0 and i_mod1000000 == 0 and v == 0:
		return "many"
	return "other"


static func _c_gd(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0 or n == 11.0:
		return "one"
	if n == 2.0 or n == 12.0:
		return "two"
	if (floorf(n) == n and n >= 3.0 and n <= 10.0) or (floorf(n) == n and n >= 13.0 and n <= 19.0):
		return "few"
	return "other"


static func _c_sl(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var i_mod100 := i % 100
	if v == 0 and i_mod100 == 1:
		return "one"
	if v == 0 and i_mod100 == 2:
		return "two"
	if (v == 0 and i_mod100 >= 3 and i_mod100 <= 4) or v != 0:
		return "few"
	return "other"


static func _c_dsb(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var f: int = o.f
	var i_mod100 := i % 100
	var f_mod100 := f % 100
	if (v == 0 and i_mod100 == 1) or f_mod100 == 1:
		return "one"
	if (v == 0 and i_mod100 == 2) or f_mod100 == 2:
		return "two"
	if (v == 0 and i_mod100 >= 3 and i_mod100 <= 4) or (f_mod100 >= 3 and f_mod100 <= 4):
		return "few"
	return "other"


static func _c_cs(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	if i == 1 and v == 0:
		return "one"
	if i >= 2 and i <= 4 and v == 0:
		return "few"
	if v != 0:
		return "many"
	return "other"


static func _c_pl(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	if i == 1 and v == 0:
		return "one"
	if v == 0 and i_mod10 >= 2 and i_mod10 <= 4 and not (i_mod100 >= 12 and i_mod100 <= 14):
		return "few"
	if (v == 0 and i != 1 and i_mod10 >= 0 and i_mod10 <= 1) \
			or (v == 0 and i_mod10 >= 5 and i_mod10 <= 9) \
			or (v == 0 and i_mod100 >= 12 and i_mod100 <= 14):
		return "many"
	return "other"


static func _c_be(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	if n_mod10 == 1.0 and n_mod100 != 11.0:
		return "one"
	if floorf(n_mod10) == n_mod10 and n_mod10 >= 2.0 and n_mod10 <= 4.0 and not (floorf(n_mod100) == n_mod100 and n_mod100 >= 12.0 and n_mod100 <= 14.0):
		return "few"
	if n_mod10 == 0.0 or (floorf(n_mod10) == n_mod10 and n_mod10 >= 5.0 and n_mod10 <= 9.0) \
			or (floorf(n_mod100) == n_mod100 and n_mod100 >= 11.0 and n_mod100 <= 14.0):
		return "many"
	return "other"


static func _c_lt(o: Dictionary) -> String:
	var n: float = o.n
	var f: int = o.f
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	if n_mod10 == 1.0 and not (floorf(n_mod100) == n_mod100 and n_mod100 >= 11.0 and n_mod100 <= 19.0):
		return "one"
	if floorf(n_mod10) == n_mod10 and n_mod10 >= 2.0 and n_mod10 <= 9.0 and not (floorf(n_mod100) == n_mod100 and n_mod100 >= 11.0 and n_mod100 <= 19.0):
		return "few"
	if f != 0:
		return "many"
	return "other"


static func _c_ru(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	if v == 0 and i_mod10 == 1 and i_mod100 != 11:
		return "one"
	if v == 0 and i_mod10 >= 2 and i_mod10 <= 4 and not (i_mod100 >= 12 and i_mod100 <= 14):
		return "few"
	if (v == 0 and i_mod10 == 0) or (v == 0 and i_mod10 >= 5 and i_mod10 <= 9) \
			or (v == 0 and i_mod100 >= 11 and i_mod100 <= 14):
		return "many"
	return "other"


static func _c_br(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	var n_mod1000000 := fmod(n, 1000000.0)
	if n_mod10 == 1.0 and not (n_mod100 == 11.0 or n_mod100 == 71.0 or n_mod100 == 91.0):
		return "one"
	if n_mod10 == 2.0 and not (n_mod100 == 12.0 or n_mod100 == 72.0 or n_mod100 == 92.0):
		return "two"
	if ((floorf(n_mod10) == n_mod10 and n_mod10 >= 3.0 and n_mod10 <= 4.0) or n_mod10 == 9.0) \
			and not ((floorf(n_mod100) == n_mod100 and n_mod100 >= 10.0 and n_mod100 <= 19.0) \
				or (floorf(n_mod100) == n_mod100 and n_mod100 >= 70.0 and n_mod100 <= 79.0) \
				or (floorf(n_mod100) == n_mod100 and n_mod100 >= 90.0 and n_mod100 <= 99.0)):
		return "few"
	if n != 0.0 and n_mod1000000 == 0.0:
		return "many"
	return "other"


static func _c_mt(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod100 := fmod(n, 100.0)
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	if n == 0.0 or (floorf(n_mod100) == n_mod100 and n_mod100 >= 3.0 and n_mod100 <= 10.0):
		return "few"
	if floorf(n_mod100) == n_mod100 and n_mod100 >= 11.0 and n_mod100 <= 19.0:
		return "many"
	return "other"


static func _c_ga(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	if floorf(n) == n and n >= 3.0 and n <= 6.0:
		return "few"
	if floorf(n) == n and n >= 7.0 and n <= 10.0:
		return "many"
	return "other"


static func _c_gv(o: Dictionary) -> String:
	var i: int = o.i
	var v: int = o.v
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	if v == 0 and i_mod10 == 1:
		return "one"
	if v == 0 and i_mod10 == 2:
		return "two"
	if (v == 0 and i_mod100 == 0) or i_mod100 == 20 or i_mod100 == 40 or i_mod100 == 60 \
			or i_mod100 == 80:
		return "few"
	if v != 0:
		return "many"
	return "other"


static func _c_kw(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod100 := fmod(n, 100.0)
	var n_mod1000 := fmod(n, 1000.0)
	var n_mod100000 := fmod(n, 100000.0)
	var n_mod1000000 := fmod(n, 1000000.0)
	if n == 0.0:
		return "zero"
	if n == 1.0:
		return "one"
	if n_mod100 == 2.0 or n_mod100 == 22.0 or n_mod100 == 42.0 or n_mod100 == 62.0 \
			or n_mod100 == 82.0 \
			or (n_mod1000 == 0.0 and floorf(n_mod100000) == n_mod100000 and n_mod100000 >= 1000.0 and n_mod100000 <= 20000.0) \
			or n_mod100000 == 40000.0 or n_mod100000 == 60000.0 or n_mod100000 == 80000.0 \
			or (n != 0.0 and n_mod1000000 == 100000.0):
		return "two"
	if n_mod100 == 3.0 or n_mod100 == 23.0 or n_mod100 == 43.0 or n_mod100 == 63.0 \
			or n_mod100 == 83.0:
		return "few"
	if (n != 1.0 and n_mod100 == 1.0) or n_mod100 == 21.0 or n_mod100 == 41.0 or n_mod100 == 61.0 \
			or n_mod100 == 81.0:
		return "many"
	return "other"


static func _c_ar(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod100 := fmod(n, 100.0)
	if n == 0.0:
		return "zero"
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	if floorf(n_mod100) == n_mod100 and n_mod100 >= 3.0 and n_mod100 <= 10.0:
		return "few"
	if floorf(n_mod100) == n_mod100 and n_mod100 >= 11.0 and n_mod100 <= 99.0:
		return "many"
	return "other"


static func _c_cy(o: Dictionary) -> String:
	var n: float = o.n
	if n == 0.0:
		return "zero"
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	if n == 3.0:
		return "few"
	if n == 6.0:
		return "many"
	return "other"


static func _cardinal_dispatch() -> Dictionary:
	if _cardinal_dispatch_ready:
		return _cardinal_dispatch_cache
	_dispatch_mutex.lock()
	if not _cardinal_dispatch_ready:
		var d := {}
		for code in ["am", "as", "bn", "doi", "fa", "gu", "hi", "kn", "pcm", "zu"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_hi")
		for code in ["ff", "hy", "kab"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_hy")
		for code in ["ast", "de", "en", "et", "fi", "fy", "gl", "ia", "io", "ji", "lij", "nl",
			"sc", "scn", "sv", "sw", "ur", "yi"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_en")
		d["si"] = Callable(YarnCldrPluralRules, "_c_si")
		for code in ["ak", "bho", "guw", "ln", "mg", "nso", "pa", "ti", "wa"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_ak")
		d["tzm"] = Callable(YarnCldrPluralRules, "_c_tzm")
		for code in ["af", "an", "asa", "az", "bal", "bem", "bez", "bg", "brx", "ce", "cgg",
			"chr", "ckb", "dv", "ee", "el", "eo", "eu", "fo", "fur", "gsw", "ha", "haw", "hu",
			"jgo", "jmc", "ka", "kaj", "kcg", "kk", "kkj", "kl", "ks", "ksb", "ku", "ky", "lb",
			"lg", "mas", "mgo", "ml", "mn", "mr", "nah", "nb", "nd", "ne", "nn", "nnh", "no",
			"nr", "ny", "nyn", "om", "or", "os", "pap", "ps", "rm", "rof", "rwk", "saq", "sd",
			"sdh", "seh", "sn", "so", "sq", "ss", "ssy", "st", "syr", "ta", "te", "teo", "tig",
			"tk", "tn", "tr", "ts", "ug", "uz", "ve", "vo", "vun", "wae", "xh", "xog"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_tr")
		d["da"] = Callable(YarnCldrPluralRules, "_c_da")
		d["is"] = Callable(YarnCldrPluralRules, "_c_is")
		d["mk"] = Callable(YarnCldrPluralRules, "_c_mk")
		for code in ["ceb", "fil", "tl"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_fil")
		for code in ["lv", "prg"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_lv")
		d["lag"] = Callable(YarnCldrPluralRules, "_c_lag")
		d["ksh"] = Callable(YarnCldrPluralRules, "_c_ksh")
		for code in ["he", "iw"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_he")
		for code in ["iu", "naq", "sat", "se", "sma", "smi", "smj", "smn", "sms"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_se")
		d["shi"] = Callable(YarnCldrPluralRules, "_c_shi")
		for code in ["mo", "ro"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_ro")
		for code in ["bs", "hr", "sh", "sr"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_bs")
		d["fr"] = Callable(YarnCldrPluralRules, "_c_fr")
		d["pt"] = Callable(YarnCldrPluralRules, "_c_pt")
		for code in ["ca", "it", "pt_PT", "vec"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_it")
		d["es"] = Callable(YarnCldrPluralRules, "_c_es")
		d["gd"] = Callable(YarnCldrPluralRules, "_c_gd")
		d["sl"] = Callable(YarnCldrPluralRules, "_c_sl")
		for code in ["dsb", "hsb"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_dsb")
		for code in ["cs", "sk"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_cs")
		d["pl"] = Callable(YarnCldrPluralRules, "_c_pl")
		d["be"] = Callable(YarnCldrPluralRules, "_c_be")
		d["lt"] = Callable(YarnCldrPluralRules, "_c_lt")
		for code in ["ru", "uk"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_ru")
		d["br"] = Callable(YarnCldrPluralRules, "_c_br")
		d["mt"] = Callable(YarnCldrPluralRules, "_c_mt")
		d["ga"] = Callable(YarnCldrPluralRules, "_c_ga")
		d["gv"] = Callable(YarnCldrPluralRules, "_c_gv")
		d["kw"] = Callable(YarnCldrPluralRules, "_c_kw")
		for code in ["ar", "ars"]:
			d[code] = Callable(YarnCldrPluralRules, "_c_ar")
		d["cy"] = Callable(YarnCldrPluralRules, "_c_cy")
		_cardinal_dispatch_cache = d
		_cardinal_dispatch_ready = true
	_dispatch_mutex.unlock()
	return _cardinal_dispatch_cache

static var _cardinal_dispatch_cache: Dictionary = {}
static var _cardinal_dispatch_ready := false
static var _dispatch_mutex: Mutex = Mutex.new()


# ---------------------------------------------------------------------- #
# Ordinal rule groups
# ---------------------------------------------------------------------- #

static func _o_sv(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	if (n_mod10 == 1.0 or n_mod10 == 2.0) and not (n_mod100 == 11.0 or n_mod100 == 12.0):
		return "one"
	return "other"


static func _o_fr(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	return "other"


static func _o_hu(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0 or n == 5.0:
		return "one"
	return "other"


static func _o_ne(o: Dictionary) -> String:
	var n: float = o.n
	if floorf(n) == n and n >= 1.0 and n <= 4.0:
		return "one"
	return "other"


static func _o_be(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	if (n_mod10 == 2.0 or n_mod10 == 3.0) and not (n_mod100 == 12.0 or n_mod100 == 13.0):
		return "few"
	return "other"


static func _o_uk(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	if n_mod10 == 3.0 and n_mod100 != 13.0:
		return "few"
	return "other"


static func _o_tk(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	if n_mod10 == 6.0 or n_mod10 == 9.0 or n == 10.0:
		return "few"
	return "other"


static func _o_kk(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	if n_mod10 == 6.0 or n_mod10 == 9.0 or (n_mod10 == 0.0 and n != 0.0):
		return "many"
	return "other"


static func _o_it(o: Dictionary) -> String:
	var n: float = o.n
	if n == 11.0 or n == 8.0 or n == 80.0 or n == 800.0:
		return "many"
	return "other"


static func _o_lij(o: Dictionary) -> String:
	var n: float = o.n
	if n == 11.0 or n == 8.0 or (floorf(n) == n and n >= 80.0 and n <= 89.0) or (floorf(n) == n and n >= 800.0 and n <= 899.0):
		return "many"
	return "other"


static func _o_ka(o: Dictionary) -> String:
	var i: int = o.i
	var i_mod100 := i % 100
	if i == 1:
		return "one"
	if i == 0 or (i_mod100 >= 2 and i_mod100 <= 20) or i_mod100 == 40 or i_mod100 == 60 \
			or i_mod100 == 80:
		return "many"
	return "other"


static func _o_sq(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	if n == 1.0:
		return "one"
	if n_mod10 == 4.0 and n_mod100 != 14.0:
		return "many"
	return "other"


static func _o_kw(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod100 := fmod(n, 100.0)
	if (floorf(n) == n and n >= 1.0 and n <= 4.0) or (floorf(n_mod100) == n_mod100 and n_mod100 >= 1.0 and n_mod100 <= 4.0) \
			or (floorf(n_mod100) == n_mod100 and n_mod100 >= 21.0 and n_mod100 <= 24.0) or (floorf(n_mod100) == n_mod100 and n_mod100 >= 41.0 and n_mod100 <= 44.0) \
			or (floorf(n_mod100) == n_mod100 and n_mod100 >= 61.0 and n_mod100 <= 64.0) or (floorf(n_mod100) == n_mod100 and n_mod100 >= 81.0 and n_mod100 <= 84.0):
		return "one"
	if n == 5.0 or n_mod100 == 5.0:
		return "many"
	return "other"


static func _o_en(o: Dictionary) -> String:
	var n: float = o.n
	var n_mod10 := fmod(n, 10.0)
	var n_mod100 := fmod(n, 100.0)
	if n_mod10 == 1.0 and n_mod100 != 11.0:
		return "one"
	if n_mod10 == 2.0 and n_mod100 != 12.0:
		return "two"
	if n_mod10 == 3.0 and n_mod100 != 13.0:
		return "few"
	return "other"


static func _o_mr(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	if n == 2.0 or n == 3.0:
		return "two"
	if n == 4.0:
		return "few"
	return "other"


static func _o_gd(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0 or n == 11.0:
		return "one"
	if n == 2.0 or n == 12.0:
		return "two"
	if n == 3.0 or n == 13.0:
		return "few"
	return "other"


static func _o_ca(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0 or n == 3.0:
		return "one"
	if n == 2.0:
		return "two"
	if n == 4.0:
		return "few"
	return "other"


static func _o_mk(o: Dictionary) -> String:
	var i: int = o.i
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	if i_mod10 == 1 and i_mod100 != 11:
		return "one"
	if i_mod10 == 2 and i_mod100 != 12:
		return "two"
	if (i_mod10 == 7 or i_mod10 == 8) and not (i_mod100 == 17 or i_mod100 == 18):
		return "many"
	return "other"


static func _o_az(o: Dictionary) -> String:
	var i: int = o.i
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	var i_mod1000 := i % 1000
	if i_mod10 == 1 or i_mod10 == 2 or i_mod10 == 5 or i_mod10 == 7 or i_mod10 == 8 \
			or i_mod100 == 20 or i_mod100 == 50 or i_mod100 == 70 or i_mod100 == 80:
		return "one"
	if i_mod10 == 3 or i_mod10 == 4 or i_mod1000 == 100 or i_mod1000 == 200 or i_mod1000 == 300 \
			or i_mod1000 == 400 or i_mod1000 == 500 or i_mod1000 == 600 or i_mod1000 == 700 \
			or i_mod1000 == 800 or i_mod1000 == 900:
		return "few"
	if i == 0 or i_mod10 == 6 or i_mod100 == 40 or i_mod100 == 60 or i_mod100 == 90:
		return "many"
	return "other"


static func _o_hi(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	if n == 2.0 or n == 3.0:
		return "two"
	if n == 4.0:
		return "few"
	if n == 6.0:
		return "many"
	return "other"


static func _o_bn(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0 or n == 5.0 or n == 7.0 or n == 8.0 or n == 9.0 or n == 10.0:
		return "one"
	if n == 2.0 or n == 3.0:
		return "two"
	if n == 4.0:
		return "few"
	if n == 6.0:
		return "many"
	return "other"


static func _o_or(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0 or n == 5.0 or (floorf(n) == n and n >= 7.0 and n <= 9.0):
		return "one"
	if n == 2.0 or n == 3.0:
		return "two"
	if n == 4.0:
		return "few"
	if n == 6.0:
		return "many"
	return "other"


static func _o_cy(o: Dictionary) -> String:
	var n: float = o.n
	if n == 0.0 or n == 7.0 or n == 8.0 or n == 9.0:
		return "zero"
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	if n == 3.0 or n == 4.0:
		return "few"
	if n == 5.0 or n == 6.0:
		return "many"
	return "other"


static func _ordinal_dispatch() -> Dictionary:
	if _ordinal_dispatch_ready:
		return _ordinal_dispatch_cache
	_dispatch_mutex.lock()
	if not _ordinal_dispatch_ready:
		var d := {}
		d["sv"] = Callable(YarnCldrPluralRules, "_o_sv")
		for code in ["bal", "fil", "fr", "ga", "hy", "lo", "mo", "ms", "ro", "tl", "vi"]:
			d[code] = Callable(YarnCldrPluralRules, "_o_fr")
		d["hu"] = Callable(YarnCldrPluralRules, "_o_hu")
		d["ne"] = Callable(YarnCldrPluralRules, "_o_ne")
		d["be"] = Callable(YarnCldrPluralRules, "_o_be")
		d["uk"] = Callable(YarnCldrPluralRules, "_o_uk")
		d["tk"] = Callable(YarnCldrPluralRules, "_o_tk")
		d["kk"] = Callable(YarnCldrPluralRules, "_o_kk")
		for code in ["it", "sc", "scn", "vec"]:
			d[code] = Callable(YarnCldrPluralRules, "_o_it")
		d["lij"] = Callable(YarnCldrPluralRules, "_o_lij")
		d["ka"] = Callable(YarnCldrPluralRules, "_o_ka")
		d["sq"] = Callable(YarnCldrPluralRules, "_o_sq")
		d["kw"] = Callable(YarnCldrPluralRules, "_o_kw")
		d["en"] = Callable(YarnCldrPluralRules, "_o_en")
		d["mr"] = Callable(YarnCldrPluralRules, "_o_mr")
		d["gd"] = Callable(YarnCldrPluralRules, "_o_gd")
		d["ca"] = Callable(YarnCldrPluralRules, "_o_ca")
		d["mk"] = Callable(YarnCldrPluralRules, "_o_mk")
		d["az"] = Callable(YarnCldrPluralRules, "_o_az")
		for code in ["gu", "hi"]:
			d[code] = Callable(YarnCldrPluralRules, "_o_hi")
		for code in ["as", "bn"]:
			d[code] = Callable(YarnCldrPluralRules, "_o_bn")
		d["or"] = Callable(YarnCldrPluralRules, "_o_or")
		d["cy"] = Callable(YarnCldrPluralRules, "_o_cy")
		_ordinal_dispatch_cache = d
		_ordinal_dispatch_ready = true
	_dispatch_mutex.unlock()
	return _ordinal_dispatch_cache

static var _ordinal_dispatch_cache: Dictionary = {}
static var _ordinal_dispatch_ready := false
