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

class_name YarnVirtualMachine
extends RefCounted
## Stack-based VM that executes compiled Yarn bytecode.

enum ExecutionState {
	STOPPED,
	RUNNING,
	WAITING_FOR_INPUT,
	SUSPENDED,
}

signal line_handler(line: YarnLine)
signal options_handler(options: Array[YarnOption])
signal command_handler(command_text: String)
signal node_start_handler(node_name: String)
signal node_complete_handler(node_name: String)
signal dialogue_complete_handler()
## Emitted before lines are shown so assets can be pre-loaded.
signal prepare_for_lines_handler(line_ids: PackedStringArray)

var program: YarnProgram:
	set(value):
		program = value
		_reset_state()

var variable_storage: YarnVariableStorage
var _library: YarnLibrary
var verbose_logging: bool = false
var current_state: ExecutionState = ExecutionState.STOPPED
var _has_error: bool = false
var _current_node: YarnNode
var _instruction_pointer: int = 0
var _stack: Array = []
var _pending_options: Array[YarnOption] = []
var _call_stack: Array[Dictionary] = []
var _saliency_candidates: Array[Dictionary] = []
var saliency_strategy: YarnSaliencyStrategy

const TRACKING_VARIABLE_HEADER := "$Yarn.Internal.TrackingVariable"
const NODE_GROUP_HUB_HEADER := "$Yarn.Internal.NodeGroupHub"
const NODE_GROUP_HEADER := "$Yarn.Internal.NodeGroup"
const SALIENCY_VARIABLES_HEADER := "$Yarn.Internal.ContentSaliencyVariables"
const SALIENCY_COMPLEXITY_HEADER := "$Yarn.Internal.ContentSaliencyComplexity"
const VISITING_VARIABLE_PREFIX := "$Yarn.Internal.Visiting."


static func generate_visit_variable_name(node_name: String) -> String:
	return VISITING_VARIABLE_PREFIX + node_name

var max_instructions_per_step: int = 0
var _instruction_count: int = 0
var max_call_stack_depth: int = 0
## Prevents re-entrant calls to continue_dialogue from signal handlers.
var _is_continuing: bool = false


func set_library(library: YarnLibrary) -> void:
	_library = library


func set_saliency_strategy(strategy: YarnSaliencyStrategy) -> void:
	saliency_strategy = strategy


func is_continuing() -> bool:
	return _is_continuing


func has_error() -> bool:
	return _has_error


var last_error: String = ""


func get_current_node_name() -> String:
	if _current_node == null:
		return ""
	return _current_node.node_name


func is_running() -> bool:
	return current_state != ExecutionState.STOPPED


func is_waiting_for_input() -> bool:
	return current_state == ExecutionState.WAITING_FOR_INPUT


func unload_all() -> void:
	program = null
	_set_stopped()


func set_node(node_name: String) -> bool:
	if program == null or program.nodes.is_empty():
		_fail("cannot load node '%s': no nodes have been loaded" % node_name)
		return false

	if not program.has_node(node_name):
		_set_stopped()
		_fail("no node named '%s' has been loaded" % node_name)
		return false

	_load_node(node_name, true)
	return true


func _load_node(node_name: String, clear_state: bool) -> void:
	_current_node = program.get_node(node_name)

	if clear_state:
		_reset_state()
		_has_error = false
		last_error = ""

	_instruction_pointer = 0

	if verbose_logging:
		print("VM: Loading node '%s' with %d instructions:" % [node_name, _current_node.instructions.size()])
		for i in range(_current_node.instructions.size()):
			var inst := _current_node.instructions[i]
			var opcode_name: String = YarnInstruction.OpCode.keys()[inst.opcode] if inst.opcode < YarnInstruction.OpCode.size() else str(inst.opcode)
			var extra := ""
			if inst.opcode == YarnInstruction.OpCode.ADD_OPTION:
				extra = " line=%s dest=%d has_cond=%s" % [inst.line_id, inst.destination, inst.has_condition]
			elif inst.opcode == YarnInstruction.OpCode.JUMP_TO or inst.opcode == YarnInstruction.OpCode.JUMP_IF_FALSE:
				extra = " dest=%d" % inst.destination
			elif inst.opcode == YarnInstruction.OpCode.RUN_LINE:
				extra = " line=%s subs=%d" % [inst.line_id, inst.substitution_count]
			elif inst.opcode == YarnInstruction.OpCode.RUN_COMMAND:
				extra = " cmd=%s" % inst.command_text
			print("  [%d] %s%s" % [i, opcode_name, extra])

	node_start_handler.emit(node_name)
	prepare_for_lines_handler.emit(_collect_line_ids(_current_node))


