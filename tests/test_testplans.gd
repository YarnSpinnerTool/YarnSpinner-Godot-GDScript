extends GutTest
## Runs Yarn Spinner test plans against this runtime.
##
## A test plan is a transcript and it lists, in order, every line, option,
## command and stop that a compiled Yarn program is expected to produce! Plus
## the actions a player would take (selecting an option, setting a variable,
## jumping to a node, changing the saliency strategy). If thte VM produces
## exactly that transcript,it is behaving.
##
## This file is the GDScript counterpart of three pieces of teh C# test suite:
##   * TestPlan.cs parses the .testplan language (ANTLR grammar,
##     YarnSpinner.Tests/TestPlan/YarnSpinnerTestPlan.g4).
##   * TestBase.RunStandardTestcase drives the dialogue checks each step.
##     TestPlanRunner (at the bottom of this file) mirrors it.
##   * LanguageTests.TestSources decides which files run, and registers the
##     functions the test scripts call.
##
## Each case needs four fixture files in tests/testplans/ ...
##   <Case>.yarnc          the the compiled program
##   <Case>-Lines.csv      the string table (id, text, file, node, lineNumber)
##   <Case>-Metadata.csv   line tags (id, node, lineNumber, tags)
##   <Case>.testplan       the transcript
##
## To run this file on its own, copy the project to a scratch directory, add
## GUT, and run it headless with -gdir=res://tests -gprefix=test_.


## The fixture files for each case
const FIXTURE_DIR := "res://tests/testplans/"

## Node every plan starts from unless it says otherwise with `start:`..
const START_NODE := "Start"

## Locale used when composing line text, so [plural] and [ordinal] resolve the
## way the C# tests expect...
const LOCALE_CODE := "en"

const _YarnProgramParser := preload("res://addons/yarn_spinner/core/yarn_program_parser.gd")

const CASES := [
	"Commands",
	"DecimalNumbers",
	"Detours",
	"Detours-MayDetourToThemselves",
	"Enums",
	"Enums-FunctionsAcceptingStringMayAcceptAnyStringEnum",
	"Enums-FunctionsReturningStringMayBeComparedToAnyStringEnum",
	"Escaping",
	"Expressions",
	"FormatFunctions",
	"Functions",
	"IfStatements",
	"Indentation",
	"Inference-FunctionsAndVarsInheritType",
	"Inference-FunctionsCalledWithConvertibleParameters",
	"InlineExpressions",
	"Jumps",
	"LineGroups",
	"Lines",
	"NodeGroups",
	"NodeGroupsContentQuerying",
	"NodeGroupsWithImplicitDeclarations",
	"NodeGroupVisitTracking",
	"Once",
	"ShadowLines",
	"ShortcutOptions",
	"SmartVariables",
	"Smileys",
	"Types",
	"VariableStorage",
	"VeryLargeFileOfVariables",
	"VisitCount",
	"Visited",
	"VisitTracking",
]

const SKIPPED_CASES := {
	"DuplicateLineTags": "teh C# version only checks that it fails to compile, so no .testplan",
	"ParseFailures": "TestCases/ParseFailures/*.yarn have no .testplan, C# only checks that they fail to compile",
	"Duplicates": "TestCases/Duplicates/*.yarn are not TestSources inputs (FileSources is not recursive)... ProjectTests uses them for duplicate line ID checks",}

## COMMENT and WHITESPACE are recognised so they can be skipped..
enum Token {
	END_OF_FILE,
	SEPARATOR,
	ENVIRONMENT,
	START,
	LINE,
	STAR,
	OPTION,
	DISABLED,
	COMMAND,
	STOP,
	SELECT,
	SET,
	EQUALS,
	SALIENCY,
	NODE,
	COMMENT,
	WHITESPACE,
	BOOL,
	IDENTIFIER,
	HASHTAG,
	VARIABLE,
	NUMBER,
	TEXT,
}

