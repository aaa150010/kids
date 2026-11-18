class_name InteractionController
extends Node

## 全局输入仲裁（由 main 实例化，通过 main_hub 组的 ipc 属性访问）
## 高优先级持有者接管期间，低优先级交互应主动忽略输入
## 用法：拖拽前 claim(&"drag", PRIORITY_DRAG)，结束时 release(&"drag")

signal owner_changed(owner: StringName, priority: int)

const PRIORITY_DIALOG := 500 # 弹窗（最高，覆盖一切游戏输入）
const PRIORITY_DRAG := 400   # 拖拽中
const PRIORITY_SELECT := 300 # 选中/点选流程
const PRIORITY_BOARD := 100  # 棋盘等常规游戏输入
const PRIORITY_IDLE := 0     # 无持有者

# StringName -> int
var _claims: Dictionary = {}


func claim(owner: StringName, priority: int) -> bool:
	var top := current_priority()
	var holder := current_owner()
	if not _claims.has(owner) and priority < top:
		return false # 已有更高优先级的持有者，拒绝接管
	_claims[owner] = priority
	var now_owner := current_owner()
	if now_owner != holder or current_priority() != top:
		owner_changed.emit(now_owner, current_priority())
	return true


func release(owner: StringName) -> void:
	if not _claims.has(owner):
		return
	_claims.erase(owner)
	owner_changed.emit(current_owner(), current_priority())


func current_owner() -> StringName:
	var best := &""
	var top := PRIORITY_IDLE
	for owner in _claims.keys():
		var priority := int(_claims[owner])
		if priority >= top:
			top = priority
			best = owner
	return best


func current_priority() -> int:
	var top := PRIORITY_IDLE
	for priority in _claims.values():
		top = maxi(top, int(priority))
	return top


func is_blocked_by_dialog() -> bool:
	# 供游戏查询弹窗是否接管了输入
	return current_priority() >= PRIORITY_DIALOG


func reset() -> void:
	_claims.clear()
	owner_changed.emit(&"", PRIORITY_IDLE)
