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

class_name YarnUnicodeNormalization
extends RefCounted

const UNICODE_VERSION := "17.0.0"

const _S_BASE := 0xAC00
const _L_BASE := 0x1100
const _V_BASE := 0x1161
const _T_BASE := 0x11A7
const _L_COUNT := 19
const _V_COUNT := 21
const _T_COUNT := 28
const _N_COUNT := 588
const _S_COUNT := 11172

const _CLASS_MASK := 0xFF
const _QUICK_CHECK_MASK := 0x300
const _QUICK_CHECK_MAYBE := 0x200
const _NO_BOUNDARY := 0x400

const _TABLE_SIZE := 37520
const _TABLE: PackedStringArray = [
	"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",
	"i+R2kiMvpv44S7yY+uMs8WLK7yzxYsrvLPEt1B9bG178+0wX7bdcJPeQ3EP+tR7yr2W5i+TID1N7nCN+mNrjHPHDpO+ciX47",
	"yZEfoPZ4m/gKGq8ria+g8bqS+AoaryuJr6DxupLHr9W7PVcST6b2LrBcLHeRHPk6qs964uuoPuuJr6P6rLderN9OcjvJPST3",
	"kL23kD21kNxDcn7eRXIXye0kt4P/uu5/WYP8MWsC/+3AF7iVuC63ktxK8m4k70a+qjWIY/4BlJ+LeADl5yIeQPm5iG+i/DdR",
	"/iGUXyjxEMovNMz79ycLSf9C0l+X9NUjXpf01yP9m0n/ZtLfiPQ1Jt6I9Dcm3ojaqzHxxZT/Yso/gvJrTjyC8mtOPILya058",
	"K+W/lfKPpPyiiEdSflHEIym/KOJLKP8llH805deBeDTl14F4NOXXgXgR5V9E+Xeh/LoS70L5daXxtZz0Lyf9caQvnngc6Y8n",
	"/btJ/27Sn0j6BhJPJP0DiSdSew0Ujv7sNYEPCfP+vd2QMG//9yGkbx+Vfx+VfwSVN434CCpvGvERlF8a8dWU/2rKP4vyyyae",
	"RfllE8+i/LKJ6+uFBX5r8CLZUpStITuFsrU0h1G2jsY3yg7Q2EHZ29QvKDsIY1Bfo3rSGoXcRtxO3EHcj7iTuD/xAOIu4tWI",
	"BxIPIh5MvDpxN/FGxBsTDyfuIX4j8SbEmxJvRjyCeHPiLYi3JH4T8VbEWxNvQ3wE8TTiI4mPIp5OPIP4aOKZxLOIZxO/m3gO",
	"8THExxLPJZ5HXJ/DTuJ4JjfOJD3yF4XbQI424hV6fj7lN5/ym09zdTbJfs/Lr8JW2OF3UJjvBMp3M5V7LZV7M5V7Dz2/kMr1",
	"MO17UPYnkqGeIrLBRWRzi0z2OE7iDvrNFeY9D9pkK9Wp2H7x/sVJ3EEcdT8C7XWB6nGB6nGB6rGb8tpNee2nvNaDbCetcztp",
	"ndtN9dpP/FnK+1nK+1nKey6+k1JeqyzeaWcBHmFRbT+Nxs8+GgcHafztozL/QM8vpzL+mdZ9lP2FZD1B9rJRRg3bGql4e6OK",
	"+ye+x+W/yu59rVV4zg/u+X2lK6tEb1X8EdpL3VYbv3nzkzs0wbvF51Vvp3naDz+i8dsDwmsIf0x4mPB3KP1h4iXC2xn7hvAK",
	"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",
	"241osBv5YDeWwN5sIrxHTFtkbltwjT6+2NzmBD5ubn+ue9L8fLJPhLJFPQAfaavwsk7wLtMF6g44fpBK/84dCr93n8LdId+5",
	"yyt+U6wfzB7V9wF+FbLr4Vs03+r7AD+5N9b4Zxre6afkOt8FPP5f3nKdo/wd0Yd8C/HtwN8lXkL8PeKHiR8h/r5w4xs9pSQ/",
	"SvwY8ePEy0jfCeIfUfqPSX6K5KdJXk7yT4mfIf4Z8bMm7bGV2reI6ldE5dF5ie3qv8VwNd9m0f1p9PhTIl9UxfwHyEdPS/ys",
	"v/12zfCvOCa8ucP7O+TNTXxSyizqm2LPUb1iK2mXblUsZyx9o6e/yXfSzdqp9xV8d70q/XJzJc/tlPZoIaFbQqN9l4RYLa9q",
	"f8a94JPC3YZPlvDq8K0T/RuCvXyUv4l808W454wKtVqaaX/GveDNwh307ZTOcq+VAN9O85fvlf2er/a3Eb4d45J7Pn+Q87cC",
	"e2sfT4itofLXeapw/Eab+wrv6xxVTGe050wt7301VHs/qOFt2p9L+BwN79L+jHvXeZK+mZTTju1rcG0h2CXP2YBvMeotfJ/B",
	"bWqeWCnMh29D+otrtl7+QfgtQhv4QdbUxkdNqxdfX9Pq/W0riX+tpne/6/q/oG/ibdEuatfVAn3C+bnpwgspfoLxLTurd/wP",
	"ko/xjcx29ayWSO2P28FP0i8TPti4D5VwkGFfRL/+W1Czb6oZ6f5u9Y4v63qJb4Bp/dRQ+7G7/oe8OfEw4M2J6/JGwBuTPJx4",
	"Y0wv32LSy7nTVbVvBsVc4byJsnnXO3Os9be/3/27iWcLny1ltMpd9pp+FXhHzYqCp75rtWS8a/19Xbyd+F0aziWeR3wc8XuI",
	"5wsvNf4tk0u0jz5uT1K6S4Wuq1iHL/fbYPhcWCXpq0v9t1J7vkp8G7XvduLbqL23C5/pI9/twdf2G8t/dGi/Rt+Irmp9Mq7y",
	"29iTZH8TW0m6X6zKL++Myf7jVxpn56g9Anz4pRy3Xtm4z72C+up2+xV9odD9OOA8KRpwV8DhVvV+NmKA+ZnrNsA2OH+dAnhJ",
	"ovkZ7SHAT90C5/FOm+k57mDA6YAL8d7eTz27FXRmQppHAfeF9Ish/m/oFwBt8uJA83O4D+crPd9DvB3O2D6E8nSC+F6A8wEX",
	"Aq7VzvwMz9fZNp7t+cE5tzPJ3I8gPsn8XHwo4PGA7wU8vQr4pmqqfcbBOVYxpPkQ8KhAlf5ziP8G6wL3UU8BjgYcBzgL8NOA",
	"fwAcAmecSYBHAX7QB8az0hcAbwS8C3DtVPM7hzoQPxDiJ6SY31N9CeevB+HZc4CDIc0ciL8Z4qMAvwj4dE3VF99C/D8BO+Gs",
	"93rA4XgGDHhVbaXzLOAvIE19ODNuBrgU0oyG+C/bw50S4AA4b471gd+qp8rwBsSXDjP3EfgOcN366tlfId4Jd0FJcIYdDvH3",
	"3wpn1T7ukXYAfhTw6Rvg/AzursshPhficwBPA/wx4JOA20TD3R3ER8A5/W14Zg94JDz7QGNVnmkQvx7SbwT8ynBzf70Fzyg9",
	"FyA+ymMzxVa48wm/yxzvhfJsuVk9eyxN4ZGQPgfwKXj2CYh/G/AHgH8CfD/cY3TsAOtXB/P7w8NNVXn2Qnwc3Gn0SzO/G8H4",
	"KT7uSTYA/hvgdYBP+LhLQb/UELhXqQ/4TsAvAT4MOBHuYYJaqvreBvHnIX0WxD8A+DTgb0BPONzn7IY0qwG37gjjGdLfB3gZ",
	"4ELAYzqa3+WOAVwtUpXnFMT/CHdK8YDrdTK/Bw6A+NOQ7wLYeywEbIH7qKWgZw3cnxztXvm9VmPAwwEnAX4D7gfioZw/Q5pZ",
	"gAdlmd9vj71F6ZkL8WGAa2ZbTO8iukH8M4DPAl4Ffk/PtFd5HYf4ujFQd7i7ez5apR8M8f0hfT7EL/dxB7gN8KMdlc5AsOE/",
	"Q3x/8P3ZHqPiiyD+bcCZgGvDfWPsWHM/AryTzAY8CfAswA1vU2W4BeLbwB1mLuC2t5nfc+4F/G6s0vkT6MyFu9DhnWFsAN4D",
	"aTqMM787rQ94EZSnD8TfC7gQ8BrATeDdoSfcx46CO/ylEP9CdxUfkW9+Z5sIOKCXSj8D4hfis71VmppxCk+B+945gF+MVfhZ",
	"iN8Sa457w13xHRPM75BnoQ8p4PqdFb4R7pbb91PljIX4BRCP/s7LYf8QAvfMKweo+C2AeyQqfB7KENDF/L76O0j/LeB6AxVu",
	"C7gh3GmH+cB4B453oXMgvhfEL+qCfnYw3yeZ+/XjXfopeLZpis3UN+cJiN8NGP28Pgfcpqu5z04fwAMATxuidD4/1Bx/Celt",
	"3WBeDIP5C74A+wA3g/Qz4A65BPwFVkCaMxB/CrAF/Ahm36X0jIJ4K6yDeyHeBv5HPQHfAukjRiqdvQEPgTRHIX4K+DLEjlLx",
	"CyH+Zx/+DsfSVXpPBpzVQJpVED8O4u+CNfoIlG0DpLGDL1VgDygnxG+C96/nM5XOTYD/CnktbWu+P3cAfgp8InIg3/mQZg7g",
	"ZYA3wnvxSxgP+DXA5YBjcmymv0u4AXxJRgFeA9gD+DXAnz5g7neWBPHFgA8ALgPcfowqW85Y6DuIb9kT9r2Q13eAa4N/bvF4",
	"9Ww6xN+Up+LvBJ1pgF+CNCXjoGyQJtHH75kyAWcDXg34YcDVwX/n5Gxzv54IwDmAZwP+AMr2McRbwSf3J0gzAuJHAc6cqOr7",
	"AcSfANyuF8xfiN8GZ4BrJyk9oycr/Do8uxfwCh9+RuhblAz+iaumKZ0vQPxOwPXBF6kQcJvp6llHgML7Ic12wF8DPgHpD881",
	"93UqmaXS/APwY+AD9Q3gUPCHav2QSl8f4qPBT+oDwKXoPwX4J/idSq3HoL/mKP1z4Hc8C+PBB3khtptKXw5p3gD/rA1wfuIB",
	"n6yecG58/QI4t+kD/l+AP4Jnqz2m0m+ANIsgHn2+EDcH/MpClf4kxLftC+nBL/t5wLsAXwB8EJ6NfNJm6mvWBX4T8Avgg/1g",
	"nAPOBH/wgyuUzh8hjd9KFV/9aYXnA94Gvz9ISYDxAPEXAPuBb5obcG3AnQBbnrNZ/hu2aBcj",
]

