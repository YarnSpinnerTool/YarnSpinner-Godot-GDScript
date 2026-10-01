# Yarn Spinner for Godot (GDScript) — Changelog

## Early Access 3.2

### Yarn Project inspector

The inspector for `.yarnproject` files now matches Yarn Spinner for Unity's!

- The Yarn Spinner header (logo and links) from the dialogue runner's
  inspector now appears on Yarn Projects, Yarn scripts, and `.ysls.json`
  files too!
- Compile errors are listed in the inspector, grouped b y script. Projects that 
  fail to compile still import, so their errors are shown!
- The project's source file patterns can be edited, added, and removed
  directly in the inspector. Patterns now support folders and `**` anywhere
  (`Dialogue/**/*.yarn`), and `excludeFiles` is respected!
- **Add Line Tags to Yarn Scripts** adds `#line:` IDs to every untagged
  line, using either the random or the descriptive line tagger!
- **Export Strings and Metadata as CSV** writes a Godot translation CSV
  using the project's base language, plus a `-metadata.csv` file with each
  line's file, node, line number and tags. Aw yeah.
- **Update Existing Strings Files** finds the translation CSVs that contain
  the project's lines, adds new lines, removes deleted ones, and marks
  translations whose source text has changed with `(NEEDS UPDATE)`!
- The project can generate a typed variable storage class, with a property
  for each declared variable and a GDScript enum for each Yarn enum. Choose
  its class name and parent class in the inspector!
- Changes are made with **Apply** and **Revert**, and switching away from a
  project with unapplied changes asks whether to keep them. This is very Unity-esque,
  so we're open to feedback.

These settings are also available in the Import dock.

### Strict warning compatibility

A handful of internal variable declarations relied on inferring their type
from a `Variant` value, which fails to compile in projects that escalate
GDScript's `INFERENCE_ON_VARIANT` warning to an error. Those declarations
now use explicit types, so the addon compiles cleanly under strict warning
settings!

### Sample gallery ordering and thumbnails

The Samples tab in the Yarn Spinner editor screen now lists samples in a
learning-path order (starting points first, then core features,
presentation, voice over, and saliency) instead of alphabetically, and
every sample card has a screenshot.

### YarnDialoguePresenter is abstract

`YarnDialoguePresenter` is now marked `@abstract`, matching its Yarn Spinner for Unity
equivalent (`DialoguePresenterBase`). Attaching the base script to a node
used to look like it worked, then displayed nothing at runtime; the editor
now refuses the attach outright. Attach one of the presenters from
`addons/yarn_spinner/ui/` (`YarnLinePresenter`, `YarnOptionsPresenter`,
and friends), or subclass the base for your own. Existing subclasses are
unaffected!

### Functions can be used inside lines

A function call inside a line, like `Rosa: You have {coin_count()} coins.`,
used to fail to compille with "Can't determine the type of the expression".
This was because compiler was never told what your functions return, so it 
could only guess from where each call was used, and a line doesn't say.

Now, before compiling, the importer it scans your scripts for functions 
(the same scan that writes the `.ysls.json`, so `_yarn_function_`
methods and functions added with `add_function()` are both found) and passes
each one's parameter and return types to the compiler. It also declares the
built-in functions teh compiler didn't know about: `visited`,
`visited_count`, `has_any_content`, `abs`, `sign`, `clamp`, `lerp`,
`inverse_lerp`, `smoothstep`, `pow`, `sqrt`, `wrap`, `mod`, `plural`,
`ordinal`, `length`, `uppercase` and `lowercase`.

Calling a function with the wrong type of argument, or using its result as
the wrong type, is now a compile error instead of a problem at runtime! Hooray.
Functions are found in the same files the `.ysls.json` is written from: the
Yarn Project's folder and the scenes that use it, or the folder set in the
Yarn Project's **Ysls Scan Path** import option.