func continue_dialogue() -> void:
	if _is_continuing:
		if current_state == ExecutionState.SUSPENDED:
			current_state = ExecutionState.RUNNING
		return

	if _has_error:
		push_error("virtual machine: cannot continue after error")
		return

	if _current_node == null:
		push_error("virtual machine: cannot continue running dialogue, no node has been selected")
		return

	if current_state == ExecutionState.WAITING_FOR_INPUT:
		push_error("virtual machine: cannot continue running dialogue, still waiting on option selection")
		return

	if _library == null:
		push_error("virtual machine: cannot continue running dialogue, no library has been set")
		return

	_is_continuing = true
	current_state = ExecutionState.RUNNING
	_instruction_count = 0

	while _current_node != null and current_state == ExecutionState.RUNNING and not _has_error:
		if max_instructions_per_step > 0:
			_instruction_count += 1
			if _instruction_count > max_instructions_per_step:
				_fail("exceeded maximum instructions per step (%d) - possible infinite loop" % max_instructions_per_step)
				break

		if _instruction_pointer < 0 or _instruction_pointer >= _current_node.instructions.size():
			_fail("instruction pointer out of bounds (%d) in node '%s'" % [_instruction_pointer, _current_node.node_name])
			break

		_execute_next_instruction()

		if _has_error:
			break

		if _current_node != null and _instruction_pointer >= _current_node.instructions.size():
			_return_from_node(_current_node)
			_set_stopped()
			dialogue_complete_handler.emit()

	_is_continuing = false


const NO_OPTION_SELECTED := -1


## Pushes destination + true flag onto stack for the JUMP_IF_FALSE / POP / PEEK_AND_JUMP
## sequence that the compiler emits after SHOW_OPTIONS.
func set_selected_option(option_index: int) -> void:
	if current_state != ExecutionState.WAITING_FOR_INPUT:
		push_error("virtual machine: set_selected_option was called, but dialogue wasn't waiting for a selection")
		return

	if option_index == NO_OPTION_SELECTED:
		if verbose_logging:
			print("VM: set_selected_option: no option selected, pushing false for fallthrough")
		_push(false)
	else:
		if option_index < 0 or option_index >= _pending_options.size():
			push_error("virtual machine: %d is not a valid option ID (expected a number between 0 and %d)" % [option_index, _pending_options.size() - 1])
			return

		var selected := _pending_options[option_index]
		if verbose_logging:
			print("VM: set_selected_option index=%d line_id=%s dest=%d" % [option_index, selected.line_id, selected.destination])

		_push(selected.destination)
		_push(true)

	_pending_options.clear()
	current_state = ExecutionState.RUNNING


func signal_content_complete() -> void:
	if current_state != ExecutionState.SUSPENDED:
		push_warning("virtual machine: signal_content_complete called but not in SUSPENDED state (current: %s)" % ExecutionState.keys()[current_state])
		return
	current_state = ExecutionState.RUNNING


func stop() -> void:
	_set_stopped()
	_is_continuing = false
	dialogue_complete_handler.emit()


func has_visited_node(node_name: String) -> bool:
	return get_visit_count(node_name) > 0


func get_visit_count(node_name: String) -> int:
	if variable_storage == null:
		return 0
	var var_name := generate_visit_variable_name(node_name)
	var value: Variant = variable_storage.get_value(var_name)
	if value == null:
		return 0
	return int(value)


func reset_visit_tracking() -> void:
	if variable_storage != null:
		for var_name in variable_storage.get_all_variable_names():
			if var_name.begins_with(VISITING_VARIABLE_PREFIX):
				variable_storage.set_value(var_name, 0.0)


# =============================================================================
# NODE HEADER ACCESS
# =============================================================================

func _get_node_for_headers(node_name: String) -> YarnNode:
	if program == null:
		push_error("virtual machine: can't get headers for node '%s', because no program is set" % node_name)
		return null
	if program.nodes.is_empty():
		push_error("virtual machine: can't get headers for node '%s', because the program contains no nodes" % node_name)
		return null
	var node := program.get_node(node_name)
	if node == null:
		push_error("virtual machine: can't get headers for node '%s': no node with this name was found" % node_name)
	return node


