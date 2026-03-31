extends GutTest
## Tests for YarnVariableStorage base class features (type validation, coercion, etc.)


var _storage: YarnInMemoryVariableStorage


func before_each():
	_storage = YarnInMemoryVariableStorage.new()
	add_child_autofree(_storage)


# --- Yarn type names ---

func test_yarn_type_name_string():
	assert_eq(YarnVariableStorage.yarn_type_name("hello"), "string")


func test_yarn_type_name_number():
	assert_eq(YarnVariableStorage.yarn_type_name(42), "number")
	assert_eq(YarnVariableStorage.yarn_type_name(3.14), "number")


func test_yarn_type_name_bool():
	assert_eq(YarnVariableStorage.yarn_type_name(true), "bool")


func test_yarn_type_name_unknown():
	assert_eq(YarnVariableStorage.yarn_type_name([1, 2, 3]), "unknown")


# --- Type compatibility ---

func test_int_float_compatible():
	assert_true(YarnVariableStorage.is_yarn_type_compatible(42, 3.14))
	assert_true(YarnVariableStorage.is_yarn_type_compatible(3.14, 42))


func test_string_number_incompatible():
	assert_false(YarnVariableStorage.is_yarn_type_compatible("hello", 42))


func test_bool_number_incompatible():
	assert_false(YarnVariableStorage.is_yarn_type_compatible(true, 42))


# --- Type validation ---

func test_validate_rejects_non_yarn_types():
	_storage.set_value("$x", 10)
	# Arrays are not valid Yarn types
	assert_false(_storage.validate_value_type("$x", [1, 2, 3]))
	assert_push_error_count(1)


func test_validate_rejects_type_change():
	_storage.set_value("$name", "Alice")
	# Can't assign a number to a string variable
	assert_false(_storage.validate_value_type("$name", 42))
	assert_push_error_count(1)


func test_validate_allows_compatible_types():
	_storage.set_value("$score", 10)
	# int -> float is fine (both are "number")
	assert_true(_storage.validate_value_type("$score", 3.14))


# --- Variable kind ---

func test_stored_variable_kind():
	_storage.set_value("$x", 10)
	assert_eq(_storage.get_variable_kind("$x"), YarnVariableStorage.VariableKind.STORED)


func test_unknown_variable_kind():
	assert_eq(_storage.get_variable_kind("$nonexistent"), YarnVariableStorage.VariableKind.UNKNOWN)


# --- Typed getters ---

func test_try_get_float():
	_storage.set_value("$score", 42.5)
	var result := _storage.try_get_float("$score")
	assert_true(result.found)
	assert_almost_eq(result.value, 42.5, 0.01)


func test_try_get_float_from_int():
	_storage.set_value("$score", 42)
	var result := _storage.try_get_float("$score")
	assert_true(result.found)
	assert_eq(result.value, 42.0)


func test_try_get_float_missing():
	var result := _storage.try_get_float("$missing")
	assert_false(result.found)
	assert_eq(result.value, 0.0)
	assert_push_warning_count(1)


func test_try_get_string():
	_storage.set_value("$name", "Alice")
	var result := _storage.try_get_string("$name")
	assert_true(result.found)
	assert_eq(result.value, "Alice")


func test_try_get_string_wrong_type():
	_storage.set_value("$score", 42)
	var result := _storage.try_get_string("$score")
	assert_false(result.found)


func test_try_get_bool():
	_storage.set_value("$flag", true)
	var result := _storage.try_get_bool("$flag")
	assert_true(result.found)
	assert_true(result.value)


func test_try_get_bool_wrong_type():
	_storage.set_value("$name", "hello")
	var result := _storage.try_get_bool("$name")
	assert_false(result.found)


# --- Convenience getters with defaults ---

func test_get_float_default():
	assert_eq(_storage.get_float("$missing", 99.0), 99.0)
	assert_push_warning_count(1)


func test_get_string_default():
	assert_eq(_storage.get_string("$missing", "default"), "default")
	assert_push_warning_count(1)


func test_get_bool_default():
	assert_eq(_storage.get_bool("$missing", true), true)
	assert_push_warning_count(1)


# --- Change listeners ---

func test_change_listener():
	var received := []
	var listener := func(var_name: String, new_val: Variant, old_val: Variant):
		received.append({"name": var_name, "new": new_val, "old": old_val})

	_storage.register_change_listener("$hp", listener)
	_storage.set_value("$hp", 100)
	_storage.set_value("$hp", 80)

	assert_eq(received.size(), 2)
	assert_eq(received[0].new, 100)
	assert_eq(received[1].new, 80)
	assert_eq(received[1].old, 100)


func test_unregister_change_listener():
	var counter := [0]
	var listener := func(_n: String, _nv: Variant, _ov: Variant): counter[0] += 1

	_storage.register_change_listener("$hp", listener)
	_storage.set_value("$hp", 100)
	_storage.unregister_change_listener("$hp", listener)
	_storage.set_value("$hp", 200)

	assert_eq(counter[0], 1, "Listener should stop receiving after unregister")


func test_global_listener():
	var received := []
	var listener := func(var_name: String, _new_val: Variant, _old_val: Variant):
		received.append(var_name)

	_storage.register_global_listener(listener)
	_storage.set_value("$a", 1)
	_storage.set_value("$b", 2)

	assert_eq(received.size(), 2)
	assert_true("$a" in received)
	assert_true("$b" in received)


func test_unregister_global_listener():
	var counter := [0]
	var listener := func(_n: String, _nv: Variant, _ov: Variant): counter[0] += 1

	_storage.register_global_listener(listener)
	_storage.set_value("$a", 1)
	_storage.unregister_global_listener(listener)
	_storage.set_value("$b", 2)

	assert_eq(counter[0], 1)


# --- set_all_variables ---

func test_set_all_variables():
	var vars := {"$x": 10, "$y": "hello", "$z": true}
	_storage.set_all_variables(vars)
	assert_eq(_storage.try_get_value("$x").value, 10)
	assert_eq(_storage.try_get_value("$y").value, "hello")
	assert_eq(_storage.try_get_value("$z").value, true)