The bundled native compiler now accepts function declarations, which is how
it gets them. The `ysc` fallback, used where there's no native compiler,
gets them from the project's `"definitions"` instead:

- The importer adds the project's `.ysls.json` to the `.yarnproject`'s
  `"definitions"` if it isn't already listed. Anything already there is
  kept, and teh file is only written when the entry is
  missing. If `"definitions"` holds something other than a path or a list
  of paths, it's left alone and you'll get a warning.
- Functions in the `.ysls.json` are now written under `"Functions"`, in the
  PascalCase shape `ysc` reads. Commands are unchanged. The VS Code
  extension reads both no problemo.
- `ysc` only reads the first file in `"definitions"`, so if your project
  already listed another definitions file first, that's the one it uses..

### Changed

- The bundled compiler binaries are now named for their platform and
  architecture: `ysc-native-macos-universal`, `ysc-native-windows-x64.exe`,
  `ysc-native-linux-x64`, and the `arm64` builds for Windows and Linux. The
  importer chooses the binary that matches the editor's platform and
  architecture. Rebuild with `native/build.sh` to get the new names!
- The bundled compiler is nowrun directly instead of through `cmd.exe` or
  `/bin/sh` etc., and reads its job from a file passed with `--input`. This
  fixes the compiler failing on Windows, where `cmd` seemed to misread Godot's
  forward-slash paths... 
- The `plural` annd `ordinal` markup markers now use the full set of Unicode
  CLDR plural rules, covering over a hundred languages, instead of a
  hand-picked list of about twenty. Languages such as Welsh, Irish,
  Scottish Gaelic, Breton, Maltese, Slovenian, Lithuanian, Latvian,
  Icelandic, and most South and Southeast Asian languages now get correct
  plural forms in `[plural value="%" ...]` and `[ordinal value="%" ...]`
  text, rather than falling back to a generic "one for 1, other for
  everything else" guess. The rules are onm their own file,
  `cldr_plural_rules.gd`, so they can be extended without touching the
  markup replacement code itself! Woo! This took a while.
- Command text is now split into arguments the same way Yarn Spinner for
  Unity does: only double quotes delimit a quoted argument, and inside one
  only `\\` and `\"` are treated as escapes. Single quotes and stray
  backslashes are no longer special. **This is breaking** if a command
  relied on single quotes to group an argument (`<<say 'hello there'>>`
  used to produce one argument; it now produces two, `'hello` and
  `there'`) or on a backslash escaping something other than a quote or
  another backslash. Wrap arguments that ned spaces in double quotes
  instead, and expect a literal backslash wherever your command text has
  one...
- `bool()` and `number()` now stop the dialoue with a clear error when
  given input they can't convert, instead of logging a warning and
  quietly substituting `false` or `0`. `bool()` also no longer accepts
  `"1"` as a stand-in for `"true"` — only `"true"` and `"false"`
  (case-insensitive) convert from a string. `format()` now takes exactly
  one substitution argument, `format(formatString, argument)`, matching
  every other Yarn Spinner runtime; every `{0}` in the format string is
  replaced, and any other numbered placeholder is an error rather than
  being left in the text or silently stripped.
- Numbers are now stored and displayed as 32-bit floats, matching the
  Yarn Spinner value model, and print using the same shortest
  round-trip formatting as the other runtimes (`0.1` stays `0.1`,
  `10000000` stays plain, `1000000000` becomes `1E+09`) instead of a
  fixed six-decimal-place format that could show trailing precision Yarn
  never had. I felt this was important for parity with the TypeScript runner
  that is used for people's testing.
- Malformed markup now logs a warning describing what went wrong and
  where, instead of failing silently and falling back to the raw text.
- **Breaking:** `YarnLine.text` now includes the character name (so the same
  as `LocalizedLine.Text` in Yarn Spinner for Unity). Use
  `text_without_character_name` (or `get_plain_text()`) where you want the
  line without the name. The built-in line presenter has a new
  `show_character_name_in_line` option for when there's no separate
  character name label.
