extends Node

signal download_progress(story_id: String, received: int, total: int)
signal audio_ready(story_id: String, path: String)
signal download_failed(story_id: String, message: String)
signal queue_changed

const BASE_URL := "https://lynote.xyz/play-app/stories/"
const CACHE_DIR := "user://story-audio/"
const MAX_DOWNLOADS := 2
const MAX_FILE_BYTES := 20 * 1024 * 1024
var suspended := false
var _queue: Array[String] = []
var _active: Dictionary = {}
var _verified: Dictionary = {}
var _poll_time := 0.0
var _resume_after_focus := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	for filename in DirAccess.get_files_at(CACHE_DIR):
		if filename.ends_with(".part"):
			_remove(CACHE_DIR + filename)
	call_deferred("_restore_saved_queue")


func _restore_saved_queue() -> void:
	for story_id in SaveStore.story_downloads():
		if not (story_id in _queue) and _valid_entry(story_id) and not is_cached(story_id):
			_queue.append(story_id)
	suspended = not _queue.is_empty()
	_persist_queue()


func _valid_hash(value: String) -> bool:
	if value.length() != 64: return false
	for character in value:
		if not (character in "0123456789abcdef"): return false
	return true


func _entry(story_id: String) -> Dictionary:
	return ContentDB.story_audio_entry(story_id)


func _valid_entry(story_id: String) -> bool:
	var entry := _entry(story_id)
	var digest := str(entry.get("sha256", ""))
	var byte_count := int(entry.get("size", 0))
	return _valid_hash(digest) and byte_count > 0 and byte_count <= MAX_FILE_BYTES and str(entry.get("url", "")) == "audio/" + digest + ".mp3"


func available(story_id: String) -> bool:
	return _valid_entry(story_id)


func _path(story_id: String) -> String:
	return CACHE_DIR + str(_entry(story_id).get("sha256", "")) + ".mp3"


func is_cached(story_id: String) -> bool:
	if not _valid_entry(story_id): return false
	var path := _path(story_id)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	var length := file.get_length()
	file.close()
	return length == int(_entry(story_id).get("size", 0))


func cached_path(story_id: String) -> String:
	if not is_cached(story_id): return ""
	var path := _path(story_id)
	var digest := str(_entry(story_id).sha256)
	if _verified.get(path, "") != digest:
		if UpdateService.file_sha256(path) != digest:
			_remove(path)
			return ""
		_verified[path] = digest
	return path


func pending_ids() -> Array:
	var result: Array = _active.keys()
	result.append_array(_queue)
	return result


func enqueue(ids: Array, priority: bool = false) -> void:
	for value in ids:
		var story_id := str(value)
		if not _valid_entry(story_id):
			download_failed.emit(story_id, "这一篇的音频暂未准备好，可以先看文字。")
			continue
		var cached := cached_path(story_id)
		if not cached.is_empty():
			audio_ready.emit(story_id, cached)
			continue
		if _active.has(story_id): continue
		_queue.erase(story_id)
		if priority: _queue.push_front(story_id)
		else: _queue.append(story_id)
	suspended = false
	_persist_queue()
	_pump()


func resume_downloads() -> void:
	suspended = false
	_pump()
	queue_changed.emit()


func pause_downloads(automatic: bool = false) -> void:
	_resume_after_focus = automatic
	suspended = true
	for story_id in _active.keys():
		var work: Dictionary = _active[story_id]
		var request: HTTPRequest = work.request
		_active.erase(story_id)
		request.cancel_request()
		request.queue_free()
		_remove(str(work.part))
		if not (story_id in _queue): _queue.push_front(story_id)
	_persist_queue()


func cancel_downloads() -> void:
	_resume_after_focus = false
	pause_downloads()
	_queue.clear()
	suspended = false
	_persist_queue()


func _persist_queue() -> void:
	SaveStore.set_story_downloads(pending_ids())
	queue_changed.emit()


func total_bytes(ids: Array) -> int:
	var total := 0
	for story_id in ids:
		if _valid_entry(str(story_id)): total += int(_entry(str(story_id)).size)
	return total