## Fixed strings innn the grammar...
const LITERAL_TOKENS := [
	["---", Token.SEPARATOR],
	["environment:", Token.ENVIRONMENT],
	["start:", Token.START],
	["line:", Token.LINE],
	["*", Token.STAR],
	["option:", Token.OPTION],
	["[disabled]", Token.DISABLED],
	["command:", Token.COMMAND],
	["stop", Token.STOP],
	["select:", Token.SELECT],
	["set:", Token.SET],
	["=", Token.EQUALS],
	["saliency:", Token.SALIENCY],
	["node:", Token.NODE],
]

## Tokens that can begin a step...
const STEP_START_TOKENS := [
	Token.LINE,
	Token.OPTION,
	Token.COMMAND,
	Token.STOP,
	Token.SELECT,
	Token.SET,
	Token.SALIENCY,
	Token.NODE,
]

## Lexer output and read position
var _tokens: Array[Dictionary] = []
var _token_index: int = 0


## One test per case...
func test_testplan(case_name: String = use_parameters(CASES)) -> void:
	var fixture := _load_fixture(case_name)
	var fixture_error: String = fixture.error
	if not fixture_error.is_empty():
		fail_test("[%s] %s" % [case_name, fixture_error])
		return

	var plan := _parse_test_plan(fixture.testplan)
	var plan_error: String = plan.error
	if not plan_error.is_empty():
		fail_test("[%s] syntax errors in test plan: %s" % [case_name, plan_error])
		return

	var program: YarnProgram = _YarnProgramParser.parse_from_bytes(fixture.program_bytes)
	if program == null or program.nodes.is_empty():
		fail_test("[%s] compiled program could not be parsed" % case_name)
		return
	# The compiler emits the text and tags beside the program rather than
	# inside it so CSVs are attached here..
	program.string_table = fixture.string_table
	program.line_metadata = fixture.line_metadata

	# Some cases exist only to prove they compile (their plan is just `stop`,
	# and they have no Start node to run)...
	if not program.has_node(START_NODE):
		pass_test("[%s] no %s node; compilation only" % [case_name, START_NODE])
		return

	var storage: YarnInMemoryVariableStorage = autofree(YarnInMemoryVariableStorage.new())
	var runner := TestPlanRunner.new(program, storage, LOCALE_CODE)
	var runs: Array = plan.runs
	var failure := runner.run(runs)
	if failure.is_empty():
		pass_test("[%s] %d run(s) matched the test plan" % [case_name, runs.size()])
	else:
		fail_test("[%s] %s" % [case_name, failure])


## Reports each skipped case as pending! Use the reason from
## SKIPPED_CASES.
func test_testplan_skipped(case_name: String = use_parameters(SKIPPED_CASES.keys())) -> void:
	pending("[%s] skipped: %s" % [case_name, SKIPPED_CASES[case_name]])

func _load_fixture(case_name: String) -> Dictionary:
	var base_path := FIXTURE_DIR.path_join(case_name)
	var program_path := base_path + ".yarnc"
	var testplan_path := base_path + ".testplan"
	var lines_path := base_path + "-Lines.csv"
	var metadata_path := base_path + "-Metadata.csv"

	for path in [program_path, testplan_path, lines_path, metadata_path]:
		if not FileAccess.file_exists(path):
			return {"error": "missing fixture %s" % path}

	var program_bytes := FileAccess.get_file_as_bytes(program_path)
	if program_bytes.is_empty():
		return {"error": "empty compiled program %s" % program_path}

	return {
		"error": "",
		"program_bytes": program_bytes,
		"testplan": FileAccess.get_file_as_string(testplan_path),
		"string_table": _read_string_table(lines_path),
		"line_metadata": _read_line_metadata(metadata_path),
	}

func _read_string_table(path: String) -> Dictionary:
	var string_table := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return string_table
	file.get_csv_line()
	while not file.eof_reached():
		var csv_line := file.get_csv_line()
		if csv_line.size() >= 2:
			var line_id := csv_line[0]
			if not line_id.is_empty():
				string_table[line_id] = csv_line[1]
	file.close()
	return string_table

