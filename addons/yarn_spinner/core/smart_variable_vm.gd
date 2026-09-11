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

class_name YarnSmartVariableVM
extends RefCounted
## Lightweight static VM for evaluating compiled smart variable bytecode.


## Returns {found: bool, value: Variant}.
static func try_evaluate(node: YarnNode, variable_storage: YarnVariableStorage, library: YarnLibrary) -> Dictionary:
	if node == null:
		return {found = false, value = null}

	var stack: Array = []
	var ip: int = 0

	while ip < node.instructions.size():
		var instruction: YarnInstruction = node.instructions[ip]

		match instruction.opcode:
			YarnInstruction.OpCode.PUSH_STRING:
				stack.push_back(instruction.string_value)

			YarnInstruction.OpCode.PUSH_FLOAT:
				stack.push_back(YarnNumber.to_f32(instruction.float_value))

			YarnInstruction.OpCode.PUSH_BOOL:
				stack.push_back(instruction.bool_value)

			YarnInstruction.OpCode.POP:
				if stack.is_empty():
					return _error(node, "stack underflow")
				stack.pop_back()

			YarnInstruction.OpCode.CALL_FUNC:
				if library == null:
					return _error(node, "no library is available")
				if not library.has_function(instruction.function_name):
					return _error(node, "function '%s' is not present in the library" % instruction.function_name)
				var result: Variant = library.call_function(instruction.function_name, stack, null)
				if YarnLibrary.is_function_error(result):
					return _error(node, library.take_function_error())
				if result is int:
					result = float(result)
				if result is float:
					result = YarnNumber.to_f32(result)
				stack.push_back(result)

			YarnInstruction.OpCode.PUSH_VARIABLE:
				var value: Variant = null
				if variable_storage != null:
					value = variable_storage.get_value(instruction.variable_name)
				if value == null:
					return _error(node, "failed to fetch any value for %s when evaluating a smart variable" % instruction.variable_name)
				stack.push_back(value)

			YarnInstruction.OpCode.JUMP_IF_FALSE:
				if stack.is_empty():
					return _error(node, "stack underflow")
				if not _is_truthy(stack.back()):
					ip = instruction.destination
					continue

			YarnInstruction.OpCode.STOP:
				break

			_:
				return _error(node, "invalid opcode %s when evaluating a smart variable" % str(instruction.opcode))

		ip += 1

	if stack.is_empty():
		return _error(node, "stack did not contain a value after evaluation")

	var calculated: Variant = stack.pop_back()

	if not stack.is_empty():
		return _error(node, "stack had %d dangling value(s)" % stack.size())

	return {found = true, value = calculated}


static func try_evaluate_named(
	variable_name: String,
	program: YarnProgram,
	variable_storage: YarnVariableStorage,
	library: YarnLibrary
) -> Dictionary:
	if program == null:
		return {found = false, value = null, error = "no program is loaded"}
	if variable_name.is_empty():
		return {found = false, value = null, error = "smart variable name cannot be empty"}
	var node := program.get_node(variable_name)
	if node == null:
		return {found = false, value = null}
	return try_evaluate(node, variable_storage, library)


static func _error(node: YarnNode, message: String) -> Dictionary:
	return {found = false, value = null, error = "error when evaluating smart variable %s: %s" % [node.node_name, message]}


## Evaluates condition variables for a node group via smart variable bytecode.
static func get_saliency_options_for_node_group(
	group_name: String,
	program: YarnProgram,
	variable_storage: YarnVariableStorage,
	library: YarnLibrary
) -> Array[Dictionary]:
	var result := try_get_saliency_options_for_node_group(group_name, program, variable_storage, library)
	var error: String = result.error
	if not error.is_empty():
		push_error("smart variable vm: %s" % error)
	return result.options


static func try_get_saliency_options_for_node_group(
	group_name: String,
	program: YarnProgram,
	variable_storage: YarnVariableStorage,
	library: YarnLibrary
) -> Dictionary:
	var candidates: Array[Dictionary] = []

	if program == null:
		return {"options": candidates, "error": "can't get saliency options for '%s', because no program is loaded" % group_name}

	var node := program.get_node(group_name)
	if node == null:
		return {"options": candidates, "error": "error getting available content for node group %s: not a valid node group name" % group_name}

	if not node.has_header(YarnProgram.NODE_GROUP_HUB_HEADER):
		return {"options": candidates, "error": ""}

	for member_name in program.nodes:
		var member: YarnNode = program.nodes[member_name]
		if member.get_header(YarnProgram.NODE_GROUP_HEADER) != group_name:
			continue
		var candidate := _build_member_candidate(member_name, member, variable_storage, library, program)
		if candidate.has("error"):
			var no_candidates: Array[Dictionary] = []
			return {"options": no_candidates, "error": candidate.error}
		candidates.append(candidate)

	return {"options": candidates, "error": ""}


static func _build_member_candidate(
	member_name: String,
	member: YarnNode,
	variable_storage: YarnVariableStorage,
	library: YarnLibrary,
	program: YarnProgram
) -> Dictionary:
	var passing := 0
	var failing := 0

	for var_name in member.get_header("$Yarn.Internal.ContentSaliencyVariables").split(";", false):
		var evaluation := try_evaluate_named(var_name, program, variable_storage, library)
		if evaluation.has("error"):
			return {"error": evaluation.error}
		elif not evaluation.found:
			return {"error": "failed to evaluate saliency condition smart variable %s: variable not found in program" % var_name}
		elif _is_truthy(evaluation.value):
			passing += 1
		else:
			failing += 1

	var complexity := -1
	var complexity_header := member.get_header("$Yarn.Internal.ContentSaliencyComplexity")
	if complexity_header.is_valid_int():
		complexity = complexity_header.to_int()

	return {
		"content_id": member.node_name if not member.node_name.is_empty() else member_name,
		"complexity": complexity,
		"conditions_passed": passing,
		"conditions_failed": failing,
		"destination": 0,
		"content_type": YarnSaliencyStrategy.ContentType.NODE,
	}


static func _is_truthy(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is float or value is int:
		return value != 0
	if value is String:
		return value.strip_edges().to_lower() == "true"
	return true