- **Breaking:** `allow_option_fallthrough` on the dialogue runner now
  defaults to `true` (alsoo matching Unity). An option group with no available
  options now continues past the options instead of stopping the dialogue!
- **Breaking:** the in-memory variable storage now rejects variable names
  that don't start with `$`, as Unity does. Set `validate_variable_names`
  to `false` to turn this off.
- **Breaking:** action markup handlers now receive the line's
  `YarnMarkupParseResult` in `on_prepare_for_line` and
  `on_line_display_begin`, not the `YarnLine`. The wave and colour pulse
  example handlers have been removed.
- **Breaking:** command parameters are now converted the same way Unity
  converts them. An `int` parameter no longer accepts `1.5`, a `bool`
  parameter no longer accepts `yes`, `on` or `1`, and a `Vector2`,
  `Vector3` or `Color` that can't be parsed is now an error instead of
  zero. A parameter typed as a node class that names a node which doesn't
  exist now receives `null` with a warning, rather than failing the
  command. `command_unhandled` is now only emitted for commands that
  aren't registered at all; other command failures are logged as errors.
- **Breaking:** `<<wait>>` now requires a duration, as in Unity. It used to
  default to one second.
- **Breaking:** the line advancer's defaults now match Unity: the hurry up
  input is `ui_accept`/Space and the next line input is
  `ui_cancel`/Escape. The line presenter's old `hurry_action` property has
  been removed; use a line advancer or `YarnLinePresenterButtonHandler`.
- **Breaking:** `YarnLineProvider` is now a `Resource`, and can be set on
  the dialogue runner in the inspector along with its text, asset and
  fallback locales.
- Functions registered with `add_function` now take their argument count
  and types from the method's signature, and reject return values that
  aren't a Yarn type. Static `_yarn_function_` methods on `class_name`
  scripts are registered automatically; non-static ones are only picked
  up from autoloads.
- Booleans now show as `True` and `False` when substituted into a line,
  matching Unity.
- The virtual machine's instruction and call depth limits are now off by
  default, as Unity has no such limits.
- Requesting the next line now also hurries up the current one, so a
  presenter only needs to watch for one of them.
- Variable change listeners fire every time a variable is set, and
  initial values are read from the program rather than copied into
  storage, as in Unity.
- Added `YarnTypewriter`, with instant, letter and word typewriters, and a
  custom typewriter option on the line presenter.
- Added `save_state_to_persistent_storage()` and
  `load_state_from_persistent_storage()` to the dialogue runner.
- `format()` now follows .NET's format rules exactly, including padding,
  precision and custom numeric formats.
- Added `get_line_ids_for_nodes()` to `YarnProjectResource` and
  `get_line_ids_for_node()` to `YarnProgram`, the equivalent of
  `YarnProject.GetLineIDsForNodes()` in Unity, for preloading or debugging
  the lines in a set of nodes.
- Line and option text is now normalised to Unicode NFC (composed) form
  before its markup is parsed, the same as Yarn Spinner for Unity. A line
  written with a combining accent, like `e` followed by U+0301, now
  produces the same text and the same attribute positions as one written
  with a precomposed `é`.
- When a Yarn Project's Ysls Scan Path is empty, the folder searched for
  Commands and Functions now starts at the project's own folder and only
  moves up while it finds no scripts. It never moves into a folder that
  holds another Yarn Project, so projects that sit side by side no longer
  pick up each other's Commands in their `.ysls.json`.
- With an empty Ysls Scan Path, the `.ysls.json` now also lists the
  Commands and Functions from every scene that uses the Yarn Project,
  wherever their scripts live. The scenes are found by reading them as
  text, and the search follows the scripts attached to their nodes,
  instanced and inherited scenes, the scripts and scenes those scripts
  preload or name by class, and your autoloads. Scenes that only use a
  different Yarn Project are skipped. A project whose scenes use shared
  scripts, like a character script in another folder, now gets those
  scripts' Commands.