func _read_line_metadata(path: String) -> Dictionary:
	var line_metadata := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return line_metadata
	file.get_csv_line()
	while not file.eof_reached():
		var csv_line := file.get_csv_line()
		if csv_line.size() >= 4:
			var line_id := csv_line[0]
			var tags := csv_line[3]
			if not line_id.is_empty() and not tags.is_empty():
				line_metadata[line_id] = PackedStringArray(tags.split(" "))
	file.close()
	return line_metadata

func _tokenize(source: String) -> Dictionary:
	var tokens: Array[Dictionary] = []
	var position := 0
	var length := source.length()
	while position < length:
		var best_length := 0
		var best_type := -1
		for literal in LITERAL_TOKENS:
			var literal_text: String = literal[0]
			if literal_text.length() > best_length and source.substr(position, literal_text.length()) == literal_text:
				best_length = literal_text.length()
				best_type = int(literal[1])
		# Order matters: BOOL before IDENTIFIER so `true` lexes as a boolean,
		# and HASHTAG after IDENTIFIER because both can follow a `#`.
		var rule_matches := [
			[_match_comment(source, position), Token.COMMENT],
			[_match_whitespace(source, position), Token.WHITESPACE],
			[_match_bool(source, position), Token.BOOL],
			[_match_identifier(source, position), Token.IDENTIFIER],
			[_match_hashtag(source, position), Token.HASHTAG],
			[_match_variable(source, position), Token.VARIABLE],
			[_match_number(source, position), Token.NUMBER],
			[_match_text(source, position), Token.TEXT],
		]
		for rule_match in rule_matches:
			var match_length: int = rule_match[0]
			if match_length > best_length:
				best_length = match_length
				best_type = int(rule_match[1])
		if best_length == 0:
			return {"tokens": tokens, "error": "token recognition error at offset %d: '%s'" % [position, source.substr(position, 20)]}
		if best_type != Token.COMMENT and best_type != Token.WHITESPACE:
			tokens.append({"type": best_type, "text": source.substr(position, best_length)})
		position += best_length
	tokens.append({"type": Token.END_OF_FILE, "text": "<EOF>"})
	return {"tokens": tokens, "error": ""}

func _match_comment(source: String, position: int) -> int:
	if source.substr(position, 2) != "//":
		return 0
	var index := position + 2
	while index < source.length():
		var code := source.unicode_at(index)
		if code == 10 or code == 13:
			break
		index += 1
	return index - position


## WS: spaces, tabs, carriage returns and newlines.
func _match_whitespace(source: String, position: int) -> int:
	var index := position
	while index < source.length():
		var code := source.unicode_at(index)
		if code != 32 and code != 9 and code != 10 and code != 13:
			break
		index += 1
	return index - position


## BOOL: the words `true` and `false`, used by `set:`.
func _match_bool(source: String, position: int) -> int:
	if source.substr(position, 4) == "true":
		return 4
	if source.substr(position, 5) == "false":
		return 5
	return 0


## IDENTIFIER: a letter or underscore, then letters, digits or underscores.
## Used for node names, environment names and saliency modes.
func _match_identifier(source: String, position: int) -> int:
	if position >= source.length() or not _is_identifier_start(source.unicode_at(position)):
		return 0
	var index := position + 1
	while index < source.length():
		var code := source.unicode_at(index)
		if not _is_identifier_start(code) and not _is_digit(code):
			break
		index += 1
	return index - position


## HASHTAG_CONTENT: `#` followed by at least one character that isn't
## whitespace or another `#`. A lone `#` is not a token.
func _match_hashtag(source: String, position: int) -> int:
	if source.unicode_at(position) != 35:
		return 0
	var index := position + 1
	while index < source.length():
		var code := source.unicode_at(index)
		if code == 32 or code == 9 or code == 10 or code == 13 or code == 35:
			break
		index += 1
	if index == position + 1:
		return 0
	return index - position


