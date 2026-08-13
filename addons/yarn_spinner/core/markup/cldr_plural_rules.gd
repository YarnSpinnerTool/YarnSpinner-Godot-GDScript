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
## "1.50" or "1.5") can never be recovered. This implementation treats v
## as the count of significant fraction digits and derives f from those
## digits directly, which makes v and w (fraction digits without trailing
## zeros) identical, and likewise f and t identical. Every rule below that
## the CLDR spec writes in terms of v/f still behaves correctly for that
## reason: v/f and w/t only ever disagree over trailing zeros this code
## cannot see.


## Number of decimal places examined when deriving fraction operands.
const _FRACTION_PRECISION := 6

## Legacy or alternate language codes mapped to the code CLDR data uses.
const _LANGUAGE_ALIASES := {
	"iw": "he",
	"in": "id",
	"tl": "fil",
	"no": "nb",
}


## Returns the CLDR operand set for a non-negative number.
static func get_operands(value: float) -> Dictionary:
	var n := absf(value)
	var i := int(n)

	var fraction_digits := ""
	var remainder := n - float(i)
	if remainder > 0.0:
		var scaled := "%.*f" % [_FRACTION_PRECISION, remainder]
		var dot_index := scaled.find(".")
		if dot_index != -1:
			fraction_digits = scaled.substr(dot_index + 1)
			while fraction_digits.length() > 0 and fraction_digits.ends_with("0"):
				fraction_digits = fraction_digits.substr(0, fraction_digits.length() - 1)

	var v := fraction_digits.length()
	var f := 0 if v == 0 else int(fraction_digits)

	return {
		"n": n,
		"i": i,
		"v": v,
		"f": f,
		"t": f,
	}


## Normalises a locale/language code: lowercase, region and script stripped,
## legacy aliases resolved.
static func normalise_language(language_code: String) -> String:
	var code := language_code.split("-")[0].split("_")[0].to_lower()
	return _LANGUAGE_ALIASES.get(code, code)


## Returns the CLDR cardinal plural case ("zero", "one", "two", "few",
## "many", or "other") for the given language and number.
static func get_cardinal_case(language_code: String, value: float) -> String:
	var language := normalise_language(language_code)
	var rule: Callable = _cardinal_dispatch().get(language, Callable())
	if not rule.is_valid():
		rule = Callable(YarnCldrPluralRules, "_c_default")
	var operands := get_operands(value)
	return rule.call(operands)


## Returns the CLDR ordinal plural case ("zero", "one", "two", "few",
## "many", or "other") for the given language and integer.
static func get_ordinal_case(language_code: String, value: int) -> String:
	var language := normalise_language(language_code)
	var rule: Callable = _ordinal_dispatch().get(language, Callable())
	if not rule.is_valid():
		rule = Callable(YarnCldrPluralRules, "_o_default")
	return rule.call(absi(value))


# ---------------------------------------------------------------------- #
# Cardinal rule groups
# ---------------------------------------------------------------------- #

## Fallback used by every locale with no distinct cardinal forms, and any
## locale this file doesn't recognise.
static func _c_default(_o: Dictionary) -> String:
	return "other"


## one: i = 1 and v = 0. The most common CLDR cardinal shape.
static func _c_one_i1v0(o: Dictionary) -> String:
	if o.i == 1 and o.v == 0:
		return "one"
	return "other"


## Danish: one for exactly 1, and also for any decimal value whose integer
## part is 0 or 1 (so 0.5 and 1.5 both read as "one").
static func _c_danish(o: Dictionary) -> String:
	if o.v == 0 and o.i == 1:
		return "one"
	if o.v != 0 and (o.i == 0 or o.i == 1):
		return "one"
	return "other"


## Icelandic: one for integers ending in 1 (not 11), and for every value
## with a non-zero fraction.
static func _c_icelandic(o: Dictionary) -> String:
	if o.t == 0 and int(o.i) % 10 == 1 and int(o.i) % 100 != 11:
		return "one"
	if o.t != 0:
		return "one"
	return "other"


## French: 0 and 1 both read as singular; whole millions get their own form.
static func _c_french(o: Dictionary) -> String:
	if o.i == 0 or o.i == 1:
		return "one"
	if o.v == 0 and o.i != 0 and int(o.i) % 1000000 == 0:
		return "many"
	return "other"


