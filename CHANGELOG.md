# Yarn Spinner for Godot (GDScript) — Changelog

## Alpha 9 (in progress)

### Strict warning compatibility

A handful of internal variable declarations relied on inferring their type
from a `Variant` value, which fails to compile in projects that escalate
GDScript's `INFERENCE_ON_VARIANT` warning to an error. Those declarations
now use explicit types, so the addon compiles cleanly under strict warning
settings.

### Sample gallery ordering and thumbnails

The Samples tab in the Yarn Spinner editor screen now lists samples in a
learning-path order (starting points first, then core features,
presentation, voice over, and saliency) instead of alphabetically, and
every sample card has an up-to-date gameplay screenshot.

### YarnDialoguePresenter is abstract

`YarnDialoguePresenter` is now marked `@abstract`, matching its Yarn Spinner for Unity
equivalent (`DialoguePresenterBase`). Attaching the base script to a node
used to look like it worked, then displayed nothing at runtime; the editor
now refuses the attach outright. Attach one of the presenters from
`addons/yarn_spinner/ui/` (`YarnLinePresenter`, `YarnOptionsPresenter`,
and friends), or subclass the base for your own. Existing subclasses are
unaffected!

### Changed

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

### Fixed

- `[plural]` and `[ordinal]` markup now follows the active locale. The
  line's locale was being set after its text had already been parsed, so
  every line used English plural and ordinal rules regardless of what
  `set_locale()` was called with.
- Option text now processes `select`, `plural`, and `ordinal` markup, the
  same as lines do. These markers in an option used to be stripped to
  nothing by the display path.
- Modulo by zero now stops the dialogue with a clear error instead of
  returning 0. Note the divisor converts to an integer first, so a
  divisor smaller than 1 also counts as zero.
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