- The Ysls Scan Path import option is now empty by default, so new Yarn
  Projects get the search above instead of scanning the whole project.
  `res://`, the old default, is stored in the import settings of existing
  projects, so it's now treated the same as empty. Any other folder is
  still used as it is.
- The `.ysls.json` rewritten when you save ascriipt, and the Commands
  palette in the Yarn Spinner tab, now use each project's Ysls Scan Path
  import option, and the rewrite is skipped for projects with Generate Ysls
  turned off. The Dialogue Runner's Regenerregte YSLS button uses the same
  search when its own Ysls Scan Path is empty.

### Fixed

- Negative numbers now pick their plural form from the size of the number,
  ignoring the sign. `[plural value=-1 one="% apple" other="% apples"]` 
  now reads "-1 apple" rather than "-1 apples". Only the operands changed!
- Fixed bugs in CLDR plural rules!
- `[plural]` and `[ordinal]` markup now follows the active locale. The
  line's locale was being set after its text had already been parsed, so
  every line used English plural and ordinal rules regardless of what
  `set_locale()` was called with.
- Option text now processes `select`, `plural`, and `ordinal` markup, the
  same as lines do. These markers in an option used to be stripped to
  nothing by the display path.
- Modulo by zero now stops the dialogue with a clear error instead of
  returning 0. Note both operands round to the nearest integer first
  (halves round to even), so a divisor between -0.5 and 0.5 also counts
  as zero.
- Shadow lines (`#shadow:`) now display their source line's text, and play
  its voice over audio, instead of showing a raw line ID. The line provider
  resolves the shadow source before any lookup, the same way Yarn Spinner
  for Unity does.
- A line with no text in the current locale now logs a warning naming the
  line and locale. It still displays the line ID as before, but no longer
  does so silently.
- The continue button installed by the action markup handler now advances
  the line. It was calling a method that doesn't exist on the dialogue
  runner, behind a guard that hid the mistake, so pressing it did nothing.
- Preloaded assets are now actually used. Background loads started by
  `preload_assets()` were never collected, so every line fell back to a
  synchronous load anyway, and a line ID that had ever been preloaded could
  never be requested again. Finished loads are now collected whenever an
  asset is fetched.
- The bundled native compiler is invoked once per compile instead of twice.
  The first invocation was a leftover that ran the binary with no input and
  could stall the editor waiting on it.
- Compiling with the native compiler now works when the project or the
  Godot cache directory has spaces or shell metacharacters in its path, and
  two editor instances compiling at the same time no longer overwrite each
  other's temporary files.
- Dividing zero by zero in a Yarn expression now produces NaN, matching
  Yarn Spinner for Unity. A hand-rolled guard was returning infinity.
- A broken script now stops the dialogue with a clear error instead of
  limping on with wrong values! Calling an unknown function, or reading a
  variable that doesn't exist anywhere (storage, smart variables, or the
  program's initial values), used to log and continue with null on the
  VM stack, which sent the story down branches nobody wrote. All Yarn
  Spinner runtimes now fail identically here hooray.
- A smart variable whose expression leaves the wrong number of values on
  the stack is now reported as an error instead of silently returning
  whichever value happened to be on top.