## Italian / Spanish: singular only for exactly 1; whole millions get their
## own form.
static func _c_it_es(o: Dictionary) -> String:
	if o.i == 1 and o.v == 0:
		return "one"
	if o.v == 0 and o.i != 0 and int(o.i) % 1000000 == 0:
		return "many"
	return "other"


## Russian / Ukrainian / Belarusian.
static func _c_russian(o: Dictionary) -> String:
	if o.v != 0:
		return "other"
	var i: int = o.i
	var mod10 := i % 10
	var mod100 := i % 100
	if mod10 == 1 and mod100 != 11:
		return "one"
	if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
		return "few"
	if mod10 == 0 or (mod10 >= 5 and mod10 <= 9) or (mod100 >= 11 and mod100 <= 14):
		return "many"
	return "other"


## Polish.
static func _c_polish(o: Dictionary) -> String:
	var i: int = o.i
	if o.i == 1 and o.v == 0:
		return "one"
	if o.v != 0:
		return "other"
	var mod10 := i % 10
	var mod100 := i % 100
	if mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
		return "few"
	if (i != 1 and (mod10 == 0 or mod10 == 1)) or (mod10 >= 5 and mod10 <= 9) or (mod100 >= 12 and mod100 <= 14):
		return "many"
	return "other"


## Czech / Slovak.
static func _c_czech_slovak(o: Dictionary) -> String:
	if o.i == 1 and o.v == 0:
		return "one"
	if int(o.i) >= 2 and int(o.i) <= 4 and o.v == 0:
		return "few"
	if o.v != 0:
		return "many"
	return "other"


## Romanian.
static func _c_romanian(o: Dictionary) -> String:
	if o.i == 1 and o.v == 0:
		return "one"
	var mod100: int = int(o.i) % 100
	if o.v != 0 or o.i == 0 or (mod100 >= 2 and mod100 <= 19):
		return "few"
	return "other"


## Bosnian / Croatian / Serbian (and other Serbo-Croatian variants).
static func _c_bcs(o: Dictionary) -> String:
	var i: int = o.i
	var f: int = o.f
	var i_mod10 := i % 10
	var i_mod100 := i % 100
	var f_mod10 := f % 10
	var f_mod100 := f % 100
	if (o.v == 0 and i_mod10 == 1 and i_mod100 != 11) or (o.v != 0 and f_mod10 == 1 and f_mod100 != 11):
		return "one"
	if (o.v == 0 and i_mod10 >= 2 and i_mod10 <= 4 and (i_mod100 < 12 or i_mod100 > 14)) \
		or (o.v != 0 and f_mod10 >= 2 and f_mod10 <= 4 and (f_mod100 < 12 or f_mod100 > 14)):
		return "few"
	return "other"


## Arabic.
static func _c_arabic(o: Dictionary) -> String:
	var n: float = o.n
	if n == 0.0:
		return "zero"
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	if o.v == 0:
		var mod100: int = int(o.i) % 100
		if mod100 >= 3 and mod100 <= 10:
			return "few"
		if mod100 >= 11 and mod100 <= 99:
			return "many"
	return "other"


## Hebrew (modern CLDR: only "one", "two", and "other" survive in current
## data; older revisions also had a "many" case, which is intentionally not
## reproduced here).
static func _c_hebrew(o: Dictionary) -> String:
	if o.i == 1 and o.v == 0:
		return "one"
	if o.i == 2 and o.v == 0:
		return "two"
	return "other"


## Welsh.
static func _c_welsh(o: Dictionary) -> String:
	match o.n:
		0.0: return "zero"
		1.0: return "one"
		2.0: return "two"
		3.0: return "few"
		6.0: return "many"
		_: return "other"


