# ======================================================================== #
#                    Yarn Spinner for Godot (GDScript)                     #
# ======================================================================== #
#                                                                          #
# (C) Yarn Spinner Pty. Ltd.                                               #
#                                                                          #
# Yarn Spinner is a trademark of Secret Lab Pty. Ltd.,                     #
# used under license.                                                      #
#                                                                          #
# This code is subject to the terms of the license defined                 #
# in LICENSE.md.                                                           #
#                                                                          #
# For help, support, and more information, visit:                          #
#   https://yarnspinner.dev                                                #
#   https://docs.yarnspinner.dev                                           #
#                                                                          #
# ======================================================================== #

class_name YarnPromise
extends RefCounted
## A completion object for our new presenter system.
##
## Raw signals are basically broadcasts in that they fires while nobody is
## awaiting andare lost forever, and awaiting after the fact hangs. A promise
## remembers being settled so [method wait] resumes immediately when called
## on an already-settled promise so completion can never be lost to
## ordering. This is Paris' GDScript stand-in for an awaitable task...
##
## Idempotent (thanks, Tim). Only the first [method settle] wins, later calls are no-ops. 
## The dialogue runner uses one promise per presenter per
## piece of content ("this presenter has finished this line"), and a shared
## promise for option selection ("the first valid selection wins").

## Fired on settlement carrying the settled value. Prefer [method wait]
## over awaiting this directly...
signal completed(value)

var is_settled: bool = false
var value: Variant = null


## Settles the promise with [param result]. First call wins; later calls
## are noooooops
func settle(result: Variant = null) -> void:
	if is_settled:
		return
	is_settled = true
	value = result
	completed.emit(result)


## Awaitable: resumes when the promise settles immediately if it already
## has and returns the settled value.
func wait() -> Variant:
	if not is_settled:
		await completed
	return value
