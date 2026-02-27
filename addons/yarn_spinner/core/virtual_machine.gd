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
## Stack-based VM that executes compiled Yarn bytecode. Port of Unity's VirtualMachine.

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

var program: YarnProgram
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

var max_instructions_per_step: int = 10000
var _instruction_count: int = 0
var max_call_stack_depth: int = 100
## Prevents re-entrant calls to continue_dialogue from signal handlers.
var _is_continuing: bool = false


func set_library(library: YarnLibrary) -> void:
	_library = library


func set_saliency_strategy(strategy: YarnSaliencyStrategy) -> void:
	saliency_strategy = strategy


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


func set_node(node_name: String) -> bool:
	if program == null:
		push_error("virtual machine: no program loaded")
		return false

	if not program.has_node(node_name):
		push_error("virtual machine: node '%s' not found" % node_name)
		return false

	_current_node = program.get_node(node_name)
	_instruction_pointer = 0
	_stack.clear()
	_pending_options.clear()
	_call_stack.clear()
	_has_error = false
	current_state = ExecutionState.RUNNING

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

	var line_ids := _collect_line_ids(_current_node)
	if not line_ids.is_empty():
		prepare_for_lines_handler.emit(line_ids)

	return true


func continue_dialogue() -> void:
	if _is_continuing:
		return

	if _has_error:
		push_error("virtual machine: cannot continue after error")
		return

	if current_state == ExecutionState.STOPPED:
		push_error("virtual machine: cannot continue, dialogue is stopped")
		return

	if current_state == ExecutionState.WAITING_FOR_INPUT:
		push_error("virtual machine: cannot continue, waiting for option selection")
		return

	_is_continuing = true
	current_state = ExecutionState.RUNNING
	_instruction_count = 0

	while current_state == ExecutionState.RUNNING and not _has_error:
		_instruction_count += 1
		if _instruction_count > max_instructions_per_step:
			push_error("virtual machine: exceeded maximum instructions per step (%d) - possible infinite loop" % max_instructions_per_step)
			_has_error = true
			last_error = "exceeded maximum instructions - possible infinite loop"
			current_state = ExecutionState.STOPPED
			break

		if _current_node == null:
			push_error("virtual machine: no current node")
			_has_error = true
			current_state = ExecutionState.STOPPED
			break
		if _instruction_pointer < 0 or _instruction_pointer >= _current_node.instructions.size():
			push_error("virtual machine: instruction pointer out of bounds (%d)" % _instruction_pointer)
			_has_error = true
			current_state = ExecutionState.STOPPED
			break
		_execute_next_instruction()

	_is_continuing = false


const NO_OPTION_SELECTED := -1


## Pushes destination + true flag onto stack for the JUMP_IF_FALSE / POP / PEEK_AND_JUMP
## sequence that the compiler emits after SHOW_OPTIONS.
func set_selected_option(option_index: int) -> void:
	if current_state != ExecutionState.WAITING_FOR_INPUT:
		push_error("virtual machine: not waiting for option selection")
		return

	if option_index == NO_OPTION_SELECTED:
		# No option selected - push false so JUMP_IF_FALSE skips to fallthrough
		if verbose_logging:
			print("VM: set_selected_option: no option selected, pushing false for fallthrough")
		_push(false)
		_pending_options.clear()
		current_state = ExecutionState.RUNNING
		return

	if option_index < 0 or option_index >= _pending_options.size():
		push_error("virtual machine: invalid option index %d" % option_index)
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
	current_state = ExecutionState.STOPPED
	_is_continuing = false
	_stack.clear()
	_pending_options.clear()
	_call_stack.clear()


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

func get_header_value(node_name: String, header_name: String) -> String:
	if program == null:
		return ""
	var node := program.get_node(node_name)
	if node == null:
		return ""
	return node.headers.get(header_name, "")


func get_headers(node_name: String) -> Dictionary:
	if program == null:
		return {}
	var node := program.get_node(node_name)
	if node == null:
		return {}
	return node.headers.duplicate()


func get_string_id_for_node(node_name: String) -> String:
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
		return false
	var node := program.get_node(node_name)
	if node == null:
		return false
	return node.headers.has(NODE_GROUP_HUB_HEADER)


func has_salient_content(node_group_name: String) -> bool:
	var options := get_saliency_options_for_node_group(node_group_name)
	if options.is_empty():
		return false
	if saliency_strategy == null:
		return true
	var context := {
		"vm": self,
		"variable_storage": variable_storage
	}
	var selected_index := saliency_strategy.select_candidate(options, context)
	return selected_index >= 0