static var _unstable_regex: RegEx = RegEx.create_from_string("[\\x{300}-\\x{10FFFF}]")
static var _loaded := false
static var _load_mutex: Mutex = Mutex.new()
static var _properties: Dictionary = {}
static var _decompositions: Dictionary = {}
static var _compositions: Dictionary = {}


static func nfc(text: String) -> String:
	var found := _unstable_regex.search(text)
	if found == null:
		return text
	_ensure_loaded()
	var start := found.get_start()
	var boundary := maxi(start - 1, 0)
	var last_class := 0
	for index in range(start, text.length()):
		var code := text.unicode_at(index)
		if code < 0x300:
			last_class = 0
			boundary = index
			continue
		var info: int = _properties.get(code, 0)
		var combining_class := info & _CLASS_MASK
		if (info & _QUICK_CHECK_MASK) != 0 or (combining_class != 0 and last_class > combining_class):
			return text.substr(0, boundary) + _normalize(text.substr(boundary))
		if (info & _NO_BOUNDARY) == 0:
			boundary = index
		last_class = combining_class
	return text


static func _normalize(text: String) -> String:
	var decomposed := PackedInt32Array()
	for code in text.to_utf32_buffer().to_int32_array():
		if code >= _S_BASE and code < _S_BASE + _S_COUNT:
			var s_index := code - _S_BASE
			decomposed.append(_L_BASE + s_index / _N_COUNT)
			decomposed.append(_V_BASE + (s_index % _N_COUNT) / _T_COUNT)
			if s_index % _T_COUNT != 0:
				decomposed.append(_T_BASE + s_index % _T_COUNT)
			continue
		var mapping: Variant = _decompositions.get(code)
		if mapping == null:
			decomposed.append(code)
		else:
			decomposed.append_array(mapping)

	var count := decomposed.size()
	var infos := PackedInt32Array()
	infos.resize(count)
	for index in count:
		infos[index] = _properties.get(decomposed[index], 0)

	for index in range(1, count):
		var info := infos[index]
		var combining_class := info & _CLASS_MASK
		if combining_class == 0 or (infos[index - 1] & _CLASS_MASK) <= combining_class:
			continue
		var code := decomposed[index]
		var target := index
		while target > 0 and (infos[target - 1] & _CLASS_MASK) > combining_class:
			infos[target] = infos[target - 1]
			decomposed[target] = decomposed[target - 1]
			target -= 1
		infos[target] = info
		decomposed[target] = code

	var starter := -1
	var last_class := 0
	var written := 0
	for index in count:
		var code := decomposed[index]
		var info := infos[index]
		var combining_class := info & _CLASS_MASK
		if starter >= 0 and (info & _QUICK_CHECK_MAYBE) != 0 and (last_class == 0 or last_class < combining_class):
			var composite := _compose(decomposed[starter], code)
			if composite >= 0:
				decomposed[starter] = composite
				continue
		if combining_class == 0:
			starter = written
		last_class = combining_class
		decomposed[written] = code
		written += 1
	decomposed.resize(written)
	return decomposed.to_byte_array().get_string_from_utf32()