## VARIABLE: `$` followed by an identifier, as used by `set:`.
func _match_variable(source: String, position: int) -> int:
	if source.unicode_at(position) != 36:
		return 0
	var identifier_length := _match_identifier(source, position + 1)
	if identifier_length == 0:
		return 0
	return identifier_length + 1


## NUMBER: one or more digits. Plans only ever use whole numbers, for
## `select:` indices and `set:` values.
func _match_number(source: String, position: int) -> int:
	var index := position
	while index < source.length() and _is_digit(source.unicode_at(index)):
		index += 1
	return index - position

func _match_text(source: String, position: int) -> int:
	if source.unicode_at(position) != 96:
		return 0
	var closing := source.find("`", position + 1)
	if closing == -1:
		return 0
	return closing - position + 1


func _is_identifier_start(code: int) -> bool:
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 95


func _is_digit(code: int) -> bool:
	return code >= 48 and code <= 57

func _parse_test_plan(source: String) -> Dictionary:
	var lexed := _tokenize(source)
	var lex_error: String = lexed.error
	if not lex_error.is_empty():
		return {"runs": [], "error": lex_error}
	_tokens = lexed.tokens
	_token_index = 0

	var environment := ""
	if _peek_type() == Token.ENVIRONMENT:
		_next_token()
		if _peek_type() != Token.IDENTIFIER:
			return {"runs": [], "error": _syntax_error("environment:", "IDENTIFIER").error}
		environment = _next_token().text
		if _peek_type() != Token.SEPARATOR:
			return {"runs": [], "error": _syntax_error("environment: " + environment, "'---'").error}
		_next_token()

	var runs: Array = []
	while true:
		var start_node := START_NODE
		if _peek_type() == Token.START:
			_next_token()
			if _peek_type() != Token.IDENTIFIER:
				return {"runs": [], "error": _syntax_error("start:", "IDENTIFIER").error}
			start_node = _next_token().text
		var steps: Array[Dictionary] = []
		while STEP_START_TOKENS.has(_peek_type()):
			var step := _parse_step()
			if step.has("error"):
				return {"runs": [], "error": step.error}
			steps.append(step)
		if steps.is_empty():
			return {"runs": [], "error": "expected a step but found '%s'" % _peek_text()}
		runs.append({"start_node": start_node, "steps": steps})
		if _peek_type() == Token.SEPARATOR:
			_token_index += 1
			continue
		if _peek_type() == Token.END_OF_FILE:
			break
		return {"runs": [], "error": "unexpected '%s'" % _peek_text()}
	return {"environment": environment, "runs": runs, "error": ""}

