# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

extends Node
## Sample player node demonstrating methods that can be bound to Yarn functions.
##
## This shows how to create methods that work with YarnBindingLoader
## for both commands (actions) and functions (queries).


## Player's current health.
var health: int = 100

## Player's current gold.
var gold: int = 50

## Items in the player's inventory.
var inventory: Array[String] = []


# === Functions (queries that return values) ===

## Returns the player's current health.
## Bound as: {player_health()} or <<if player_health() < 50>>
func get_health() -> int:
	return health


## Returns the player's current gold amount.
## Bound as: {player_gold()} or <<if player_gold() >= 100>>
func get_gold() -> int:
	return gold


## Checks if the player has a specific item.
## Bound as: {has_item("key")} or <<if has_item("sword")>>
func has_item(item_name: String) -> bool:
	return item_name in inventory


## Returns how many of a specific item the player has.
## Bound as: {item_count("potion")}
func count_item(item_name: String) -> int:
	return inventory.count(item_name)


## Checks if the player can afford a purchase.
## Bound as: <<if can_afford(50)>>
func can_afford(amount: float) -> bool:
	return gold >= int(amount)


# === Commands (actions that do something) ===

## Adds an item to the player's inventory.
## Bound as: <<give_item "sword">>
func add_item(item_name: String) -> void:
	inventory.append(item_name)
	print("Player received: %s" % item_name)


## Removes an item from the player's inventory.
## Bound as: <<take_item "key">>
func remove_item(item_name: String) -> void:
	var idx := inventory.find(item_name)
	if idx >= 0:
		inventory.remove_at(idx)
		print("Player lost: %s" % item_name)


## Modifies the player's gold.
## Bound as: <<add_gold 100>> or <<add_gold -50>>
func modify_gold(amount: String) -> void:
	gold += int(amount)
	gold = maxi(0, gold)
	print("Player gold: %d" % gold)


## Heals or damages the player.
## Bound as: <<heal 25>> or <<heal -10>> for damage
func modify_health(amount: String) -> void:
	health += int(amount)
	health = clampi(health, 0, 100)
	print("Player health: %d" % health)


## Resets the player to starting state.
func reset() -> void:
	health = 100
	gold = 50
	inventory.clear()
