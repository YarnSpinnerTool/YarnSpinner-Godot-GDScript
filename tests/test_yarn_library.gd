extends GutTest


var _lib: YarnLibrary


func before_each():
	_lib = YarnLibrary.new()


func _call(func_name: String, args: Array) -> Variant:
	var stack: Array = args.duplicate()
	stack.append(float(args.size()))
	return _lib.call_function(func_name, stack, null)


# --- Built-in functions ---

func test_builtin_functions_registered():
	assert_true(_lib.has_function("Number.Add"))
	assert_true(_lib.has_function("Bool.Not"))
	assert_true(_lib.has_function("String.Add"))
	assert_true(_lib.has_function("random"))
	assert_true(_lib.has_function("round"))
	assert_true(_lib.has_function("floor"))
	assert_true(_lib.has_function("ceil"))
	assert_true(_lib.has_function("visited"))
	assert_true(_lib.has_function("visited_count"))
	assert_true(_lib.has_function("has_any_content"))


# --- Custom function registration ---

func test_register_function_with_explicit_count():
	_lib.register_function("double", func(x): return x * 2, 1)
	assert_true(_lib.has_function("double"))
	assert_eq(_lib.get_function_param_count("double"), 1)


func test_register_function_infers_parameter_count():
	_lib.register_function("add_two", func(a, b): return a + b)
	assert_eq(_lib.get_function_param_count("add_two"), 2)
	assert_eq(_call("add_two", [2.0, 3.0]), 5.0)


func _with_default(a: float, b: float = 10.0) -> float:
	return a * 100.0 + b


func test_bound_arguments_fill_trailing_parameters():
	_lib.register_function("bound", Callable(self, "_with_default").bind(99.0))
	assert_eq(_call("bound", [2.0]), 299.0)
	assert_true(YarnLibrary.is_function_error(_call("bound", [])))
	assert_push_error_count(1)


func test_register_duplicate_function_is_rejected():
	_lib.register_function("once", func(): return 1.0)
	_lib.register_function("once", func(): return 2.0)
	assert_push_error_count(1)
	assert_eq(_call("once", []), 1.0)


func test_register_function_name_with_space_is_rejected():
	_lib.register_function("bad name", func(): return 1.0)
	assert_false(_lib.has_function("bad name"))
	assert_push_error_count(1)


func test_unregister_function():
	_lib.register_function("temp_func", func(): return 0, 0)
	assert_true(_lib.has_function("temp_func"))
	_lib.unregister_function("temp_func")
	assert_false(_lib.has_function("temp_func"))


func test_function_argument_count_mismatch_is_an_error():
	var result: Variant = _call("Number.Add", [1.0])
	assert_true(YarnLibrary.is_function_error(result))
	assert_push_error_count(1)


func test_function_without_return_value_is_an_error():
	_lib.register_function("nothing", func(): pass)
	var result: Variant = _call("nothing", [])
	assert_true(YarnLibrary.is_function_error(result))
	assert_push_error_count(1)


func test_integer_results_become_numbers():
	var result: Variant = _call("floor", [2.7])
	assert_true(result is float)
	assert_eq(result, 2.0)


func test_bool_results_are_not_function_errors():
	var result: Variant = _call("Number.EqualTo", [1.0, 1.0])
	assert_false(YarnLibrary.is_function_error(result))
	assert_eq(result, true)


func test_function_error_sentinel_only_matches_itself():
	assert_false(YarnLibrary.is_function_error(true))
	assert_false(YarnLibrary.is_function_error(1.0))
	assert_false(YarnLibrary.is_function_error("__yarn_function_error__"))
	assert_true(YarnLibrary.is_function_error(YarnLibrary.FUNCTION_ERROR))


# --- Command registration ---

func test_register_command():
	_lib.register_command("noop", func(): pass)
	assert_true(_lib.has_command("noop"))


func test_register_duplicate_command_is_rejected():
	_lib.register_command("noop", func(): pass)
	_lib.register_command("noop", func(): pass)
	assert_push_error_count(1)


func test_register_command_name_with_space_is_rejected():
	_lib.register_command("two words", func(): pass)
	assert_false(_lib.has_command("two words"))
	assert_push_error_count(1)


func test_unregister_command():
	_lib.register_command("temp_cmd", func(): pass)
	_lib.unregister_command("temp_cmd")
	assert_false(_lib.has_command("temp_cmd"))


# --- Command dispatch ---