static func _compose(first: int, second: int) -> int:
	if first >= _L_BASE and first < _L_BASE + _L_COUNT and second >= _V_BASE and second < _V_BASE + _V_COUNT:
		return _S_BASE + ((first - _L_BASE) * _V_COUNT + second - _V_BASE) * _T_COUNT
	if first >= _S_BASE and first < _S_BASE + _S_COUNT and (first - _S_BASE) % _T_COUNT == 0 and second > _T_BASE and second < _T_BASE + _T_COUNT:
		return first + second - _T_BASE
	return _compositions.get((first << 21) | second, -1)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_load_mutex.lock()
	if not _loaded:
		_load_tables()
		_loaded = true
	_load_mutex.unlock()


static func _load_tables() -> void:
	var bytes := Marshalls.base64_to_raw("".join(_TABLE)).decompress(_TABLE_SIZE, FileAccess.COMPRESSION_DEFLATE)
	if bytes.size() != _TABLE_SIZE:
		push_error("unicode normalization: the normalization table could not be read, so text will not be normalized")
		return
	var data := bytes.to_int32_array()
	var properties: Dictionary = {}
	var decompositions: Dictionary = {}
	var compositions: Dictionary = {}
	var raw: Dictionary = {}
	var code := 0
	var index := 1
	for entry in data[0]:
		code += data[index]
		var info := data[index + 1]
		index += 2
		var mapping_length := (info >> 10) & 3
		if mapping_length > 0:
			raw[code] = data.slice(index, index + mapping_length)
			if (info >> 12) & 1 == 1:
				compositions[(data[index] << 21) | data[index + 1]] = code
			index += mapping_length
		properties[code] = info & (_CLASS_MASK | _QUICK_CHECK_MASK)
	for mapped in raw:
		decompositions[mapped] = _expand(raw, mapped)
	for key in properties:
		var leading: int = decompositions[key][0] if decompositions.has(key) else key
		if (properties[key] & _CLASS_MASK) != 0 or (properties.get(leading, 0) & _CLASS_MASK) != 0:
			properties[key] |= _NO_BOUNDARY
	_properties = properties
	_decompositions = decompositions
	_compositions = compositions


static func _expand(raw: Dictionary, code: int) -> PackedInt32Array:
	if not raw.has(code):
		return PackedInt32Array([code])
	var result := PackedInt32Array()
	for part in raw[code]:
		result.append_array(_expand(raw, part))
	return result
