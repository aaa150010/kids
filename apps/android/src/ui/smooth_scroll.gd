class_name SmoothScrollContainer
extends ScrollContainer

## 大厅丝滑滚动：触摸直跟（松手前不插值）+ 松手惯性（指数阻尼）+ 边界回弹 + 滚轮平滑
## 只接管纵向滚动；惯性改的是 scroll_vertical 属性，不碰 Container 子节点 position/size
## 回退开关：USE_NATIVE = true 时 create() 返回原生 ScrollContainer（大厅只需改这一行）

const USE_NATIVE := false
# 手感参数（集中可调）
const DRAG_DEADZONE := 6.0        # 触发滚动所需最小位移（像素）
const OVERSCROLL_RESIST := 0.42   # 越界后继续拖动的阻力系数
const VELOCITY_WINDOW_MS := 100   # 松手初速度采样窗口（毫秒）
const INERTIA_DAMPING := 3.4      # 惯性指数阻尼系数（越大停得越快）
const INERTIA_MIN_SPEED := 30.0   # 低于该速度结束惯性（像素/秒）
const BOUNCE_TIME := 0.25         # 边界回弹时长
const WHEEL_STEP := 280.0         # 鼠标滚轮单步滚动量
const WHEEL_TIME := 0.22          # 滚轮平滑时长

var _touching := false            # 有触点落在本控件内
var _dragging := false            # 已越过死区，正在直跟拖动
var _pending := 0.0               # 死区内累计位移
var _scroll_pos := 0.0            # 浮点滚动位置（避免 int 取整抖动）
var _velocity := 0.0              # 惯性速度（像素/秒，正=scroll_vertical 增大）
var _samples: Array = []          # [msec, scroll_pos] 采样点
var _bounce_tween: Tween = null
var _pointer := -2
var _suppress_click := false
var _internal_set := false        # 内部写 scroll_vertical 时屏蔽同步回调


static func create() -> ScrollContainer:
	# 回退=原生行为
	if USE_NATIVE:
		return ScrollContainer.new()
	return SmoothScrollContainer.new()


func _ready() -> void:
	# 原生 ScrollContainer 只负责裁切，滚动条始终隐藏，触摸位移由本类唯一处理。
	scroll_deadzone = 1000000
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	set_process(false) # 无惯性时不开帧回调
	get_v_scroll_bar().value_changed.connect(_on_bar_value_changed)
	get_v_scroll_bar().visible = false
	_scroll_pos = float(scroll_vertical)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		cancel_gesture()
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var hub := get_tree().get_first_node_in_group("main_hub")
	if hub != null and hub.ipc != null and hub.ipc.current_priority() >= InteractionController.PRIORITY_DRAG:
		cancel_gesture()
		return
	var index := -1
	var pressed := false
	var released := false
	var position := Vector2.ZERO
	if event is InputEventScreenTouch:
		index = event.index
		position = event.position
		pressed = event.pressed and not event.canceled
		released = not event.pressed or event.canceled
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag and event.index == _pointer:
		_drag_by(-event.relative.y)
	elif event is InputEventMouseMotion and _pointer == -1 and _touching:
		_drag_by(-event.relative.y)
	if pressed and not _touching and get_global_rect().has_point(position):
		_suppress_click = absf(_velocity) >= INERTIA_MIN_SPEED or (_bounce_tween != null and _bounce_tween.is_running())
		_pointer = index
		_on_press()
		_record_sample()
		if _suppress_click:
			get_viewport().set_input_as_handled()
	elif released and index == _pointer:
		var suppress := _suppress_click or _dragging
		_on_release()
		_pointer = -2
		_suppress_click = false
		if suppress:
			get_viewport().set_input_as_handled()


func cancel_gesture() -> void:
	if _dragging:
		propagate_notification(NOTIFICATION_SCROLL_END)
	_touching = false
	_dragging = false
	_pointer = -2
	_pending = 0.0
	_samples.clear()
	_stop_motion()
	_set_scroll_pos(clampf(_scroll_pos, 0.0, _max_scroll()))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree():
		cancel_gesture()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_wheel(-1.0)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_wheel(1.0)
			accept_event()


