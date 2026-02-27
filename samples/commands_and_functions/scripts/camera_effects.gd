# This Source Code Form is subject to the terms of the LICENSE.md file
# located in the root of this project.

extends Camera2D
## Sample camera node demonstrating async commands that make dialogue wait.
##
## Shows how to return a Signal from command methods to pause
## dialogue until an effect completes.


## Shakes the camera (dialogue does NOT wait).
## Bound as: <<shake 0.5>>
func shake(intensity: String) -> void:
	var strength := float(intensity) * 20.0
	var tween := create_tween()
	tween.tween_property(self, "offset", Vector2(strength, 0), 0.05)
	tween.tween_property(self, "offset", Vector2(-strength, 0), 0.05)
	tween.tween_property(self, "offset", Vector2(strength * 0.5, 0), 0.05)
	tween.tween_property(self, "offset", Vector2.ZERO, 0.1)


## Shakes the camera and WAITS for completion.
## Bound as: <<shake_and_wait 0.5 1.0>>
## Returns a Signal so dialogue pauses until shake finishes.
func shake_and_wait(intensity: String, duration: String = "0.5") -> Signal:
	var strength := float(intensity) * 20.0
	var time := float(duration)

	var tween := create_tween()
	var shake_count := int(time / 0.1)

	for i in range(shake_count):
		var decay := 1.0 - (float(i) / shake_count)
		tween.tween_property(self, "offset", Vector2(strength * decay, 0), 0.025)
		tween.tween_property(self, "offset", Vector2(-strength * decay, 0), 0.025)
		tween.tween_property(self, "offset", Vector2(0, strength * decay * 0.5), 0.025)
		tween.tween_property(self, "offset", Vector2(0, -strength * decay * 0.5), 0.025)

	tween.tween_property(self, "offset", Vector2.ZERO, 0.05)

	# Return the signal - dialogue waits for this!
	return tween.finished


## Zooms the camera in or out (async - dialogue waits).
## Bound as: <<zoom 1.5 0.5>>
func zoom_to(target_zoom: String, duration: String = "0.3") -> Signal:
	var target := float(target_zoom)
	var time := float(duration)

	var tween := create_tween()
	tween.tween_property(self, "zoom", Vector2(target, target), time)

	return tween.finished


## Resets camera to default state.
func reset() -> void:
	offset = Vector2.ZERO
	zoom = Vector2.ONE
