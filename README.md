# Yarn Spinner for Godot (GDScript)

> [!NOTE]
> This is Yarn Spinner for Godot (GDScript) Early Access 3.3.

Yarn Spinner for Godot (GDScript) is a pure-GDScript implementation of the Yarn Spinner dialogue system for the Godot engine. It runs compiled Yarn programs, with support for node groups, saliency, detours, smart variables, localisation, and voice over.

Requires Godot 4.6 or later (not the .NET/Mono version).

> [!IMPORTANT]
> Yarn Spinner+ for Godot (GDScript) is available to buy at [yarnspinner.dev/godot](https://yarnspinner.dev/godot). It comes with the Classic RPG and Snaaake dialogue presenters, plus priority email support, and buying it supports the team behind Yarn Spinner. Yarn Spinner for Godot (GDScript) will always be available here for free, too. You can also support us on [GitHub Sponsors](https://github.com/sponsors/YarnSpinnerTool) or [Patreon](https://patreon.com/secretlab).

Visit the [documentation](https://yarnspinner.dev/docs/godot/gdscript/) and [Yarn Spinner site](https://yarnspinner.dev) for more information. New to Yarn itself? Start with [Writing Yarn](https://yarnspinner.dev/docs/yarn/). For a five minute setup, see [QUICKSTART.md](QUICKSTART.md). To compare the free version with Yarn Spinner+, see [What each version includes](https://yarnspinner.dev/docs/godot/gdscript/01-installation/#what-each-version-includes).

> [!TIP]
> **Please submit bug reports and feature requests here:** https://github.com/YarnSpinnerTool/IssuesDiscussion/issues

## Samples

The samples live in their own project in the [YarnSpinner-Godot-Samples](https://github.com/YarnSpinnerTool/YarnSpinner-Godot-Samples) repository. 

The samples project ships without this addon: copy this repository's `addons/yarn_spinner/` folder into the samples project's `addons/` directory first (the samples README has step-by-step instructions), then open the project in Godot 4.6+, open the scene for the sample you want, and run it with "Run Current Scene" (F6). The [Samples](https://yarnspinner.dev/docs/godot/gdscript/07-samples/) docs walk through each one.

## Differences from Yarn Spinner for Godot (C#)

Yarn Spinner for Godot (C#) uses the core Yarn Spinner C# library directly. 

It requires the .NET-enabled build of Godot, a `.csproj`/`.sln`, and compiles Yarn scripts inside the editor via a C# import plugin. 

This GDScript version is a complete reimplementation of the Yarn Spinner runtime in pure GDScript, with no .NET dependency, no DLLs, no C# project needed. It works with the standard (non-.NET) Godot editor and export templates, making it accessible to GDScript-only projects. 

Yarn scripts are compiled with the Yarn Spinner compiler bundled with the addon (with `ysc` as a fallback), and both versions produce identical runtime behaviour from the same `.yarn` source files.

## Good to know

- **Culture** -- `string()`, `number()`, `bool()` and `format()` always use the invariant culture, so `string(3.5)` is `3.5` on every device.
- **Extra built-in functions** -- As well as Yarn Spinner's built-in functions, this implementation provides `abs`, `clamp`, `lerp`, `inverse_lerp`, `smoothstep`, `pow`, `sqrt`, `sign`, `wrap`, `mod`, `length`, `uppercase`, `lowercase`, `first_letter_caps`, `plural` and `ordinal`. Other Yarn Spinner runtimes don't have these, so scripts that call them won't run there unless you register matching functions.
- **Execution limits** -- The virtual machine can optionally stop runaway scripts with `max_instructions_per_step` and `max_call_stack_depth`. Both are off by default.

## License

This project uses the Yarn Spinner Public License. You're free to use it in your own projects, commercial or otherwise. The only restrictions are around redistributing it as part of a competing dialogue tool, and using it to train AI models. Full details are in [LICENSE.md](LICENSE.md). For a plain-language summary of the license terms and the intent behind its use, see the [YSPL FAQ](https://yarnspinner.dev/yspl).

## Installation

The addon is the `addons/yarn_spinner/` folder inside this repository. That folder is the only part that goes into your project; the rest of the repository (tests, compiler sources, this file) stays behind.

1. Clone or download this repository.
2. Copy `addons/yarn_spinner/` into your Godot project's `addons/` directory, or symlink it from your checkout. The result should be `res://addons/yarn_spinner/plugin.cfg` in your project.
3. In the Godot editor, go to **Project > Project Settings > Plugins** and enable **Yarn Spinner**.
4. Drop your `.yarnproject` and `.yarn` files into your Godot project. The plugin compiles them automatically on import using its bundled compiler -- any time a `.yarn` file or the `.yarnproject` changes, Godot reimports and recompiles. No separate install is needed.
5. Only if the bundled compiler isn't available for your platform: install `ysc` (the [Yarn Spinner Console](https://github.com/YarnSpinnerTool/YarnSpinner-Console) tool) as a fallback with `dotnet tool install YarnSpinner.Console --global --version 3.2.2`.
6. Assign the imported `.yarnproject` to a Dialogue Runner in your scene.

If Godot reports missing dependencies on `res://addons/yarn_spinner/...` paths, or scripts fail to parse with `Could not find type "YarnDialogueRunner"`, the addon isn't at the path the project expects. The usual cause is copying the whole repository into `addons/`, which puts the addon at `addons/YarnSpinner-Godot-GDScript/addons/yarn_spinner`. Move the inner `yarn_spinner` folder so it sits directly under `addons/`, then reload the project.

Full instructions are in [Installation](https://yarnspinner.dev/docs/godot/gdscript/01-installation/), including [turning on the plugin](https://yarnspinner.dev/docs/godot/gdscript/01-installation/#turning-on-the-plugin), [the compiler](https://yarnspinner.dev/docs/godot/gdscript/01-installation/#the-compiler) and [what to do if something's not right](https://yarnspinner.dev/docs/godot/gdscript/01-installation/#if-somethings-not-right). For setting up Yarn Projects, see [Setting Up Your Godot Project](https://yarnspinner.dev/docs/godot/gdscript/03-setting-up-your-godot-project/).

## How It Works

The Yarn Spinner compiler (bundled with the addon, or `ysc`) compiles `.yarn` scripts into a binary protobuf program. This plugin reads that binary at import time, parses it into an in-memory program representation, and executes it in a stack-based virtual machine. The VM handles control flow, variable storage, function calls, and content delivery. A dialogue runner orchestrates the VM and routes lines, options, and commands to presenter nodes in your scene tree.

You write dialogue in Yarn, and the plugin compiles and runs it. Compilation happens automatically when Godot imports the `.yarnproject` file, using the compiler binary bundled with the addon (or `ysc` from your PATH as a fallback). See [Understanding Yarn Spinner](https://yarnspinner.dev/docs/godot/gdscript/02-understanding-yarn-spinner/), [Yarn Projects](https://yarnspinner.dev/docs/godot/gdscript/03-setting-up-your-godot-project/01-yarn-projects/) and [Importing Yarn Files](https://yarnspinner.dev/docs/godot/gdscript/03-setting-up-your-godot-project/02-importing-yarn-files/).

## Architecture

The plugin has three layers:

**Core** (`addons/yarn_spinner/core/`) contains the runtime engine. The protobuf parser reads compiled `.yarnproject` binaries. The virtual machine executes instructions. The yarn library provides built-in functions and operators. Variable storage holds game state. The line provider resolves localised text and applies markup. The saliency system selects content when multiple candidates match.

**Dialogue Runner** (`addons/yarn_spinner/dialogue_runner.gd`) is the main node you add to your scene. It owns the VM, discovers commands from your scene tree, coordinates presenters, and exposes signals for dialogue lifecycle events. All configuration is done through its exported properties in the inspector.

**Presenters** (`addons/yarn_spinner/ui/`) display content to the player. The line presenter shows dialogue text with typewriter effects. The options presenter shows choice buttons. The voice over presenter plays audio files synced to lines. You can subclass `YarnDialoguePresenter` to build your own.

## Components

### YarnDialogueRunner

The central node. Add it to your scene, assign a `.yarnproject`, and call `start_dialogue()`. Key properties:

- `yarn_project` -- the compiled Yarn project to run
- `start_node` -- which node to begin from (default: `"Start"`)
- `auto_start` -- start dialogue when the scene loads
- `variable_storage` -- where game state is stored (auto-created if not set)
- `saliency_strategy` -- how to pick between competing content candidates
- `show_selected_option_as_line` -- re-display the chosen option as a line of dialogue
- `auto_discover_commands` -- find `_yarn_command_*` methods in your scene automatically

Signals: `dialogue_started`, `dialogue_completed`, `dialogue_cancelled`, `node_started`, `node_completed`, `command_unhandled`, `command_received`.

See [Dialogue Runner](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/01-dialogue-runner/).

To choose a Yarn node from a dropdown on your own scripts, export a `String` with the `yarn_node` hint, naming the property that holds the Dialogue Runner or Yarn Project:

```gdscript
@export var dialogue_runner: YarnDialogueRunner
@export_custom(PROPERTY_HINT_NONE, "yarn_node:dialogue_runner") var start_at: String
```

### YarnLinePresenter

Displays a line of dialogue with optional typewriter animation (letter-by-letter or word-by-word). Expects a `RichTextLabel` for text and an optional `Label` for character names. Shows a continue indicator when the line is fully revealed. See [Line Presenter](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/02-line-presenter/), [Typewriter and Effects](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/04-typewriter-and-effects/) and [Markup](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/05-markup/).

### YarnOptionsPresenter

Shows dialogue choices as buttons. Creates a button per option, handles keyboard and mouse selection, and can hide or disable unavailable options. See [Options Presenter](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/03-options-presenter/).

### YarnDialoguePresenter

Base class for custom presenters. Override `run_line()` to handle lines and `run_options()` to handle choices. Multiple presenters can be active at once -- the runner coordinates them. See [Building Your Own Presenter](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/07-building-your-own-presenter/), [A Different Kind of Presenter](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/08-a-different-kind-of-presenter/) and [Async and Cancellation](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/08-async-and-cancellation/). For voice-over, see [Voice-Over](https://yarnspinner.dev/docs/godot/gdscript/04-showing-dialogue/06-voice-over/).

### YarnVariableStorage

Base class for game state storage. The built-in `YarnInMemoryVariableStorage` stores variables in a dictionary. Subclass it to save to disk or sync with your game systems. Supports typed access (`get_float`, `get_bool`, `get_string`) and change subscriptions with automatic cleanup. See [Variables and Storage](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/04-variables-and-storage/) and [Smart Variables](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/05-smart-variables/).

### Custom Commands

Define commands in your scripts by naming methods `_yarn_command_<name>`. The runner discovers them automatically. Return a `Signal` to make the runner wait for it before continuing.

A `static` method is called with just its arguments. A method that isn't `static` belongs to a node, so its first argument in Yarn is the name of the node to call it on. Methods on autoloads are called with just their arguments, `static` or not.

```gdscript
static func _yarn_command_shake(intensity: float) -> void:
    # called from Yarn: <<shake 2.5>>
    pass

# On a script attached to a node called Door
func _yarn_command_fade(duration: float) -> Signal:
    # called from Yarn: <<fade Door 0.5>>
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, duration)
    return tween.finished
```

See [Commands](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/01-commands/), [Functions](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/02-functions/) and [Putting It Together](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/03-putting-it-together/). For choosing between node group variants, see [Saliency and Storylets](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/06-saliency-and-storylets/) and [Custom Saliency Strategies](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/07-custom-saliency-strategies/).

### Localisation

Localisation uses Godot's `TranslationServer`. Export your Yarn strings to CSV, translate them, and import them through Godot's standard localisation workflow (Project Settings > Localization > Translations). Set the `translation_prefix` on the dialogue runner to control the key prefix (default: `"YARN_"`). See [Localising Your Game](https://yarnspinner.dev/docs/godot/gdscript/06-localisation-and-assets/01-localising-your-game/) and [Line and Asset Providers](https://yarnspinner.dev/docs/godot/gdscript/06-localisation-and-assets/02-line-and-asset-providers/).