func _parse_step() -> Dictionary:
	var keyword := _next_token()
	var keyword_type: int = keyword.type
	if keyword_type == Token.LINE:
		# `line: *` expects a line but doesn't care what it says, so the text
		# is stored as null and the runner skips the text comparison.
		var line_text: Variant = null
		if _peek_type() == Token.TEXT:
			line_text = _trim_backticks(_next_token().text)
		elif _peek_type() == Token.STAR:
			_next_token()
		else:
			return _syntax_error("line:", "TEXT or '*'")
		return {"kind": "line", "text": line_text, "hashtags": _parse_hashtags()}
	if keyword_type == Token.OPTION:
		# Options accumulate until a `select:` arrives; `[disabled]` means the
		# option is expected to be shown but not selectable.
		if _peek_type() != Token.TEXT:
			return _syntax_error("option:", "TEXT")
		var option_text := _trim_backticks(_next_token().text)
		var hashtags := _parse_hashtags()
		var available := true
		if _peek_type() == Token.DISABLED:
			_next_token()
			available = false
		return {"kind": "option", "text": option_text, "hashtags": hashtags, "available": available}
	if keyword_type == Token.COMMAND:
		if _peek_type() != Token.TEXT:
			return _syntax_error("command:", "TEXT")
		return {"kind": "command", "text": _trim_backticks(_next_token().text)}
	if keyword_type == Token.STOP:
		return {"kind": "stop"}
	if keyword_type == Token.SELECT:
		# Plans number options from 1; the VM numbers them from 0, so
		# `select: 0` becomes -1, which is the "no option selected" value used
		# when every option is unavailable.
		if _peek_type() != Token.NUMBER:
			return _syntax_error("select:", "NUMBER")
		return {"kind": "select", "index": int(_next_token().text) - 1}
	if keyword_type == Token.SET:
		if _peek_type() != Token.VARIABLE:
			return _syntax_error("set:", "VARIABLE")
		var variable_name: String = _next_token().text
		if _peek_type() != Token.EQUALS:
			return _syntax_error("set: " + variable_name, "'='")
		_next_token()
		if _peek_type() == Token.BOOL:
			return {"kind": "set", "variable": variable_name, "value": _next_token().text == "true"}
		if _peek_type() == Token.NUMBER:
			return {"kind": "set", "variable": variable_name, "value": int(_next_token().text)}
		return _syntax_error("set: " + variable_name + " =", "BOOL or NUMBER")
	if keyword_type == Token.SALIENCY:
		if _peek_type() != Token.IDENTIFIER:
			return _syntax_error("saliency:", "IDENTIFIER")
		return {"kind": "saliency", "mode": _next_token().text}
	if keyword_type == Token.NODE:
		if _peek_type() != Token.IDENTIFIER:
			return _syntax_error("node:", "IDENTIFIER")
		return {"kind": "node", "node_name": _next_token().text}
	return {"error": "unhandled step type '%s'" % keyword.text}

func _parse_hashtags() -> PackedStringArray:
	var hashtags := PackedStringArray()
	while _peek_type() == Token.HASHTAG:
		var hashtag: String = _next_token().text
		hashtags.append(hashtag.substr(1))
	return hashtags


func _syntax_error(after: String, expected: String) -> Dictionary:
	return {"error": "expected %s after '%s' but found '%s'" % [expected, after, _peek_text()]}


func _trim_backticks(text: String) -> String:
	return text.lstrip("`").rstrip("`")


func _peek_type() -> int:
	return _tokens[_token_index].type


func _peek_text() -> String:
	return _tokens[_token_index].text

func _next_token() -> Dictionary:
	var token := _tokens[_token_index]
	if _token_index < _tokens.size() - 1:
		_token_index += 1
	return token

