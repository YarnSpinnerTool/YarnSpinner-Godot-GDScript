extends GutTest


const CARDINAL_CASES := [
	["en", 1, "one"], ["en", 0, "other"], ["en", 1.5, "other"], ["en", -1, "other"],
	["pt", 0, "one"], ["pt", 1.5, "one"], ["pt", 1000000, "many"],
	["fr", 0.5, "one"], ["es", 1, "one"], ["pt_PT", 1, "one"], ["vec", 1, "one"],
	["kn", 0, "one"], ["zu", 0, "one"], ["ff", 0.5, "one"], ["hy", 1.5, "one"],
	["mr", 0, "other"], ["ne", 0, "other"],
	["is", 0.5, "other"], ["is", 1.1, "one"], ["is", 21, "one"],
	["he", 0.5, "one"], ["he", 2, "two"], ["iw", 2, "two"],
	["mt", 2, "two"], ["mt", 3, "few"],
	["ro", 101, "few"], ["ro", -1, "other"],
	["mk", 11, "other"], ["mk", 1.1, "one"],
	["br", 13, "few"], ["kw", 1000, "two"], ["kw", 100000, "two"],
	["be", 2.5, "few"], ["lt", 2.5, "few"], ["ar", 3.5, "few"], ["ar", -2, "two"], ["ars", 3, "few"],
	["ru", 2, "few"], ["ru", -2, "other"], ["pl", -2, "other"], ["cs", 1.5, "many"],
	["da", 1.5, "one"], ["da", -0.5, "one"],
	["lv", 0.1, "one"], ["lv", 10.5, "other"], ["prg", 0, "zero"], ["ksh", 0, "zero"],
	["tzm", 11, "one"], ["ak", 0.5, "one"], ["pa", 0.5, "one"], ["lag", 0.5, "one"],
	["ceb", 4, "other"], ["tl", 4, "other"], ["sl", 102, "two"], ["dsb", 0.01, "one"],
	["shi", 2.5, "few"], ["cy", 6, "many"], ["ga", 7, "many"], ["gd", 11, "one"],
	["gv", 0.5, "many"], ["se", 2, "two"], ["si", 0.1, "one"],
	["sh", 0.2, "few"], ["bs", 21, "one"], ["sr", 1.1, "one"],
	["ja", 1, "other"], ["in", 1, "other"], ["no", 1, "one"],
]

const ORDINAL_CASES := [
	["en", 1, "one"], ["en", 2, "two"], ["en", 3, "few"], ["en", 11, "other"],
	["en", 21, "one"], ["en", 111, "other"], ["en", 2.5, "other"],
	["en", -1, "one"], ["en", -2, "two"],
	["sv", 11, "one"], ["sv", 2, "one"], ["sv", 12, "other"],
	["hy", 1, "one"], ["hy", 2, "other"], ["tg", 6, "other"],
	["mk", 1, "one"], ["mk", 11, "other"], ["mk", 7, "many"], ["mk", -1, "other"],
	["vi", 1, "one"], ["ms", 1, "one"], ["lo", 1, "one"], ["bal", 1, "one"],
	["ro", 1, "one"], ["mo", 1, "one"], ["fr", 1, "one"], ["pt", 1, "other"],
	["be", 2, "few"], ["be", 12, "few"],
	["kw", 1000, "other"], ["kw", 5, "many"], ["kw", 21, "one"],
	["lij", 85, "many"], ["sc", 8, "many"], ["scn", 80, "many"], ["vec", 800, "many"], ["it", 11, "many"],
	["or", 8, "one"], ["ka", -1, "other"], ["cy", 0, "zero"], ["ne", 2.5, "one"],
	["uk", 23, "few"], ["tk", 10, "few"], ["ca", 3, "one"], ["gd", 12, "two"],
	["hi", 6, "many"], ["bn", 10, "one"], ["mr", 3, "two"], ["hu", 5, "one"],
]

const MANY_WITHOUT_COMPACT_EXPONENT_CASES := [
	["fr", 2, "other"], ["fr", 1000000, "many"], ["fr", 1000000.5, "other"],
	["pt", 2, "other"], ["pt", -1, "other"], ["pt", 2000000, "many"],
	["es", 0, "other"], ["es", 2000000, "many"],
	["it", 0, "other"], ["it", 1000000, "many"],
	["ca", 1000000, "many"], ["pt_PT", 0, "other"], ["vec", -1000000, "many"],
]


func test_cardinal_cases_match_reference():
	for c in CARDINAL_CASES:
		assert_eq(YarnCldrPluralRules.get_cardinal_case(c[0], c[1]), c[2], "cardinal %s %s" % [c[0], c[1]])


func test_ordinal_cases_match_reference():
	for c in ORDINAL_CASES:
		assert_eq(YarnCldrPluralRules.get_ordinal_case(c[0], c[1]), c[2], "ordinal %s %s" % [c[0], c[1]])