func get_header_value(node_name: String, header_name: String) -> String:
	var node := _get_node_for_headers(node_name)
	if node == null:
		return ""
	return node.get_header(header_name)


func has_header(node_name: String, header_name: String) -> bool:
	if program == null:
		return false
	var node := program.get_node(node_name)
	if node == null:
		return false
	return node.has_header(header_name)


func get_headers(node_name: String) -> Dictionary:
	var node := _get_node_for_headers(node_name)
	if node == null:
		return {}
	var result := {}
	for header in node.get_all_headers():
		if not result.has(header["key"]):
			result[header["key"]] = header["value"]
	return result


func get_all_headers(node_name: String) -> Array[Dictionary]:
	var node := _get_node_for_headers(node_name)
	if node == null:
		return []
	return node.get_all_headers()


func get_string_id_for_node(node_name: String) -> String:
	if program == null or program.nodes.is_empty():
		push_error("virtual machine: no nodes are loaded")
		return ""
	if not program.has_node(node_name):
		push_error("virtual machine: no node named '%s'" % node_name)
		return ""
	return "line:%s" % node_name


func get_all_node_names() -> PackedStringArray:
	if program == null:
		return PackedStringArray()
	return program.get_node_names()


# =============================================================================
# NODE GROUP SALIENCY
# =============================================================================

func is_node_group(node_name: String) -> bool:
	if program == null:
		push_error("virtual machine: can't determine if '%s' is a node group, because no program has been set" % node_name)
		return false
	var node := program.get_node(node_name)
	if node == null:
		return false
	return node.has_header(NODE_GROUP_HUB_HEADER)


func has_salient_content(node_group_name: String) -> bool:
	if program == null or not program.has_node(node_group_name):
		push_error("virtual machine: '%s' is not a valid node name" % node_group_name)
		return false
	var options := get_saliency_options_for_node_group(node_group_name)
	var typed_options: Array[Dictionary] = []
	typed_options.assign(options)
	var context := {
		"vm": self,
		"variable_storage": variable_storage
	}
	var selected_index := get_effective_saliency_strategy().select_candidate(typed_options, context)
	return selected_index >= 0 and selected_index < typed_options.size()


func get_saliency_options_for_node_group(node_group_name: String) -> Array:
	if program == null:
		push_error("virtual machine: '%s' is not a valid node name" % node_group_name)
		return []

	var node := program.get_node(node_group_name)
	if node == null:
		push_error("virtual machine: '%s' is not a valid node name" % node_group_name)
		return []

	if not node.has_header(NODE_GROUP_HUB_HEADER):
		return [{
			"content_id": node_group_name,
			"complexity": 0,
			"conditions_passed": 1,
			"conditions_failed": 0,
			"content_type": YarnSaliencyStrategy.ContentType.NODE,
			"destination": 0,
		}]

	return YarnSmartVariableVM.get_saliency_options_for_node_group(
		node_group_name, program, variable_storage, _library)


func get_effective_saliency_strategy() -> YarnSaliencyStrategy:
	if saliency_strategy == null:
		saliency_strategy = YarnSaliencyStrategy.YarnRandomBestLeastRecentlyViewedSaliencyStrategy.new()
	return saliency_strategy


func _collect_line_ids(node: YarnNode) -> PackedStringArray:
	var ids := PackedStringArray()
	for inst in node.instructions:
		if inst.opcode == YarnInstruction.OpCode.RUN_LINE:
			ids.append(inst.line_id)
		elif inst.opcode == YarnInstruction.OpCode.ADD_OPTION:
			ids.append(inst.line_id)
	return ids


