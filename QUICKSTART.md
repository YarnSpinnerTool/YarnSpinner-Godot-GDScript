# Quickstart

> [!CAUTION]
> This is an Alpha release of Yarn Spinner for Godot (GDScript). There will be bugs, we might change the API or features with an update, or something may break. We do not recommend you use this to ship a game just yet. 

This gets you from zero to running dialogue in about five minutes. It assumes you already know how to write Yarn, and how to use Godot.

> [!IMPORTANT]
> Yarn Spinner for Godot (GDScript) is not yet for sale (it will always be available here for free, too). We rely on your support to keep everything free and accessible. If you want to support us during the Alpha period, you can support us on [GitHub Sponsors](https://github.com/sponsors/YarnSpinnerTool) or [Patreon](https://patreon.com/secretlab). GitHub sponsors of $25 and above, and Patreon members of the "Scribe" or above tier will receive a license to the paid version when it is released.

## Install the Plugin

1. Copy `addons/yarn_spinner/` into your Godot project's `addons/` directory.
2. Go to **Project > Project Settings > Plugins** and enable **Yarn Spinner**.

## Add Your Yarn Files

Make sure you have a `.yarnproject` and your `.yarn` files, then drop them into your Godot project. The `.yarnproject` tells the compiler which `.yarn` files to include.

### Automatic compilation

If `ysc` (the Yarn Spinner compiler) is on your system PATH, compilation is automatic. Whenever Godot imports or reimports the `.yarnproject`, the plugin runs `ysc compile` for all `.yarn` files in scope. Editing a `.yarn` file or the `.yarnproject` itself triggers a reimport, so you never need to compile manually.

Install the required version of `ysc` globally with:

```
dotnet tool install YarnSpinner.Console --global --version 3.1.0-alpha1`
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

1. **YarnDialogueRunner** -- add a Node, attach the `YarnDialogueRunner` script. In the inspector, set `Yarn Project` to your `.yarnproject` file.

2. **LinePresenter** -- add a PanelContainer, attach the `YarnLinePresenter` script. Give it a `RichTextLabel` child named `TextLabel` for dialogue text, a `Label` named `CharacterLabel` for the speaker name, and optionally a `Label` named `ContinueIndicator`.

3. **OptionsPresenter** -- add a PanelContainer, attach the `YarnOptionsPresenter` script. Give it a `VBoxContainer` child named `OptionsContainer` -- buttons are created automatically at runtime.

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

Commands let Yarn tell your game to do things. The easiest way is the naming convention -- prefix any method with `_yarn_command_` and the runner finds it automatically.

```gdscript
# On any node in your scene tree:

func _yarn_command_shake(intensity: float) -> void:
    # <<shake 2.5>>
    # Runs instantly, dialogue continues immediately
    camera.shake(intensity)

func _yarn_command_fade(duration: float) -> Signal:
    # <<fade 0.5>>
    # Returns a Signal -- dialogue waits for it to complete
    var tween = create_tween()
    tween.tween_property($Overlay, "modulate:a", 1.0, duration)
    return tween.finished

func _yarn_command_wait(seconds: float) -> Signal:
    # <<wait 1.5>>
    return get_tree().create_timer(seconds).timeout
```

Make sure `auto_discover_commands` is enabled on the dialogue runner (it is by default). The runner scans the scene tree on startup and registers everything it finds.

If a command returns `void`, dialogue continues immediately. If it returns a `Signal`, dialogue pauses until that signal fires.

### Instance Commands

For commands that target specific nodes (like `<<move mae center>>`), define the method on the node's class:

```gdscript
class_name Character
extends Node2D

func _yarn_command_move(destination: String) -> Signal:
    var target := get_node("/root/Game/Waypoints/" + destination)
    var tween := create_tween()
    tween.tween_property(self, "position", target.position, 1.0)
    return tween.finished
```

Register the class as an instance command source:

```gdscript
func _ready():
    var library := dialogue_runner.get_library()
    library.register_instance_command("move", Character)
    library.set_target_root(self)
```

Now `<<move mae center>>` finds the node named "mae", checks it's a `Character`, and calls `_yarn_command_move("center")` on it.

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
dialogue_runner.unhandled_command.connect(func(text): print("Unknown: ", text))
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

To make your own persenter UI subclass `YarnDialoguePresenter`:

```gdscript
extends YarnDialoguePresenter

func run_line(line: YarnLine) -> Variant:
    $Label.text = line.get_plain_text()
    visible = true
    # Wait for player to click
    await $Button.pressed
    visible = false
    return null

func run_options(options: Array[YarnOption]) -> int:
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

If you're using node groups (multiple versions of the same content with `when:` conditions), set a saliency strategy on the runner:

```gdscript
dialogue_runner.saliency_strategy = YarnRandomBestLeastRecentlyViewedSaliencyStrategy.new()
```

Available strategies: `YarnFirstSaliencyStrategy`, `YarnBestSaliencyStrategy`, `YarnRandomSaliencyStrategy`, `YarnBestLeastRecentlyViewedSaliencyStrategy`, `YarnRandomBestLeastRecentlyViewedSaliencyStrategy`.

## VS Code Autocomplete

The plugin generates a `.ysls.json` file next to each `.yarnproject` for the next version of the Yarn Spinner for Visual Studio Code Extension to know about your commands and functions. This happens automatically when you save `.gd` files. 