func test_many_follows_cldr_with_zero_compact_exponent():
	for c in MANY_WITHOUT_COMPACT_EXPONENT_CASES:
		assert_eq(YarnCldrPluralRules.get_cardinal_case(c[0], c[1]), c[2], "cardinal %s %s" % [c[0], c[1]])


func test_locale_codes_resolve_full_code_then_language():
	assert_eq(YarnCldrPluralRules.get_cardinal_case("pt_PT", 0), "other")
	assert_eq(YarnCldrPluralRules.get_cardinal_case("pt-PT", 0), "other")
	assert_eq(YarnCldrPluralRules.get_cardinal_case("pt-pt", 0), "other")
	assert_eq(YarnCldrPluralRules.get_cardinal_case("pt_BR", 0), "one")
	assert_eq(YarnCldrPluralRules.get_cardinal_case("en_US", 1), "one")
	assert_eq(YarnCldrPluralRules.get_cardinal_case("EN", 1), "one")
	assert_eq(YarnCldrPluralRules.get_cardinal_case("sr_Latn", 21), "one")
	assert_eq(YarnCldrPluralRules.get_cardinal_case("xx", 1), "other")
	assert_eq(YarnCldrPluralRules.get_ordinal_case("en-GB", 22), "two")
	assert_eq(YarnCldrPluralRules.get_ordinal_case("pt_PT", 1), "other")


func test_operands_follow_invariant_number_string():
	var o := YarnCldrPluralRules.get_operands(793.207065)
	assert_eq(o.i, 793)
	assert_eq(o.v, 6)
	assert_eq(o.f, 207065)

	o = YarnCldrPluralRules.get_operands(-2.5)
	assert_eq(o.n, 2.5)
	assert_eq(o.i, -2)
	assert_eq(o.v, 1)
	assert_eq(o.f, 5)

	o = YarnCldrPluralRules.get_operands(0.1)
	assert_eq(o.v, 1)
	assert_eq(o.f, 1)

	o = YarnCldrPluralRules.get_operands(0.0001)
	assert_eq(o.v, 4)
	assert_eq(o.f, 1)

	o = YarnCldrPluralRules.get_operands(1000000.0)
	assert_eq(o.v, 0)
	assert_eq(o.f, 0)

	o = YarnCldrPluralRules.get_operands(1e-5)
	assert_eq(o.v, 0)

	o = YarnCldrPluralRules.get_operands(1.5e-5)
	assert_eq(o.v, 5)

	o = YarnCldrPluralRules.get_operands(3e9)
	assert_eq(o.i, 2147483647)

	o = YarnCldrPluralRules.get_operands(-3e9)
	assert_eq(o.i, -2147483648)

	o = YarnCldrPluralRules.get_operands(YarnNumber.to_f32(1.1))
	assert_eq(o.v, 15)
	assert_eq(o.f, 1)


func test_plural_marker_keeps_sign_when_choosing_case():
	var parser := YarnLineParser.new()
	var builtin := YarnBuiltInMarkupReplacer.new()
	parser.register_marker_processor("plural", builtin)
	parser.register_marker_processor("ordinal", builtin)

	var result := parser.parse_string("[plural value=-1 one=\"% apple\" other=\"% apples\"/]", "en")
	assert_eq(result.text, "-1 apples")

	result = parser.parse_string("[plural value=1 one=\"% apple\" other=\"% apples\"/]", "en_US")
	assert_eq(result.text, "1 apple")

	result = parser.parse_string("[ordinal value=2.5 one=\"%st\" two=\"%nd\" few=\"%rd\" other=\"%th\"/]", "en")
	assert_eq(result.text, "2.5th")

	result = parser.parse_string("[ordinal value=-2 one=\"%st\" two=\"%nd\" few=\"%rd\" other=\"%th\"/]", "en")
	assert_eq(result.text, "-2nd")

	result = parser.parse_string("[plural value=0 one=\"% maçã\" many=\"% de maçãs\" other=\"% maçãs\"/]", "pt_BR")
	assert_eq(result.text, "0 maçã")


func test_plural_marker_uses_float32_value():
	var parser := YarnLineParser.new()
	parser.register_marker_processor("plural", YarnBuiltInMarkupReplacer.new())

	var result := parser.parse_string("[plural value=1.1 one=\"% epli\" other=\"% epli2\"/]", "is")
	assert_eq(result.text, "1.1 epli")

	result = parser.parse_string("[plural value=1.1 one=\"% apple\" other=\"% apples\"/]", "en")
	assert_eq(result.text, "1.1 apples")

	result = parser.parse_string("[plural value=-0.0 one=\"% apple\" other=\"% apples\"/]", "en")
	assert_eq(result.text, "-0 apples")

	result = parser.parse_string("[plural value=2.5 one=\"% x\" few=\"% y\" other=\"% z\"/]", "be")
	assert_eq(result.text, "2.5 y")