func _process(delta: float) -> void:
	# 松手后的惯性：指数阻尼衰减，触界即停并回弹对齐
	if _touching:
		set_process(false)
		return
	_velocity *= exp(-INERTIA_DAMPING * delta)
	_set_scroll_pos(_scroll_pos + _velocity * delta)
	var max_scroll := _max_scroll()
	if _scroll_pos <= 0.0 or _scroll_pos >= max_scroll:
		_velocity = 0.0
		_start_bounce()
		return
	if absf(_velocity) < INERTIA_MIN_SPEED:
		_velocity = 0.0
		set_process(false)


func _on_press() -> void:
	_touching = true
	_dragging = false
	_pending = 0.0
	_velocity = 0.0
	_samples.clear()
	_stop_motion()


func _on_release() -> void:
	if not _touching:
		return
	_touching = false
	var was_dragging := _dragging
	_dragging = false
	_pending = 0.0
	if not was_dragging:
		return
	propagate_notification(NOTIFICATION_SCROLL_END)
	_record_sample()
	_velocity = _sampled_velocity()
	_samples.clear()
	if _out_of_bounds():
		_start_bounce()
	elif absf(_velocity) >= INERTIA_MIN_SPEED:
		set_process(true)


func _drag_by(delta_scroll: float) -> void:
	if not _touching:
		return
	if not _dragging:
		_pending += delta_scroll
		if absf(_pending) < DRAG_DEADZONE:
			return
		_dragging = true
		delta_scroll = _pending
		# 与原生行为一致：开始滚动时通知子按钮取消按下态
		propagate_notification(NOTIFICATION_SCROLL_BEGIN)
	_apply_scroll_delta(delta_scroll)
	_record_sample()


# 直跟：松手前不做任何插值，越界方向施加阻力
func _apply_scroll_delta(delta_scroll: float) -> void:
	var max_scroll := _max_scroll()
	var moving_outward := (_scroll_pos <= 0.0 and delta_scroll < 0.0) or (_scroll_pos >= max_scroll and delta_scroll > 0.0)
	if moving_outward:
		delta_scroll *= OVERSCROLL_RESIST
	_set_scroll_pos(_scroll_pos + delta_scroll)


func _record_sample() -> void:
	var now := Time.get_ticks_msec()
	_samples.append([now, _scroll_pos])
	while _samples.size() > 2 and now - int(_samples[0][0]) > VELOCITY_WINDOW_MS:
		_samples.pop_front()


# 初速度取最近 100ms 位移采样
func _sampled_velocity() -> float:
	if _samples.size() < 2:
		return 0.0
	var first: Array = _samples[0]
	var last: Array = _samples[_samples.size() - 1]
	var dt := float(int(last[0]) - int(first[0])) / 1000.0
	if dt <= 0.004:
		return 0.0
	return (float(last[1]) - float(first[1])) / dt


func _wheel(direction: float) -> void:
	_touching = false
	_dragging = false
	_velocity = 0.0
	_stop_motion()
	var target := clampf(_scroll_pos + direction * WHEEL_STEP, 0.0, _max_scroll())
	_start_tween_to(target, WHEEL_TIME)


# 边界回弹：TRANS_CUBIC 缓出
func _start_bounce() -> void:
	set_process(false)
	var target := clampf(_scroll_pos, 0.0, _max_scroll())
	if is_equal_approx(target, _scroll_pos):
		_set_scroll_pos(target)
		return
	_start_tween_to(target, BOUNCE_TIME)


func _start_tween_to(target: float, duration: float) -> void:
	_kill_bounce()
	_bounce_tween = create_tween()
	_bounce_tween.tween_method(_set_scroll_pos, _scroll_pos, target, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _stop_motion() -> void:
	_velocity = 0.0
	set_process(false)
	_kill_bounce()


func _kill_bounce() -> void:
	if _bounce_tween != null and _bounce_tween.is_valid():
		_bounce_tween.kill()
	_bounce_tween = null


func _set_scroll_pos(value: float) -> void:
	_scroll_pos = value
	_internal_set = true
	scroll_vertical = int(roundf(value))
	_internal_set = false


# 外部（焦点跟随、代码赋值）直接改 scroll_vertical 时同步浮点位置
func _on_bar_value_changed(value: float) -> void:
	if _internal_set:
		return
	_scroll_pos = value


func _max_scroll() -> float:
	var bar := get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


func _out_of_bounds() -> bool:
	return _scroll_pos < 0.0 or _scroll_pos > _max_scroll()
