# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

extends Node2D
## Main controller for the Bindings Sample.
##
## This sample demonstrates the YarnBindingLoader system which allows
## visual configuration of Yarn commands and functions in the inspector.
##
## === HOW TO USE THE INSPECTOR (Recommended) ===
##
## In a real project, you would configure bindings visually:
##
## 1. Select the YarnBindingLoader node in the Scene tree
## 2. In the Inspector, find the "Bindings" array property
## 3. Click "Add Element" to add a new binding
## 4. Configure each binding:
##
##    Example Command Binding:
##      Yarn Name: shake
##      Type: COMMAND
##      Target Node: ../Camera2D
##      Method Name: shake
##      Description: Shakes the camera
##
##    Example Function Binding:
##      Yarn Name: player_health
##      Type: FUNCTION
##      Target Node: ../Player
##      Method Name: get_health
##      Parameter Count: 0
##      Description: Returns player's current health
##
## This sample uses code to set up bindings because .tscn files
## can't easily store Resource arrays. In your project, use the inspector!


@onready var dialogue_runner: YarnDialogueRunner = $YarnDialogueRunner
@onready var binding_loader: YarnBindingLoader = $YarnBindingLoader
@onready var player: Node = $Player
@onready var camera: Camera2D = $Camera2D
@onready var screen_effects: ColorRect = $UILayer/ScreenEffects
@onready var line_presenter: YarnLinePresenter = $UILayer/LinePresenter
@onready var options_presenter: YarnOptionsPresenter = $UILayer/OptionsPresenter
@onready var status_label: Label = $UILayer/UI/StatusPanel/StatusLabel
@onready var start_button: Button = $UILayer/UI/StartButton
@onready var restart_button: Button = $UILayer/UI/RestartButton


func _ready() -> void:
	# Add presenters to dialogue runner (they're in UILayer for proper rendering)
	dialogue_runner.add_presenter(line_presenter)
	dialogue_runner.add_presenter(options_presenter)

	# Set up bindings programmatically (in your project, use the inspector instead!)
	_setup_bindings()

	start_button.pressed.connect(_on_start_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	dialogue_runner.dialogue_completed.connect(_on_dialogue_completed)

	# Listen for binding events
	binding_loader.bindings_registered.connect(_on_bindings_registered)
	binding_loader.binding_failed.connect(_on_binding_failed)

	restart_button.visible = false
	_update_status()


## Sets up all Yarn bindings programmatically.
## In a real project, you'd configure these in the inspector instead!
func _setup_bindings() -> void:
	# Disable auto-register since we're adding bindings manually first
	binding_loader.auto_register = false

	# === PLAYER COMMANDS (actions) ===
	# These modify game state when called from Yarn

	# <<give_item "item_name">> - Adds an item to inventory
	binding_loader.add_binding(
		"give_item",
		YarnCommandBinding.Type.COMMAND,
		player,
		"add_item"
	)

	# <<heal amount>> - Modifies player's health (syncs with Yarn $health variable)
	binding_loader.add_binding(
		"heal",
		YarnCommandBinding.Type.COMMAND,
		player,
		"modify_health"
	)

	# === CAMERA COMMANDS (some async - dialogue waits) ===

	# <<shake intensity>> - Shakes camera (non-blocking)
	binding_loader.add_binding(
		"shake",
		YarnCommandBinding.Type.COMMAND,
		camera,
		"shake"
	)

	# <<shake_and_wait intensity duration>> - Shakes camera (blocking - dialogue waits)
	binding_loader.add_binding(
		"shake_and_wait",
		YarnCommandBinding.Type.COMMAND,
		camera,
		"shake_and_wait"
	)

	# <<zoom level duration>> - Zooms camera (blocking)
	binding_loader.add_binding(
		"zoom",
		YarnCommandBinding.Type.COMMAND,
		camera,
		"zoom_to"
	)

	# === SCREEN EFFECT COMMANDS (async - dialogue waits) ===

	# <<fade_out duration>> - Fades to black
	binding_loader.add_binding(
		"fade_out",
		YarnCommandBinding.Type.COMMAND,
		screen_effects,
		"fade_out"
	)

	# <<fade_in duration>> - Fades from black
	binding_loader.add_binding(
		"fade_in",
		YarnCommandBinding.Type.COMMAND,
		screen_effects,
		"fade_in"
	)

	# <<flash color duration>> - Flashes the screen
	binding_loader.add_binding(
		"flash",
		YarnCommandBinding.Type.COMMAND,
		screen_effects,
		"flash"
	)

	# Now register all bindings
	binding_loader.register_all()


func _on_start_pressed() -> void:
	start_button.visible = false
	dialogue_runner.start_dialogue("Start")


func _on_restart_pressed() -> void:
	# Reset all game state
	player.reset()
	$Camera2D.reset()

	restart_button.visible = false
	start_button.visible = true
	_update_status()


func _on_dialogue_completed() -> void:
	restart_button.visible = true
	_update_status()


func _on_bindings_registered() -> void:
	print("=== Bindings Sample ===")
	print(binding_loader.get_debug_info())


func _on_binding_failed(binding: YarnCommandBinding, reason: String) -> void:
	push_error("Binding failed: %s - %s" % [binding.yarn_name, reason])


func _process(_delta: float) -> void:
	if dialogue_runner.is_running():
		_update_status()


func _update_status() -> void:
	# Read state from Yarn variables (which the dialogue updates via <<set>>)
	var yarn_health: int = 100
	var yarn_gold: int = 50
	var storage := dialogue_runner.variable_storage
	if storage:
		yarn_health = int(storage.get_value("$health"))
		yarn_gold = int(storage.get_value("$gold"))

	var lines := PackedStringArray()
	lines.append("Health: %d/100" % yarn_health)
	lines.append("Gold: %d" % yarn_gold)
	lines.append("Inventory: %s" % (", ".join(player.inventory) if player.inventory.size() > 0 else "(empty)"))
	status_label.text = "\n".join(lines)
