class_name DragController
extends Node

## 通用拖拽编排：ghost 是独立顶层浮层（CanvasLayer），不改造原控件树
## 用法：
##   var drag := DragController.new(); add_child(drag)
##   drag.begin(payload, func(): return _make_ghost(), {"start": pos, "hit_test": _hit_test})
##   drag.move_to(pos) / drag.drop(pos) / drag.cancel()
## 可选回调：opts.on_hover(target)、opts.on_drop(payload, pos, target)、opts.on_cancel()

signal drag_started(payload: Variant)
signal drag_moved(position: Vector2)
signal hover_changed(target: Variant)
signal dropped(payload: Variant, position: Vector2, target: Variant)
signal canceled(payload: Variant)

const GHOST_LAYER := 96 # 低于弹窗层（100），高于游戏内容

var active := false
var payload: Variant = null
var ghost: CanvasItem = null
var hover_target: Variant = null

var _layer: CanvasLayer
var _start_pos := Vector2.ZERO
var _offset := Vector2.ZERO
var _hit_test := Callable()
var _on_hover := Callable()
var _on_drop := Callable()
var _on_cancel := Callable()


func begin(payload_value: Variant, ghost_builder: Callable, opts: Dictionary = {}) -> bool:
	if active:
		return false
	var node: Variant = ghost_builder.call()
	if not (node is CanvasItem):
		push_warning("DragController: ghost_builder 必须返回 Control 或 Node2D")
		if node is Object and node.has_method("queue_free"):
			node.queue_free()
		return false
	# 弹窗接管输入时拒绝开拖
	var controller := _ipc()
	if controller != null and not controller.claim(&"drag", InteractionController.PRIORITY_DRAG):
		node.queue_free()
		return false
	payload = payload_value
	ghost = node
	_start_pos = opts.get("start", Vector2.ZERO)
	_offset = opts.get("offset", _default_offset(node))
	_hit_test = opts.get("hit_test", Callable())
	_on_hover = opts.get("on_hover", Callable())
	_on_drop = opts.get("on_drop", Callable())
	_on_cancel = opts.get("on_cancel", Callable())
	hover_target = null
	_ghost_layer().add_child(ghost)
	_place(_start_pos)
	active = true
	SfxMap.play(&"drag_start")
	drag_started.emit(payload)
	return true


func move_to(position: Vector2) -> void:
	if not active:
		return
	_place(position)
	drag_moved.emit(position)
	if _hit_test.is_valid():
		var target: Variant = _hit_test.call(position)
		if target != hover_target:
			hover_target = target
			hover_changed.emit(target)
			if _on_hover.is_valid():
				_on_hover.call(target)


func drop(position: Vector2) -> void:
	if not active:
		return
	move_to(position)
	var dropped_payload: Variant = payload
	var target: Variant = hover_target
	var callback := _on_drop
	_finish(true)
	SfxMap.play(&"drop")
	dropped.emit(dropped_payload, position, target)
	if callback.is_valid():
		callback.call(dropped_payload, position, target)


func cancel() -> void:
	if not active:
		return
	var canceled_payload: Variant = payload
	var callback := _on_cancel
	_finish(true)
	SfxMap.play(&"cancel")
	canceled.emit(canceled_payload)
	if callback.is_valid():
		callback.call()


func _exit_tree() -> void:
	_finish(true)


func _finish(free_ghost: bool) -> void:
	active = false
	if free_ghost and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	payload = null
	hover_target = null
	_hit_test = Callable()
	_on_hover = Callable()
	_on_drop = Callable()
	_on_cancel = Callable()
	var controller := _ipc()
	if controller != null:
		controller.release(&"drag")


func _place(position: Vector2) -> void:
	if ghost is Control or ghost is Node2D:
		ghost.set("position", position + _offset)


func _default_offset(node: CanvasItem) -> Vector2:
	# 默认让 ghost 中心跟随触点
	if node is Control:
		return -node.size * 0.5
	return Vector2.ZERO


func _ghost_layer() -> CanvasLayer:
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = GHOST_LAYER
		_layer.name = "DragGhostLayer"
		add_child(_layer)
	return _layer


func _ipc() -> InteractionController:
	var tree := get_tree()
	if tree == null:
		return null
	var hub := tree.get_first_node_in_group("main_hub")
	if hub == null:
		return null
	return hub.get("ipc")
