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

class_name YarnSaliencyStrategy
extends RefCounted
## Base class for saliency selection strategies.

enum ContentType {
	NODE,
	LINE,
}

const VIEW_COUNT_KEY_PREFIX := "$Yarn.Internal.Content.ViewCount."


static func get_view_count_key(content_id: String) -> String:
	return VIEW_COUNT_KEY_PREFIX + content_id


## Returns the selected candidate index, or -1 if none selected.
func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
	push_error("saliency strategy: select_candidate not implemented")
	return -1


func on_candidate_selected(candidate: Dictionary, context: Dictionary) -> void:
	pass


static func filter_valid_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var valid: Array[Dictionary] = []
	for candidate in candidates:
		if candidate.get("conditions_failed", 0) == 0:
			valid.append(candidate)
	return valid


static func get_candidate_index(candidates: Array[Dictionary], candidate: Dictionary) -> int:
	for i in range(candidates.size()):
		if candidates[i] == candidate:
			return i
	for i in range(candidates.size()):
		if candidates[i].get("content_id", "") == candidate.get("content_id", ""):
			return i
	return -1


static func valid_candidate_indices(candidates: Array[Dictionary]) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for i in range(candidates.size()):
		if candidates[i].get("conditions_failed", 0) == 0:
			indices.append(i)
	return indices


static func get_view_count(context: Dictionary, content_id: String) -> int:
	var variable_storage: Variant = context.get("variable_storage")
	if variable_storage == null or content_id.is_empty():
		return 0
	var raw_count: Variant = variable_storage.get_value(get_view_count_key(content_id))
	if raw_count is float or raw_count is int:
		return int(raw_count)
	return 0


static func increment_view_count(context: Dictionary, candidate: Dictionary) -> void:
	var variable_storage: Variant = context.get("variable_storage")
	if variable_storage == null:
		return
	var content_id: String = candidate.get("content_id", "")
	if content_id.is_empty():
		push_error("saliency strategy: content has an empty content_id")
		return
	var count := get_view_count(context, content_id) + 1
	variable_storage.set_value(get_view_count_key(content_id), float(count))


## Always returns the first non-failing item.
class YarnFirstSaliencyStrategy extends YarnSaliencyStrategy:

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.valid_candidate_indices(candidates)
		if valid.is_empty():
			return -1
		return valid[0]


## Returns the highest-complexity non-failing item.
class YarnBestSaliencyStrategy extends YarnSaliencyStrategy:

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var best := -1
		for index in YarnSaliencyStrategy.valid_candidate_indices(candidates):
			if best == -1 or candidates[index].get("complexity", 0) > candidates[best].get("complexity", 0):
				best = index
		return best


## Returns a random non-failing item. GDScript-only convenience strategy.
class YarnRandomSaliencyStrategy extends YarnSaliencyStrategy:

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.valid_candidate_indices(candidates)
		if valid.is_empty():
			return -1
		return valid[randi_range(0, valid.size() - 1)]


## Returns the best of the least-recently viewed items.
class YarnBestLeastRecentlyViewedSaliencyStrategy extends YarnSaliencyStrategy:

	func on_candidate_selected(candidate: Dictionary, context: Dictionary) -> void:
		YarnSaliencyStrategy.increment_view_count(context, candidate)

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var best := -1
		var best_views := 0
		for index in YarnSaliencyStrategy.valid_candidate_indices(candidates):
			var views := YarnSaliencyStrategy.get_view_count(context, candidates[index].get("content_id", ""))
			if best == -1 or views < best_views:
				best = index
				best_views = views
			elif views == best_views and candidates[index].get("complexity", 0) > candidates[best].get("complexity", 0):
				best = index
		return best


## Returns a random choice from the best of the least-recently viewed items.
## This is the default strategy.
class YarnRandomBestLeastRecentlyViewedSaliencyStrategy extends YarnSaliencyStrategy:

	func on_candidate_selected(candidate: Dictionary, context: Dictionary) -> void:
		YarnSaliencyStrategy.increment_view_count(context, candidate)

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.valid_candidate_indices(candidates)
		if valid.is_empty():
			return -1

		var views: Dictionary[int, int] = {}
		var min_views := -1
		for index in valid:
			var count := YarnSaliencyStrategy.get_view_count(context, candidates[index].get("content_id", ""))
			views[index] = count
			if min_views == -1 or count < min_views:
				min_views = count

		var max_complexity := 0
		var has_complexity := false
		for index in valid:
			if views[index] != min_views:
				continue
			var complexity: int = candidates[index].get("complexity", 0)
			if not has_complexity or complexity > max_complexity:
				max_complexity = complexity
				has_complexity = true

		var best_group := PackedInt32Array()
		for index in valid:
			if views[index] == min_views and candidates[index].get("complexity", 0) == max_complexity:
				best_group.append(index)

		return best_group[randi_range(0, best_group.size() - 1)]
