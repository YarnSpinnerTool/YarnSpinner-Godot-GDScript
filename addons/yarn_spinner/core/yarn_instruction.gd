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

class_name YarnInstruction
extends Resource
## Represents a single instruction in a yarn node.

enum OpCode {
	JUMP_TO,
	PEEK_AND_JUMP,
	RUN_LINE,
	RUN_COMMAND,
	ADD_OPTION,
	SHOW_OPTIONS,
	PUSH_STRING,
	PUSH_FLOAT,
	PUSH_BOOL,
	JUMP_IF_FALSE,
	POP,
	CALL_FUNC,
	PUSH_VARIABLE,
	STORE_VARIABLE,
	STOP,
	RUN_NODE,
	PEEK_AND_RUN_NODE,
	DETOUR_TO_NODE,
	PEEK_AND_DETOUR_TO_NODE,
	RETURN,
	ADD_SALIENCY_CANDIDATE,
	ADD_SALIENCY_CANDIDATE_FROM_NODE,
	SELECT_SALIENCY_CANDIDATE
}

@export var opcode: OpCode = OpCode.STOP

@export var string_value: String = ""
@export var line_id: String = ""
@export var node_name: String = ""
@export var variable_name: String = ""
@export var function_name: String = ""
@export var command_text: String = ""
@export var content_id: String = ""

@export var destination: int = 0
@export var substitution_count: int = 0
@export var complexity_score: int = 0

@export var bool_value: bool = false
@export var has_condition: bool = false

@export var float_value: float = 0.0


static func jump_to(dest: int) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.JUMP_TO
	inst.destination = dest
	return inst


static func peek_and_jump() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.PEEK_AND_JUMP
	return inst


static func run_line(id: String, subs: int) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.RUN_LINE
	inst.line_id = id
	inst.substitution_count = subs
	return inst


static func run_command(text: String, subs: int) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.RUN_COMMAND
	inst.command_text = text
	inst.substitution_count = subs
	return inst


static func add_option(id: String, dest: int, subs: int, has_cond: bool) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.ADD_OPTION
	inst.line_id = id
	inst.destination = dest
	inst.substitution_count = subs
	inst.has_condition = has_cond
	return inst


static func show_options() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.SHOW_OPTIONS
	return inst


static func push_string(value: String) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.PUSH_STRING
	inst.string_value = value
	return inst


static func push_float(value: float) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.PUSH_FLOAT
	inst.float_value = value
	return inst


static func push_bool(value: bool) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.PUSH_BOOL
	inst.bool_value = value
	return inst


static func jump_if_false(dest: int) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.JUMP_IF_FALSE
	inst.destination = dest
	return inst


static func pop() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.POP
	return inst


static func call_func(name: String) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.CALL_FUNC
	inst.function_name = name
	return inst


static func push_variable(name: String) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.PUSH_VARIABLE
	inst.variable_name = name
	return inst


static func store_variable(name: String) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.STORE_VARIABLE
	inst.variable_name = name
	return inst


static func stop() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.STOP
	return inst


static func run_node(name: String) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.RUN_NODE
	inst.node_name = name
	return inst


static func peek_and_run_node() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.PEEK_AND_RUN_NODE
	return inst


static func detour_to_node(name: String) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.DETOUR_TO_NODE
	inst.node_name = name
	return inst


static func peek_and_detour_to_node() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.PEEK_AND_DETOUR_TO_NODE
	return inst


static func return_inst() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.RETURN
	return inst


static func add_saliency_candidate(id: String, complexity: int, dest: int) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.ADD_SALIENCY_CANDIDATE
	inst.content_id = id
	inst.complexity_score = complexity
	inst.destination = dest
	return inst


static func add_saliency_candidate_from_node(name: String, dest: int) -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.ADD_SALIENCY_CANDIDATE_FROM_NODE
	inst.node_name = name
	inst.destination = dest
	return inst


static func select_saliency_candidate() -> YarnInstruction:
	var inst := YarnInstruction.new()
	inst.opcode = OpCode.SELECT_SALIENCY_CANDIDATE
	return inst
