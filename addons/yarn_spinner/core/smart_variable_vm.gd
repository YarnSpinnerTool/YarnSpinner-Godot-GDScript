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
	if node == null or node.instructions.is_empty():
		return {found = false, value = null}

	var stack: Array = []
	var ip: int = 0

	while ip < node.instructions.size():
		var instruction: YarnInstruction = node.instructions[ip]
		ip += 1

		match instruction.opcode:
			YarnInstruction.OpCode.PUSH_STRING:
				stack.push_back(instruction.string_value)

			YarnInstruction.OpCode.PUSH_FLOAT:
				stack.push_back(instruction.float_value)

			YarnInstruction.OpCode.PUSH_BOOL:
				stack.push_back(instruction.bool_value)

			YarnInstruction.OpCode.PUSH_VARIABLE:
				if variable_storage == null:
					return {found = false, value = null}
				var value: Variant = variable_storage.get_value(instruction.variable_name)
				stack.push_back(value)

			YarnInstruction.OpCode.CALL_FUNC:
				if library == null:
					return {found = false, value = null}
				var result: Variant = library.call_function(instruction.function_name, stack, null)
				if result == YarnLibrary.FUNCTION_ERROR:
					library.take_function_error()
					return {found = false, value = null}
				if result != null:
					stack.push_back(result)

			YarnInstruction.OpCode.POP:
				if stack.is_empty():
					return {found = false, value = null}
				stack.pop_back()

			YarnInstruction.OpCode.JUMP_IF_FALSE:
				if stack.is_empty():
					return {found = false, value = null}
				var value: Variant = stack.back()
				if not _is_truthy(value):
					ip = instruction.destination

			YarnInstruction.OpCode.STOP:
				break

			_:
				# unsupported opcode for smart variable evaluation
				return {found = false, value = null}

	if stack.size() != 1:
		# A well-formed smart variable node leaves exactly one value: its
		# result. Anything else means the expression bytecode is corrupt,
		# and returning whatever happens to be on top would hide that.
		push_error("smart variable vm: expected exactly 1 value on the stack after evaluation, found %d" % stack.size())
		return {found = false, value = null}

	return {found = true, value = stack.back()}


## Evaluates condition variables for a node group via smart variable bytecode.
static func get_saliency_options_for_node_group(
	group_name: String,
	program: YarnProgram,
	variable_storage: YarnVariableStorage,
	library: YarnLibrary
) -> Array:
	if program == null:
		return []

	var node := program.get_node(group_name)
	if node == null:
		return []

	if not node.headers.has("$Yarn.Internal.NodeGroupHub"):
		return []

	# Every node tagged
	# with this group's NodeGroup header is a candidate. The hub node itself
	# carries no candidate instructions, so we enumerate the program's nodes
	# rather than scanning the hub. Each candidate's saliency-condition
	# variables are evaluated to count passing/failing conditions; the saliency
	# strategy is responsible for discarding the failing ones.
	var candidates: Array[Dictionary] = []
	for member_name in program.nodes:
		var member: YarnNode = program.nodes[member_name]
		if member.headers.get("$Yarn.Internal.NodeGroup", "") != group_name:
			continue
		candidates.append(_build_member_candidate(member_name, member, variable_storage, library, program))

	return candidates


static func _build_member_candidate(
	member_name: String,
	member: YarnNode,
	variable_storage: YarnVariableStorage,
	library: YarnLibrary,
	program: YarnProgram
) -> Dictionary:
	var passing := 0
	var failing := 0

	var saliency_vars_header: String = member.headers.get("$Yarn.Internal.ContentSaliencyVariables", "")
	if not saliency_vars_header.is_empty():
		for var_name in saliency_vars_header.split(";", false):
			var_name = var_name.strip_edges()
			if var_name.is_empty():
				continue
			var value: Variant = _evaluate_smart_or_stored(var_name, variable_storage, library, program)
			if value != null and _is_truthy(value):
				passing += 1
			else:
				failing += 1

	# Complexity score defaults to -1 when the header is absent, as in Unity.
	var complexity := -1
	var complexity_header: String = member.headers.get("$Yarn.Internal.ContentSaliencyComplexity", "")
	if complexity_header.is_valid_int():
		complexity = complexity_header.to_int()

	return {
		"content_id": member_name,
		"complexity": complexity,
		"conditions_passed": passing,
		"conditions_failed": failing,
		"destination": 0,
		"content_type": YarnSaliencyStrategy.ContentType.NODE,
	}


## Tries smart variable nodes first, then falls back to storage.
static func _evaluate_smart_or_stored(
	variable_name: String,
	variable_storage: YarnVariableStorage,
	library: YarnLibrary,
	program: YarnProgram
) -> Variant:
	if program != null:
		var smart_nodes := program.get_smart_variable_nodes()
		for smart_node in smart_nodes:
			if smart_node.node_name == variable_name:
				var result := try_evaluate(smart_node, variable_storage, library)
				if result.found:
					return result.value

	if variable_storage != null:
		return variable_storage.get_value(variable_name)

	return null


static func _is_truthy(value: Variant) -> bool:
	if value == null:
		return false
	if value is bool:
		return value
	if value is float or value is int:
		return value != 0
	if value is String:
		return not value.is_empty()
	return true