class TestPlanRunner:
	extends RefCounted

	var program: YarnProgram
	var storage: YarnInMemoryVariableStorage
	var library: YarnLibrary
	var vm: YarnVirtualMachine
	var smart_variable_evaluator: YarnSmartVariableEvaluator
	var locale_code: String
	## First mismatch found, or empty while everything still matches.
	var failure: String = ""
	## The step currently being waited on, read by the VM handlers.
	var _expectation: Dictionary = {}
	## Options seen since the last `select:`, in plan order...
	var _expected_options: Array[Dictionary] = []
	## Human-readable position in the plan, prefixed to failures.
	var _step_label: String = ""
	## How many options the VM last deliveredd used to validate `select:`.
	var _delivered_option_count: int = 0
	## Whether the dialogue has finished. Tracked here rather than read from
	## the VM because a plan may continue with a new run after a stop...
	var _stopped: bool = true

	func _init(test_program: YarnProgram, variable_storage: YarnInMemoryVariableStorage, locale: String) -> void:
		program = test_program
		storage = variable_storage
		locale_code = locale

		storage.clear()

		library = YarnLibrary.new()
		vm = YarnVirtualMachine.new()
		vm.set_library(library)
		vm.variable_storage = storage

		smart_variable_evaluator = YarnSmartVariableEvaluator.new()
		smart_variable_evaluator.attach_to_storage(storage)
		storage.smart_variable_evaluator = smart_variable_evaluator

		library.set_virtual_machine(vm)

		_apply_saliency_strategy(YarnSaliencyStrategy.YarnBestLeastRecentlyViewedSaliencyStrategy.new())

		library.register_function("assert", _assert, 1)
		library.register_function("add_three_operands", _add_three_operands, 3)
		library.register_function("set_objective_complete", _set_objective_complete, 1)
		library.register_function("is_objective_active", _is_objective_active, 1)
		library.register_function("get_quest_status", _get_quest_status, 1)

		vm.program = program
		library.set_program(program)
		storage.set_program(program)
		smart_variable_evaluator.set_program_context(program, library)

		library.register_function("dummy_bool", _dummy_bool, 0)
		library.register_function("dummy_number", _dummy_number, 0)
		library.register_function("dummy_string", _dummy_string, 0)

		vm.line_handler.connect(_on_line)
		vm.options_handler.connect(_on_options)
		vm.command_handler.connect(_on_command)
		vm.dialogue_complete_handler.connect(_on_dialogue_complete)

	func run(runs: Array) -> String:
		var saliency_strategies := {
			"first": YarnSaliencyStrategy.YarnFirstSaliencyStrategy.new(),
			"best": YarnSaliencyStrategy.YarnBestSaliencyStrategy.new(),
			"best_least_recently_seen": YarnSaliencyStrategy.YarnBestLeastRecentlyViewedSaliencyStrategy.new(),
		}
		_expected_options.clear()

		for run_index in range(runs.size()):
			var steps: Array = runs[run_index].steps
			var start_node: String = runs[run_index].start_node
			_step_label = "run %d, start" % (run_index + 1)
			_expectation = {}
			# Variables and visit counts deliberately carry over between runs;
			# only the dialogue position is reset.
			if not vm.set_node(start_node):
				_fail("no node named '%s' in program" % start_node)
				return failure
			_stopped = false

			for step_index in range(steps.size()):
				var step: Dictionary = steps[step_index]
				var kind: String = step.kind
				_step_label = "run %d, step %d (%s)" % [run_index + 1, step_index + 1, describe_step(step)]

				if kind == "line" or kind == "command" or kind == "stop":
					# Content steps: expect this, then let the VM run until it
					# delivers something.
					_expectation = step
					_continue_dialogue()
				elif kind == "option":
					# Options are collected, not awaited; the `select:` that
					# follows is what actually runs the dialogue.
					_expected_options.append(step)
				elif kind == "select":
					_expectation = step
					_continue_dialogue()
					if failure.is_empty():
						_select_option(step.index)
					_expected_options.clear()
				elif kind == "node":
					# Jump elsewhere without ending the dialogue, as a game
					# would when starting a different conversation.
					if not program.has_node(step.node_name) or not vm.set_node(step.node_name):
						_fail("no node named '%s' has been loaded" % step.node_name)
					else:
						_stopped = false
				elif kind == "set":
					# Only variables the program knows about can be set, which
					# catches plans that drift from their script. Numbers are
					# stored as floats because that is Yarn's only number type.
					if not program.initial_values.has(step.variable):
						_fail("variable %s is not valid in program" % step.variable)
					elif step.value is bool:
						storage.set_value(step.variable, step.value)
					else:
						storage.set_value(step.variable, float(step.value))
				elif kind == "saliency":
					if saliency_strategies.has(step.mode):
						_apply_saliency_strategy(saliency_strategies[step.mode])
					else:
						_fail("unknown saliency strategy '%s'" % step.mode)
				else:
					_fail("unhandled step type '%s'" % kind)

				if not failure.is_empty():
					return failure
				# A stop ends this run; anything after it belongs to the next.
				if kind == "stop":
					break

		return failure

	static func describe_step(step: Dictionary) -> String:
		var kind: String = step.get("kind", "")
		if kind == "line":
			if step.text == null:
				return "line: *"
			return "line: `%s`" % step.text
		if kind == "option":
			return "option: `%s`%s" % [step.text, "" if step.available else " [disabled]"]
		if kind == "command":
			return "command: `%s`" % step.text
		if kind == "stop":
			return "stop"
		if kind == "select":
			return "select: %d" % (int(step.index) + 1)
		if kind == "set":
			return "set: %s = %s" % [step.variable, str(step.value)]
		if kind == "saliency":
			return "saliency: %s" % step.mode
		if kind == "node":
			return "node: %s" % step.node_name
		return "no step"

	func _apply_saliency_strategy(strategy: YarnSaliencyStrategy) -> void:
		vm.set_saliency_strategy(strategy)
		library.set_vm_context(strategy, storage)

	func _fail(message: String) -> void:
		if failure.is_empty():
			failure = "%s: %s" % [_step_label, message]

	func _continue_dialogue() -> void:
		if _stopped:
			_fail("expected %s, but the dialogue has already stopped" % describe_step(_expectation))
			return
		if vm.current_state == YarnVirtualMachine.ExecutionState.WAITING_FOR_INPUT:
			_fail("cannot continue running dialogue; still waiting on option selection")
			return
		# A line or command leaves the VM suspended until the presenter says
		# it has finished; there are no presenters here!!!
		# immediately and carry on.
		if vm.current_state == YarnVirtualMachine.ExecutionState.SUSPENDED:
			vm.signal_content_complete()
		vm.continue_dialogue()
		if vm.has_error():
			var error_text := vm.last_error if not vm.last_error.is_empty() else "virtual machine stopped with an error (see log)"
			_fail("runtime error: %s" % error_text)

	func _select_option(index: int) -> void:
		if vm.current_state != YarnVirtualMachine.ExecutionState.WAITING_FOR_INPUT:
			_fail("select was requested, but the dialogue wasn't waiting for a selection")
			return
		if index != YarnVirtualMachine.NO_OPTION_SELECTED and (index < 0 or index >= _delivered_option_count):
			_fail("%d is not a valid option ID (expected a number between 0 and %d)" % [index, _delivered_option_count - 1])
			return
		vm.set_selected_option(index)

	func _compose_text(line_id: String, substitutions: Array) -> Dictionary:
		if not program.string_table.has(line_id):
			return {"text": line_id, "error": "string table does not contain line ID '%s'" % line_id}
		var text: String = program.string_table[line_id]
		if text.is_empty():
			var shadow_source_id := _shadow_source_id(line_id)
			if not shadow_source_id.is_empty():
				if not program.string_table.has(shadow_source_id):
					return {"text": line_id, "error": "string table does not contain shadow source line ID '%s'" % shadow_source_id}
				text = program.string_table[shadow_source_id]
		var line_parser := YarnLineParser.new()
		var builtin_replacer := YarnBuiltInMarkupReplacer.new()
		line_parser.register_marker_processor("select", builtin_replacer)
		line_parser.register_marker_processor("ordinal", builtin_replacer)
		line_parser.register_marker_processor("plural", builtin_replacer)
		var substituted_text := YarnLineParser.expand_substitutions(text, substitutions)
		return {"text": line_parser.parse_string(substituted_text, locale_code).text, "error": ""}

	func _shadow_source_id(line_id: String) -> String:
		var metadata: PackedStringArray = program.line_metadata.get(line_id, PackedStringArray())
		for tag in metadata:
			if tag.begins_with("shadow:"):
				return "line:" + tag.substr("shadow:".length())
		return ""

	func _check_hashtags(line_id: String, hashtags: PackedStringArray) -> bool:
		if hashtags.is_empty():
			return true
		var metadata: PackedStringArray = program.line_metadata.get(line_id, PackedStringArray())
		for hashtag in hashtags:
			if not metadata.has(hashtag) and hashtag != line_id:
				_fail("metadata for %s is expected to contain '%s' but was [%s]" % [line_id, hashtag, ", ".join(metadata)])
				return false
		return true

	func _on_line(line: YarnLine) -> void:
		var composed := _compose_text(line.line_id, line.substitutions)
		if _expectation.get("kind", "") != "line":
			_fail("expected %s, not line \"%s\"" % [describe_step(_expectation), composed.text])
			return
		var compose_error: String = composed.error
		if not compose_error.is_empty():
			_fail(compose_error)
			return
		var expected_text: Variant = _expectation.text
		if expected_text != null and composed.text != expected_text:
			_fail("line text mismatch: expected `%s`, actual `%s`" % [expected_text, composed.text])
			return
		_check_hashtags(line.line_id, _expectation.hashtags)

	func _on_options(options: Array[YarnOption]) -> void:
		_delivered_option_count = options.size()
		if _expectation.get("kind", "") != "select":
			var option_texts := PackedStringArray()
			for option in options:
				option_texts.append(_compose_text(option.line_id, option.substitutions).text)
			_fail("expected %s, not options [%s]" % [describe_step(_expectation), ", ".join(option_texts)])
			return
		if options.size() != _expected_options.size():
			var delivered_texts := PackedStringArray()
			for option in options:
				delivered_texts.append(_compose_text(option.line_id, option.substitutions).text)
			_fail("expected %d options, got %d: [%s]" % [_expected_options.size(), options.size(), ", ".join(delivered_texts)])
			return

		var is_any_available := false
		for i in range(options.size()):
			var option := options[i]
			var option_expectation := _expected_options[i]
			var composed := _compose_text(option.line_id, option.substitutions)
			var compose_error: String = composed.error
			if not compose_error.is_empty():
				_fail(compose_error)
				return
			var expected_text: Variant = option_expectation.text
			if expected_text != null and composed.text != expected_text:
				_fail("option %d text mismatch: expected `%s`, actual `%s`" % [i + 1, expected_text, composed.text])
				return
			if not _check_hashtags(option.line_id, option_expectation.hashtags):
				return
			if option.is_available != option_expectation.available:
				_fail("option \"%s\"'s availability was expected to be %s" % [composed.text, option_expectation.available])
				return
			if option.is_available:
				is_any_available = true

		var selected_index: int = _expectation.index
		if is_any_available:
			var matching_count := 0
			for option in options:
				if option.option_index == selected_index:
					matching_count += 1
			if matching_count != 1:
				_fail("one option should have the ID that we want to select (%d), found %d" % [selected_index, matching_count])
		elif selected_index != YarnVirtualMachine.NO_OPTION_SELECTED:
			_fail("no option is available, so the selected index should be %d, not %d" % [YarnVirtualMachine.NO_OPTION_SELECTED, selected_index])

	func _on_command(command_text: String) -> void:
		if _expectation.get("kind", "") != "command":
			_fail("expected %s, not command \"%s\"" % [describe_step(_expectation), command_text])
			return
		if command_text != _expectation.text:
			_fail("command text mismatch: expected `%s`, actual `%s`" % [_expectation.text, command_text])

	func _on_dialogue_complete() -> void:
		_stopped = true
		if _expectation.get("kind", "") != "stop":
			_fail("expected %s, not stop" % describe_step(_expectation))

	func _assert(value: bool) -> bool:
		if not value:
			_fail("assertion should pass")
			library.report_function_error("assert: assertion should pass")
		return true

	func _add_three_operands(a: float, b: float, c: float) -> float:
		return float(_to_int32(a) + _to_int32(b) + _to_int32(c))

	func _set_objective_complete(_objective: String) -> bool:
		return true

	func _is_objective_active(_objective: String) -> bool:
		return true

	func _get_quest_status(_quest_name: String) -> String:
		return "InProgress"

	func _dummy_bool() -> bool:
		return true

	func _dummy_number() -> float:
		return 1.0

	func _dummy_string() -> String:
		return "string"

	static func _to_int32(value: float) -> int:
		var floored := int(floorf(value))
		var remainder := value - floorf(value)
		if remainder > 0.5:
			return floored + 1
		if remainder < 0.5:
			return floored
		return floored if floored % 2 == 0 else floored + 1
