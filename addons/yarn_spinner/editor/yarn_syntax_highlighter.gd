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

@tool
extends SyntaxHighlighter
## Context-aware syntax highlighter for .yarn source, modelled on the official
## Yarn Spinner TextMate grammar (YarnSpinner-VSCode-Neue). Unlike Godot's
## CodeHighlighter it understands node header vs body context, highlights jump
## targets, character names, variables, inline expressions and markup tags.

const STATE_PREAMBLE := 0
const STATE_HEADER := 1
const STATE_BODY := 2

const _ID_HEAD := "a-zA-Z_\\x{00A8}\\x{00AA}\\x{00AD}\\x{00AF}\\x{00B2}-\\x{00B5}\\x{00B7}-\\x{00BA}" \
	+ "\\x{00BC}-\\x{00BE}\\x{00C0}-\\x{00D6}\\x{00D8}-\\x{00F6}\\x{00F8}-\\x{00FF}" \
	+ "\\x{0100}-\\x{02FF}\\x{0370}-\\x{167F}\\x{1681}-\\x{180D}\\x{180F}-\\x{1DBF}" \
	+ "\\x{1E00}-\\x{1FFF}" \
	+ "\\x{200B}-\\x{200D}\\x{202A}-\\x{202E}\\x{203F}-\\x{2040}\\x{2054}\\x{2060}-\\x{206F}" \
	+ "\\x{2070}-\\x{20CF}\\x{2100}-\\x{218F}\\x{2460}-\\x{24FF}\\x{2776}-\\x{2793}" \
	+ "\\x{2C00}-\\x{2DFF}\\x{2E80}-\\x{2FFF}" \
	+ "\\x{3004}-\\x{3007}\\x{3021}-\\x{302F}\\x{3031}-\\x{303F}\\x{3040}-\\x{D7FF}" \
	+ "\\x{F900}-\\x{FD3D}\\x{FD40}-\\x{FDCF}\\x{FDF0}-\\x{FE1F}\\x{FE30}-\\x{FE44}" \
	+ "\\x{FE47}-\\x{FFFD}" \
	+ "\\x{10000}-\\x{1FFFD}\\x{20000}-\\x{2FFFD}\\x{30000}-\\x{3FFFD}\\x{40000}-\\x{4FFFD}" \
	+ "\\x{50000}-\\x{5FFFD}\\x{60000}-\\x{6FFFD}\\x{70000}-\\x{7FFFD}\\x{80000}-\\x{8FFFD}" \
	+ "\\x{90000}-\\x{9FFFD}\\x{A0000}-\\x{AFFFD}\\x{B0000}-\\x{BFFFD}\\x{C0000}-\\x{CFFFD}" \
	+ "\\x{D0000}-\\x{DFFFD}\\x{E0000}-\\x{EFFFD}"
const _ID_TAIL := "0-9\\x{0300}-\\x{036F}\\x{1DC0}-\\x{1DFF}\\x{20D0}-\\x{20FF}\\x{FE20}-\\x{FE2F}"
const _ID := "[" + _ID_HEAD + "][" + _ID_HEAD + _ID_TAIL + "]*"

const _CONTROL_KEYWORDS := ["if", "elseif", "else", "endif", "once", "endonce", "return", "jump", "detour"]
const _DECL_KEYWORDS := ["set", "call", "declare", "enum", "case", "endenum", "local"]
const _EXPRESSION_COMMAND_KEYWORDS := ["if", "elseif", "set", "call", "declare", "case"]
const _WHEN_KEYWORDS := ["always", "once", "if"]
const _WORD_OPERATORS := ["to", "lte", "gte", "is", "eq", "lt", "gt", "neq", "and", "or", "xor", "not", "as"]
const _TYPE_NAMES := ["string", "number", "bool"]

var _c: Dictionary = {}
var _rx: Dictionary = {}
var _line_end_states := PackedInt32Array()
var _connected_edit: TextEdit


func _clear_highlighting_cache() -> void:
	_c.clear()
	_line_end_states.clear()


func _update_cache() -> void:
	var te := get_text_edit()
	if _connected_edit == te:
		return
	if is_instance_valid(_connected_edit) and _connected_edit.lines_edited_from.is_connected(_on_lines_edited_from):
		_connected_edit.lines_edited_from.disconnect(_on_lines_edited_from)
	_connected_edit = te
	if te != null and not te.lines_edited_from.is_connected(_on_lines_edited_from):
		te.lines_edited_from.connect(_on_lines_edited_from)


