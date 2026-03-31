extends GutTest
## Tests for YarnMarkupAttribute and YarnMarkupParseResult.


# --- YarnMarkupAttribute ---

func test_attribute_with_properties():
	var prop := YarnMarkupProperty.from_string("color", "red")
	var attr := YarnMarkupAttribute.new(0, 0, 5, "style", [prop])
	assert_eq(attr.properties.size(), 1)
	assert_eq(attr.value, "red")


func test_attribute_shift():
	var attr := YarnMarkupAttribute.new(10, 5, 3, "test", [])
	var shifted := attr.shift(5)
	assert_eq(shifted.position, 15)
	assert_eq(shifted.length, 3)
	assert_eq(shifted.name, "test")


func test_attribute_shift_negative():
	var attr := YarnMarkupAttribute.new(10, 5, 3, "test", [])
	var shifted := attr.shift(-3)
	assert_eq(shifted.position, 7)


func test_try_get_property_missing():
	var attr := YarnMarkupAttribute.new(0, 0, 0, "test", [])
	assert_null(attr.try_get_property("nonexistent"))


func test_try_get_property_case_insensitive():
	var prop := YarnMarkupProperty.from_string("Name", "Alice")
	var attr := YarnMarkupAttribute.new(0, 0, 0, "character", [prop])
	# Should find "Name" when searching for "name" (case-insensitive)
	assert_not_null(attr.try_get_property("name"))


func test_try_get_string_property():
	var prop := YarnMarkupProperty.from_string("name", "Alice")
	var attr := YarnMarkupAttribute.new(0, 0, 0, "character", [prop])
	assert_eq(attr.try_get_string_property("name"), "Alice")
	assert_eq(attr.try_get_string_property("missing", "default"), "default")


func test_try_get_int_property():
	var prop := YarnMarkupProperty.from_int("count", 42)
	var attr := YarnMarkupAttribute.new(0, 0, 0, "test", [prop])
	assert_eq(attr.try_get_int_property("count"), 42)
	assert_eq(attr.try_get_int_property("missing", -1), -1)


func test_try_get_float_property():
	var prop := YarnMarkupProperty.from_float("speed", 1.5)
	var attr := YarnMarkupAttribute.new(0, 0, 0, "test", [prop])
	assert_almost_eq(attr.try_get_float_property("speed"), 1.5, 0.01)


func test_try_get_float_from_int_property():
	var prop := YarnMarkupProperty.from_int("delay", 5)
	var attr := YarnMarkupAttribute.new(0, 0, 0, "test", [prop])
	assert_almost_eq(attr.try_get_float_property("delay"), 5.0, 0.01)


func test_try_get_bool_property():
	var prop := YarnMarkupProperty.from_bool("active", true)
	var attr := YarnMarkupAttribute.new(0, 0, 0, "test", [prop])
	assert_true(attr.try_get_bool_property("active"))
	assert_false(attr.try_get_bool_property("missing", false))


func test_has_value():
	var attr_no_val := YarnMarkupAttribute.new(0, 0, 0, "test", [])
	assert_false(attr_no_val.has_value())

	var prop := YarnMarkupProperty.from_string("x", "y")
	var attr_with_val := YarnMarkupAttribute.new(0, 0, 0, "test", [prop])
	assert_true(attr_with_val.has_value())


# --- YarnMarkupParseResult ---

func test_parse_result_text_for_attribute():
	var attr := YarnMarkupAttribute.new(6, 0, 5, "b", [])
	var result := YarnMarkupParseResult.new("Hello World!", [attr])
	assert_eq(result.text_for_attribute(attr), "World")


func test_parse_result_text_for_zero_length():
	var attr := YarnMarkupAttribute.new(0, 0, 0, "pause", [])
	var result := YarnMarkupParseResult.new("text", [attr])
	assert_eq(result.text_for_attribute(attr), "")


func test_parse_result_find_attribute():
	var attr1 := YarnMarkupAttribute.new(0, 0, 5, "b", [])
	var attr2 := YarnMarkupAttribute.new(6, 0, 5, "i", [])
	var result := YarnMarkupParseResult.new("Hello World!", [attr1, attr2])

	assert_not_null(result.try_get_attribute_with_name("b"))
	assert_not_null(result.try_get_attribute_with_name("i"))
	assert_null(result.try_get_attribute_with_name("u"))


func test_delete_range_shifts_remaining():
	var to_delete := YarnMarkupAttribute.new(0, 0, 6, "del", [])
	var remaining := YarnMarkupAttribute.new(6, 0, 5, "keep", [])
	var result := YarnMarkupParseResult.new("Hello World!", [to_delete, remaining])
	var new_result := result.delete_range(to_delete)
	assert_eq(new_result.text, "World!")
	assert_eq(new_result.attributes.size(), 1)
	assert_eq(new_result.attributes[0].position, 0)


func test_delete_range_zero_length():
	var to_delete := YarnMarkupAttribute.new(3, 0, 0, "del", [])
	var other := YarnMarkupAttribute.new(0, 0, 5, "keep", [])
	var result := YarnMarkupParseResult.new("Hello", [to_delete, other])
	var new_result := result.delete_range(to_delete)
	assert_eq(new_result.text, "Hello")
	assert_eq(new_result.attributes.size(), 1)
	assert_eq(new_result.attributes[0].name, "keep")


func test_delete_range_removes_contained_attributes():
	# An attribute entirely inside the deletion range should be removed
	var to_delete := YarnMarkupAttribute.new(0, 0, 10, "del", [])
	var inside := YarnMarkupAttribute.new(2, 0, 3, "gone", [])
	var result := YarnMarkupParseResult.new("0123456789rest", [to_delete, inside])
	var new_result := result.delete_range(to_delete)
	assert_eq(new_result.text, "rest")
	assert_eq(new_result.attributes.size(), 0)
