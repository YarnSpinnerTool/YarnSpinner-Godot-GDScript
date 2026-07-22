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

class_name YarnAsync
extends RefCounted
## Async helpers shared by the runner and presenters.

## Awaitable pause-respecting wait.. teh clock only advances on frames where
## [param node] can process, so dialogue timers honour the node's
## [member Node.process_mode] under [member SceneTree.paused] exactly like
## the rest of the engine (unlike [method SceneTree.create_timer], whose
## default keeps ticking during pause hah). Returns early if the node leaves
## the tree or is freed..

static func wait(node: Node, seconds: float) -> void:
	if node == null or not node.is_inside_tree():
		return
	var tree := node.get_tree()
	var remaining := seconds
	while remaining > 0.0:
		await tree.process_frame
		if not is_instance_valid(node) or not node.is_inside_tree():
			return
		if not node.can_process():
			continue
		remaining -= node.get_process_delta_time()
