extends GutTest


func _make_option(raw: String, subs: Array[String] = [], available: bool = true) -> YarnOption:
	var opt := YarnOption.new()
	opt.raw_text = raw
	opt.substitutions = subs
	opt.is_available = available
	return opt


func test_plain_text():
	var opt := _make_option("Go north")
	assert_eq(opt.text, "Go north")


func test_substitution():
	var opt := _make_option("Give {0} gold", ["50"])
	assert_eq(opt.text, "Give 50 gold")


func test_unavailable_option():
	var opt := _make_option("Locked door", [], false)
	assert_false(opt.is_available)


func test_lazy_computation():
	var opt := _make_option("Option {0}", ["A"])
	var _first := opt.text
	opt.raw_text = "Different {0}"
	assert_eq(opt.text, "Option A")


func test_text_setter_bypasses_lazy():
	var opt := _make_option("Original")
	opt.text = "Overridden"
	assert_eq(opt.text, "Overridden")


func test_get_plain_text_strips_markup():
	var opt := _make_option("[b]Bold option[/b]")
	var plain := opt.get_plain_text()
	assert_false(plain.contains("[b]"))
	assert_true(plain.contains("Bold option"))