- `round()` and `round_places()` now round half to even ("banker's
  rounding", so 2.5 rounds to 2 and 3.5 to 4), matching every other Yarn
  Spinner runtime. Godot's own `roundf()` rounds half away from zero. Agian,
  important while folks are testing/using the TypeScript runner as part
  of their toolchain (e.g. VSCode).
- A truncated or corrupt compiled program now fails to load with an error
  instead of hanging the editor.
- Instructions the runtime doesn't recognise now stop the dialogue with an
  error instead of shifting every jump in the node.
- When a node has the same header more than once, the first one now wins,
  and `get_all_headers()` returns every one of them.
- Dialogue completion now happens in the same order as Unity: nodes
  report completion when the dialogue is stopped, and
  `dialogue_completed` fires before the runner is marked as stopped.
- Starting dialogue at a node that doesn't exist now logs an error and
  doesn't start, instead of emitting `dialogue_started` first.
- Saliency strategies now pick between tied candidates the same way Unity
  does, and store view counts as floats like every other Yarn number.
- Escaped square brackets in a line (`\[` and `\]`) now display as
  brackets instead of being read as BBCode tags, and overlapping markup
  such as `[b]a [i]b[/b] c[/i]` now renders correctly.
- Pauses in lines now respect hurry up, and wait for the game to be
  unpaused.
- Command text is now split on every Unicode whitespace character, not
  just spaces and tabs.
- Disabled presenters are now skipped, as in Unity.
- Calling `start_dialogue()` from a `dialogue_completed` handler now starts
  the new dialogue properly, instead of leaving the runner stuck.
- Changing `yarn_project` while dialogue is running is now refused with an
  error, the same as `set_project()`.
- Checking a node group for content (`has_any_content()`, or
  `get_saliency_options_for_node_group()`) now stops with an error if one
  of its conditions can't be evaluated, as Unity does, instead of quietly
  treating that condition as failed.
- Command discovery now only loads scripts that actually declare a
  `_yarn_command_` or `_yarn_function_` method, instead of any script that
  mentions one.
- Exported games no longer search every `class_name` script for commands
  and functions when dialogue starts. (Sorry) Exported scripts don't include their
  source, so that search couldn't rule anything out and ended up loading
  every script. The plugin now records which scripts declare commands and
  functions when you export, much like Yarn Spinner for Unity generates its
  command registrations at build time, and the exported game loads only
  those!
- Lines, options, plural rules and variable name hashing can now be used
  from more than one thread at once. Every line and option used to share a
  single markup parser, so reading line text from worker threads (for
  example, preparing lines ahead of time) could produce the wrong text or
  crash the game.
- Fixed several `YarnEffects` helpers:
  - The typewriters, including `typewriter_with_line()`, now take an
    optional cancellation token and finish immediately when hurried.
  - `typewriter_words()` now reveals text a whole word at a time, instead
    of by overall proportion.
  - `typewriter_with_line()` now returns a signal that fires when the line
    has finished, using the same typewriter as the line presenter, so
    pauses respect hurry-up and game pause.
  - Instant typewriters return a signal that can still be awaited.
  - `shake()` no longer divides by zero for very short shakes.
- Registering several replacement marker processors on a line presenter no
  longer logs "already registered" errors for the processors registered
  before it.
- A dialogue runner that leaves the scene before its first command search
  runs no longer logs a script error.
- When two different scripts declare the same command or function name,
  the second one is now reported as an error instead of being silently
  ignored, as Unity does.
- Commands on nodes added to the scene after dialogue started are now
  found. If a command isn't registered and the scene has changed since it
  was last searched, the runner searches it again before giving up.
- The voice over presenter now asks for a shadow line's audio using its
  source line's ID, so shadow lines get the source line's clip even when a
  custom line provider doesn't resolve shadow lines itself.
- `set_content_saliency_strategy()` can now be called before the dialogue
  runner is ready. It used to crash; the strategy is now kept and applied
  when the runner sets up, and re-applied each time dialogue starts while
  Saliency Strategy is Custom.
- Command bindings set up in a scene's Inspector (the Bindings list on a
  `YarnBindingLoader`) are now found when writing the `.ysls.json` and the
  compiler's Function declarations. Scenes are read as text, not
  instantiated.
- `.ysls.json` entries for Command bindings now have the target method's
  real parameters, return type and async flag, instead of no parameters.
- Writing the `.ysls.json` no longer loads every `.tres` and `.res` file
  in the scan folder. Only files that hold Command bindings are read, so
  materials, textures and models aren't loaded or imported along the way.