func _execute_next_instruction() -> void:
	var instruction := _current_node.instructions[_instruction_pointer]
	var debug_ip := _instruction_pointer
	_instruction_pointer += 1

	if verbose_logging:
		var opcode_name: String = YarnInstruction.OpCode.keys()[instruction.opcode] if instruction.opcode < YarnInstruction.OpCode.size() else str(instruction.opcode)
		print("VM [%s] ip=%d %s stack=%s" % [_current_node.node_name, debug_ip, opcode_name, _stack])

	match instruction.opcode:
		YarnInstruction.OpCode.JUMP_TO:
			_instruction_pointer = instruction.destination

		YarnInstruction.OpCode.PEEK_AND_JUMP:
			var dest: Variant = _peek()
			if _has_error:
				return
			if not (dest is float or dest is int):
				_fail("PEEK_AND_JUMP expected a number, got %s" % type_string(typeof(dest)))
				return
			_instruction_pointer = YarnNumber.to_int32(float(dest))

		YarnInstruction.OpCode.RUN_LINE:
			_execute_run_line(instruction)

		YarnInstruction.OpCode.RUN_COMMAND:
			_execute_run_command(instruction)

		YarnInstruction.OpCode.ADD_OPTION:
			_execute_add_option(instruction)

		YarnInstruction.OpCode.SHOW_OPTIONS:
			_execute_show_options()

		YarnInstruction.OpCode.PUSH_STRING:
			_push(instruction.string_value)

		YarnInstruction.OpCode.PUSH_FLOAT:
			_push(instruction.float_value)

		YarnInstruction.OpCode.PUSH_BOOL:
			_push(instruction.bool_value)

		YarnInstruction.OpCode.JUMP_IF_FALSE:
			var value: Variant = _peek()
			if _has_error:
				return
			if not _value_to_bool(value):
				_instruction_pointer = instruction.destination

		YarnInstruction.OpCode.POP:
			_pop()

		YarnInstruction.OpCode.CALL_FUNC:
			_execute_call_function(instruction)

		YarnInstruction.OpCode.PUSH_VARIABLE:
			if variable_storage == null:
				_fail("no variable storage set")
				return
			var value: Variant = variable_storage.get_value(instruction.variable_name)
			if value == null and program != null:
				value = program.get_initial_value(instruction.variable_name)
			if value == null:
				_fail("variable storage returned a null value for variable '%s'" % instruction.variable_name)
				return
			_push(value)

		YarnInstruction.OpCode.STORE_VARIABLE:
			if variable_storage == null:
				_fail("no variable storage set")
				return
			var value: Variant = _peek()
			if _has_error:
				return
			if value is float or value is int:
				variable_storage.set_value(instruction.variable_name, YarnNumber.to_f32(float(value)))
			elif value is String or value is bool:
				variable_storage.set_value(instruction.variable_name, value)
			else:
				_fail("invalid Yarn value type %s" % type_string(typeof(value)))

		YarnInstruction.OpCode.STOP:
			_return_from_node(_current_node)

			while not _call_stack.is_empty():
				var return_point: Dictionary = _call_stack.pop_back()
				_return_from_node(program.get_node(return_point.node_name))

			dialogue_complete_handler.emit()
			_set_stopped()

		YarnInstruction.OpCode.RUN_NODE:
			_execute_jump_to_node(instruction.node_name, false)

		YarnInstruction.OpCode.PEEK_AND_RUN_NODE:
			_execute_jump_to_node("", false, true)

		YarnInstruction.OpCode.DETOUR_TO_NODE:
			_execute_jump_to_node(instruction.node_name, true)

		YarnInstruction.OpCode.PEEK_AND_DETOUR_TO_NODE:
			_execute_jump_to_node("", true, true)

		YarnInstruction.OpCode.RETURN:
			_return_from_node(_current_node)
			if _call_stack.is_empty():
				dialogue_complete_handler.emit()
				_set_stopped()
			else:
				var return_point: Dictionary = _call_stack.pop_back()
				if not program.has_node(return_point.node_name):
					_set_stopped()
					_fail("no node named '%s' has been loaded" % return_point.node_name)
					return
				_load_node(return_point.node_name, false)
				_instruction_pointer = return_point.ip

		YarnInstruction.OpCode.ADD_SALIENCY_CANDIDATE:
			_execute_add_saliency_candidate(instruction)

		YarnInstruction.OpCode.ADD_SALIENCY_CANDIDATE_FROM_NODE:
			_execute_add_saliency_from_node(instruction)

		YarnInstruction.OpCode.SELECT_SALIENCY_CANDIDATE:
			_execute_select_saliency_candidate()

		_:
			_fail("instruction %d in node '%s' is not a supported instruction" % [debug_ip, _current_node.node_name])


func _execute_run_line(instruction: YarnInstruction) -> void:
	var line := YarnLine.new()
	line.line_id = instruction.line_id

	if instruction.substitution_count > _stack.size():
		_fail("not enough values on stack for line substitutions (need %d, have %d)" % [instruction.substitution_count, _stack.size()])
		return

	var subs: Array[String] = []
	for i in range(instruction.substitution_count):
		var value: Variant = _pop()
		if _has_error:
			return
		subs.push_front(_value_to_string(value))
	line.substitutions = subs

	current_state = ExecutionState.SUSPENDED
	line_handler.emit(line)


