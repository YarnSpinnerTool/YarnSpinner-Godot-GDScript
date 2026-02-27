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
## Matches Unity's IContentSaliencyStrategy interface.

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
		if candidates[i].get("content_id", "") == candidate.get("content_id", ""):
			return i
	return -1


## Always returns the first non-failing item.
class YarnFirstSaliencyStrategy extends YarnSaliencyStrategy:

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.filter_valid_candidates(candidates)
		if valid.is_empty():
			return -1
		return YarnSaliencyStrategy.get_candidate_index(candidates, valid[0])


## Returns the highest-complexity non-failing item.
class YarnBestSaliencyStrategy extends YarnSaliencyStrategy:

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.filter_valid_candidates(candidates)
		if valid.is_empty():
			return -1

		valid.sort_custom(func(a, b):
			return a.get("complexity", 0) > b.get("complexity", 0))

		return YarnSaliencyStrategy.get_candidate_index(candidates, valid[0])


## Returns a random non-failing item. GDScript-only convenience strategy.
class YarnRandomSaliencyStrategy extends YarnSaliencyStrategy:

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.filter_valid_candidates(candidates)
		if valid.is_empty():
			return -1

		var selected: Dictionary = valid[randi_range(0, valid.size() - 1)]
		return YarnSaliencyStrategy.get_candidate_index(candidates, selected)


## Returns the best of the least-recently viewed items.
class YarnBestLeastRecentlyViewedSaliencyStrategy extends YarnSaliencyStrategy:

	func on_candidate_selected(candidate: Dictionary, context: Dictionary) -> void:
		var variable_storage: Variant = context.get("variable_storage")
		if variable_storage == null:
			return

		var content_id: String = candidate.get("content_id", "")
		if content_id.is_empty():
			return

		var view_count_key := YarnSaliencyStrategy.get_view_count_key(content_id)
		var raw_count: Variant = variable_storage.get_value(view_count_key)
		var current_count: int = int(raw_count) if raw_count != null else 0
		variable_storage.set_value(view_count_key, current_count + 1)

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.filter_valid_candidates(candidates)
		if valid.is_empty():
			return -1

		var variable_storage: Variant = context.get("variable_storage")

		var view_count_content: Array[Dictionary] = []
		for candidate in valid:
			var content_id: String = candidate.get("content_id", "")
			var view_count := 0

			if variable_storage != null and not content_id.is_empty():
				var view_count_key := YarnSaliencyStrategy.get_view_count_key(content_id)
				var raw_count: Variant = variable_storage.get_value(view_count_key)
				if raw_count != null:
					view_count = int(raw_count)

			view_count_content.append({
				"view_count": view_count,
				"candidate": candidate
			})

		# Sort by view count ascending, then complexity descending
		view_count_content.sort_custom(func(a, b):
			if a.view_count != b.view_count:
				return a.view_count < b.view_count
			return a.candidate.get("complexity", 0) > b.candidate.get("complexity", 0))

		var best_candidate: Dictionary = view_count_content[0].candidate
		return YarnSaliencyStrategy.get_candidate_index(candidates, best_candidate)


## Returns a random choice from the best of the least-recently viewed items.
## This is the default strategy.
class YarnRandomBestLeastRecentlyViewedSaliencyStrategy extends YarnSaliencyStrategy:

	func on_candidate_selected(candidate: Dictionary, context: Dictionary) -> void:
		var variable_storage: Variant = context.get("variable_storage")
		if variable_storage == null:
			return

		var content_id: String = candidate.get("content_id", "")
		if content_id.is_empty():
			return

		var view_count_key := YarnSaliencyStrategy.get_view_count_key(content_id)
		var raw_count: Variant = variable_storage.get_value(view_count_key)
		var current_count: int = int(raw_count) if raw_count != null else 0
		variable_storage.set_value(view_count_key, current_count + 1)

	func select_candidate(candidates: Array[Dictionary], context: Dictionary) -> int:
		var valid := YarnSaliencyStrategy.filter_valid_candidates(candidates)
		if valid.is_empty():
			return -1

		var variable_storage: Variant = context.get("variable_storage")

		var view_count_content: Array[Dictionary] = []
		for candidate in valid:
			var content_id: String = candidate.get("content_id", "")
			var view_count := 0

			if variable_storage != null and not content_id.is_empty():
				var view_count_key := YarnSaliencyStrategy.get_view_count_key(content_id)
				var raw_count: Variant = variable_storage.get_value(view_count_key)
				if raw_count != null:
					view_count = int(raw_count)

			view_count_content.append({
				"view_count": view_count,
				"complexity": candidate.get("complexity", 0),
				"candidate": candidate
			})

		var min_view_count: int = view_count_content[0].view_count
		for item in view_count_content:
			if item.view_count < min_view_count:
				min_view_count = item.view_count

		var least_viewed_group: Array[Dictionary] = []
		for item in view_count_content:
			if item.view_count == min_view_count:
				least_viewed_group.append(item)

		var max_complexity: int = least_viewed_group[0].complexity
		for item in least_viewed_group:
			if item.complexity > max_complexity:
				max_complexity = item.complexity

		var best_complexity_group: Array[Dictionary] = []
		for item in least_viewed_group:
			if item.complexity == max_complexity:
				best_complexity_group.append(item)

		var selected_item: Dictionary = best_complexity_group[randi_range(0, best_complexity_group.size() - 1)]
		return YarnSaliencyStrategy.get_candidate_index(candidates, selected_item.candidate)