func _on_lines_edited_from(from_line: int, to_line: int) -> void:
	var keep := maxi(mini(from_line, to_line) - 1, 0)
	if _line_end_states.size() > keep:
		_line_end_states.resize(keep)


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	_ensure_regex()
	_ensure_colors()
	var te := get_text_edit()
	if te == null:
		return {}
	var state := _state_before(line)
	var text := te.get_line(line)
	if _line_end_states.size() == line:
		_line_end_states.append(_next_state(text, state))
	var n := text.length()
	if n == 0:
		return {}

	var buf := PackedColorArray()
	buf.resize(n)
	buf.fill(_c.base)

	var start := _first_non_space(text)
	if state == STATE_BODY:
		if text.substr(start, 3) == "===":
			_paint(buf, start, start + 3, _c.delimiter)
			_overlay_comment(text, start + 3, buf)
		else:
			_highlight_body(text, start, buf)
	elif text.substr(start, 3) == "---":
		_paint(buf, start, start + 3, _c.delimiter)
		_overlay_comment(text, start + 3, buf)
	elif state == STATE_PREAMBLE and text.substr(start, 1) == "#":
		_scan_trailer(text, start, buf, false)
	else:
		_highlight_header(text, buf)

	# Convert the per-character colour buffer into Godot's column->color map.
	var result := {0: {"color": buf[0]}}
	var prev: Color = buf[0]
	for col in range(1, n):
		if buf[col] != prev:
			result[col] = {"color": buf[col]}
			prev = buf[col]
	return result


# -------------------------------------------------------------------------- #
#  Context detection
# -------------------------------------------------------------------------- #

func _state_before(line: int) -> int:
	if line <= 0:
		return STATE_PREAMBLE
	var computed := _line_end_states.size()
	if computed < line:
		var te := get_text_edit()
		var state := _line_end_states[computed - 1] if computed > 0 else STATE_PREAMBLE
		_line_end_states.resize(line)
		for i in range(computed, line):
			state = _next_state(te.get_line(i), state)
			_line_end_states[i] = state
	return _line_end_states[line - 1]


func _next_state(text: String, state: int) -> int:
	var stripped := text.strip_edges()
	if state == STATE_BODY:
		return STATE_HEADER if stripped.begins_with("===") else STATE_BODY
	if stripped.begins_with("---"):
		return STATE_BODY
	if state == STATE_PREAMBLE and (stripped.is_empty() or stripped.begins_with("#") or stripped.begins_with("//")):
		return STATE_PREAMBLE
	return STATE_HEADER


# -------------------------------------------------------------------------- #
#  Header highlighting
# -------------------------------------------------------------------------- #

func _highlight_header(text: String, buf: PackedColorArray) -> void:
	var hm := _r("header").search(text)
	if hm == null:
		_overlay_comment(text, 0, buf)
		return

	var key := hm.get_string(1)
	var value_start := hm.get_end(2)
	_paint(buf, hm.get_start(2), value_start, _c.symbol)

	if key == "title":
		_paint(buf, hm.get_start(1), hm.get_end(1), _c.keyword)
		var tm := _r("id").search(text, value_start)
		var after := value_start
		if tm:
			_paint(buf, tm.get_start(), tm.get_end(), _c.node)
			after = tm.get_end()
		_overlay_comment(text, after, buf)
	elif key == "when":
		_paint(buf, hm.get_start(1), hm.get_end(1), _c.control)
		var end := _scan_expression(text, value_start, buf, true)
		_overlay_comment(text, end, buf)
	else:
		_paint(buf, hm.get_start(1), hm.get_end(1), _c.keyword if key == "tags" else _c.attribute)
		var comment := text.find("//", value_start)
		var value_end := comment if comment != -1 else text.length()
		_paint(buf, value_start, value_end, _c.string)
		_overlay_comment(text, value_end, buf)


# -------------------------------------------------------------------------- #
#  Body highlighting
# -------------------------------------------------------------------------- #

func _highlight_body(text: String, start: int, buf: PackedColorArray) -> void:
	var n := text.length()
	var i := start
	while i < n:
		var c := text[i]
		var two := text.substr(i, 2)
		if c == " " or c == "\t":
			i += 1
		elif two == "//":
			_paint(buf, i, n, _c.comment)
			return
		elif two == "->" or two == "=>":
			_paint(buf, i, i + 2, _c.symbol)
			i += 2
		elif two == "<<":
			i = _scan_command(text, i, buf)
		elif c == "#":
			_scan_trailer(text, i, buf, true)
			return
		else:
			_scan_text(text, i, buf)
			return