## Irish.
static func _c_irish(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	if n == 2.0:
		return "two"
	if n >= 3.0 and n <= 6.0:
		return "few"
	if n >= 7.0 and n <= 10.0:
		return "many"
	return "other"


## Scottish Gaelic.
static func _c_scottish_gaelic(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0 or n == 11.0:
		return "one"
	if n == 2.0 or n == 12.0:
		return "two"
	if (n >= 3.0 and n <= 10.0) or (n >= 13.0 and n <= 19.0):
		return "few"
	return "other"


## Breton.
static func _c_breton(o: Dictionary) -> String:
	if o.v != 0:
		return "other"
	var i: int = o.i
	var mod10 := i % 10
	var mod100 := i % 100
	if mod10 == 1 and mod100 != 11 and mod100 != 71 and mod100 != 91:
		return "one"
	if mod10 == 2 and mod100 != 12 and mod100 != 72 and mod100 != 92:
		return "two"
	if (mod10 == 3 or mod10 == 4 or mod10 == 9) \
		and not (mod100 >= 10 and mod100 <= 19) \
		and not (mod100 >= 70 and mod100 <= 79) \
		and not (mod100 >= 90 and mod100 <= 99):
		return "few"
	if i != 0 and mod100 == 0 and i % 1000000 == 0:
		return "many"
	return "other"


## Manx.
static func _c_manx(o: Dictionary) -> String:
	if o.v == 0 and int(o.i) % 10 == 1:
		return "one"
	if o.v == 0 and int(o.i) % 10 == 2:
		return "two"
	if o.v == 0:
		var mod100: int = int(o.i) % 100
		if mod100 == 0 or mod100 == 20 or mod100 == 40 or mod100 == 60 or mod100 == 80:
			return "few"
	if o.v != 0:
		return "many"
	return "other"


## Maltese.
static func _c_maltese(o: Dictionary) -> String:
	var n: float = o.n
	if n == 1.0:
		return "one"
	var mod100: int = int(o.i) % 100
	if n == 0.0 or (mod100 >= 2 and mod100 <= 10):
		return "few"
	if mod100 >= 11 and mod100 <= 19:
		return "many"
	return "other"


## Slovenian.
static func _c_slovenian(o: Dictionary) -> String:
	if o.v != 0:
		return "few"
	var mod100: int = int(o.i) % 100
	if mod100 == 1:
		return "one"
	if mod100 == 2:
		return "two"
	if mod100 == 3 or mod100 == 4:
		return "few"
	return "other"


## Lithuanian.
static func _c_lithuanian(o: Dictionary) -> String:
	if o.f != 0:
		return "many"
	var i: int = o.i
	var mod10 := i % 10
	var mod100 := i % 100
	if mod10 == 1 and not (mod100 >= 11 and mod100 <= 19):
		return "one"
	if mod10 >= 2 and mod10 <= 9 and not (mod100 >= 11 and mod100 <= 19):
		return "few"
	return "other"


## Latvian.
static func _c_latvian(o: Dictionary) -> String:
	var i: int = o.i
	var f: int = o.f
	if o.v == 0:
		var i_mod10 := i % 10
		var i_mod100 := i % 100
		if i_mod10 == 0 or (i_mod100 >= 11 and i_mod100 <= 19):
			return "zero"
		if i_mod10 == 1 and i_mod100 != 11:
			return "one"
	else:
		var f_mod100 := f % 100
		if f_mod100 >= 11 and f_mod100 <= 19:
			return "zero"
		var f_mod10 := f % 10
		if f_mod10 == 1 and f_mod100 != 11:
			return "one"
	return "other"


## Macedonian.
static func _c_macedonian(o: Dictionary) -> String:
	if (o.v == 0 and int(o.i) % 10 == 1) or (o.f % 10 == 1):
		return "one"
	return "other"


## Filipino.
static func _c_filipino(o: Dictionary) -> String:
	if o.v == 0:
		var i: int = o.i
		if i == 1 or i == 2 or i == 3:
			return "one"
		var mod10 := i % 10
		if mod10 != 4 and mod10 != 6 and mod10 != 9:
			return "one"
	else:
		var f_mod10: int = o.f % 10
		if f_mod10 != 4 and f_mod10 != 6 and f_mod10 != 9:
			return "one"
	return "other"


## Sinhala.
static func _c_sinhala(o: Dictionary) -> String:
	var n: float = o.n
	if n == 0.0 or n == 1.0:
		return "one"
	if o.i == 0 and o.f == 1:
		return "one"
	return "other"


## "Zero or one": common to Hindi-family languages, Amharic, Armenian, and
## Persian: one for a zero integer part or a value of exactly 1.
static func _c_zero_or_one(o: Dictionary) -> String:
	if o.i == 0 or o.n == 1.0:
		return "one"
	return "other"


## Nepali: one for an integer part of 0 or 1.
static func _c_nepali(o: Dictionary) -> String:
	if o.i == 0 or o.i == 1:
		return "one"
	return "other"


## Cornish. CLDR's Cornish rules also cover several very large-number
## clauses (multiples of 100,000 and 1,000,000); those are omitted here as
## unreachable in practice for dialogue text.
static func _c_cornish(o: Dictionary) -> String:
	var n: float = o.n
	if n == 0.0:
		return "zero"
	if n == 1.0:
		return "one"
	var mod100: int = int(o.i) % 100
	if mod100 == 2 or mod100 == 22 or mod100 == 42 or mod100 == 62 or mod100 == 82:
		return "two"
	if mod100 == 3 or mod100 == 23 or mod100 == 43 or mod100 == 63 or mod100 == 83:
		return "few"
	if n != 1.0 and (mod100 == 1 or mod100 == 21 or mod100 == 41 or mod100 == 61 or mod100 == 81):
		return "many"
	return "other"


static func _cardinal_dispatch() -> Dictionary:
	if _cardinal_dispatch_cache.is_empty():
		var default_group := Callable(YarnCldrPluralRules, "_c_one_i1v0")
		var no_plural := Callable(YarnCldrPluralRules, "_c_default")
		var zero_or_one := Callable(YarnCldrPluralRules, "_c_zero_or_one")
		var d := {}

		for code in ["en", "de", "nl", "sv", "et", "fi", "eu", "gl", "hu", "tr", "az", "kk",
			"ky", "uz", "mn", "ka", "ta", "te", "kn", "ml", "sw", "ha", "so", "ur", "pt",
			"af", "sq", "bg", "el", "eo", "fo", "nb", "nn", "yi", "ca", "sd", "ks", "os",
			"dv", "ee", "ff", "fy", "gsw", "ku", "lb", "lg", "ps", "rm", "st", "ts", "xh"]:
			d[code] = default_group

		for code in ["ja", "ko", "zh", "yue", "vi", "th", "id", "ms", "my", "lo", "km", "bo",
			"ig", "yo", "dz", "wo", "sah"]:
			d[code] = no_plural

		for code in ["hi", "bn", "gu", "pa", "mr", "fa", "am", "hy"]:
			d[code] = zero_or_one

		d["da"] = Callable(YarnCldrPluralRules, "_c_danish")
		d["is"] = Callable(YarnCldrPluralRules, "_c_icelandic")
		d["fr"] = Callable(YarnCldrPluralRules, "_c_french")
		d["it"] = Callable(YarnCldrPluralRules, "_c_it_es")
		d["es"] = Callable(YarnCldrPluralRules, "_c_it_es")
		d["ru"] = Callable(YarnCldrPluralRules, "_c_russian")
		d["uk"] = Callable(YarnCldrPluralRules, "_c_russian")
		d["be"] = Callable(YarnCldrPluralRules, "_c_russian")
		d["pl"] = Callable(YarnCldrPluralRules, "_c_polish")
		d["cs"] = Callable(YarnCldrPluralRules, "_c_czech_slovak")
		d["sk"] = Callable(YarnCldrPluralRules, "_c_czech_slovak")
		d["ro"] = Callable(YarnCldrPluralRules, "_c_romanian")
		d["hr"] = Callable(YarnCldrPluralRules, "_c_bcs")
		d["sr"] = Callable(YarnCldrPluralRules, "_c_bcs")
		d["bs"] = Callable(YarnCldrPluralRules, "_c_bcs")
		d["ar"] = Callable(YarnCldrPluralRules, "_c_arabic")
		d["he"] = Callable(YarnCldrPluralRules, "_c_hebrew")
		d["cy"] = Callable(YarnCldrPluralRules, "_c_welsh")
		d["ga"] = Callable(YarnCldrPluralRules, "_c_irish")
		d["gd"] = Callable(YarnCldrPluralRules, "_c_scottish_gaelic")
		d["br"] = Callable(YarnCldrPluralRules, "_c_breton")
		d["gv"] = Callable(YarnCldrPluralRules, "_c_manx")
		d["kw"] = Callable(YarnCldrPluralRules, "_c_cornish")
		d["mt"] = Callable(YarnCldrPluralRules, "_c_maltese")
		d["sl"] = Callable(YarnCldrPluralRules, "_c_slovenian")
		d["lt"] = Callable(YarnCldrPluralRules, "_c_lithuanian")
		d["lv"] = Callable(YarnCldrPluralRules, "_c_latvian")
		d["mk"] = Callable(YarnCldrPluralRules, "_c_macedonian")
		d["fil"] = Callable(YarnCldrPluralRules, "_c_filipino")
		d["si"] = Callable(YarnCldrPluralRules, "_c_sinhala")
		d["ne"] = Callable(YarnCldrPluralRules, "_c_nepali")

		_cardinal_dispatch_cache = d
	return _cardinal_dispatch_cache

static var _cardinal_dispatch_cache: Dictionary = {}


# ---------------------------------------------------------------------- #
# Ordinal rule groups
# ---------------------------------------------------------------------- #

## Fallback for every locale with no distinct ordinal forms.
static func _o_default(_n: int) -> String:
	return "other"


## English.
static func _o_english(n: int) -> String:
	var mod10 := n % 10
	var mod100 := n % 100
	if mod10 == 1 and mod100 != 11:
		return "one"
	if mod10 == 2 and mod100 != 12:
		return "two"
	if mod10 == 3 and mod100 != 13:
		return "few"
	return "other"


## French: only "1st" is distinct.
static func _o_one_only(n: int) -> String:
	if n == 1:
		return "one"
	return "other"


## Italian.
static func _o_italian(n: int) -> String:
	if n == 8 or n == 11 or n == 80 or n == 800:
		return "many"
	return "other"


## Welsh.
static func _o_welsh(n: int) -> String:
	match n:
		0, 7, 8, 9: return "zero"
		1: return "one"
		2: return "two"
		3, 4: return "few"
		5, 6: return "many"
		_: return "other"


## Scottish Gaelic.
static func _o_scottish_gaelic(n: int) -> String:
	if n == 1 or n == 11:
		return "one"
	if n == 2 or n == 12:
		return "two"
	if n == 3 or n == 13:
		return "few"
	return "other"


## Catalan.
static func _o_catalan(n: int) -> String:
	if n == 1 or n == 3:
		return "one"
	if n == 2:
		return "two"
	if n == 4:
		return "few"
	return "other"


## Azerbaijani.
static func _o_azerbaijani(n: int) -> String:
	var mod10 := n % 10
	var mod100 := n % 100
	var mod1000 := n % 1000
	if mod10 == 1 or mod10 == 2 or mod10 == 5 or mod10 == 7 or mod10 == 8 \
		or mod100 == 20 or mod100 == 50 or mod100 == 70 or mod100 == 80:
		return "one"
	if mod10 == 3 or mod10 == 4 or mod1000 == 100 or mod1000 == 200 or mod1000 == 300 \
		or mod1000 == 400 or mod1000 == 500 or mod1000 == 600 or mod1000 == 700 \
		or mod1000 == 800 or mod1000 == 900:
		return "few"
	if n == 0 or mod10 == 6 or mod100 == 40 or mod100 == 60 or mod100 == 90:
		return "many"
	return "other"


## Kazakh.
static func _o_kazakh(n: int) -> String:
	var mod10 := n % 10
	if mod10 == 6 or mod10 == 9 or (mod10 == 0 and n != 0):
		return "many"
	return "other"


## Georgian.
static func _o_georgian(n: int) -> String:
	if n == 1:
		return "one"
	var mod100 := n % 100
	if n == 0 or (mod100 >= 2 and mod100 <= 20) or mod100 == 40 or mod100 == 60 or mod100 == 80:
		return "many"
	return "other"


## Hungarian.
static func _o_hungarian(n: int) -> String:
	if n == 1 or n == 5:
		return "one"
	return "other"


## Bengali / Assamese.
static func _o_bengali(n: int) -> String:
	if n == 1 or n == 5 or n == 7 or n == 8 or n == 9 or n == 10:
		return "one"
	if n == 2 or n == 3:
		return "two"
	if n == 4:
		return "few"
	if n == 6:
		return "many"
	return "other"


## Hindi / Gujarati.
static func _o_hindi(n: int) -> String:
	if n == 1:
		return "one"
	if n == 2 or n == 3:
		return "two"
	if n == 4:
		return "few"
	if n == 6:
		return "many"
	return "other"


## Marathi.
static func _o_marathi(n: int) -> String:
	if n == 1:
		return "one"
	if n == 2 or n == 3:
		return "two"
	if n == 4:
		return "few"
	return "other"


## Nepali.
static func _o_nepali(n: int) -> String:
	if n >= 1 and n <= 4:
		return "one"
	return "other"


## Ukrainian.
static func _o_ukrainian(n: int) -> String:
	if n % 10 == 3 and n % 100 != 13:
		return "few"
	return "other"


## Swedish.
static func _o_swedish(n: int) -> String:
	var mod10 := n % 10
	var mod100 := n % 100
	if (mod10 == 1 or mod10 == 2) and mod100 != 11 and mod100 != 12:
		return "one"
	return "other"


## Albanian.
static func _o_albanian(n: int) -> String:
	if n == 1:
		return "one"
	if n % 10 == 4 and n % 100 != 14:
		return "many"
	return "other"


## Armenian.
static func _o_armenian(n: int) -> String:
	if n == 1 or n == 2 or n == 3 or n % 10 == 0:
		return "one"
	return "other"


## Turkmen.
static func _o_turkmen(n: int) -> String:
	var mod10 := n % 10
	if mod10 == 6 or mod10 == 9 or n == 10:
		return "few"
	return "other"


## Tajik.
static func _o_tajik(n: int) -> String:
	if n % 10 == 6 or (n % 10 == 0 and n != 0):
		return "few"
	return "other"


static func _ordinal_dispatch() -> Dictionary:
	if _ordinal_dispatch_cache.is_empty():
		var d := {}
		d["en"] = Callable(YarnCldrPluralRules, "_o_english")
		d["fr"] = Callable(YarnCldrPluralRules, "_o_one_only")
		d["fil"] = Callable(YarnCldrPluralRules, "_o_one_only")
		d["it"] = Callable(YarnCldrPluralRules, "_o_italian")
		d["cy"] = Callable(YarnCldrPluralRules, "_o_welsh")
		d["ga"] = Callable(YarnCldrPluralRules, "_o_one_only")
		d["gd"] = Callable(YarnCldrPluralRules, "_o_scottish_gaelic")
		d["ca"] = Callable(YarnCldrPluralRules, "_o_catalan")
		d["az"] = Callable(YarnCldrPluralRules, "_o_azerbaijani")
		d["kk"] = Callable(YarnCldrPluralRules, "_o_kazakh")
		d["ka"] = Callable(YarnCldrPluralRules, "_o_georgian")
		d["hu"] = Callable(YarnCldrPluralRules, "_o_hungarian")
		d["bn"] = Callable(YarnCldrPluralRules, "_o_bengali")
		d["as"] = Callable(YarnCldrPluralRules, "_o_bengali")
		d["hi"] = Callable(YarnCldrPluralRules, "_o_hindi")
		d["gu"] = Callable(YarnCldrPluralRules, "_o_hindi")
		d["mr"] = Callable(YarnCldrPluralRules, "_o_marathi")
		d["ne"] = Callable(YarnCldrPluralRules, "_o_nepali")
		d["uk"] = Callable(YarnCldrPluralRules, "_o_ukrainian")
		d["sv"] = Callable(YarnCldrPluralRules, "_o_swedish")
		d["sq"] = Callable(YarnCldrPluralRules, "_o_albanian")
		d["hy"] = Callable(YarnCldrPluralRules, "_o_armenian")
		d["tk"] = Callable(YarnCldrPluralRules, "_o_turkmen")
		d["tg"] = Callable(YarnCldrPluralRules, "_o_tajik")
		_ordinal_dispatch_cache = d
	return _ordinal_dispatch_cache

static var _ordinal_dispatch_cache: Dictionary = {}