func get_saliency_options_for_node_group(node_group_name: String) -> Array:
	if program == null:
		return []

	var node := program.get_node(node_group_name)
	if node == null:
		return []

	# Non-hub nodes get wrapped as a single saliency candidate.
	if not node.headers.has(NODE_GROUP_HUB_HEADER):
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


func _build_saliency_candidate_from_instruction(instruction: YarnInstruction, parent_node: YarnNode) -> Dictionary:
	var content_id_str: String = str(instruction.destination)
	var candidate := {
		"content_id": content_id_str,
		"complexity": instruction.float_value if instruction.float_value != 0.0 else -1,
		"conditions_passed": 0,
		"conditions_failed": 0,
		"destination": instruction.destination,
		"content_type": YarnSaliencyStrategy.ContentType.NODE,
	}

	if parent_node.headers.has(SALIENCY_VARIABLES_HEADER):
		var condition_vars: String = parent_node.headers[SALIENCY_VARIABLES_HEADER]
		var var_names := condition_vars.split(";", false)
		for var_name in var_names:
			var_name = var_name.strip_edges()
			if var_name.is_empty():
				continue
			var value: Variant = YarnSmartVariableVM._evaluate_smart_or_stored(
				var_name, variable_storage, _library, program)
			if value != null and _is_truthy(value):
				candidate.conditions_passed += 1
			else:
				candidate.conditions_failed += 1

	return candidate


func _collect_line_ids(node: YarnNode) -> PackedStringArray:
	var ids := PackedStringArray()
	for inst in node.instructions:
		if inst.opcode == YarnInstruction.OpCode.RUN_LINE:
			ids.append(inst.line_id)
		elif inst.opcode == YarnInstruction.OpCode.ADD_OPTION:
			ids.append(inst.line_id)
	return ids


func _execute_next_instruction() -> void:
	if _current_node == null:
		current_state = ExecutionState.STOPPED
		dialogue_complete_handler.emit()
		return

	if _instruction_pointer >= _current_node.instructions.size():
		# The compiler always emits RETURN which handles call stack unwinding;
		# a bare IP overflow here does NOT unwind.
		_return_from_node(_current_node)
		current_state = ExecutionState.STOPPED
		dialogue_complete_handler.emit()
		return

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
			if dest is float:
				dest = int(dest)
			elif dest is int:
				pass  # already int
			else:
				push_error("virtual machine: PEEK_AND_JUMP expected number, got %s" % type_string(typeof(dest)))
				_has_error = true
				current_state = ExecutionState.STOPPED
				return
			_instruction_pointer = dest

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
			if not _is_truthy(value):
				_instruction_pointer = instruction.destination

		YarnInstruction.OpCode.POP:
			_pop()

		YarnInstruction.OpCode.CALL_FUNC:
			_execute_call_function(instruction)

		YarnInstruction.OpCode.PUSH_VARIABLE:
			if variable_storage == null:
				push_error("virtual machine: no variable storage set")
				_has_error = true
				current_state = ExecutionState.STOPPED
				return
			var value: Variant = variable_storage.get_value(instruction.variable_name)
			# Fall back to Program.InitialValues if not in storage.
			if value == null and program != null:
				value = program.get_initial_value(instruction.variable_name)
			if value == null and not instruction.variable_name.begins_with("$Yarn.Internal."):
				push_error("virtual machine: variable '%s' not found" % instruction.variable_name)
			_push(value)

		YarnInstruction.OpCode.STORE_VARIABLE:
			if variable_storage == null:
				push_error("virtual machine: no variable storage set")
				_has_error = true
				current_state = ExecutionState.STOPPED
				return
			var value: Variant = _peek()
			if _has_error:
				return
			variable_storage.set_value(instruction.variable_name, value)

		YarnInstruction.OpCode.STOP:
			_return_from_node(_current_node)

			while not _call_stack.is_empty():
				var return_point: Dictionary = _call_stack.pop_back()
				_return_from_node(return_point.node)

			current_state = ExecutionState.STOPPED
			dialogue_complete_handler.emit()

		YarnInstruction.OpCode.RUN_NODE:
			_execute_run_node(instruction.node_name, false)

		YarnInstruction.OpCode.PEEK_AND_RUN_NODE:
			var node_name: Variant = _peek()
			if _has_error:
				return
			if not node_name is String:
				push_error("virtual machine: PEEK_AND_RUN_NODE expected string, got %s" % type_string(typeof(node_name)))
				_has_error = true
				current_state = ExecutionState.STOPPED
				return
			_execute_run_node(node_name, false)

		YarnInstruction.OpCode.DETOUR_TO_NODE:
			_execute_run_node(instruction.node_name, true)

		YarnInstruction.OpCode.PEEK_AND_DETOUR_TO_NODE:
			var node_name: Variant = _peek()
			if _has_error:
				return
			if not node_name is String:
				push_error("virtual machine: PEEK_AND_DETOUR_TO_NODE expected string, got %s" % type_string(typeof(node_name)))
				_has_error = true
				current_state = ExecutionState.STOPPED
				return
			_execute_run_node(node_name, true)

		YarnInstruction.OpCode.RETURN:
			_return_from_node(_current_node)
			if not _call_stack.is_empty():
				var return_point: Dictionary = _call_stack.pop_back()
				_current_node = return_point.node
				_instruction_pointer = return_point.ip
				_execute_set_node_signals(_current_node)
			else:
				current_state = ExecutionState.STOPPED
				dialogue_complete_handler.emit()

		YarnInstruction.OpCode.ADD_SALIENCY_CANDIDATE:
			_execute_add_saliency_candidate(instruction)

		YarnInstruction.OpCode.ADD_SALIENCY_CANDIDATE_FROM_NODE:
			_execute_add_saliency_from_node(instruction)

		YarnInstruction.OpCode.SELECT_SALIENCY_CANDIDATE:
			_execute_select_saliency_candidate()


