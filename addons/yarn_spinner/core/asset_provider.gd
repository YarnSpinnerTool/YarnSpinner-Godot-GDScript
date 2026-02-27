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

class_name YarnAssetProvider
extends RefCounted
## Provides assets associated with yarn dialogue lines.

var base_path: String = "res://dialogue/assets/"
var audio_base_path: String = "res://audio/dialogue/"
var image_base_path: String = "res://images/dialogue/"
var audio_extensions: PackedStringArray = [".ogg", ".wav", ".mp3"]
var image_extensions: PackedStringArray = [".png", ".jpg", ".webp"]
var auto_discover: bool = true
var max_cache_size: int = 100
var use_threaded_loading: bool = true

var _assets: Dictionary[String, String] = {}
var _cache: Dictionary[String, Resource] = {}
var _audio_cache: Dictionary[String, AudioStream] = {}
var _image_cache: Dictionary[String, Texture2D] = {}

## LRU eviction order for cached assets.
var _cache_access_order: Array[String] = []

var _pending_loads: Dictionary[String, Dictionary] = {}


func set_base_path(path: String) -> void:
	base_path = path
	if not base_path.ends_with("/"):
		base_path += "/"


func register_asset(line_id: String, resource_path: String) -> void:
	_assets[line_id] = resource_path


func register_assets(mappings: Dictionary) -> void:
	for line_id in mappings:
		_assets[line_id] = mappings[line_id]