### Documentation

- The custom presenter example in the quick start now uses the new
  presenter contract (`run_line(line, token) -> void`, await inside). The
  old example still showed the pre-Alpha 7 return-a-Variant style!
- Corrected signal and property names in the README and quick start:
  `command_unhandled` (not `unhandled_command`) and
  `show_selected_option_as_line` (not `run_selected_option_as_line`).
- The docs now lead with the bundled native compiler, which needs no
  setup. Installing `ysc` via the .NET SDK is documented as the fallback
  for platforms without a bundled binary. This will improve in the next
  alpha, so probably worth still keeping `ysc` around for now.

## Alpha 8 (2026-07-28)

Lots of nice little qualkity of life changes! Scene-based options, some tweaks to boolean flag parameters (to match Yarn Spinner for Unity), and a word wrap fix in the line presenter. If you show options with the built-in presenter, note that
option text no longer includes the character name prefix.

### Options are scene-based

The options presenter now instantiates a scene per option, similar to the way Yarn
Spinner for Unity instantiates its Option Item prefab. The default is the
new `ui/option_item.tscn` (a `YarnOptionItem` wrapping a focus-styled
button); edit that scene or point `option_button_scene` at your own to
restyle options. Plain `BaseButton` scenes still work. When
every option in a group is unavailable, the presenter now declines
immediately instead of waiting on an empty screen. Option text no longer
includes the character name prefix (an option written as
`-> Tom: Who are you?` displays as "Who are you?"), the same as Yarn Spinner forUnity's option items; `YarnOption` gained `character_name` and
`text_without_character_name` if you need either piece.

The voice over samples' options are styled similarly to the Yarn Spinner for Unity voice over sample's Option Item (60pt flat text, grey until selected, bottom-centre
panel).

### Word wrap is precalculated

The line presenter now lays out the whole line before the typewriter reveals
any of it, so words no longer jump to the next line partway through being
typed! Hooray. A word that won't fit on the current line starts on the next one
from its first character, which is what Yarn Spinner for Unity's TMP does with
`maxVisibleCharacters`. Sorry about that. Shoutout if you're still having problems.

### Boolean parameters accept their name as a flag

A command parameter of type `bool` can now be set to `true` by passing the
parameter's own name as a bareword, matching Yarn Spinner for Unity's convention. So for a handler like:

```gdscript
func _yarn_command_play_animation(layer: String, state: String, wait: bool = false) -> void: ...
```

both of these now work, and mean the same thing:

```
<<play_animation Tom Gesture LookAround wait>>
<<play_animation Tom Gesture LookAround true>>
```

`true`/`1`/`yes`/`on` (and `false`/`0`/`no`/`off`) keep working as before;
this only adds the flag form.

If you only write command handlers without a trailing `bool` flag, or you
already pass `true`/`false` explicitly, nothing should really change.

## Alpha 7 (2026-07-22)

This alpha reworks how presenters and the dialogue runner talk to each
other! If you implemented presenters or commands against an earlier alpha,
read the Breaking changes, please! Most migrations _should_ be signature change and the deletion of boilerplate. Hopefully.

### Breaking: one presenter contract

`run_line` no longer returns a `Variant`. There is now exactly one way to
write a presenter: **return when you're done, and await inside for anything
that takes time.** (In the previous alpha you couldn't await inside
`run_line` at all. The whole pattern we were previously using is is gone.)

So, before, you did something like this:
```gdscript
func run_line(line: YarnLine, token: YarnCancellationToken = null) -> Variant:
    label.text = line.text
    return _my_done_signal        # or: return null
```

And now, you do something like this:
```gdscript
func run_line(line: YarnLine, token: YarnCancellationToken = null) -> void:
    label.text = line.text
    await token.wait_for_next_content()   # hold the line open until dismissed
    label.text = ""
```