func _execute_run_line(instruction: YarnInstruction) -> void:
	var line := YarnLine.new()
	line.line_id = instruction.line_id

	if instruction.substitution_count > _stack.size():
		push_error("virtual machine: not enough values on stack for line substitutions (need %d, have %d)" % [instruction.substitution_count, _stack.size()])
		_has_error = true
		current_state = ExecutionState.STOPPED
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
		push_error("virtual machine: not enough values on stack for command substitutions (need %d, have %d)" % [instruction.substitution_count, _stack.size()])
		_has_error = true
		current_state = ExecutionState.STOPPED
		return

	# Position-based replacement handles edge cases where markers overlap.
	var replacements: Array[Dictionary] = []
	for i in range(instruction.substitution_count - 1, -1, -1):
		var value: Variant = _pop()
		if _has_error:
			return
		var marker := "{%d}" % i
		var pos := text.rfind(marker)
		if pos != -1:
			replacements.append({"pos": pos, "len": marker.length(), "value": _value_to_string(value)})

	# Apply from end to start so earlier positions remain valid.
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
		push_error("virtual machine: not enough values on stack for option (need %d, have %d)" % [pops_needed, _stack.size()])
		_has_error = true
		current_state = ExecutionState.STOPPED
		return

	var option := YarnOption.new()
	option.line_id = instruction.line_id
	option.destination = instruction.destination
	option.option_index = _pending_options.size()

	var subs: Array[String] = []
	for i in range(instruction.substitution_count):
		var value = _pop()
		if _has_error:
			return
		subs.push_front(_value_to_string(value))
	option.substitutions = subs

	if instruction.has_condition:
		var condition_value: Variant = _pop()
		if _has_error:
			return
		option.is_available = _is_truthy(condition_value)
	else:
		option.is_available = true

	if verbose_logging:
		print("VM: ADD_OPTION line=%s dest=%d available=%s" % [option.line_id, option.destination, option.is_available])
	_pending_options.append(option)


func _execute_show_options() -> void:
	if _pending_options.is_empty():
		current_state = ExecutionState.STOPPED
		dialogue_complete_handler.emit()
		return

	current_state = ExecutionState.WAITING_FOR_INPUT
	options_handler.emit(_pending_options.duplicate())


func _execute_call_function(instruction: YarnInstruction) -> void:
	if _library == null:
		push_error("virtual machine: no library set for function call")
		return

	var func_name := instruction.function_name
	var result: Variant = _library.call_function(func_name, _stack, self)
	if result != null:
		_push(result)


func _execute_run_node(node_name: String, is_detour: bool) -> void:
	if not program.has_node(node_name):
		push_error("virtual machine: node '%s' not found" % node_name)
		_has_error = true
		last_error = "node '%s' not found" % node_name
		current_state = ExecutionState.STOPPED
		dialogue_complete_handler.emit()
		return

	if is_detour:
		# Detours preserve the current node; execution returns here after the detour completes.
		if _call_stack.size() >= max_call_stack_depth:
			push_error("virtual machine: exceeded maximum call stack depth (%d) - possible infinite recursion" % max_call_stack_depth)
			_has_error = true
			last_error = "exceeded maximum call stack depth - possible infinite recursion"
			current_state = ExecutionState.STOPPED
			dialogue_complete_handler.emit()
			return

		_call_stack.push_back({
			"node": _current_node,
			"ip": _instruction_pointer
		})
	else:
		_return_from_node(_current_node)

		while not _call_stack.is_empty():
			var return_point: Dictionary = _call_stack.pop_back()
			_return_from_node(return_point.node)

		# Clear before setting new node so ResetState order is correct.
		_stack.clear()
		_pending_options.clear()

	_current_node = program.get_node(node_name)
	_instruction_pointer = 0

	node_start_handler.emit(node_name)

	var line_ids := _collect_line_ids(_current_node)
	if not line_ids.is_empty():
		prepare_for_lines_handler.emit(line_ids)