func load_mappings_from_csv(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	if file.eof_reached():
		file.close()
		return OK

	var header := file.get_csv_line()
	if header.is_empty() or (header.size() == 1 and header[0].is_empty()):
		file.close()
		return OK

	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.is_empty() or row.size() < 2:
			continue
		var line_id := row[0]
		var asset_path := row[1]
		if not line_id.is_empty() and not asset_path.is_empty():
			_assets[line_id] = asset_path

	file.close()
	return OK


func get_asset(line_id: String) -> Resource:
	if _cache.has(line_id):
		_update_access_order(line_id)
		return _cache[line_id]

	if not _assets.has(line_id):
		return null

	var path: String = _assets[line_id]

	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = base_path + path

	if ResourceLoader.exists(path):
		var resource := ResourceLoader.load(path)
		_add_to_cache(line_id, resource, "_cache")
		return resource

	return null


func get_audio(line_id: String) -> AudioStream:
	if _audio_cache.has(line_id):
		_update_access_order(line_id)
		return _audio_cache[line_id]

	var resource := get_asset(line_id)
	if resource is AudioStream:
		return resource

	if auto_discover:
		var audio := _discover_audio(line_id)
		if audio != null:
			_add_to_cache(line_id, audio, "_audio_cache")
			return audio

	return null


func get_texture(line_id: String) -> Texture2D:
	if _image_cache.has(line_id):
		_update_access_order(line_id)
		return _image_cache[line_id]

	var resource := get_asset(line_id)
	if resource is Texture2D:
		return resource

	if auto_discover:
		var image := _discover_image(line_id)
		if image != null:
			_add_to_cache(line_id, image, "_image_cache")
			return image

	return null


func _update_access_order(line_id: String) -> void:
	var idx := _cache_access_order.find(line_id)
	if idx >= 0:
		_cache_access_order.remove_at(idx)
	_cache_access_order.append(line_id)


func _discover_audio(line_id: String) -> AudioStream:
	var path := _find_audio_path(line_id)
	if path.is_empty():
		return null
	var resource := load(path)
	if resource is AudioStream:
		return resource
	return null


func _discover_image(line_id: String) -> Texture2D:
	var path := _find_image_path(line_id)
	if path.is_empty():
		return null
	var resource := load(path)
	if resource is Texture2D:
		return resource
	return null


func _sanitise_line_id(line_id: String) -> String:
	return line_id.replace(":", "_").replace("/", "_").replace("\\", "_")


func preload_assets(line_ids: PackedStringArray) -> void:
	for line_id in line_ids:
		if _assets.has(line_id) and not _cache.has(line_id):
			var path: String = _assets[line_id]
			if not path.begins_with("res://") and not path.begins_with("user://"):
				path = base_path + path

			if use_threaded_loading and ResourceLoader.exists(path):
				_start_threaded_load(line_id, path, "_cache")
			else:
				get_asset(line_id)

		if auto_discover:
			if not _audio_cache.has(line_id):
				var audio_path := _find_audio_path(line_id)
				if audio_path and use_threaded_loading:
					_start_threaded_load(line_id, audio_path, "_audio_cache")
				elif audio_path:
					var audio := load(audio_path)
					if audio is AudioStream:
						_add_to_cache(line_id, audio, "_audio_cache")

			if not _image_cache.has(line_id):
				var image_path := _find_image_path(line_id)
				if image_path and use_threaded_loading:
					_start_threaded_load(line_id, image_path, "_image_cache")
				elif image_path:
					var image := load(image_path)
					if image is Texture2D:
						_add_to_cache(line_id, image, "_image_cache")


func _start_threaded_load(line_id: String, path: String, cache_name: String) -> void:
	var load_key := "%s:%s" % [cache_name, line_id]
	if _pending_loads.has(load_key):
		return  # already loading

	var err := ResourceLoader.load_threaded_request(path)
	if err == OK:
		_pending_loads[load_key] = {"path": path, "cache": cache_name, "line_id": line_id}


func poll_threaded_loads() -> void:
	var completed: Array[String] = []

	for load_key in _pending_loads:
		var info: Dictionary = _pending_loads[load_key]
		var status := ResourceLoader.load_threaded_get_status(info.path)

		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(info.path)
			if resource != null:
				_add_to_cache(info.line_id, resource, info.cache)
			completed.append(load_key)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			completed.append(load_key)

	for key in completed:
		_pending_loads.erase(key)


func _find_audio_path(line_id: String) -> String:
	var filename := _sanitise_line_id(line_id)
	for ext in audio_extensions:
		var path := audio_base_path.path_join(filename + ext)
		if ResourceLoader.exists(path):
			return path
	return ""


func _find_image_path(line_id: String) -> String:
	var filename := _sanitise_line_id(line_id)
	for ext in image_extensions:
		var path := image_base_path.path_join(filename + ext)
		if ResourceLoader.exists(path):
			return path
	return ""


func _add_to_cache(line_id: String, resource: Resource, cache_name: String) -> void:
	var cache: Dictionary
	match cache_name:
		"_cache":
			cache = _cache
		"_audio_cache":
			cache = _audio_cache
		"_image_cache":
			cache = _image_cache
		_:
			return

	if max_cache_size > 0:
		var total_size := _cache.size() + _audio_cache.size() + _image_cache.size()
		while total_size >= max_cache_size and not _cache_access_order.is_empty():
			var oldest := _cache_access_order.pop_front()
			_cache.erase(oldest)
			_audio_cache.erase(oldest)
			_image_cache.erase(oldest)
			total_size = _cache.size() + _audio_cache.size() + _image_cache.size()

	cache[line_id] = resource

	var idx := _cache_access_order.find(line_id)
	if idx >= 0:
		_cache_access_order.remove_at(idx)
	_cache_access_order.append(line_id)


func clear_cache() -> void:
	_cache.clear()
	_audio_cache.clear()
	_image_cache.clear()
	_cache_access_order.clear()
	_pending_loads.clear()


func clear() -> void:
	_assets.clear()
	_cache.clear()
	_audio_cache.clear()
	_image_cache.clear()
	_cache_access_order.clear()
	_pending_loads.clear()


func get_cache_stats() -> Dictionary:
	return {
		"general_cache_size": _cache.size(),
		"audio_cache_size": _audio_cache.size(),
		"image_cache_size": _image_cache.size(),
		"total_cached": _cache.size() + _audio_cache.size() + _image_cache.size(),
		"max_cache_size": max_cache_size,
		"pending_loads": _pending_loads.size()
	}


func has_asset(line_id: String) -> bool:
	return _assets.has(line_id)