func _scan_text(text: String, start: int, buf: PackedColorArray) -> void:
	var n := text.length()
	var cm := _r("charname").search(text, start)
	if cm and not cm.get_string(1).strip_edges().is_empty():
		_paint(buf, cm.get_start(1), cm.get_end(1), _c.character)
		_paint(buf, cm.get_start(2), cm.get_end(2), _c.symbol)

	var i := start
	while i < n:
		var c := text[i]
		var two := text.substr(i, 2)
		if c == "\\":
			i += 2
		elif c == "{":
			i = _scan_braced_expression(text, i, buf)
		elif c == "#":
			_scan_trailer(text, i, buf, true)
			return
		elif two == "<<":
			_scan_trailer(text, _scan_command(text, i, buf), buf, true)
			return
		elif two == "//":
			_paint(buf, i, n, _c.comment)
			return
		elif c == "[":
			i = _scan_markup(text, i, buf)
		else:
			i += 1


func _scan_trailer(text: String, start: int, buf: PackedColorArray, allow_commands: bool) -> void:
	var n := text.length()
	var i := start
	while i < n:
		var c := text[i]
		var two := text.substr(i, 2)
		if two == "//":
			_paint(buf, i, n, _c.comment)
			return
		elif c == "#":
			i = _scan_hashtag(text, i, buf)
		elif allow_commands and two == "<<":
			i = _scan_command(text, i, buf)
		else:
			i += 1


func _scan_hashtag(text: String, start: int, buf: PackedColorArray) -> int:
	var n := text.length()
	var i := start + 1
	while i < n and (text[i] == " " or text[i] == "\t" or text[i] == "#"):
		i += 1
	var m := _r("hashtag_text").search(text, i)
	if m:
		i = m.get_end()
	_paint(buf, start, i, _c.tag)
	return i


func _scan_markup(text: String, start: int, buf: PackedColorArray) -> int:
	var n := text.length()
	_paint(buf, start, start + 1, _c.symbol)
	var i := start + 1
	var has_name := false
	var in_value := false
	while i < n:
		var c := text[i]
		var two := text.substr(i, 2)
		if c == "#" or two == "<<" or two == "//":
			return i
		elif c == "\\":
			i += 2
		elif c == "{":
			i = _scan_braced_expression(text, i, buf)
			has_name = true
			in_value = false
		elif c == "]":
			_paint(buf, i, i + 1, _c.symbol)
			return i + 1
		elif c == " " or c == "\t":
			i += 1
		elif c == "/" or c == "=":
			_paint(buf, i, i + 1, _c.symbol)
			in_value = c == "="
			i += 1
		elif in_value:
			in_value = false
			has_name = true
			if c == "\"":
				i = _scan_markup_string(text, i, buf)
			else:
				var vm := _r("markup_value").search(text, i)
				if vm == null:
					return i
				var value := vm.get_string()
				var color: Color = _c.string
				if c == "-" or c.is_valid_int():
					color = _c.number
				elif value == "true" or value == "false":
					color = _c.constant
				_paint(buf, i, vm.get_end(), color)
				i = vm.get_end()
		else:
			var im := _r("markup_ident").search(text, i)
			if im == null:
				return i
			_paint(buf, i, im.get_end(), _c.attribute if has_name else _c.markup)
			has_name = true
			i = im.get_end()
	return n


func _scan_markup_string(text: String, start: int, buf: PackedColorArray) -> int:
	var n := text.length()
	_paint(buf, start, start + 1, _c.string)
	var i := start + 1
	while i < n:
		var c := text[i]
		var two := text.substr(i, 2)
		if c == "\"":
			_paint(buf, i, i + 1, _c.string)
			return i + 1
		elif c == "{":
			i = _scan_braced_expression(text, i, buf)
		elif c == "#" or two == "<<" or two == "//":
			return i
		elif c == "\\":
			_paint(buf, i, i + 2, _c.string)
			i += 2
		else:
			_paint(buf, i, i + 1, _c.string)
			i += 1
	return n


