# Yarn Spinner for Godot (GDScript)

> [!CAUTION]
> This is an Alpha release of Yarn Spinner for Godot (GDScript). There will be bugs, we might change the API or features with an update, or something may break. We do not recommend you use this to ship a game just yet. 

Yarn Spinner for Godot (GDScript) is a pure-GDScript implementation of the Yarn Spinner dialogue system for the Godot engine. It runs compiled Yarn programs and aims for full feature parity with Yarn Spinner for Unity 3.1, including node groups, saliency, detours, smart variables, localisation, and voice over support.

Requires Godot 4.6 or later (not the .NET/Mono version).

> [!IMPORTANT]
> Yarn Spinner for Godot (GDScript) is not yet for sale (it will always be available here for free, too). We rely on your support to keep everything free and accessible. If you want to support us during the Alpha period, you can support us on [GitHub Sponsors](https://github.com/sponsors/YarnSpinnerTool) or [Patreon](https://patreon.com/secretlab). GitHub sponsors of $25 and above, and Patreon members of the "Scribe" or above tier will receive a license to the paid version when it is released.

Visit the [documentation](https://docs.yarnspinner.dev/yar-spinner-for-godot/godot-gdscript) and [Yarn Spinner site](https://yarnspiner.dev) for more information.

> [!TIP]
> **Please submit issues or feature requests via this form during the pre-release period:** http://yarnspinner.dev/pre-release-feedback

## Samples

We only have a few Samples in the Alpha period. To try them, open `project.godot` in your installation of Godot 4.6+, then open the Scene for the sample you want to try, and run it with the "Run Current Scene" (F6) button. The included samples are:

- **Yarn Basics** -- An interactive tour of Yarn language features: variables, conditionals, options, jumps, detours, commands, functions, once statements, and markup. Focuses on the Yarn language itself rather than GDScript integration.
- **Voice Over** -- Demonstrates voice acting playback synced with dialogue, with localisation across four languages (English, German, Chinese, Portuguese). Uses Godot's TranslationServer and supports live language switching during dialogue.
- **Commands and Functions** -- Demonstrates registering custom Yarn commands and functions using the `YarnBindingLoader` system. Binds game actions (camera shake, screen fade, inventory, health) to Yarn commands so they can be called from dialogue scripts.
- **Instance Commands** -- Shows how to call methods on specific scene nodes from Yarn using instance commands. Characters define `_yarn_command_*` methods, and Yarn scripts target them by name (e.g. `<<move mae center>>`). Supports both instant and async (dialogue-blocking) commands.

The intention is that Yarn Spinner for Godot (C#) and Godot (GDScript) will ship with a full suite of samples on par with the samples supplied as part of Yarn Spinner for Unity.

## Differences from Yarn Spinner for Godot (C#)

Yarn Spinner for Godot (C#) is a port of Yarn Spinner for Unity that uses the core Yarn Spinner C# library directly. 

It requires the .NET-enabled build of Godot, a `.csproj`/`.sln`, and compiles Yarn scripts inside the editor via a C# import plugin. 

This GDScript version is a complete reimplementation of the Yarn Spinner runtime in pure GDScript, with no .NET dependency, no DLLs, no C# project needed. It works with the standard (non-.NET) Godot editor and export templates, making it accessible to GDScript-only projects. 

Yarn scripts are compiled externally with `ysc` and both versions produce identical runtime behaviour from the same `.yarn` source files.

## Differences from Yarn Spinner for Unity

The VM, protobuf parser, library, and markup system were all written to match Unity's behaviour, but there are some differences:

- **CLDR plural rules** -- This implementation has rules covering the top ~20 languages (English, French, German, Spanish, Russian, Arabic, Polish, Czech, Japanese, Korean, Chinese, etc.). If you're using `[plural]` or `[ordinal]` markup tags with a less common language, you might get the default "one/other" fallback instead of the correct plural form.
- **No Unicode NFC normalisation** -- Unity normalises markup input text to NFC (composed) form before parsing. Godot doesn't have a built-in NFC normaliser, so precomposed and decomposed Unicode characters are treated as-is. This only matters if your Yarn scripts contain combining characters like `e` + `\u0301` instead of `é`.
- **Async model** -- Unity uses C# `async`/`await` with `YarnTask` and `CancellationTokenSource` chains. This implementation uses Godot signals and `await` with a simpler `YarnCancellationToken`. The behaviour is largely the same, but the presenter API signatures are different (signals instead of tasks).
- **Command discovery** -- Unity uses `[YarnCommand]` attributes on methods. This implementation uses a naming convention (`_yarn_command_<name>`) and scene tree scanning. Both approaches auto-discover commands, just with different syntax.
- **Error handling** -- Unity throws exceptions for invalid states (missing variables, bad option indices, etc.). This implementation uses `push_error`/`push_warning` and continues where possible, which is more idiomatic for GDScript.
- **Localisation** -- Unity has multiple line provider backends (built-in, Unity Localization package, Addressables). This implementation uses Godot's `TranslationServer` directly.

## License

This project uses the Yarn Spinner Public License. You're free to use it in your own projects, commercial or otherwise. The only restrictions are around redistributing it as part of a competing dialogue tool, and using it to train AI models. Full details are in [LICENSE.md](LICENSE.md).

## Installation

1. Copy the `addons/yarn_spinner/` folder into your Godot project's `addons/` directory.
2. In the Godot editor, go to **Project > Project Settings > Plugins** and enable **Yarn Spinner**.
3. Install `ysc` (the [Yarn Spinner Console](https://github.com/YarnSpinnerTool/YarnSpinner-Console) tool) from : `dotnet tool install YarnSpinner.Console --global --version 3.1.0-alpha1`
4. Drop your `.yarnproject` and `.yarn` files into your Godot project. The plugin automatically compiles them via `ysc` on import -- any time a `.yarn` file or the `.yarnproject` changes, Godot reimports and recompiles.
5. Assign the imported `.yarnproject` to a Dialogue Runner in your scene.

## How It Works

The Yarn Spinner compiler (`ysc`) compiles `.yarn` scripts into a binary protobuf program. This plugin reads that binary at import time, parses it into an in-memory program representation, and executes it in a stack-based virtual machine. The VM handles control flow, variable storage, function calls, and content delivery. A dialogue runner orchestrates the VM and routes lines, options, and commands to presenter nodes in your scene tree.

You write dialogue in Yarn, and the plugin compiles and runs it. If `ysc` is on your PATH, compilation happens automatically when Godot imports the `.yarnproject` file.

## Architecture

The plugin has three layers:

**Core** (`addons/yarn_spinner/core/`) contains the rntime engine. The protobuf parser reads compiled `.yarnproject` binaries. The virtual machine executes instructions. The yarn library provides built-in functions and operators. Variable storage holds game state. The line provider resolves localised text and applies markup. The saliency system selects content when multiple candidates match

**Dialogue Runner** (`addons/yarn_spinner/dialogue_runner.gd`) is the main node you add to your scene. It owns the VM, discovers commands from your scene tree, coordinates presenters, and exposes signals for dialogue lifecycle events. All configuration is done through its exported properties in the inspector.

**Presenters** (`addons/yarn_spinner/ui/`) display content to the player. The line presenter shows dialogue text with typewriter effects. The options presenter shows choice buttons. The voice over presenter plays audio files synced to lines. You can subclass `YarnDialoguePresenter` to build your own.

## Components

### YarnDialogueRunner

The central node. Add it to your scene, assign a `.yarnproject`, an call `start_dialogue()`. Key properties:

- `yarn_project` -- the compiled Yarn project to run
- `start_node` -- which node to begin from (default: `"Start"`)
- `auto_start` -- start dialogue when the scene loads
- `variable_storage` -- where game state is stored (auto-created if not set)
- `saliency_strategy` -- how to pick between competing content candidates
- `run_selected_option_as_line` -- re-display the chosen option as a line of dialogue
- `auto_discover_commands` -- find `_yarn_command_*` methods in your scene automatically

Signals: `dialogue_started`, `dialogue_completed`, `node_started`, `node_completed`, `unhandled_command`.

### YarnLinePresenter

Displays a line of dialogue with optional typewriter animation (letter-by-letter or word-by-word). Expects a `RichTextLabel` for text and an optional `Label` for character names. Shows a continue indicator when the line is fully revealed.

### YarnOptionsPresenter

Shows dialogue choices as buttons. Creates a button per option, handles keyboard and mouse selection, and can hide or disable unavailable options.

### YarnDialoguePresenter

Base class for custom presenters. Override `run_line()` to handle lines and `run_options()` to handle choices. Multiple presenters can be active at once -- the runner coordinates them.

### YarnVariableStorage

Base class for game state storage. The built-in `YarnInMemoryVariableStorage` stores variables in a dictionary. Subclass it to save to disk or sync with your game systems. Supports typed access (`get_float`, `get_bool`, `get_string`) and change subscriptions with automatic cleanup.

### Custom Commands

Define commands in your scripts by naming methods `_yarn_command_<name>`. The runner discovers them automatically. Return a `Signal` to make the runner wait for it before continuing.

```gdscript
func _yarn_command_shake(intensity: float) -> void:
    # called from Yarn: <<shake 2.5>>
    pass

func _yarn_command_fade(duration: float) -> Signal:
    # async: runner waits for the signal
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, duration)
    return tween.finished
```

### Localisation

Localisation uses Godot's `TranslationServer`. Export your Yarn strings to CSV, translate them, and import them through Godot's standard localisation workflow (Project Settings > Localization > Translations). Set the `translation_prefix` on the dialogue runner to control the key prefix (default: `"YARN_"`).