func storage_bytes() -> int:
	var total := 0
	for filename in DirAccess.get_files_at(CACHE_DIR):
		if not filename.ends_with(".mp3"): continue
		var file := FileAccess.open(CACHE_DIR + filename, FileAccess.READ)
		if file != null:
			total += file.get_length()
			file.close()
	return total


func free_bytes() -> int:
	var directory := DirAccess.open(CACHE_DIR)
	return directory.get_space_left() if directory != null else 0


func clear_cached(ids: Array) -> void:
	pause_downloads()
	if not ContentDB.stories.is_empty() and ids.size() == ContentDB.stories.size():
		for filename in DirAccess.get_files_at(CACHE_DIR):
			if filename.ends_with(".mp3") and _valid_hash(filename.trim_suffix(".mp3")):
				_remove(CACHE_DIR + filename)
		_verified.clear()
	for value in ids:
		var story_id := str(value)
		_queue.erase(story_id)
		if _valid_entry(story_id):
			var path := _path(story_id)
			_remove(path)
			_verified.erase(path)
	_persist_queue()


func _pump() -> void:
	if suspended or not is_inside_tree(): return
	while _active.size() < MAX_DOWNLOADS and not _queue.is_empty():
		var story_id: String = _queue.pop_front()
		if not _valid_entry(story_id): continue
		var cached := cached_path(story_id)
		if not cached.is_empty():
			audio_ready.emit(story_id, cached)
			continue
		var entry := _entry(story_id)
		var free := free_bytes()
		if free > 0 and free < int(entry.size) + 8 * 1024 * 1024:
			_queue.push_front(story_id)
			suspended = true
			download_failed.emit(story_id, "平板空间不够啦，请先清理一些已下载音频。文字仍然可以看。")
			break
		var path := _path(story_id)
		var part := path + ".part"
		_remove(part)
		var request := HTTPRequest.new()
		request.use_threads = true
		request.timeout = 120.0
		request.accept_gzip = false
		request.body_size_limit = int(entry.size)
		request.download_file = part
		add_child(request)
		_active[story_id] = {"request": request, "entry": entry.duplicate(true), "part": part, "path": path}
		request.request_completed.connect(_on_download_finished.bind(story_id, request.get_instance_id()))
		var error := request.request(BASE_URL + str(entry.url))
		if error != OK:
			_active.erase(story_id)
			request.queue_free()
			_remove(part)
			download_failed.emit(story_id, "暂时连不上故事音频，点播放可以重试。")
	_persist_queue()


func _on_download_finished(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, story_id: String, request_id: int) -> void:
	if not _active.has(story_id): return
	if _active[story_id].request.get_instance_id() != request_id: return
	var work: Dictionary = _active[story_id]
	_active.erase(story_id)
	var request: HTTPRequest = work.request
	request.queue_free()
	var part := str(work.part)
	var valid := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	var file := FileAccess.open(part, FileAccess.READ)
	valid = valid and file != null
	if file != null:
		valid = valid and file.get_length() == int(work.entry.size)
		file.close()
	if valid: valid = UpdateService.file_sha256(part) == str(work.entry.sha256)
	if valid:
		_remove(str(work.path))
		valid = DirAccess.rename_absolute(ProjectSettings.globalize_path(part), ProjectSettings.globalize_path(str(work.path))) == OK
	if valid:
		_verified[str(work.path)] = str(work.entry.sha256)
		audio_ready.emit(story_id, str(work.path))
	else:
		_remove(part)
		if not (story_id in _queue): _queue.append(story_id)
		suspended = true
		download_failed.emit(story_id, "音频下载没有完成，已保留下载任务。联网后可以重试。")
	_persist_queue()
	call_deferred("_pump")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _process(delta: float) -> void:
	_poll_time += delta
	if _poll_time < 0.25: return
	_poll_time = 0.0
	for story_id in _active:
		var work: Dictionary = _active[story_id]
		var request: HTTPRequest = work.request
		download_progress.emit(story_id, request.get_downloaded_bytes(), int(work.entry.size))


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST] and not _active.is_empty():
		pause_downloads(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _resume_after_focus:
		_resume_after_focus = false
		resume_downloads()
