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
## Binary protobuf reader for parsing .yarnc files.

enum WireType {
	VARINT = 0,       # int32, int64, uint32, uint64, sint32, sint64, bool, enum
	FIXED64 = 1,      # fixed64, sfixed64, double
	LENGTH_DELIM = 2, # string, bytes, embedded messages, packed repeated
	START_GROUP = 3,  # deprecated
	END_GROUP = 4,    # deprecated
	FIXED32 = 5       # fixed32, sfixed32, float
}

var _buffer: PackedByteArray
var _position: int = 0


func init_from_bytes(data: PackedByteArray) -> void:
	_buffer = data
	_position = 0


func init_from_file(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	_buffer = file.get_buffer(file.get_length())
	file.close()
	_position = 0
	return OK


func is_eof() -> bool:
	return _position >= _buffer.size()


func is_at_end(end_pos: int) -> bool:
	return _position >= end_pos


func get_position() -> int:
	return _position


func set_position(pos: int) -> void:
	_position = pos


func read_byte() -> int:
	if _position >= _buffer.size():
		push_error("protobuf reader: attempted to read past end of buffer")
		return 0
	var b := _buffer[_position]
	_position += 1
	return b


func read_varint() -> int:
	var result: int = 0
	var shift: int = 0
	while true:
		var b := read_byte()
		result |= (b & 0x7F) << shift
		if (b & 0x80) == 0:
			break
		shift += 7
		if shift >= 64:
			push_error("protobuf reader: varint too long")
			break
	return result


func read_svarint() -> int:
	var n := read_varint()
	return (n >> 1) ^ -(n & 1)


func read_fixed32() -> int:
	var b0 := read_byte()
	var b1 := read_byte()
	var b2 := read_byte()
	var b3 := read_byte()
	return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)


func read_fixed64() -> int:
	var lo := read_fixed32()
	var hi := read_fixed32()
	return lo | (hi << 32)


func read_float() -> float:
	var bits := read_fixed32()
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, bits)
	return bytes.decode_float(0)


func read_double() -> float:
	var bits := read_fixed64()
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, bits)
	return bytes.decode_double(0)


func read_bytes() -> PackedByteArray:
	var length := read_varint()
	if _position + length > _buffer.size():
		push_error("protobuf reader: length-delimited field extends past buffer")
		return PackedByteArray()
	var result := _buffer.slice(_position, _position + length)
	_position += length
	return result


func read_string() -> String:
	return read_bytes().get_string_from_utf8()


func read_bool() -> bool:
	return read_varint() != 0


func read_tag() -> Dictionary:
	var tag := read_varint()
	return {
		"field_number": tag >> 3,
		"wire_type": tag & 0x07
	}


func skip_field(wire_type: int) -> void:
	match wire_type:
		WireType.VARINT:
			read_varint()
		WireType.FIXED64:
			_position += 8
		WireType.LENGTH_DELIM:
			var length := read_varint()
			_position += length
		WireType.FIXED32:
			_position += 4
		_:
			push_error("protobuf reader: unknown wire type %d" % wire_type)


## Returns the end position for sub-parsing.
func begin_embedded_message() -> int:
	var length := read_varint()
	return _position + length
