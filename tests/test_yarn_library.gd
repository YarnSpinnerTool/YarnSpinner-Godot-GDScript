extends GutTest


var _lib: YarnLibrary


func before_each():
	_lib = YarnLibrary.new()


# --- Built-in functions ---

func test_builtin_functions_registered():
	assert_true(_lib.has_function("Number.Add"))
	assert_true(_lib.has_function("Bool.Not"))
	assert_true(_lib.has_function("String.Add"))
	assert_true(_lib.has_function("random"))
	assert_true(_lib.has_function("round"))
	assert_true(_lib.has_function("floor"))
	assert_true(_lib.has_function("ceil"))
	assert_true(_lib.has_function("length"))
	assert_true(_lib.has_function("uppercase"))
	assert_true(_lib.has_function("lowercase"))


# --- Custom function registration ---

func test_register_and_call_custom_function():
	_lib.register_function("double", func(x): return x * 2, 1)
	assert_true(_lib.has_function("double"))
	assert_eq(_lib.get_function_param_count("double"), 1)


func test_unregister_function():
	_lib.register_function("temp_func", func(): return 0, 0)
	assert_true(_lib.has_function("temp_func"))
	_lib.unregister_function("temp_func")
	assert_false(_lib.has_function("temp_func"))


# --- Command registration ---

func test_register_command():
	_lib.register_command("noop", func(): pass)
	assert_true(_lib.has_command("noop"))


func test_unregister_command():
	_lib.register_command("temp_cmd", func(): pass)
	_lib.unregister_command("temp_cmd")
	assert_false(_lib.has_command("temp_cmd"))


# --- Command dispatch ---

func test_dispatch_empty_command():
	var result := _lib.dispatch_command("", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.EMPTY_COMMAND)
	assert_false(result.handled)


func test_dispatch_whitespace_only():
	var result := _lib.dispatch_command("   ", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.EMPTY_COMMAND)


func test_dispatch_unknown_command():
	var result := _lib.dispatch_command("nonexistent_cmd", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.NOT_FOUND)
	assert_false(result.handled)


func test_dispatch_registered_command():
	var called := []
	_lib.register_command("greet", func(): called.append(true))
	var result := _lib.dispatch_command("greet", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.SUCCESS)
	assert_true(result.handled)
	assert_eq(called.size(), 1)


func test_dispatch_command_with_args():
	var received_args := []
	_lib.register_command("log", func(msg, level): received_args.append([msg, level]))
	var result := _lib.dispatch_command("log hello warning", self)
	assert_eq(result.status, YarnLibrary.CommandDispatchStatus.SUCCESS)
	assert_eq(received_args[0][0], "hello")
	assert_eq(received_args[0][1], "warning")


func test_dispatch_command_with_quoted_args():
	var received := []
	_lib.register_command("say", func(text): received.append(text))
	_lib.dispatch_command('say "hello world"', self)
	assert_eq(received[0], "hello world")


# --- Type coercion (tested directly since lambdas don't expose type info to reflection) ---

func test_coerce_string_to_int():
	assert_eq(_lib._coerce_value("42", TYPE_INT), 42)
	assert_eq(_lib._coerce_value("3.7", TYPE_INT), 3)
	assert_eq(_lib._coerce_value("invalid", TYPE_INT), 0)


func test_coerce_string_to_float():
	assert_almost_eq(_lib._coerce_value("3.14", TYPE_FLOAT) as float, 3.14, 0.01)
	assert_almost_eq(_lib._coerce_value("42", TYPE_FLOAT) as float, 42.0, 0.01)
	assert_almost_eq(_lib._coerce_value("invalid", TYPE_FLOAT) as float, 0.0, 0.01)


func test_coerce_string_to_bool():
	assert_true(_lib._coerce_value("true", TYPE_BOOL))
	assert_true(_lib._coerce_value("1", TYPE_BOOL))
	assert_true(_lib._coerce_value("yes", TYPE_BOOL))
	assert_false(_lib._coerce_value("false", TYPE_BOOL))
	assert_false(_lib._coerce_value("0", TYPE_BOOL))


func test_coerce_string_to_vector2():
	assert_eq(_lib._coerce_value("(10,20)", TYPE_VECTOR2), Vector2(10, 20))
	assert_eq(_lib._coerce_value("10,20", TYPE_VECTOR2), Vector2(10, 20))


func test_coerce_string_to_vector3():
	assert_eq(_lib._coerce_value("(1,2,3)", TYPE_VECTOR3), Vector3(1, 2, 3))


func test_coerce_string_to_color_hex():
	assert_eq(_lib._coerce_value("#ff0000", TYPE_COLOR), Color.RED)


func test_coerce_string_to_color_name():
	assert_eq(_lib._coerce_value("blue", TYPE_COLOR), Color.BLUE)
	assert_eq(_lib._coerce_value("red", TYPE_COLOR), Color.RED)
	assert_eq(_lib._coerce_value("transparent", TYPE_COLOR), Color.TRANSPARENT)