func _execute_run_command(instruction: YarnInstruction) -> void:
	var text := instruction.command_text

	if instruction.substitution_count > _stack.size():
		_fail("not enough values on stack for command substitutions (need %d, have %d)" % [instruction.substitution_count, _stack.size()])
		return

	var replacements: Array[Dictionary] = []
	for i in range(instruction.substitution_count - 1, -1, -1):
		var value: Variant = _pop()
		if _has_error:
			return
		var marker := "{%d}" % i
		var pos := text.rfind(marker)
		if pos != -1:
			replacements.append({"pos": pos, "len": marker.length(), "value": _value_to_string(value)})

	replacements.sort_custom(func(a, b): return a.pos > b.pos)
	for r in replacements:
		text = text.substr(0, r.pos) + r.value + text.substr(r.pos + r.len)

	current_state = ExecutionState.SUSPENDED
	command_handler.emit(text)


func _execute_add_option(instruction: YarnInstruction) -> void:
	var pops_needed := instruction.substitution_count
	if instruction.has_condition:
		pops_needed += 1

	if pops_needed > _stack.size():
		_fail("not enough values on stack for option (need %d, have %d)" % [pops_needed, _stack.size()])
		return

	var option := YarnOption.new()
	option.line_id = instruction.line_id
	option.destination = instruction.destination
	option.option_index = _pending_options.size()

	var subs: Array[String] = []
	for i in range(instruction.substitution_count):
		var value: Variant = _pop()
		if _has_error:
			return
		subs.push_front(_value_to_string(value))
	option.substitutions = subs

	if instruction.has_condition:
		var condition_value: Variant = _pop()
		if _has_error:
			return
		option.is_available = _value_to_bool(condition_value)
	else:
		option.is_available = true

	if verbose_logging:
		print("VM: ADD_OPTION line=%s dest=%d available=%s" % [option.line_id, option.destination, option.is_available])
	_pending_options.append(option)


func _execute_show_options() -> void:
	if _pending_options.is_empty():
		_set_stopped()
		dialogue_complete_handler.emit()
		return

	current_state = ExecutionState.WAITING_FOR_INPUT
	options_handler.emit(_pending_options.duplicate())


func _execute_call_function(instruction: YarnInstruction) -> void:
	var func_name := instruction.function_name

	if _library == null:
		_fail("no library set for function call '%s'" % func_name)
		return
	if not _library.has_function(func_name):
		_fail("function '%s' is not present in the library" % func_name)
		return

	var result: Variant = _library.call_function(func_name, _stack, self)
	if YarnLibrary.is_function_error(result):
		var message := _library.take_function_error()
		_fail("function '%s' failed: %s" % [func_name, message])
		return
	_push(result)


func _execute_jump_to_node(node_name: String, is_detour: bool, peek_name: bool = false) -> void:
	if is_detour:
		if max_call_stack_depth > 0 and _call_stack.size() >= max_call_stack_depth:
			_fail("exceeded maximum call stack depth (%d) - possible infinite recursion" % max_call_stack_depth)
			return
		_call_stack.push_back({
			"node_name": _current_node.node_name,
			"ip": _instruction_pointer,
		})
	else:
		_return_from_node(_current_node)

		while not _call_stack.is_empty():
			var return_point: Dictionary = _call_stack.pop_back()
			_return_from_node(program.get_node(return_point.node_name))

	if peek_name:
		var peeked: Variant = _peek()
		if _has_error:
			return
		node_name = _value_to_string(peeked)

	if not program.has_node(node_name):
		_set_stopped()
		_fail("no node named '%s' has been loaded" % node_name)
		return

	_load_node(node_name, not is_detour)


func _execute_add_saliency_candidate(instruction: YarnInstruction) -> void:
	var condition_value: Variant = _pop()
	if _has_error:
		return
	var condition_passed := _value_to_bool(condition_value)
	_saliency_candidates.append({
		"content_id": instruction.content_id,
		"complexity": instruction.complexity_score,
		"destination": instruction.destination,
		"conditions_passed": 1 if condition_passed else 0,
		"conditions_failed": 0 if condition_passed else 1,
		"content_type": YarnSaliencyStrategy.ContentType.LINE,
	})


