class_name GestureRecognizer
extends Node

## 逐触点手势识别：tap / long_press / drag，支持多点（按 touch index 独立跟踪）
## 使用方在 _input 或 _gui_input 中调用 forward(event) 转发事件，监听下方信号即可
## 桌面调试时鼠标左键被视作 index 0 的触点

signal tap(position: Vector2, index: int)
signal long_press(position: Vector2, index: int)
signal long_press_progress(progress: float, index: int)
signal drag_start(position: Vector2, index: int)
signal drag_move(position: Vector2, delta: Vector2, index: int)
signal drag_end(position: Vector2, index: int)

# 判定参数（全部集中在此，便于统一微调）
const TAP_MAX_DISTANCE := 12.0        # tap 允许的最大位移（像素）
const TAP_MAX_TIME := 0.45            # 与长按阈值衔接，避免按住0.35–0.45秒时无响应
const LONG_PRESS_TIME := 0.45         # 长按触发时长（秒）
const LONG_PRESS_MAX_DISTANCE := 16.0 # 长按等待期间允许的最大位移
const DRAG_MIN_DISTANCE := 16.0       # 进入拖拽的最小位移

# index -> {start, last, msec, dragging, long_fired}
var _touches: Dictionary = {}
var _last_touch_msec := -1000
const MOUSE_INDEX := 0 # 保持使用方的鼠标触点编号；通过模拟事件过滤避免覆盖触摸
const EMULATED_MOUSE_GUARD_MSEC := 200


func forward(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return # 鼠标模拟触摸；桌面调试走原始鼠标分支
		_last_touch_msec = Time.get_ticks_msec()
		if event.canceled:
			_touches.erase(event.index)
		elif event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index, event.position)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		_move(event.index, event.position, event.relative)
	elif event is InputEventMouse:
		# 安卓会为触摸补发鼠标事件；不能再次生成同一手势。
		if event.device == InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() - _last_touch_msec < EMULATED_MOUSE_GUARD_MSEC:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(MOUSE_INDEX, event.position)
			else:
				_release(MOUSE_INDEX, event.position)
		elif event is InputEventMouseMotion and _touches.has(MOUSE_INDEX):
			_move(MOUSE_INDEX, event.position, event.relative)


func cancel_all() -> void:
	# 弹窗接管等场景下复位全部触点状态
	_touches.clear()


func is_pressing(index: int = -1) -> bool:
	if index < 0:
		return not _touches.is_empty()
	return _touches.has(index)


func _press(index: int, position: Vector2) -> void:
	_touches[index] = {
		"start": position,
		"last": position,
		"msec": Time.get_ticks_msec(),
		"dragging": false,
		"long_fired": false,
	}


func _move(index: int, position: Vector2, delta: Vector2) -> void:
	if not _touches.has(index):
		return
	var touch: Dictionary = _touches[index]
	touch["last"] = position
	if bool(touch["dragging"]):
		drag_move.emit(position, delta, index)
		return
	if (position - touch["start"]).length() >= DRAG_MIN_DISTANCE:
		touch["dragging"] = true
		touch["long_fired"] = true # 进入拖拽后不再触发长按
		drag_start.emit(touch["start"], index)
		# 开始拖动的回调可能因弹窗或状态切换取消本次手势。
		if _touches.has(index):
			drag_move.emit(position, delta, index)


func _release(index: int, position: Vector2) -> void:
	if not _touches.has(index):
		return
	var touch: Dictionary = _touches[index]
	_touches.erase(index)
	var elapsed := (Time.get_ticks_msec() - int(touch["msec"])) / 1000.0
	if bool(touch["dragging"]):
		drag_end.emit(position, index)
	elif not bool(touch["long_fired"]) and (elapsed <= TAP_MAX_TIME or not not long_press.get_connections().is_empty()) and (position - touch["start"]).length() <= TAP_MAX_DISTANCE:
		# 没有长按行为的控件与普通按钮一致：按住后抬起仍可点击。
		tap.emit(position, index)


func _process(_delta: float) -> void:
	# 长按计时与"按住中"进度回调（供使用方做视觉提示）
	for index in _touches.keys():
		if not _touches.has(index):
			continue # 前一个触点的信号回调可能已取消全部手势
		var touch: Dictionary = _touches[index]
		if bool(touch["dragging"]) or bool(touch["long_fired"]):
			continue
		var offset: Vector2 = touch["last"] - touch["start"]
		if offset.length() >= LONG_PRESS_MAX_DISTANCE:
			continue # 位移过大，等待 tap 或拖拽判定
		var elapsed := (Time.get_ticks_msec() - int(touch["msec"])) / 1000.0
		if elapsed >= LONG_PRESS_TIME:
			if not long_press.get_connections().is_empty():
				touch["long_fired"] = true
				long_press.emit(touch["last"], index)
		else:
			long_press_progress.emit(clampf(elapsed / LONG_PRESS_TIME, 0.0, 1.0), index)