# --- Instance commands ---

func test_register_instance_command():
	_lib.register_instance_command("dance", load("res://tests/test_yarn_library.gd"))
	assert_true(_lib.has_instance_command("dance"))


func test_unregister_instance_command():
	_lib.register_instance_command("dance", load("res://tests/test_yarn_library.gd"))
	_lib.unregister_instance_command("dance")
	assert_false(_lib.has_instance_command("dance"))


# --- Built-in math functions ---

func test_division_by_zero():
	assert_eq(_lib._op_number_divide(1.0, 0.0), INF)
	assert_eq(_lib._op_number_divide(-1.0, 0.0), -INF)


func test_modulo_int_conversion():
	assert_eq(_lib._op_number_modulo(7.0, 3.0), 1.0)
	assert_eq(_lib._op_number_modulo(10.5, 3.0), 1.0)


func test_modulo_by_zero():
	_lib._op_number_modulo(5.0, 0.0)
	assert_push_error_count(1)


func test_inc_no_decimal():
	assert_eq(_lib._builtin_inc(5.0), 6)


func test_inc_with_decimal():
	assert_eq(_lib._builtin_inc(5.3), 6)


func test_dec_no_decimal():
	assert_eq(_lib._builtin_dec(5.0), 4)


func test_dec_with_decimal():
	assert_eq(_lib._builtin_dec(5.7), 5)


func test_decimal_function():
	assert_almost_eq(_lib._builtin_decimal(3.5), 0.5, 0.001)
	assert_almost_eq(_lib._builtin_decimal(-3.5), -0.5, 0.001)


func test_round_places():
	assert_almost_eq(_lib._builtin_round_places(3.14159, 2.0), 3.14, 0.001)
	assert_almost_eq(_lib._builtin_round_places(3.14159, 0.0), 3.0, 0.001)


func test_clamp():
	assert_eq(_lib._builtin_clamp(5.0, 0.0, 10.0), 5.0)
	assert_eq(_lib._builtin_clamp(-5.0, 0.0, 10.0), 0.0)
	assert_eq(_lib._builtin_clamp(15.0, 0.0, 10.0), 10.0)


func test_lerp():
	assert_eq(_lib._builtin_lerp(0.0, 10.0, 0.5), 5.0)
	assert_eq(_lib._builtin_lerp(0.0, 10.0, 0.0), 0.0)
	assert_eq(_lib._builtin_lerp(0.0, 10.0, 1.0), 10.0)


func test_inverse_lerp():
	assert_eq(_lib._builtin_inverse_lerp(0.0, 10.0, 5.0), 0.5)
	assert_eq(_lib._builtin_inverse_lerp(5.0, 5.0, 5.0), 0.0)


# --- Built-in string functions ---

func test_string_length():
	assert_eq(_lib._builtin_length("hello"), 5)
	assert_eq(_lib._builtin_length(""), 0)


func test_uppercase():
	assert_eq(_lib._builtin_uppercase("hello"), "HELLO")


func test_lowercase():
	assert_eq(_lib._builtin_lowercase("HELLO"), "hello")


func test_first_letter_caps():
	assert_eq(_lib._builtin_first_letter_caps("hello"), "Hello")
	assert_eq(_lib._builtin_first_letter_caps(""), "")


# --- Built-in conversion functions ---

func test_string_conversion():
	assert_eq(_lib._builtin_string(42.0), "42")
	assert_eq(_lib._builtin_string(3.14), "3.14")
	assert_eq(_lib._builtin_string(true), "true")


func test_number_conversion():
	assert_eq(_lib._builtin_number("42"), 42.0)
	assert_eq(_lib._builtin_number(true), 1.0)
	assert_eq(_lib._builtin_number(false), 0.0)


func test_bool_conversion():
	assert_true(_lib._builtin_bool("true"))
	assert_false(_lib._builtin_bool("false"))
	assert_true(_lib._builtin_bool(1.0))
	assert_false(_lib._builtin_bool(0.0))


# --- Built-in format function ---

func test_format_with_placeholders():
	assert_eq(_lib._builtin_format(["Hello {0}, you have {1} gold", "Alice", 50]), "Hello Alice, you have 50 gold")


func test_format_with_specifiers():
	assert_eq(_lib._builtin_format(["Value is {0:F2}", 3.14]), "Value is 3.14")


func test_format_empty():
	assert_eq(_lib._builtin_format([]), "")


# --- Enum operations ---

func test_enum_equal_string():
	assert_true(_lib._op_enum_equal("Red", "Red"))
	assert_false(_lib._op_enum_equal("Red", "Blue"))


func test_enum_equal_int():
	assert_true(_lib._op_enum_equal(1, 1))
	assert_false(_lib._op_enum_equal(1, 2))


func test_enum_not_equal():
	assert_true(_lib._op_enum_not_equal("Red", "Blue"))
	assert_false(_lib._op_enum_not_equal("Red", "Red"))