func _execute_add_saliency_from_node(instruction: YarnInstruction) -> void:
	var node_name := instruction.node_name
	if program == null:
		_fail("failed to add saliency candidate from node '%s': no program is loaded" % node_name)
		return
	if not program.has_node(node_name):
		_fail("failed to add saliency candidate from node '%s': no node with this name is loaded" % node_name)
		return

	var node := program.get_node(node_name)

	var conditions_passed := 0
	var conditions_failed := 0
	for var_name in node.get_header(SALIENCY_VARIABLES_HEADER).split(";", false):
		var evaluation := YarnSmartVariableVM.try_evaluate_named(var_name, program, variable_storage, _library)
		if evaluation.has("error"):
			_fail("failed to add saliency candidate from node '%s': %s" % [node_name, evaluation.error])
			return
		if evaluation.found and _value_to_bool(evaluation.value):
			conditions_passed += 1
		else:
			conditions_failed += 1

	var complexity := -1
	var complexity_header := node.get_header(SALIENCY_COMPLEXITY_HEADER)
	if complexity_header.is_valid_int():
		complexity = complexity_header.to_int()

	_saliency_candidates.append({
		"content_id": node_name,
		"complexity": complexity,
		"destination": instruction.destination,
		"node_name": node_name,
		"conditions_passed": conditions_passed,
		"conditions_failed": conditions_failed,
		"content_type": YarnSaliencyStrategy.ContentType.NODE,
	})


func _execute_select_saliency_candidate() -> void:
	var context := {
		"vm": self,
		"variable_storage": variable_storage
	}

	var strategy := get_effective_saliency_strategy()
	var selected_index := strategy.select_candidate(_saliency_candidates, context)

	if selected_index >= _saliency_candidates.size():
		var candidate_count := _saliency_candidates.size()
		_saliency_candidates.clear()
		_fail("content saliency strategy did not return a valid selection (index %d of %d candidates)" % [selected_index, candidate_count])
		return

	if selected_index < 0:
		_saliency_candidates.clear()
		_push(false)
		return

	var best_candidate: Dictionary = _saliency_candidates[selected_index]
	strategy.on_candidate_selected(best_candidate, context)
	_saliency_candidates.clear()

	_push(best_candidate.destination)
	_push(true)


func _push(value: Variant) -> void:
	if value is int:
		value = float(value)
	if value is float:
		value = YarnNumber.to_f32(value)
	_stack.push_back(value)


func _pop() -> Variant:
	if _stack.is_empty():
		if _current_node != null and _instruction_pointer > 0 and _instruction_pointer - 1 < _current_node.instructions.size():
			var prev_ip := _instruction_pointer - 1
			var inst := _current_node.instructions[prev_ip]
			_fail("stack underflow at instruction %d (opcode %s) in node '%s'" % [prev_ip, inst.opcode, _current_node.node_name])
		else:
			_fail("stack underflow")
		return null
	return _stack.pop_back()


func _peek() -> Variant:
	if _stack.is_empty():
		_fail("stack underflow on peek")
		return null
	return _stack.back()


func _fail(message: String) -> void:
	push_error("virtual machine: %s" % message)
	_has_error = true
	last_error = message
	current_state = ExecutionState.STOPPED


func _reset_state() -> void:
	_stack.clear()
	_pending_options.clear()
	_call_stack.clear()
	_instruction_pointer = 0


func _set_stopped() -> void:
	current_state = ExecutionState.STOPPED
	_reset_state()
	_current_node = null


static func _value_to_bool(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is float or value is int:
		return value != 0
	if value is String:
		return value.strip_edges().to_lower() == "true"
	return true


static func _value_to_string(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool:
		return "True" if value else "False"
	if value is float or value is int:
		return YarnNumber.to_display_string(float(value))
	return str(value)


func _return_from_node(node: YarnNode) -> void:
	if node == null:
		return

	node_complete_handler.emit(node.node_name)

	if not node.has_header(TRACKING_VARIABLE_HEADER) or variable_storage == null:
		return

	var tracking_var := node.get_header(TRACKING_VARIABLE_HEADER)
	var raw_value: Variant = variable_storage.get_value(tracking_var)
	if raw_value is float or raw_value is int:
		variable_storage.set_value(tracking_var, YarnNumber.to_f32(float(raw_value) + 1.0))
	else:
		push_error("virtual machine: failed to get the tracking variable for node '%s'" % node.node_name)
