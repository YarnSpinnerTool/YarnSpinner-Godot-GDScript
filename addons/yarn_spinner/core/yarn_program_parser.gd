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

extends RefCounted
## Parses compiled yarn spinner programs from protobuf binary format (.yarnc files).

const ProtobufReader := preload("res://addons/yarn_spinner/core/protobuf_reader.gd")

const PROGRAM_NAME := 1
const PROGRAM_NODES := 2
const PROGRAM_INITIAL_VALUES := 3
const PROGRAM_LANGUAGE_VERSION := 4

const NODE_NAME := 1
const NODE_INSTRUCTIONS := 7
const NODE_HEADERS := 6

const HEADER_KEY := 1
const HEADER_VALUE := 2

const INST_JUMP_TO := 1
const INST_PEEK_AND_JUMP := 2
const INST_RUN_LINE := 3
const INST_RUN_COMMAND := 4
const INST_ADD_OPTION := 5
const INST_SHOW_OPTIONS := 6
const INST_PUSH_STRING := 7
const INST_PUSH_FLOAT := 8
const INST_PUSH_BOOL := 9
const INST_JUMP_IF_FALSE := 10
const INST_POP := 11
const INST_CALL_FUNC := 12
const INST_PUSH_VARIABLE := 13
const INST_STORE_VARIABLE := 14
const INST_STOP := 15
const INST_RUN_NODE := 16
const INST_PEEK_AND_RUN_NODE := 17
const INST_DETOUR_TO_NODE := 18
const INST_PEEK_AND_DETOUR_TO_NODE := 19
const INST_RETURN := 20
const INST_ADD_SALIENCY_CANDIDATE := 21
const INST_ADD_SALIENCY_CANDIDATE_FROM_NODE := 22
const INST_SELECT_SALIENCY_CANDIDATE := 23

const OPERAND_STRING := 1
const OPERAND_BOOL := 2
const OPERAND_FLOAT := 3


static func parse_from_file(path: String) -> YarnProgram:
	var reader := ProtobufReader.new()
	var err := reader.init_from_file(path)
	if err != OK:
		push_error("yarn program parser: failed to open file %s" % path)
		return null
	return _parse_program(reader)


static func parse_from_bytes(data: PackedByteArray) -> YarnProgram:
	var reader := ProtobufReader.new()
	reader.init_from_bytes(data)
	return _parse_program(reader)


static func _parse_program(reader: ProtobufReader) -> YarnProgram:
	var program := YarnProgram.new()

	while not reader.is_eof():
		var tag := reader.read_tag()
		match tag.field_number:
			PROGRAM_NAME:
				program.program_name = reader.read_string()
			PROGRAM_NODES:
				var entry := _parse_map_entry_string_node(reader)
				if entry.key != "":
					program.nodes[entry.key] = entry.value
			PROGRAM_INITIAL_VALUES:
				var entry := _parse_map_entry_string_operand(reader)
				if entry.key != "":
					program.initial_values[entry.key] = entry.value
			PROGRAM_LANGUAGE_VERSION:
				program.language_version = reader.read_varint()
			_:
				reader.skip_field(tag.wire_type)

	return program


static func _parse_map_entry_string_node(reader: ProtobufReader) -> Dictionary:
	var end_pos := reader.begin_embedded_message()
	var key := ""
	var value: YarnNode = null

	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			1:  # key
				key = reader.read_string()
			2:  # value
				value = _parse_node(reader)
			_:
				reader.skip_field(tag.wire_type)

	return {"key": key, "value": value}


static func _parse_map_entry_string_operand(reader: ProtobufReader) -> Dictionary:
	var end_pos := reader.begin_embedded_message()
	var key := ""
	var value: Variant = null

	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			1:  # key
				key = reader.read_string()
			2:  # value (operand)
				value = _parse_operand(reader)
			_:
				reader.skip_field(tag.wire_type)

	return {"key": key, "value": value}


static func _parse_node(reader: ProtobufReader) -> YarnNode:
	var end_pos := reader.begin_embedded_message()
	var node := YarnNode.new()

	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			NODE_NAME:
				node.node_name = reader.read_string()
			NODE_HEADERS:
				var header := _parse_header(reader)
				node.headers[header.key] = header.value
			NODE_INSTRUCTIONS:
				var inst := _parse_instruction(reader)
				if inst != null:
					node.instructions.append(inst)
			_:
				reader.skip_field(tag.wire_type)

	return node


static func _parse_header(reader: ProtobufReader) -> Dictionary:
	var end_pos := reader.begin_embedded_message()
	var key := ""
	var value := ""

	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			HEADER_KEY:
				key = reader.read_string()
			HEADER_VALUE:
				value = reader.read_string()
			_:
				reader.skip_field(tag.wire_type)

	return {"key": key, "value": value}


