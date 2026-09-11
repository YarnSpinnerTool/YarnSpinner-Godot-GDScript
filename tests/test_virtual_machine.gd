extends GutTest

const _YarnProgramParser := preload("res://addons/yarn_spinner/core/yarn_program_parser.gd")

var _storage: YarnInMemoryVariableStorage
var _library: YarnLibrary
var _vm: YarnVirtualMachine


func before_each():
	_storage = YarnInMemoryVariableStorage.new()
	add_child_autofree(_storage)
	_library = YarnLibrary.new()
	_vm = YarnVirtualMachine.new()
	_vm.set_library(_library)
	_library.set_virtual_machine(_vm)
	_vm.variable_storage = _storage


func _make_program(instructions: Array[YarnInstruction]) -> YarnProgram:
	var node := YarnNode.new()
	node.node_name = "Start"
	node.instructions = instructions
	var program := YarnProgram.new()
	program.nodes["Start"] = node
	return program


func test_bool_values_format_like_the_reference_runtime():
	assert_eq(YarnVirtualMachine._value_to_string(true), "True")
	assert_eq(YarnVirtualMachine._value_to_string(false), "False")
	assert_eq(YarnVirtualMachine._value_to_string(1.0), "1")


func test_bool_function_results_reach_the_line():
	_vm.program = _make_program([
		YarnInstruction.push_float(1.0),
		YarnInstruction.push_float(1.0),
		YarnInstruction.push_float(2.0),
		YarnInstruction.call_func("Number.EqualTo"),
		YarnInstruction.run_line("line:result", 1),
		YarnInstruction.stop(),
	])
	var lines: Array[YarnLine] = []
	_vm.line_handler.connect(func(line: YarnLine): lines.append(line))

	assert_true(_vm.set_node("Start"))
	_vm.continue_dialogue()

	assert_false(_vm.has_error())
	assert_eq(lines.size(), 1)
	assert_eq(lines[0].substitutions, ["True"] as Array[String])


func test_set_node_does_not_start_running():
	_vm.program = _make_program([YarnInstruction.stop()])
	assert_true(_vm.set_node("Start"))
	assert_eq(_vm.current_state, YarnVirtualMachine.ExecutionState.STOPPED)
	assert_eq(_vm.get_current_node_name(), "Start")


func test_stop_emits_dialogue_complete_and_clears_node():
	_vm.program = _make_program([YarnInstruction.stop()])
	_vm.set_node("Start")
	var completions := [0]
	_vm.dialogue_complete_handler.connect(func(): completions[0] += 1)
	_vm.stop()
	assert_eq(completions[0], 1)
	assert_eq(_vm.get_current_node_name(), "")


func test_stop_instruction_completes_before_stopping():
	_vm.program = _make_program([YarnInstruction.stop()])
	_vm.set_node("Start")
	var node_at_completion := [""]
	_vm.dialogue_complete_handler.connect(func(): node_at_completion[0] = _vm.get_current_node_name())
	_vm.continue_dialogue()
	assert_eq(node_at_completion[0], "Start")
	assert_eq(_vm.current_state, YarnVirtualMachine.ExecutionState.STOPPED)


func test_execution_limits_are_off_by_default():
	assert_eq(_vm.max_instructions_per_step, 0)
	assert_eq(_vm.max_call_stack_depth, 0)


func test_truncated_program_fails_instead_of_hanging():
	var program: YarnProgram = _YarnProgramParser.parse_from_bytes(PackedByteArray([0x12, 50, 0x0A, 0x02, 0x41, 0x42]))
	assert_null(program)
	assert_push_error_count(2)


func test_unknown_instructions_keep_their_slot():
	var bytes := PackedByteArray([
		0x12, 17,
			0x0A, 0x01, 0x4E,
			0x12, 12,
				0x0A, 0x01, 0x4E,
				0x3A, 0x03, 0xC2, 0x01, 0x00,
				0x3A, 0x02, 0x7A, 0x00,
	])
	var program: YarnProgram = _YarnProgramParser.parse_from_bytes(bytes)
	assert_not_null(program)
	var instructions: Array[YarnInstruction] = program.get_node("N").instructions
	assert_eq(instructions.size(), 2)
	assert_eq(instructions[0].opcode, YarnInstruction.OpCode.UNKNOWN)
	assert_eq(instructions[1].opcode, YarnInstruction.OpCode.STOP)


func test_unknown_instruction_stops_with_an_error():
	var unknown := YarnInstruction.new()
	unknown.opcode = YarnInstruction.OpCode.UNKNOWN
	_vm.program = _make_program([unknown, YarnInstruction.stop()])
	_vm.set_node("Start")
	_vm.continue_dialogue()
	assert_true(_vm.has_error())
	assert_push_error_count(1)


func test_line_ids_for_node_include_lines_and_options():
	var program := _make_program([
		YarnInstruction.run_line("line:a", 0),
		YarnInstruction.push_string("x"),
		YarnInstruction.add_option("line:b", 3, 0, false),
		YarnInstruction.stop(),
	])
	assert_eq(program.get_line_ids_for_node("Start"), PackedStringArray(["line:a", "line:b"]))
	assert_eq(program.get_line_ids_for_node("Missing").size(), 0)


func test_first_header_wins():
	var node := YarnNode.new()
	node.add_header("mood", " happy ")
	node.add_header("mood", "sad")
	assert_eq(node.get_header("mood"), "happy")
	assert_true(node.has_header("mood"))
	assert_eq(node.get_all_headers().size(), 2)


func _make_node_group_program(condition_variable: String) -> YarnProgram:
	var hub := YarnNode.new()
	hub.node_name = "Group"
	hub.add_header(YarnProgram.NODE_GROUP_HUB_HEADER, "Group")
	var member := YarnNode.new()
	member.node_name = "Group.1"
	member.add_header(YarnProgram.NODE_GROUP_HEADER, "Group")
	member.add_header("$Yarn.Internal.ContentSaliencyVariables", condition_variable)
	var program := YarnProgram.new()
	program.nodes["Group"] = hub
	program.nodes["Group.1"] = member
	return program


func test_missing_saliency_condition_variable_is_an_error():
	var program := _make_node_group_program("$missing_condition")
	_vm.program = program
	_library.set_program(program)

	var saliency := YarnSmartVariableVM.try_get_saliency_options_for_node_group("Group", program, _storage, _library)
	assert_string_contains(saliency.error, "$missing_condition")
	assert_eq(saliency.options.size(), 0)

	var result: Variant = _library.call_function("has_any_content", ["Group", 1.0], null)
	assert_true(YarnLibrary.is_function_error(result))
	assert_push_error_count(1)


func test_missing_tracking_variable_is_reported():
	var node := YarnNode.new()
	node.node_name = "Start"
	node.add_header(YarnVirtualMachine.TRACKING_VARIABLE_HEADER, "$missing_tracker")
	node.instructions = [YarnInstruction.return_inst()] as Array[YarnInstruction]
	var program := YarnProgram.new()
	program.nodes["Start"] = node
	_vm.program = program
	_vm.set_node("Start")
	_vm.continue_dialogue()
	assert_push_error_count(1)