func test_dispatch_empty_command():
	var result: Dictionary = await _lib.dispatch_command("", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.EMPTY_COMMAND)
	assert_false(result.handled)


func test_dispatch_whitespace_only():
	var result: Dictionary = await _lib.dispatch_command("   ", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.EMPTY_COMMAND)


func test_dispatch_unknown_command():
	var result: Dictionary = await _lib.dispatch_command("nonexistent_cmd", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.NOT_FOUND)
	assert_false(result.handled)


func test_dispatch_registered_command():
	var called := []
	_lib.register_command("greet", func(): called.append(true))
	var result: Dictionary = await _lib.dispatch_command("greet", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.SUCCESS)
	assert_true(result.handled)
	assert_eq(called.size(), 1)


func test_dispatch_command_with_args():
	var received_args := []
	_lib.register_command("log", func(msg, level): received_args.append([msg, level]))
	var result: Dictionary = await _lib.dispatch_command("log hello warning", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.SUCCESS)
	assert_eq(received_args[0][0], "hello")
	assert_eq(received_args[0][1], "warning")


func test_dispatch_command_with_wrong_argument_count():
	_lib.register_command("pair", func(a, b): pass)
	var result: Dictionary = await _lib.dispatch_command("pair one", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.INVALID_PARAMETER_COUNT)
	assert_false(result.handled)


func test_dispatch_command_with_quoted_args():
	var received := []
	_lib.register_command("say", func(text): received.append(text))
	await _lib.dispatch_command('say "hello world"', self)
	assert_eq(received[0], "hello world")


# --- Type coercion ---

func test_coerce_string_to_int():
	assert_eq(_lib._coerce_value("42", TYPE_INT).value, 42)
	assert_false(_lib._coerce_value("3.7", TYPE_INT).ok)
	assert_false(_lib._coerce_value("invalid", TYPE_INT).ok)


func test_coerce_string_to_float():
	assert_almost_eq(_lib._coerce_value("3.14", TYPE_FLOAT).value as float, 3.14, 0.01)
	assert_almost_eq(_lib._coerce_value("42", TYPE_FLOAT).value as float, 42.0, 0.01)
	assert_false(_lib._coerce_value("invalid", TYPE_FLOAT).ok)


func test_coerce_string_to_bool():
	assert_true(_lib._coerce_value("true", TYPE_BOOL).value)
	assert_true(_lib._coerce_value(" TRUE ", TYPE_BOOL).value)
	assert_false(_lib._coerce_value("false", TYPE_BOOL).value)
	assert_false(_lib._coerce_value("1", TYPE_BOOL).ok)
	assert_false(_lib._coerce_value("yes", TYPE_BOOL).ok)


func test_coerce_parameter_name_means_true():
	assert_true(_lib._coerce_value("WAIT", TYPE_BOOL, "", "wait").value)


func test_coerce_string_to_vector2():
	assert_eq(_lib._coerce_value("(10,20)", TYPE_VECTOR2).value, Vector2(10, 20))
	assert_eq(_lib._coerce_value("10,20", TYPE_VECTOR2).value, Vector2(10, 20))
	assert_false(_lib._coerce_value("ten,20", TYPE_VECTOR2).ok)


func test_coerce_string_to_vector3():
	assert_eq(_lib._coerce_value("(1,2,3)", TYPE_VECTOR3).value, Vector3(1, 2, 3))
	assert_false(_lib._coerce_value("(1,2)", TYPE_VECTOR3).ok)


func test_coerce_string_to_color():
	assert_eq(_lib._coerce_value("#ff0000", TYPE_COLOR).value, Color.RED)
	assert_eq(_lib._coerce_value("blue", TYPE_COLOR).value, Color.BLUE)
	assert_eq(_lib._coerce_value("transparent", TYPE_COLOR).value, Color.TRANSPARENT)
	assert_false(_lib._coerce_value("not a colour", TYPE_COLOR).ok)


# --- Instance commands ---

func test_register_instance_command():
	_lib.register_instance_command("dance", load("res://tests/test_yarn_library.gd"))
	assert_true(_lib.has_instance_command("dance"))


func test_unregister_instance_command():
	_lib.register_instance_command("dance", load("res://tests/test_yarn_library.gd"))
	_lib.unregister_instance_command("dance")
	assert_false(_lib.has_instance_command("dance"))


func test_division_by_zero():
	assert_eq(_call("Number.Divide", [1.0, 0.0]), INF)
	assert_eq(_call("Number.Divide", [-1.0, 0.0]), -INF)