func _execute_add_saliency_candidate(instruction: YarnInstruction) -> void:
	var condition_value: Variant = _pop()
	if _has_error:
		return
	# All candidates are added regardless of condition; the strategy uses pass/fail counts.
	var condition_passed := _is_truthy(condition_value)
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
	if not program.has_node(node_name):
		return

	var node := program.get_node(node_name)

	var complexity := 0
	var complexity_header := node.get_header(SALIENCY_COMPLEXITY_HEADER)
	if not complexity_header.is_empty():
		complexity = int(complexity_header)
	elif node.has_header("when"):
		# fallback: use when clause hash as complexity
		complexity = node.get_header("when").hash()

	var conditions_passed := 0
	var conditions_failed := 0
	var saliency_vars := node.get_header(SALIENCY_VARIABLES_HEADER)
	if not saliency_vars.is_empty():
		var var_names := saliency_vars.split(";")
		for var_name in var_names:
			var_name = var_name.strip_edges()
			if var_name.is_empty():
				continue
			var value: Variant = YarnSmartVariableVM._evaluate_smart_or_stored(
				var_name, variable_storage, _library, program)
			if _is_truthy(value):
				conditions_passed += 1
			else:
				conditions_failed += 1

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
	if _saliency_candidates.is_empty():
		_push(false)
		return

	var context := {
		"vm": self,
		"variable_storage": variable_storage
	}

	var selected_index := -1

	if saliency_strategy != null:
		selected_index = saliency_strategy.select_candidate(_saliency_candidates, context)
	else:
		# Fallback: first valid candidate (FirstSaliencyStrategy behavior).
		for i in range(_saliency_candidates.size()):
			if _saliency_candidates[i].get("conditions_failed", 0) == 0:
				selected_index = i
				break

	if selected_index < 0 or selected_index >= _saliency_candidates.size():
		_saliency_candidates.clear()
		_push(false)
		return

	var best_candidate: Dictionary = _saliency_candidates[selected_index]

	if saliency_strategy != null:
		saliency_strategy.on_candidate_selected(best_candidate, context)

	_saliency_candidates.clear()

	_push(best_candidate.destination)
	_push(true)


func _push(value: Variant) -> void:
	_stack.push_back(value)


func _pop() -> Variant:
	if _stack.is_empty():
		if _current_node != null and _instruction_pointer > 0:
			var prev_ip := _instruction_pointer - 1
			if prev_ip < _current_node.instructions.size():
				var inst := _current_node.instructions[prev_ip]
				push_error("virtual machine: stack underflow at instruction %d (opcode %s) in node '%s'" % [prev_ip, inst.opcode, _current_node.node_name])
			else:
				push_error("virtual machine: stack underflow")
		else:
			push_error("virtual machine: stack underflow")
		_has_error = true
		current_state = ExecutionState.STOPPED
		return null
	return _stack.pop_back()


func _peek() -> Variant:
	if _stack.is_empty():
		push_error("virtual machine: stack underflow on peek")
		_has_error = true
		current_state = ExecutionState.STOPPED
		return null
	return _stack.back()


func _is_truthy(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is float or value is int:
		return value != 0
	if value is String:
		return not value.is_empty()
	return true


func _value_to_string(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool:
		return "true" if value else "false"
	if value is float:
		var s := "%.6f" % value
		s = s.rstrip("0").rstrip(".")
		return s
	return str(value)


## Re-fires lifecycle signals when returning to a node after a detour (clearState=false).
func _execute_set_node_signals(node: YarnNode) -> void:
	if node == null:
		return
	node_start_handler.emit(node.node_name)
	var line_ids := _collect_line_ids(node)
	if not line_ids.is_empty():
		prepare_for_lines_handler.emit(line_ids)


## Emits node_complete and increments the tracking variable if one exists.
func _return_from_node(node: YarnNode) -> void:
	if node == null:
		return

	var node_name := node.node_name

	node_complete_handler.emit(node_name)

	var tracking_var := node.get_header(TRACKING_VARIABLE_HEADER)
	if not tracking_var.is_empty() and variable_storage != null:
		var raw_value: Variant = variable_storage.get_value(tracking_var)
		var current_value: float = float(raw_value) if raw_value != null else 0.0
		variable_storage.set_value(tracking_var, current_value + 1.0)
