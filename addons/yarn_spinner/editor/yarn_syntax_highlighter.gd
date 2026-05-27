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

const MODE_HEADER := 0
const MODE_BODY := 1
const MODE_DELIM := 2

var _c: Dictionary = {}
var _rx: Dictionary = {}


func _clear_highlighting_cache() -> void:
	_c.clear()


func _get_line_syntax_highlighting(line: int) -> Dictionary:
	_ensure_regex()
	_ensure_colors()
	var te := get_text_edit()
	if te == null:
		return {}
	var text := te.get_line(line)
	var n := text.length()
	if n == 0:
		return {}

	var buf := PackedColorArray()
	buf.resize(n)
	buf.fill(_c.base)

	match _line_mode(line):
		MODE_DELIM:
			_paint(buf, 0, n, _c.delimiter)
		MODE_HEADER:
			_highlight_header(text, buf)
		_:
			_highlight_body(text, buf)

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

func _line_mode(line: int) -> int:
	var te := get_text_edit()
	var cur := te.get_line(line).strip_edges()
	if cur == "---" or cur == "===":
		return MODE_DELIM
	var i := line - 1
	while i >= 0:
		var s := te.get_line(i).strip_edges()
		if s == "---":
			return MODE_BODY
		if s == "===":
			return MODE_HEADER
		i -= 1
	return MODE_HEADER


# -------------------------------------------------------------------------- #
#  Header highlighting
# -------------------------------------------------------------------------- #

func _highlight_header(text: String, buf: PackedColorArray) -> void:
	var tm := _r(&"h_title").search(text)
	if tm:
		_paint(buf, tm.get_start(2), tm.get_end(2), _c.keyword)
		_paint(buf, tm.get_start(3), tm.get_end(3), _c.symbol)
		_paint(buf, tm.get_start(4), tm.get_end(4), _c.node)
		_overlay_comment(text, buf)
		return

	var wm := _r(&"h_when").search(text)
	if wm:
		_paint(buf, wm.get_start(2), wm.get_end(2), _c.control)
		_paint(buf, wm.get_start(3), wm.get_end(3), _c.symbol)
		_highlight_code(text, wm.get_end(3), text.length(), buf, false)
		_overlay_comment(text, buf)
		return

	var gm := _r(&"h_generic").search(text)
	if gm:
		var key := gm.get_string(2)
		var key_color: Color = _c.keyword if key == "tags" else _c.attribute
		_paint(buf, gm.get_start(2), gm.get_end(2), key_color)
		_paint(buf, gm.get_start(3), gm.get_end(3), _c.symbol)
		_paint(buf, gm.get_start(4), gm.get_end(4), _c.string)
	_overlay_comment(text, buf)


# -------------------------------------------------------------------------- #
#  Body highlighting
# -------------------------------------------------------------------------- #

func _highlight_body(text: String, buf: PackedColorArray) -> void:
	var n := text.length()
	var start := _first_non_space(text)
	var lead := text.substr(start, 2)

	if lead == "->" or lead == "=>":
		_paint(buf, start, start + 2, _c.symbol)
	elif lead != "<<" and not lead.begins_with("//"):
		_try_character_name(text, buf)

	var i := 0
	while i < n:
		if i > 0 and text[i - 1] == "\\":
			i += 1
			continue
		var two := text.substr(i, 2)
		var c := text[i]
		if two == "//":
			_paint(buf, i, n, _c.comment)
			break
		elif two == "<<":
			var e := text.find(">>", i + 2)
			var inner_end := e if e != -1 else n
			_paint(buf, i, i + 2, _c.symbol)
			if e != -1:
				_paint(buf, e, e + 2, _c.symbol)
			_highlight_code(text, i + 2, inner_end, buf, true)
			i = (e + 2) if e != -1 else n
		elif c == "{":
			var e := text.find("}", i + 1)
			var inner_end := e if e != -1 else n
			_paint(buf, i, i + 1, _c.symbol)
			if e != -1:
				_paint(buf, e, e + 1, _c.symbol)
			_highlight_code(text, i + 1, inner_end, buf, false)
			i = (e + 1) if e != -1 else n
		elif c == "[":
			i = _highlight_markup(text, i, buf)
		elif c == "#":
			var m := _r(&"tag").search(text, i)
			if m and m.get_start() == i:
				_paint(buf, i, m.get_end(), _c.tag)
				i = m.get_end()
			else:
				i += 1
		else:
			i += 1


func _try_character_name(text: String, buf: PackedColorArray) -> void:
	var m := _r(&"charname").search(text)
	if m and m.get_start(2) != -1:
		_paint(buf, m.get_start(1), m.get_end(1), _c.character)
		_paint(buf, m.get_start(2), m.get_end(2), _c.symbol)


func _highlight_markup(text: String, start: int, buf: PackedColorArray) -> int:
	var n := text.length()
	var e := text.find("]", start + 1)
	var inner_end := e if e != -1 else n
	_paint(buf, start, start + 1, _c.symbol)
	if e != -1:
		_paint(buf, e, e + 1, _c.symbol)

	var name_m := _r(&"markup_name").search(text, start + 1, inner_end)
	if name_m:
		_paint(buf, name_m.get_start(), name_m.get_end(), _c.markup)
	for am in _r(&"markup_attr").search_all(text, start + 1, inner_end):
		_paint(buf, am.get_start(1), am.get_end(1), _c.attribute)
		_paint(buf, am.get_start(2), am.get_end(2), _c.symbol)
		_paint(buf, am.get_start(3), am.get_end(3), _c.string)
	return (e + 1) if e != -1 else n


