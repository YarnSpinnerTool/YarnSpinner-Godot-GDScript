extends GutTest


func _make_reader(bytes: PackedByteArray) -> RefCounted:
	# ProtobufReader doesn't have a class_name, load it directly
	var reader = load("res://addons/yarn_spinner/core/protobuf_reader.gd").new()
	reader.init_from_bytes(bytes)
	return reader


func test_read_byte():
	var reader := _make_reader(PackedByteArray([0x42, 0xFF]))
	assert_eq(reader.read_byte(), 0x42)
	assert_eq(reader.read_byte(), 0xFF)
	assert_false(reader.has_error)


func test_read_byte_past_eof():
	var reader := _make_reader(PackedByteArray([0x01]))
	reader.read_byte()
	reader.read_byte()  # should set error
	assert_true(reader.has_error)
	assert_push_error_count(1)


func test_read_varint_single_byte():
	# 0x05 = 5 (MSB not set, single byte)
	var reader := _make_reader(PackedByteArray([0x05]))
	assert_eq(reader.read_varint(), 5)
	assert_false(reader.has_error)


func test_read_varint_multi_byte():
	# 300 = 0b100101100 -> varint bytes: 0xAC 0x02
	var reader := _make_reader(PackedByteArray([0xAC, 0x02]))
	assert_eq(reader.read_varint(), 300)


func test_read_varint_zero():
	var reader := _make_reader(PackedByteArray([0x00]))
	assert_eq(reader.read_varint(), 0)


func test_read_svarint():
	# zigzag encoding: 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3
	var reader := _make_reader(PackedByteArray([0x00]))
	assert_eq(reader.read_svarint(), 0)

	reader = _make_reader(PackedByteArray([0x01]))
	assert_eq(reader.read_svarint(), -1)

	reader = _make_reader(PackedByteArray([0x02]))
	assert_eq(reader.read_svarint(), 1)

	reader = _make_reader(PackedByteArray([0x03]))
	assert_eq(reader.read_svarint(), -2)


func test_read_string():
	# length-delimited: varint length followed by UTF-8 bytes
	var text := "Hi"
	var utf8 := text.to_utf8_buffer()
	var bytes := PackedByteArray([utf8.size()])
	bytes.append_array(utf8)
	var reader := _make_reader(bytes)
	assert_eq(reader.read_string(), "Hi")


func test_read_bool():
	var reader := _make_reader(PackedByteArray([0x01]))
	assert_true(reader.read_bool())

	reader = _make_reader(PackedByteArray([0x00]))
	assert_false(reader.read_bool())


func test_read_tag():
	# field 2, wire type 0 (varint) -> (2 << 3) | 0 = 16
	var reader := _make_reader(PackedByteArray([0x10]))
	var tag: Dictionary = reader.read_tag()
	assert_eq(tag.field_number, 2)
	assert_eq(tag.wire_type, 0)


func test_read_tag_length_delimited():
	# field 1, wire type 2 (length delimited) -> (1 << 3) | 2 = 10
	var reader := _make_reader(PackedByteArray([0x0A]))
	var tag: Dictionary = reader.read_tag()
	assert_eq(tag.field_number, 1)
	assert_eq(tag.wire_type, 2)


func test_is_eof():
	var reader := _make_reader(PackedByteArray([0x01]))
	assert_false(reader.is_eof())
	reader.read_byte()
	assert_true(reader.is_eof())


func test_is_at_end():
	var reader := _make_reader(PackedByteArray([0x01, 0x02, 0x03]))
	assert_false(reader.is_at_end(2))
	reader.read_byte()
	reader.read_byte()
	assert_true(reader.is_at_end(2))


func test_position_tracking():
	var reader := _make_reader(PackedByteArray([0x01, 0x02, 0x03]))
	assert_eq(reader.get_position(), 0)
	reader.read_byte()
	assert_eq(reader.get_position(), 1)
	reader.set_position(0)
	assert_eq(reader.get_position(), 0)


func test_skip_field_varint():
	var reader := _make_reader(PackedByteArray([0x05, 0xFF]))
	reader.skip_field(0)  # VARINT
	assert_eq(reader.get_position(), 1)


func test_skip_field_fixed32():
	var reader := _make_reader(PackedByteArray([0x01, 0x02, 0x03, 0x04, 0xFF]))
	reader.skip_field(5)  # FIXED32
	assert_eq(reader.get_position(), 4)


func test_skip_field_fixed64():
	var bytes := PackedByteArray()
	bytes.resize(9)
	bytes[8] = 0xFF
	var reader := _make_reader(bytes)
	reader.skip_field(1)  # FIXED64
	assert_eq(reader.get_position(), 8)


func test_skip_field_length_delimited():
	# length = 3, then 3 bytes of data, then sentinel
	var reader := _make_reader(PackedByteArray([0x03, 0xAA, 0xBB, 0xCC, 0xFF]))
	reader.skip_field(2)  # LENGTH_DELIM
	assert_eq(reader.get_position(), 4)


func test_begin_embedded_message():
	# length = 5
	var reader := _make_reader(PackedByteArray([0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]))
	var end_pos: int = reader.begin_embedded_message()
	assert_eq(end_pos, 6)  # position 1 + length 5
	assert_eq(reader.get_position(), 1)


func test_read_fixed32():
	# 0x01020304 in little-endian
	var reader := _make_reader(PackedByteArray([0x04, 0x03, 0x02, 0x01]))
	assert_eq(reader.read_fixed32(), 0x01020304)


func test_read_float():
	# 1.0f in IEEE 754: 0x3F800000 -> little-endian: 00 00 80 3F
	var reader := _make_reader(PackedByteArray([0x00, 0x00, 0x80, 0x3F]))
	assert_almost_eq(reader.read_float(), 1.0, 0.001)


func test_empty_buffer():
	var reader := _make_reader(PackedByteArray())
	assert_true(reader.is_eof())


func test_error_propagation():
	var reader := _make_reader(PackedByteArray())
	reader.read_varint()  # should fail on first read_byte inside
	assert_true(reader.has_error)
	# Further reads return 0 immediately (has_error short-circuits)
	assert_eq(reader.read_varint(), 0)
	assert_push_error_count(1)