func _scan_command(text: String, start: int, buf: PackedColorArray) -> int:
	var n := text.length()
	_paint(buf, start, start + 2, _c.symbol)
	var i := start + 2
	while i < n:
		var c := text[i]
		if c == " " or c == "\t":
			i += 1
			continue
		if text.substr(i, 2) == ">>":
			_paint(buf, i, i + 2, _c.symbol)
			return i + 2
		if c == "{":
			return _scan_command_text(text, _scan_braced_expression(text, i, buf), buf, false)
		var wm := _r("id").search(text, i)
		if wm == null or not _is_end_of_command_keyword(text, wm.get_end()):
			return _scan_command_text(text, i, buf, true)
		var word := wm.get_string()
		if word in _CONTROL_KEYWORDS:
			_paint(buf, i, wm.get_end(), _c.control)
		elif word in _DECL_KEYWORDS:
			_paint(buf, i, wm.get_end(), _c.keyword)
		else:
			return _scan_command_text(text, i, buf, true)
		i = wm.get_end()
		if word in _EXPRESSION_COMMAND_KEYWORDS:
			i = _scan_expression(text, i, buf, false)
			if i < n and text[i] == "}":
				_paint(buf, i, i + 1, _c.symbol)
				i += 1
		elif word == "jump" or word == "detour" or word == "enum":
			i = _first_non_space(text, i)
			var target := _r("id").search(text, i)
			if target:
				_paint(buf, i, target.get_end(), _c.type if word == "enum" else _c.node)
				i = target.get_end()
			elif word != "enum" and i < n and text[i] == "{":
				i = _scan_braced_expression(text, i, buf)
	return n


func _scan_command_text(text: String, start: int, buf: PackedColorArray, with_name: bool) -> int:
	var n := text.length()
	var i := start
	if with_name:
		var nm := _r("command_name").search(text, i)
		if nm:
			_paint(buf, i, nm.get_end(), _c.command)
			i = nm.get_end()
	var segment := i
	while i < n:
		if text.substr(i, 2) == ">>":
			_paint_command_args(text, segment, i, buf)
			_paint(buf, i, i + 2, _c.symbol)
			return i + 2
		if text[i] == "{":
			_paint_command_args(text, segment, i, buf)
			i = _scan_braced_expression(text, i, buf)
			segment = i
		else:
			i += 1
	_paint_command_args(text, segment, n, buf)
	return n


func _paint_command_args(text: String, from: int, to: int, buf: PackedColorArray) -> void:
	if to <= from:
		return
	for m in _r("args_number").search_all(text, from, to):
		_paint(buf, m.get_start(), m.get_end(), _c.number)
	for m in _r("args_string").search_all(text, from, to):
		_paint(buf, m.get_start(), m.get_end(), _c.string)


func _scan_braced_expression(text: String, start: int, buf: PackedColorArray) -> int:
	_paint(buf, start, start + 1, _c.symbol)
	var end := _scan_expression(text, start + 1, buf, false)
	if end < text.length() and text[end] == "}":
		_paint(buf, end, end + 1, _c.symbol)
		return end + 1
	return end


func _scan_expression(text: String, start: int, buf: PackedColorArray, when_clause: bool) -> int:
	var n := text.length()
	var i := start
	var after_dot := false
	while i < n:
		var c := text[i]
		var two := text.substr(i, 2)
		if c == " " or c == "\t":
			i += 1
			continue
		if c == "}" or two == ">>" or (when_clause and two == "//"):
			return i
		var was_dot := after_dot
		after_dot = false
		if c == "\"":
			var sm := _r("string").search(text, i)
			_paint(buf, i, sm.get_end(), _c.string)
			i = sm.get_end()
		elif c == "$":
			var vm := _r("variable").search(text, i)
			var var_end := vm.get_end() if vm else i + 1
			_paint(buf, i, var_end, _c.variable)
			i = var_end
		elif c == ".":
			_paint(buf, i, i + 1, _c.symbol)
			after_dot = true
			i += 1
		elif c.is_valid_int():
			var num := _r("number").search(text, i)
			_paint(buf, i, num.get_end(), _c.number)
			i = num.get_end()
		else:
			var wm := _r("id").search(text, i)
			if wm:
				var word := wm.get_string()
				var end := wm.get_end()
				var next := text.substr(_first_non_space(text, end), 1)
				var color: Color = _c.base
				if when_clause and word in _WHEN_KEYWORDS:
					color = _c.control
				elif word == "true" or word == "false":
					color = _c.constant
				elif word in _WORD_OPERATORS:
					color = _c.control
				elif word in _TYPE_NAMES:
					color = _c.type
				elif word == "null":
					color = _c.base
				elif was_dot:
					color = _c.variable
				elif next == "(":
					color = _c.function
				elif next == ".":
					color = _c.type
				_paint(buf, i, end, color)
				i = end
			else:
				var om := _r("op").search(text, i)
				if om:
					_paint(buf, i, om.get_end(), _c.symbol)
					i = om.get_end()
				else:
					i += 1
	return n


