# Quickstart

This gets you from zero to running dialogue in about five minutes. It assumes you already know how to write Yarn, and how to use Godot.

> [!IMPORTANT]
> To get Yarn Spinner for Godot (GDScript), and support the team behind it, buy a copy for Godot from the Yarn Spinner Itch.io Store or from the Godot Asset Store (coming soon), or check out the Yarn Spinner Documentation to install other ways.

> [!TIP]
> **Please submit support or feature requests via this form during Early Access:** http://yarnspinner.dev/pre-release-feedback

Visit the [documentation](https://yarnspinner.dev/docs/) and [Yarn Spinner site](https://yarnspinner.dev) for more information.

## Install the Plugin

1. Clone or download [YarnSpinner-Godot-GDScript](https://github.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript). The addon is the `addons/yarn_spinner/` folder inside it.
2. Copy that folder into your Godot project's `addons/` directory, so the plugin config is at `res://addons/yarn_spinner/plugin.cfg`. Don't copy the whole repository in; that nests the addon one level too deep.
3. Go to **Project > Project Settings > Plugins** and enable **Yarn Spinner**.

## Add Your Yarn Files

Make sure you have a `.yarnproject` and your `.yarn` files, then drop them into your Godot project. The `.yarnproject` tells the compiler which `.yarn` files to include.

### Automatic compilation

Compilation is automatic and needs no setup: the addon bundles the Yarn
Spinner compiler as a native binary (`addons/yarn_spinner/native/bin/`),
so there's nothing to install. Whenever Godot imports or reimports the
`.yarnproject`, the plugin compiles all `.yarn` files in scope. Editing a
`.yarn` file or the `.yarnproject` itself triggers a reimport, so you
never need to compile manually.

If the bundled binary isn't available for your platform, the plugin falls
back to the `ysc` command line tool. Install the required version globally
with:

```
dotnet tool install YarnSpinner.Console --global --version 3.2.2
```

### Manual compilation

If `ysc` isn't on your PATH, you can compile manually:

```
ysc compile your_project.yarnproject
```

You can also set the path to `ysc` in the import options for the `.yarnproject` file in the Godot inspector, or in **Project Settings > Yarn Spinner > YSC Path**.

## Set Up the Scene

Here's a minimal scene tree exmple:

```
Game (Node2D)
├── YarnDialogueRunner (Node)
├── CanvasLayer
│   ├── LinePresenter (PanelContainer)
│   │   └── VBoxContainer
│   │       ├── CharacterLabel (Label)
│   │       ├── TextLabel (RichTextLabel)
│   │       └── ContinueIndicator (Label)
│   └── OptionsPresenter (PanelContainer)
│       └── OptionsContainer (VBoxContainer)
```

1. **YarnDialogueRunner** -- add a Node, attach the `YarnDialogueRunner` script (`addons/yarn_spinner/dialogue_runner.gd`). In the inspector, set `Yarn Project` to your `.yarnproject` file.

2. **LinePresenter** -- add a PanelContainer, attach the `YarnLinePresenter` script (`addons/yarn_spinner/ui/line_presenter.gd`). Give it a `RichTextLabel` child named `TextLabel` for dialogue text, a `Label` named `CharacterLabel` for the speaker name, and optionally a `Label` named `ContinueIndicator`.

3. **OptionsPresenter** -- add a PanelContainer, attach the `YarnOptionsPresenter` script (`addons/yarn_spinner/ui/options_presenter.gd`). Give it a `VBoxContainer` child named `OptionsContainer` -- buttons are created automatically at runtime.

The ready-made presenter scripts all live in `addons/yarn_spinner/ui/`. The `dialogue_presenter.gd` at the addon's root is the abstract base class you subclass to write a custom presenter; it can't be attached to a node directly.

## Wire It Up

In your game script, connect the presenters to the runner and start dialogue:

```gdscript
extends Node2D

@onready var dialogue_runner := $YarnDialogueRunner
@onready var line_presenter := $CanvasLayer/LinePresenter
@onready var options_presenter := $CanvasLayer/OptionsPresenter

func _ready():
	dialogue_runner.add_presenter(line_presenter)
	dialogue_runner.add_presenter(options_presenter)
	dialogue_runner.start_dialogue("Start")
```

That's it. Run the scene and your dialogue plays.

## Commands

Commands let Yarn tell your game to do things. The easiest way is the naming convention -- prefix any method with `_yarn_command_` and the runner finds it automatically. The runner looks in scripts with a `class_name`, scripts attached to nodes in the running scene, and autoloads.

Whether the method is `static` decides how you call it from Yarn.

### Static Commands

A `static` method is a command you can call from anywhere, with just its arguments:

```gdscript
static func _yarn_command_shake(intensity: float) -> void:
	# <<shake 2.5>>
	CameraRig.shake(intensity)
```

Methods on an autoload work the same way, `static` or not.

### Commands on a Node

A method that isn't `static` belongs to a node. In Yarn, the first argument is the name of the node to call it on:

```gdscript
# Character.gd, attached to a node called Mae
extends Node2D

func _yarn_command_move(x: float, y: float) -> Signal:
	# <<move Mae 700 400>>
	var tween := create_tween()
	tween.tween_property(self, "position", Vector2(x, y), 1.0)
	return tween.finished
```

The runner looks for a node called `Mae` anywhere in the running game, checks it has the script, and calls `_yarn_command_move(700, 400)` on it. Writing `<<move 700 400>>` without the node name won't work: the runner reads `700` as the node's name.

Make sure `auto_discover_commands` is enabled on the dialogue runner (it is by default).

If a command returns `void`, dialogue continues immediately. If it returns a `Signal`, or uses `await`, dialogue pauses until it finishes.

### Adding Commands from Code

To use any name and any method, add the command to the runner yourself:

```gdscript
func _ready():
	dialogue_runner.add_command("give_item", _give_item)

func _give_item(item_name: String, count: int) -> void:
	# <<give_item "brass key" 1>>
	Inventory.add(item_name, count)
```

`<<wait>>` and `<<stop>>` are built in, so don't use those names for your own commands.

## Functions

Functions let Yarn read values from your game. Register them with a name and parameter count:

```gdscript
func _ready():
	dialogue_runner.add_function("player_health", _get_health, 0)
	dialogue_runner.add_function("has_item", _check_item, 1)

func _get_health() -> float:
	return player.health

func _check_item(item_name: String) -> bool:
	return inventory.has(item_name)
```

Use them in Yarn expressions:

```yarn
<<if player_health() < 50>>
	You're not looking so good.
<<endif>>

<<if has_item("key")>>
	The door opens.
<<endif>>

You have {format("{0}", player_health())} health remaining.
```

Or use the naming convention with `_yarn_function_` prefix for auto-discovery.

## Variables

Yarn variables work automatically. Declare them in your `.yarn` files and they're stored in an in-memory dictionary:

```yarn
<<declare $coins = 0>>
<<declare $player_name = "Adventurer">>
<<declare $has_sword = false>>

<<set $coins = $coins + 50>>
Welcome, {$player_name}! You have {$coins} coins.
```

Access them from GDScript:

```gdscript
var coins = dialogue_runner.variable_storage.get_value("$coins")
dialogue_runner.variable_storage.set_value("$player_name", "Hero")
```

The runner creates a `YarnInMemoryVariableStorage` automatically. If you need persistence, subclass `YarnVariableStorage` and assign it in the inspector.

## Signals

The dialogue runner emits signals for lifecycle events:

```gdscript
dialogue_runner.dialogue_started.connect(func(): show_dialogue_ui())
dialogue_runner.dialogue_completed.connect(func(): hide_dialogue_ui())
dialogue_runner.node_started.connect(func(name): print("Entered: ", name))
dialogue_runner.node_completed.connect(func(name): print("Left: ", name))
dialogue_runner.command_unhandled.connect(func(text): print("Unknown: ", text))
```

## Useful Settings

On the `YarnDialogueRunner` in the inspector:

- **Start Node** -- which Yarn node to begin from (default: `"Start"`)
- **Auto Start** -- begin dialogue when the scene loads
- **Run Selected Option As Line** -- after the player picks an option, show it as a line of dialogue before continuing
- **Auto Discover Commands** -- scan the scene tree for `_yarn_command_*` and `_yarn_function_*` methods

On `YarnLinePresenter`:

- **Typewriter Mode** -- `INSTANT`, `LETTER` (character by character), or `WORD`
- **Characters Per Second** / **Words Per Second** -- typewriter speed
- **Auto Advance** -- automatically continue after a delay
- **Use Markup** -- enable BBCode rendering in the text label

On `YarnOptionsPresenter`:

- **Hide Unavailable** -- hide options the player can't pick (vs showing them greyed out)

## Custom Presenters

To make your own presenter UI, subclass `YarnDialoguePresenter`. `run_line`
returns nothing: hold the line open by awaiting inside it, and return when
the line is done. The token tells you when the player wants to hurry up or
skip.

```gdscript
extends YarnDialoguePresenter

func run_line(line: YarnLine, token: YarnCancellationToken = null) -> void:
	$Label.text = line.get_plain_text()
	visible = true
	# Wait for player to click (or the runner asking us to move on)
	await $Button.pressed
	visible = false

func run_options(options: Array[YarnOption], token: YarnCancellationToken = null) -> int:
	# Build your own UI, return the index of the selected option
	for i in options.size():
		var btn = Button.new()
		btn.text = options[i].get_plain_text()
		btn.pressed.connect(func(): selected = i)
		$Container.add_child(btn)
	await $Container.get_child(0).pressed  # Simplified
	return selected
```

Register it the same way:

```gdscript
dialogue_runner.add_presenter(my_custom_presenter)
```

## Node Groups and Saliency

If you're using node groups (multiple versions of the same content with `when:` conditions), choose how the runner picks between them with its **Saliency Strategy** property in the inspector: `RANDOM_BEST_LEAST_RECENT` (the default), `BEST_LEAST_RECENT`, `BEST`, `FIRST` or `RANDOM`.

To use your own strategy, extend `YarnSaliencyStrategy` and set it from code:

```gdscript
dialogue_runner.set_content_saliency_strategy(MySaliencyStrategy.new())
```

## VS Code Autocomplete

The plugin generates a `.ysls.json` file next to each `.yarnproject` for the next version of the Yarn Spinner for Visual Studio Code Extension to know about your commands and functions. This happens automatically when you save `.gd` files. 