## Highlight an expression / command body in text[from, to).
## When command_mode is true, the command keywords and the catch-all command
## name rule (matching the grammar's command-content) are applied.
func _highlight_code(text: String, from: int, to: int, buf: PackedColorArray, command_mode: bool) -> void:
	if to <= from:
		return

	if command_mode:
		_apply(_r(&"word"), text, from, to, buf, _c.command)
		_apply(_r(&"kw_control"), text, from, to, buf, _c.control)
		_apply(_r(&"kw_decl"), text, from, to, buf, _c.keyword)
		_apply(_r(&"kw_type"), text, from, to, buf, _c.type)

	_apply(_r(&"kw_const"), text, from, to, buf, _c.constant)
	_apply(_r(&"kw_op"), text, from, to, buf, _c.control)

	if command_mode:
		for m in _r(&"jump").search_all(text, from, to):
			_paint(buf, m.get_start(1), m.get_end(1), _c.control)
			if m.get_start(2) != -1:
				_paint(buf, m.get_start(2), m.get_end(2), _c.node)

	for m in _r(&"enum_access").search_all(text, from, to):
		_paint(buf, m.get_start(1), m.get_end(1), _c.type)
		_paint(buf, m.get_start(3), m.get_end(3), _c.variable)
	for m in _r(&"variable").search_all(text, from, to):
		_paint(buf, m.get_start(), m.get_end(), _c.variable)
	for m in _r(&"func_call").search_all(text, from, to):
		_paint(buf, m.get_start(1), m.get_end(1), _c.function)

	_apply(_r(&"op"), text, from, to, buf, _c.symbol)
	_apply(_r(&"num"), text, from, to, buf, _c.number)

	for m in _r(&"string").search_all(text, from, to):
		_paint(buf, m.get_start(), m.get_end(), _c.string)


# -------------------------------------------------------------------------- #
#  Helpers
# -------------------------------------------------------------------------- #

func _overlay_comment(text: String, buf: PackedColorArray) -> void:
	var idx := text.find("//")
	if idx != -1:
		_paint(buf, idx, text.length(), _c.comment)


func _paint(buf: PackedColorArray, s: int, e: int, color: Color) -> void:
	if s < 0:
		s = 0
	if e > buf.size():
		e = buf.size()
	for k in range(s, e):
		buf[k] = color


func _apply(rx: RegEx, text: String, from: int, to: int, buf: PackedColorArray, color: Color, group: int = 0) -> void:
	for m in rx.search_all(text, from, to):
		var s := m.get_start(group)
		if s != -1:
			_paint(buf, s, m.get_end(group), color)


func _first_non_space(t: String) -> int:
	var i := 0
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
func _r(key: StringName) -> RegEx:
	return _rx[key]


func _ensure_regex() -> void:
	if not _rx.is_empty():
		return
	_rx = {
		"h_title": _mk("^(\\s*)(title)(\\s*:\\s*)(.*)$"),
		"h_when": _mk("^(\\s*)(when)(\\s*:\\s*)"),
		"h_generic": _mk("^(\\s*)([A-Za-z_][A-Za-z0-9_]*)(\\s*:\\s*)(.*)$"),
		"charname": _mk("^(?!\\s*//)\\s*((?:[^:\\\\]|\\\\.)*)(?<!\\\\)(:)(?=\\s)"),
		"tag": _mk("#[^ \\t\\r\\n#$<]+"),
		"markup_name": _mk("/?[A-Za-z_][A-Za-z0-9_]*"),
		"markup_attr": _mk("([A-Za-z_][A-Za-z0-9_]*)(=)(\"[^\"]*\"|[^\\s\\]]+)"),
		"word": _mk("\\b[A-Za-z_][A-Za-z0-9_]*\\b"),
		"kw_control": _mk("\\b(if|else|elseif|endif|once|endonce|return|stop|wait)\\b"),
		"kw_decl": _mk("\\b(declare|set|local|enum|endenum|case|call|detour|jump)\\b"),
		"kw_type": _mk("\\b(string|number|bool)\\b"),
		"kw_const": _mk("\\b(true|false|null)\\b"),
		"kw_op": _mk("\\b(and|or|not|xor|is|eq|neq|gt|gte|lt|lte|to|as)\\b"),
		"jump": _mk("\\b(jump|detour)\\s+([A-Za-z_][A-Za-z0-9_.]*)"),
		"enum_access": _mk("\\b([A-Z][A-Za-z0-9_]*)(\\.)([A-Za-z_][A-Za-z0-9_]*)"),
		"variable": _mk("\\$[A-Za-z_][A-Za-z0-9_]*"),
		"func_call": _mk("\\b([A-Za-z_][A-Za-z0-9_]*)\\s*\\("),
		"num": _mk("(?<![\\w.])-?\\d+(\\.\\d+)?"),
		"op": _mk("==|!=|<=|>=|\\+=|-=|\\*=|/=|%=|<|>|=|\\+|-|\\*|/|%|!"),
		"string": _mk("\"(?:\\\\.|[^\"\\\\])*\"?"),
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