func _is_end_of_command_keyword(text: String, pos: int) -> bool:
	if pos >= text.length():
		return true
	var c := text[pos]
	return c == ">" or c.strip_edges().is_empty()


# -------------------------------------------------------------------------- #
#  Helpers
# -------------------------------------------------------------------------- #

func _overlay_comment(text: String, from: int, buf: PackedColorArray) -> void:
	var idx := text.find("//", from)
	if idx != -1:
		_paint(buf, idx, text.length(), _c.comment)


func _paint(buf: PackedColorArray, s: int, e: int, color: Color) -> void:
	if s < 0:
		s = 0
	if e > buf.size():
		e = buf.size()
	for k in range(s, e):
		buf[k] = color


func _first_non_space(t: String, from: int = 0) -> int:
	var i := from
	while i < t.length() and (t[i] == " " or t[i] == "\t"):
		i += 1
	return i


# -------------------------------------------------------------------------- #
#  Regex + colour setup
# -------------------------------------------------------------------------- #

func _mk(pattern: String) -> RegEx:
	var r := RegEx.new()
	r.compile(pattern)
	return r


## Typed accessor for the compiled-regex dictionary, so callers get RegEx (and
## thus RegExMatch from search) instead of Variant.
func _r(key: String) -> RegEx:
	return _rx[key]


func _ensure_regex() -> void:
	if not _rx.is_empty():
		return
	_rx = {
		"id": _mk("\\G" + _ID),
		"header": _mk("^[ \\t]*(" + _ID + ")([ \\t]*:[ \\t]*)"),
		"charname": _mk("\\G((?:[^:\\\\#</]|\\\\.|<(?!<)|/(?!/))*)(:)"),
		"hashtag_text": _mk("\\G[^ \\t\\r\\n#$<]+"),
		"markup_ident": _mk("\\G[\\p{L}\\p{N}_|]+"),
		"markup_value": _mk("\\G[^\\s\\]{}#<\\\\/=\"]+"),
		"command_name": _mk("\\G[^\\s>{]+"),
		"args_number": _mk("(?<![\\w.])-?\\d+(?:\\.\\d+)?"),
		"args_string": _mk("\"(?:\\\\.|[^\"\\\\])*\"?"),
		"variable": _mk("\\G\\$" + _ID),
		"number": _mk("\\G[0-9]+(?:\\.[0-9]+)?"),
		"op": _mk("\\G(?:==|!=|<=|>=|\\+=|-=|\\*=|/=|%=|&&|\\|\\||[<>=+\\-*/%!^])"),
		"string": _mk("\\G\"(?:\\\\.|[^\"\\\\])*\"?"),
	}


func _ensure_colors() -> void:
	if not _c.is_empty():
		return
	_c = {
		"base": _setting("text_color", Color("cdcfd2")),
		"comment": _setting("comment_color", Color("676767")),
		"keyword": _setting("keyword_color", Color("ff7085")),
		"control": _setting("control_flow_keyword_color", Color("ff8ccc")),
		"string": _setting("string_color", Color("ffeda1")),
		"number": _setting("number_color", Color("a1ffe0")),
		"constant": _setting("number_color", Color("a1ffe0")),
		"symbol": _setting("symbol_color", Color("abc1c2")),
		"function": _setting("function_color", Color("57b3ff")),
		"variable": _setting("member_variable_color", Color("bce0ff")),
		"type": _setting("base_type_color", Color("8effda")),
		"node": _setting("user_type_color", Color("c7ffed")),
		"character": _setting("engine_type_color", Color("8fffdb")),
		"attribute": _setting("member_variable_color", Color("bce0ff")),
		"markup": _setting("user_type_color", Color("c7ffed")),
		"tag": _setting("comment_color", Color("676767")),
		"delimiter": _setting("control_flow_keyword_color", Color("ff8ccc")),
		"command": _setting("control_flow_keyword_color", Color("ff8ccc")),
	}


func _setting(key: String, fallback: Color) -> Color:
	var settings := EditorInterface.get_editor_settings()
	var path := "text_editor/theme/highlighting/" + key
	if settings and settings.has_setting(path):
		return settings.get_setting(path)
	return fallback