static func _parse_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var inst: YarnInstruction = null

	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			INST_JUMP_TO:
				inst = _parse_jump_to_instruction(reader)
			INST_PEEK_AND_JUMP:
				inst = _parse_peek_and_jump_instruction(reader)
			INST_RUN_LINE:
				inst = _parse_run_line_instruction(reader)
			INST_RUN_COMMAND:
				inst = _parse_run_command_instruction(reader)
			INST_ADD_OPTION:
				inst = _parse_add_option_instruction(reader)
			INST_SHOW_OPTIONS:
				inst = _parse_show_options_instruction(reader)
			INST_PUSH_STRING:
				inst = _parse_push_string_instruction(reader)
			INST_PUSH_FLOAT:
				inst = _parse_push_float_instruction(reader)
			INST_PUSH_BOOL:
				inst = _parse_push_bool_instruction(reader)
			INST_JUMP_IF_FALSE:
				inst = _parse_jump_if_false_instruction(reader)
			INST_POP:
				inst = _parse_pop_instruction(reader)
			INST_CALL_FUNC:
				inst = _parse_call_func_instruction(reader)
			INST_PUSH_VARIABLE:
				inst = _parse_push_variable_instruction(reader)
			INST_STORE_VARIABLE:
				inst = _parse_store_variable_instruction(reader)
			INST_STOP:
				inst = _parse_stop_instruction(reader)
			INST_RUN_NODE:
				inst = _parse_run_node_instruction(reader)
			INST_PEEK_AND_RUN_NODE:
				inst = _parse_peek_and_run_node_instruction(reader)
			INST_DETOUR_TO_NODE:
				inst = _parse_detour_to_node_instruction(reader)
			INST_PEEK_AND_DETOUR_TO_NODE:
				inst = _parse_peek_and_detour_instruction(reader)
			INST_RETURN:
				inst = _parse_return_instruction(reader)
			INST_ADD_SALIENCY_CANDIDATE:
				inst = _parse_add_saliency_candidate_instruction(reader)
			INST_ADD_SALIENCY_CANDIDATE_FROM_NODE:
				inst = _parse_add_saliency_from_node_instruction(reader)
			INST_SELECT_SALIENCY_CANDIDATE:
				inst = _parse_select_saliency_instruction(reader)
			_:
				reader.skip_field(tag.wire_type)

	return inst


static func _parse_operand(reader: ProtobufReader) -> Variant:
	var end_pos := reader.begin_embedded_message()
	var value: Variant = null

	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			OPERAND_STRING:
				value = reader.read_string()
			OPERAND_BOOL:
				value = reader.read_bool()
			OPERAND_FLOAT:
				value = reader.read_float()
			_:
				reader.skip_field(tag.wire_type)

	return value


static func _parse_jump_to_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var dest := 0
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # destination
			dest = reader.read_varint()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.jump_to(dest)


static func _parse_peek_and_jump_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	# empty message, just consume it
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.peek_and_jump()


static func _parse_run_line_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var line_id := ""
	var sub_count := 0
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			1:  # lineID
				line_id = reader.read_string()
			2:  # substitutionCount
				sub_count = reader.read_varint()
			_:
				reader.skip_field(tag.wire_type)
	return YarnInstruction.run_line(line_id, sub_count)


static func _parse_run_command_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var text := ""
	var sub_count := 0
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			1:  # commandText
				text = reader.read_string()
			2:  # substitutionCount
				sub_count = reader.read_varint()
			_:
				reader.skip_field(tag.wire_type)
	return YarnInstruction.run_command(text, sub_count)


static func _parse_add_option_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var line_id := ""
	var dest := 0
	var sub_count := 0
	var has_cond := false
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			1:  # lineID
				line_id = reader.read_string()
			2:  # destination
				dest = reader.read_varint()
			3:  # substitutionCount
				sub_count = reader.read_varint()
			4:  # hasCondition
				has_cond = reader.read_bool()
			_:
				reader.skip_field(tag.wire_type)
	return YarnInstruction.add_option(line_id, dest, sub_count, has_cond)


static func _parse_show_options_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.show_options()


static func _parse_push_string_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var value := ""
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # value
			value = reader.read_string()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.push_string(value)


static func _parse_push_float_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var value := 0.0
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # value
			value = reader.read_float()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.push_float(value)


static func _parse_push_bool_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var value := false
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # value
			value = reader.read_bool()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.push_bool(value)


static func _parse_jump_if_false_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var dest := 0
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # destination
			dest = reader.read_varint()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.jump_if_false(dest)


static func _parse_pop_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.pop()


static func _parse_call_func_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var name := ""
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # functionName
			name = reader.read_string()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.call_func(name)


static func _parse_push_variable_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var name := ""
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # variableName
			name = reader.read_string()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.push_variable(name)


static func _parse_store_variable_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var name := ""
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # variableName
			name = reader.read_string()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.store_variable(name)


static func _parse_stop_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.stop()


static func _parse_run_node_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var name := ""
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # nodeName
			name = reader.read_string()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.run_node(name)


static func _parse_peek_and_run_node_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.peek_and_run_node()


static func _parse_detour_to_node_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var name := ""
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		if tag.field_number == 1:  # nodeName
			name = reader.read_string()
		else:
			reader.skip_field(tag.wire_type)
	return YarnInstruction.detour_to_node(name)


static func _parse_peek_and_detour_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.peek_and_detour_to_node()


static func _parse_return_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.return_inst()


static func _parse_add_saliency_candidate_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var content_id := ""
	var complexity := 0
	var dest := 0
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			1:  # contentID
				content_id = reader.read_string()
			2:  # complexityScore
				complexity = reader.read_varint()
			3:  # destination
				dest = reader.read_varint()
			_:
				reader.skip_field(tag.wire_type)
	return YarnInstruction.add_saliency_candidate(content_id, complexity, dest)


static func _parse_add_saliency_from_node_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	var name := ""
	var dest := 0
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		match tag.field_number:
			1:  # nodeName
				name = reader.read_string()
			2:  # destination
				dest = reader.read_varint()
			_:
				reader.skip_field(tag.wire_type)
	return YarnInstruction.add_saliency_candidate_from_node(name, dest)


static func _parse_select_saliency_instruction(reader: ProtobufReader) -> YarnInstruction:
	var end_pos := reader.begin_embedded_message()
	while not reader.is_at_end(end_pos):
		var tag := reader.read_tag()
		reader.skip_field(tag.wire_type)
	return YarnInstruction.select_saliency_candidate()
