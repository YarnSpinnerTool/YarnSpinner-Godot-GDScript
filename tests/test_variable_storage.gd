extends GutTest


var _storage: YarnInMemoryVariableStorage


func before_each():
	_storage = YarnInMemoryVariableStorage.new()
	add_child_autofree(_storage)


func test_set_and_get():
	_storage.set_value("$name", "Alice")
	var result := _storage.try_get_value("$name")
	assert_true(result.found)
	assert_eq(result.value, "Alice")


func test_get_missing_variable():
	var result := _storage.try_get_value("$nonexistent")
	assert_false(result.found)


func test_set_overwrite():
	_storage.set_value("$score", 10)
	_storage.set_value("$score", 20)
	assert_eq(_storage.try_get_value("$score").value, 20)


func test_clear():
	_storage.set_value("$a", 1)
	_storage.set_value("$b", 2)
	_storage.clear()
	assert_false(_storage.try_get_value("$a").found)
	assert_false(_storage.try_get_value("$b").found)


func test_contains():
	_storage.set_value("$x", true)
	assert_true(_storage.contains("$x"))
	assert_false(_storage.contains("$y"))


func test_get_all_variable_names():
	_storage.set_value("$a", 1)
	_storage.set_value("$b", "hello")
	var names := _storage.get_all_variable_names()
	assert_eq(names.size(), 2)
	assert_true("$a" in names)
	assert_true("$b" in names)


func test_get_all_variables():
	_storage.set_value("$hp", 100)
	_storage.set_value("$name", "Hero")
	var all := _storage.get_all_variables()
	assert_eq(all["$hp"], 100)
	assert_eq(all["$name"], "Hero")


func test_get_all_variables_typed():
	_storage.set_value("$score", 42.0)
	_storage.set_value("$name", "Alice")
	_storage.set_value("$alive", true)
	var typed := _storage.get_all_variables_typed()
	assert_true(typed.floats.has("$score"))
	assert_true(typed.strings.has("$name"))
	assert_true(typed.bools.has("$alive"))


func test_set_all_variables_typed():
	_storage.set_all_variables_typed(
		{"$score": 10.0},
		{"$name": "Bob"},
		{"$flag": false},
		true
	)
	assert_eq(_storage.try_get_value("$score").value, 10.0)
	assert_eq(_storage.try_get_value("$name").value, "Bob")
	assert_eq(_storage.try_get_value("$flag").value, false)


func test_set_all_variables_typed_no_clear():
	_storage.set_value("$existing", "keep me")
	_storage.set_all_variables_typed(
		{"$new": 1.0}, {}, {}, false
	)
	assert_true(_storage.contains("$existing"), "Existing vars should be preserved")
	assert_true(_storage.contains("$new"))


func test_save_and_load():
	_storage.set_value("$hp", 50)
	_storage.set_value("$quest", "active")
	var save_data := _storage.to_save_data()
	_storage.clear()
	assert_false(_storage.contains("$hp"))
	_storage.from_save_data(save_data)
	assert_eq(_storage.try_get_value("$hp").value, 50)
	assert_eq(_storage.try_get_value("$quest").value, "active")


func test_variable_changed_signal():
	var received := []
	_storage.variable_changed.connect(func(_name, _val): received.append([_name, _val]))
	_storage.set_value("$x", 42)
	assert_eq(received.size(), 1)
	assert_eq(received[0][0], "$x")
	assert_eq(received[0][1], 42)


func test_variable_changed_not_emitted_for_same_value():
	_storage.set_value("$x", 42)
	var received := []
	_storage.variable_changed.connect(func(_name, _val): received.append([_name, _val]))
	_storage.set_value("$x", 42)
	assert_eq(received.size(), 0, "Should not emit when value unchanged")


func test_validate_variable_names_warns_no_dollar():
	_storage.validate_variable_names = true
	_storage.set_value("no_dollar", "value")
	assert_true(_storage.contains("no_dollar"))
	assert_push_warning_count(1)


func test_validate_rejects_empty_name():
	_storage.validate_variable_names = true
	_storage.set_value("", "value")
	assert_false(_storage.contains(""))
	assert_push_error_count(1)


func test_debug_list_format():
	_storage.set_value("$hp", 100)
	var debug := _storage.get_debug_list()
	assert_true(debug.contains("$hp"))
	assert_true(debug.contains("100"))