func test_modulo_rounds_operands_half_to_even():
	assert_eq(_call("Number.Modulo", [7.0, 3.0]), 1.0)
	assert_eq(_call("Number.Modulo", [7.5, 2.0]), 0.0)
	assert_eq(_call("Number.Modulo", [10.5, 3.0]), 1.0)
	assert_eq(_call("Number.Modulo", [5.0, 0.6]), 0.0)


func test_modulo_by_zero():
	var result: Variant = _call("Number.Modulo", [5.0, 0.4])
	assert_true(YarnLibrary.is_function_error(result))
	assert_push_error_count(1)


func test_enum_equal():
	assert_true(_call("Enum.EqualTo", ["Red", "Red"]))
	assert_false(_call("Enum.EqualTo", ["Red", "Blue"]))
	assert_true(_call("Enum.EqualTo", [1.0, 1.0]))
	assert_true(_call("Enum.NotEqualTo", ["Red", "Blue"]))


# --- Built-in math functions ---

func test_round_is_half_to_even():
	assert_eq(_call("round", [2.5]), 2.0)
	assert_eq(_call("round", [3.5]), 4.0)
	assert_eq(_call("round", [-2.5]), -2.0)


func test_round_places():
	assert_almost_eq(_call("round_places", [3.14159, 2.0]) as float, 3.14, 0.0001)
	assert_almost_eq(_call("round_places", [3.14159, 0.0]) as float, 3.0, 0.0001)


func test_round_places_out_of_range_is_an_error():
	var result: Variant = _call("round_places", [1.0, 16.0])
	assert_true(YarnLibrary.is_function_error(result))
	assert_push_error_count(1)


func test_inc_and_dec():
	assert_eq(_call("inc", [5.0]), 6.0)
	assert_eq(_call("inc", [5.3]), 6.0)
	assert_eq(_call("dec", [5.0]), 4.0)
	assert_eq(_call("dec", [5.7]), 5.0)


func test_decimal_function():
	assert_almost_eq(_call("decimal", [3.5]) as float, 0.5, 0.001)
	assert_almost_eq(_call("decimal", [-3.5]) as float, -0.5, 0.001)


func test_dice_with_zero_sides_returns_one():
	assert_eq(_call("dice", [0.0]), 1.0)


# --- Built-in conversion functions ---

func test_string_conversion():
	assert_eq(_call("string", [42.0]), "42")
	assert_eq(_call("string", [3.14]), "3.14")
	assert_eq(_call("string", [true]), "True")
	assert_eq(_call("string", [false]), "False")


func test_number_conversion():
	assert_eq(_call("number", ["42"]), 42.0)
	assert_eq(_call("number", [true]), 1.0)
	assert_eq(_call("number", [false]), 0.0)


func test_number_conversion_rejects_text():
	var result: Variant = _call("number", ["forty two"])
	assert_true(YarnLibrary.is_function_error(result))
	assert_push_error_count(1)


func test_bool_conversion():
	assert_true(_call("bool", ["true"]))
	assert_true(_call("bool", [" True "]))
	assert_false(_call("bool", ["false"]))
	assert_true(_call("bool", [1.0]))
	assert_false(_call("bool", [0.0]))


# --- Built-in format function ---

func test_format_with_placeholder():
	assert_eq(_call("format", ["Hello {0}", "Alice"]), "Hello Alice")


func test_format_repeats_placeholder():
	assert_eq(_call("format", ["{0} {0}", "Alice"]), "Alice Alice")


func test_format_with_number_format():
	assert_eq(_call("format", ["{0:F2}", 3.14159]), "3.14")


func test_format_with_escaped_braces():
	assert_eq(_call("format", ["{{0}} {0}", 5.0]), "{0} 5")


func test_format_with_invalid_index_is_an_error():
	var result: Variant = _call("format", ["{1}", 5.0])
	assert_true(YarnLibrary.is_function_error(result))
	assert_push_error_count(1)


func test_visited_count_reads_variable_storage():
	var storage := YarnInMemoryVariableStorage.new()
	add_child_autofree(storage)
	_lib.set_vm_context(null, storage)
	storage.set_value("$Yarn.Internal.Visiting.Start", 2.0)
	assert_eq(_call("visited_count", ["Start"]), 2.0)
	assert_true(_call("visited", ["Start"]))
	assert_false(_call("visited", ["Elsewhere"]))