To migrate to the new API:
- **Sync presenters** (`return null`): change teh return type to `-> void`
  and delete the `return null`s. Done! Amazing.
- **Signal presenters** (`return my_signal`): change to `-> void` and
  replace `return my_signal` with `await my_signal`, or better, fold your
  detached helper's logic straight into `run_line`, which is usually
  simpler now that awaiting inside it works. If your dialogue can be
  stopped mid-line, also emit that signal from `on_dialogue_completed` so
  the parked `run_line` is released.

`run_options` keeps its previous approach (`-> int`: the selected index, or
-1 if you don't handle options) and may await the player's choice
internally, as before!

The runner starts every presenter in the same frame and advances only when
all of them have returned. The cancellation token is the finish-up request:
when it reports next-content, you should finish promptly.. the runner waits for you,
and logs a warning naming your presenter after 5 seconds if you don't! Don't be bad.

### Breaking: `dispatch_command` is a coroutine

`YarnLibrary.dispatch_command()` must now be awaited. Coroutine command
handlers run to completion inside it. If you called it directly, add
`await`; if you only write command handlers, nothing changes!

To be clear about who this affects: dispatch is the internal step where a
`<<command>>` in a Yarn script gets routed to your registered handler. The
dialogue runner is normally the only thing that calls it, and it already
awaits. So if your commands are ordinary `_yarn_command_*` methods or
`add_command()` registrations, you have nothing to migrate as your handlers
are called exactly as before, and a handler that awaits internally (like
the the built-in `<<wait>>`) now correctly holds the dialogue until it
finishes. Returning a Signal from a handler for async work also still
works. 

The only code that needs an `await` added is game code that was
invoking `dispatch_command()` on the library by hand, for example, a
debug console that runs Yarn commands outside of dialogue...

### Commands now receive typed parameters

Declare real types on command handlers, and arguments are converted before
the call! This includes `Node`-derived parameters, resolved by node name:

```gdscript
func _yarn_command_give(item: String, count: int, loud: bool) -> void: ...
# <<give sword 3 true>> → "sword", 3, true

func _yarn_command_focus(target: Node3D) -> void: ...
# <<focus Camera>> → the actual node
```

Supported: String, int, float, bool, Vector2, Vector3, Color, Node classes.
A value that can't convert will spit out a command error naming the argument.
Handlers registered as lambdas still receive raw strings (GDScript lambdas 
expose no parameter metadata, so use a named method)...

Note: in earlier alphas this conversion existed but never quite worked, and
coroutine command handlers invoked via `callv` silently failed, so, e.g., 
**`<<wait 2>>` did not actually wait in some configurations.** It does now;
if your timing depended on waits being skipped, re-check pacing, please!

### Behaviour changes

- Presenters no longer have `request_next()` or `request_hurry_up()`
  callbacks. The cancellation token is the only wind-down channel: watch it
  or await it in `run_line`. The runner's `request_next_content()` and
  `request_hurry_up()` still exist for game code and now just fire the
  token. A next-content request dismisses a line even mid-reveal, like
  Yarn Spinner for Unity. Two-stage "reveal, then advance" lives in
  `YarnLineAdvancer`, which was previously broken and now works, and in
  the line presenter's own direct input handling, which is unchanged.
- `YarnVoiceOverPresenter`: `end_line_when_voice_complete` now defaults to
  **true** (again, same as we do in Unity) and actually works, lol; a missing audio clip logs an
  error and skips the line instead of stalling; hurry-up no longer
  interrupts audio (only next-content does); audio is looked up through the
  runner's locale-aware pipeline first, so `set_locale()` switches voice as
  well as text.
- `request_line_cancellation` now routes through `request_next_content()`,
  so a presenter asking to end the line actually dismisses every presenter.
- All dialogue timing (typewriter, `<<wait>>`, option timeout,
  auto-advance, fades) now respects the pause model! Paused nodes stop
  their clocks per standard `process_mode` rules..!
- Keyboard input for presenters and the advancer moved to
  `_unhandled_input`, so UI controls get first look at focus and confirm
  presses. Click-to-continue stays in `_input` (a click over ttehe dialogue
  panel or a fullscreen overlay would otherwise be eaten as GUI input),
  gated to "line showing, no options up", with a new
  `click_anywhere_to_continue` export to turn it off. Use
  `runner.are_options_active()` instead of poking around in private state.

### TranslationServer for Localisation

The parallel Yarn localisation layer is gone; the single system is Godot's
own. We don't need a parallel one here, like we do in Yarn Spinner for Unity, 
as eveyrone should really be using the Godot one. Text goes through `TranslationServer` 
(keys are the line id prefixed with `YARN_` by default, and `.translation` resources 
registered in Project Settings). Voice audio goes through **translation remaps** (Project
Settings > Localization > Remaps): so just point the runner at your base-language
folder with `set_audio_base_path()` and Godot substitutes the right file
per locale on load. It's awesome.

- `set_audio_path_template("...{locale}/")` is replaced by
  `set_audio_base_path("res://.../audio/en/")` — the `{locale}` folder
  templating no longer exists.
- Live locale switching works! The lookup bypasses Godot's resource cache
  (which pins a remapped resource to its first-loaded locale) and keeps
  its own per-locale cache

### Voice presenter slimmed

`YarnVoiceOverPresenter` no longer keeps its own audio cache:
`max_cache_size`, `set_audio_for_line()` and `clear_cache()` are gone,
along with its `prepare_for_lines` pre-loading. The localisation layer
caches runner-provided audio, and Godot's own resource cache covers the
fallback path. Inspector tooltips across the addon also no longer cite
what Yarn Spinner for Unity does; they just say what the property does.

### Presenters must be listed

Child auto-discovery is gone. The runner uses exactly what is in its
Presenters array, plus anything registered at runtime with
`add_presenter()` (which is how `YarnDialogueView` registers its two).
A runner with an empty array and presenter children logs a warning naming
the first one, so a scene relying on the old discovery tells you what to
fix.

### YarnDialogueView

- Visuals now come from `ui/dialogue_view_ui.tscn` via the new `ui_scene` export,
  swap in your own scene to reskin or do other funky stuff.
- `start_node` defaults to empty, meaning "use the runner's Start Node";
  set it only to override. `auto_start` is ignored when the runner's own
  Auto Start is on. People got confused by this, sorry.

### New API

- `YarnPromise` — a completion object (`settle()` / `await wait()`);
  settlement is remembered, so late awaiters can't lose it. It's a bit
  like a Promise from other languages. Best we can do, anyway.
- `YarnCancellationToken.wait_for_next_content()` — await for
  coroutine presenters.
- `YarnAsync.wait(node, seconds)` — pause-respecting timer.
- `runner.are_options_active()`, `runner.get_presenters()`.
- `line_dismissed` signal on `YarnLinePresenter`.
- Presenter children added to the runner after startup are now discovered.

### Fixed

- Lost-completion hangs... the runner joins presenters through
  promises, so completion order can never strand the dialogue. Sorry.
- `show_selected_option_as_line` soft-locked dialogue after the first
  choice; synchronous option selection could skip the echoed line.
- `option_timeout` with fallthrough disabled stopped dialogue with an error
  instead of faling through.
- A force-advanced async command could end the wrong line later
  (epoch guards now cover commands as well as lines)...
- The built-in options presenter ignored its token: buttons survived
  timeouts and rival selections; it now winds down and returns -1.
- A presenter freed mid-line hung dialogue permanently; it now counts as
  finishedd
- External `select_option()` calls now route through the active options
  round instead of desyncing it
- Voice-over fallback paths strip the `line:` prefix when deriving
  filenames, matching the localisation resolver

## Earlier alphas

See git history.
