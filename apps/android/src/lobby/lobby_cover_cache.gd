class_name LobbyCoverCache
extends RefCounted

## 大厅封面异步缓存：后台线程解码全部封面图，卡片直接取缓存，避免首帧同步解码卡顿
## 用法：
##   LobbyCoverCache.warmup(["res://assets/covers/island.png", ...])  # 进大厅前调一次
##   LobbyCoverCache.poll()                                           # main._process 每帧调用
##   var tex := LobbyCoverCache.texture(path)                         # 命中返回 Texture2D，未命中 null
##   LobbyCoverCache.request(path, func(texture): ...)                # 未命中时注册回填回调

static var _cache: Dictionary = {}     # path -> Texture2D
static var _pending: Dictionary = {}   # path -> true（线程加载中）
static var _failed: Dictionary = {}    # path -> true（加载失败，不再重试）
static var _listeners: Dictionary = {} # path -> Array[Callable]


static func warmup(paths: Array) -> void:
	for path in paths:
		_ensure_loading(str(path))


static func texture(path: String) -> Texture2D:
	return _cache.get(path, null) as Texture2D


static func request(path: String, on_ready: Callable) -> void:
	if not on_ready.is_valid():
		return
	# 延迟投递时重新验证接收者，避免大厅重建后调用已释放卡片。
	var cached := texture(path)
	if cached != null or _failed.has(path) or path.is_empty():
		_deliver.call_deferred(on_ready, cached)
		return
	if not _listeners.has(path):
		_listeners[path] = []
	_listeners[path].append(on_ready)
	_ensure_loading(path)


# 轮询线程加载状态（主线程调用），完成的分发给等待中的卡片
static func poll() -> void:
	if _pending.is_empty():
		return
	for path in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_pending.erase(path)
			var loaded: Variant = ResourceLoader.load_threaded_get(path)
			if loaded is Texture2D:
				_cache[path] = loaded
				_flush_listeners(path, loaded)
			else:
				_failed[path] = true
				_flush_listeners(path, null)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.erase(path)
			_failed[path] = true
			push_warning("LobbyCoverCache: 封面加载失败 %s" % path)
			_flush_listeners(path, null)


static func _ensure_loading(path: String) -> void:
	if path.is_empty() or _cache.has(path) or _pending.has(path) or _failed.has(path):
		return
	if not ResourceLoader.exists(path):
		_failed[path] = true
		_flush_listeners(path, null)
		return
	var error := ResourceLoader.load_threaded_request(path, "Texture2D")
	if error != OK:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS and status != ResourceLoader.THREAD_LOAD_LOADED:
			_failed[path] = true
			_flush_listeners(path, null)
			return
	_pending[path] = true


static func _flush_listeners(path: String, loaded: Texture2D) -> void:
	var callbacks: Array = _listeners.get(path, [])
	_listeners.erase(path)
	for callback in callbacks:
		if callback is Callable:
			_deliver(callback, loaded)


static func _deliver(callback: Callable, loaded: Texture2D) -> void:
	if not callback.is_valid():
		return
	var receiver := callback.get_object()
	if receiver is Node and receiver.is_queued_for_deletion():
		return
	callback.call(loaded)
