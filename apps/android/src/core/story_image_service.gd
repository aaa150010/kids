class_name StoryImageService
extends Node

signal story_ready(story_id: String)
signal story_failed(story_id: String, message: String)

const CACHE_ROOT := "user://story-images/"
const MAX_ACTIVE := 3
const CACHE_LIMIT_BYTES := 64 * 1024 * 1024

var _cache: Dictionary = {}
var _active: Dictionary = {}
var _queued: Dictionary = {}
var _generation: Dictionary = {}
var _requests: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_ROOT))
	_trim_cache.call_deferred()


func story_state(story: Dictionary) -> Dictionary:
	var story_id := str(story.get("id", ""))
	var illustrations: Array = story.get("illustrations", [])
	if illustrations.is_empty():
		return {"ready": true, "cached": 0, "total": 0}
	var cached := 0
	for illustration in illustrations:
		if not cached_path(illustration).is_empty():
			cached += 1
	var queued := _active.has(story_id) or _queued.has(story_id)
	return {
		"ready": cached == illustrations.size(),
		"cached": cached,
		"total": illustrations.size(),
		"loading": queued,
	}


func cached_path(illustration: Dictionary) -> String:
	var local_path := str(illustration.get("asset", ""))
	if (local_path.begins_with("res://") and ResourceLoader.exists(local_path)) or FileAccess.file_exists(local_path):
		return local_path
	var digest := str(illustration.get("sha256", "")).to_lower()
	var expected_size := int(illustration.get("size", 0))
	if digest.length() != 64 or expected_size <= 0:
		return ""
	var path := CACHE_ROOT + digest + ".webp"
	if _cache.has(path) and FileAccess.file_exists(path):
		return path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != expected_size:
		if file != null:
			file.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return ""
	file.close()
	if _sha256(path).to_lower() != digest:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_cache.erase(path)
		return ""
	_cache[path] = true
	return path


func prepare_story(story: Dictionary) -> Array:
	var result: Array = []
	var missing: Array = []
	for illustration in story.get("illustrations", []):
		var path := cached_path(illustration)
		if path.is_empty():
			missing.append(illustration)
		else:
			var item: Dictionary = illustration.duplicate(true)
			item.asset = path
			result.append(item)
	if not missing.is_empty():
		if is_instance_valid(self):
			request(story, missing)
	return result


func request(story: Dictionary, only: Array = []) -> void:
	var story_id := str(story.get("id", ""))
	if story_id.is_empty() or _active.has(story_id):
		return
	var illustrations: Array = only if not only.is_empty() else story.get("illustrations", [])
	if illustrations.is_empty() or story_state(story).ready:
		return
	_queued[story_id] = {
		"story": story.duplicate(true),
		"missing": illustrations.duplicate(true),
		"generation": _next_generation(story_id),
	}
	_pump()


func retry(story: Dictionary) -> void:
	var story_id := str(story.get("id", ""))
	_queued.erase(story_id)
	_active.erase(story_id)
	_cancel_requests(story_id)
	_next_generation(story_id)
	request(story)


func _pump() -> void:
	while _active.size() < MAX_ACTIVE and not _queued.is_empty():
		var story_id := str(_queued.keys()[0])
		var job: Dictionary = _queued[story_id]
		_queued.erase(story_id)
		_active[story_id] = job
		_download_story(story_id, job.story, job.missing, int(job.generation))


func _download_story(story_id: String, story: Dictionary, illustrations: Array, generation: int) -> void:
	var failures: Array[String] = []
	var pending := illustrations.size()
	for illustration in illustrations:
		var digest := str(illustration.get("sha256", "")).to_lower()
		var url := str(illustration.get("remoteUrl", ""))
		var size := int(illustration.get("size", 0))
		if digest.length() != 64 or not url.begins_with("https://") or size <= 0:
			failures.append("插画清单不完整")
			pending -= 1
			continue
		var final_path := CACHE_ROOT + digest + ".webp"
		var part_path := final_path + ".part"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(part_path))
		var request_node := HTTPRequest.new()
		request_node.timeout = 60.0
		request_node.body_size_limit = maxi(size, 1024)
		request_node.accept_gzip = false
		request_node.download_file = part_path
		add_child(request_node)
		_track_request(story_id, request_node)
		request_node.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray):
			_untrack_request(story_id, request_node)
			request_node.queue_free()
			if not _is_current(story_id, generation):
				return
			var okay := result == HTTPRequest.RESULT_SUCCESS and status == 200
			if okay:
				var file := FileAccess.open(part_path, FileAccess.READ)
				okay = file != null and file.get_length() == size
				if file != null:
					file.close()
			if okay:
				var hash := _sha256(part_path)
				okay = hash.to_lower() == digest
			if okay:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(final_path))
				okay = DirAccess.rename_absolute(
					ProjectSettings.globalize_path(part_path),
					ProjectSettings.globalize_path(final_path)
				) == OK
			if not okay:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(part_path))
				failures.append("插画下载或校验失败")
			else:
				_cache[final_path] = true
				_trim_cache()
			pending -= 1
			if pending <= 0:
				_finish(story_id, story, failures, generation)
		)
		var error := request_node.request(url)
		if error != OK:
			_untrack_request(story_id, request_node)
			request_node.queue_free()
			failures.append("网络连接失败")
			pending -= 1
	if pending <= 0:
		_finish(story_id, story, failures, generation)


func _finish(story_id: String, story: Dictionary, failures: Array[String], generation: int) -> void:
	if not _is_current(story_id, generation):
		return
	_active.erase(story_id)
	_requests.erase(story_id)
	if failures.is_empty():
		story_ready.emit(story_id)
	else:
		story_failed.emit(story_id, failures[0])
	_pump()


func _is_current(story_id: String, generation: int) -> bool:
	if not _active.has(story_id):
		return false
	return int(_active[story_id].get("generation", -1)) == generation


func _next_generation(story_id: String) -> int:
	var generation := int(_generation.get(story_id, 0)) + 1
	_generation[story_id] = generation
	return generation


func _track_request(story_id: String, request_node: HTTPRequest) -> void:
	if not _requests.has(story_id):
		_requests[story_id] = []
	_requests[story_id].append(request_node)


func _untrack_request(story_id: String, request_node: HTTPRequest) -> void:
	if not _requests.has(story_id):
		return
	var nodes: Array = _requests[story_id]
	nodes.erase(request_node)
	if nodes.is_empty():
		_requests.erase(story_id)


func _cancel_requests(story_id: String) -> void:
	if not _requests.has(story_id):
		return
	for request_node in _requests[story_id]:
		if is_instance_valid(request_node):
			request_node.cancel_request()
			request_node.queue_free()
	_requests.erase(story_id)


func _trim_cache() -> void:
	var files: Array[Dictionary] = []
	var total := 0
	var directory := DirAccess.open(CACHE_ROOT)
	if directory == null:
		return
	for filename in directory.get_files():
		if not filename.ends_with(".webp"):
			continue
		var path := CACHE_ROOT + filename
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var size := file.get_length()
		var modified := FileAccess.get_modified_time(path)
		file.close()
		total += size
		files.append({"path": path, "size": size, "modified": modified})
	if total <= CACHE_LIMIT_BYTES:
		return
	files.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.modified) < int(b.modified))
	for item in files:
		if total <= CACHE_LIMIT_BYTES:
			break
		var path := str(item.path)
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK:
			total -= int(item.size)
			_cache.erase(path)


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		context.update(file.get_buffer(1024 * 1024))
	file.close()
	return context.finish().hex_encode()
