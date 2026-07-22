# Yarn Spinner for Godot (GDScript) — Changelog

## Alpha 7 (2026-07-22)

This alpha reworks how presenters and the dialogue runner talk to each
other! If you implemented presenters or commands against an earlier alpha,
read the Breaking changes, please! Most migrations _should_ be signature change and the
deletion of boilerplate. Hopefully.

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

- `request_next` on `YarnLinePresenter` dismisses the line even mid-reveal
  (so, like Yarn Spinner for Unity). Two-stage "reveal, then advance" lives in
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

### Presenter discovery: explicit list wins

If the runner's Presenters array has entries, only those are used. Child child
auto-discovery still happens, but only when the array is left empty, so you won't get any weird
surprises, hopefully. Nothing weird.

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
