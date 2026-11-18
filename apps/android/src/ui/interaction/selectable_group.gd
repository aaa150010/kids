class_name SelectableGroup
extends RefCounted

## 单选组管理：register 后由组统一切换选中态，视觉反馈用 apply_selected_visual
## 空点取消：在外层空白区域的 gui_input 里调 notify_empty_press()

signal selection_changed(value: Variant)

var accent := Color("#167d74")
var empty_press_clears := true

# Control -> 选中值
var _items: Dictionary = {}
var _selected: Control = null


func register(control: Control, value: Variant) -> void:
	_items[control] = value


func unregister(control: Control) -> void:
	_items.erase(control)
	if _selected == control:
		_selected = null


func select(value: Variant) -> void:
	var target: Control = null
	for control in _items.keys():
		if _items[control] == value:
			target = control
			break
	_apply(target)


func select_control(control: Control) -> void:
	if _items.has(control):
		_apply(control)


func clear() -> void:
	_apply(null)


func notify_empty_press() -> void:
	# 空点取消钩子：点到空白处时调用
	if empty_press_clears:
		clear()


func selected_value() -> Variant:
	if _selected == null or not is_instance_valid(_selected):
		return null
	return _items.get(_selected)


func has_selection() -> bool:
	return _selected != null and is_instance_valid(_selected)


func _apply(target: Control) -> void:
	if _selected == target:
		return
	if is_instance_valid(_selected):
		clear_visual(_selected)
	_selected = target
	if is_instance_valid(_selected):
		apply_selected_visual(_selected, accent)
	selection_changed.emit(selected_value())


## 选中反馈：2px 主色描边 + 放大 1.05 + 柔和阴影
static func apply_selected_visual(control: Control, tint: Color) -> void:
	var slot := "panel" if control is PanelContainer else "normal"
	if not control.has_meta("sg_saved_style"):
		control.set_meta("sg_saved_style", control.get_theme_stylebox(slot))
		control.set_meta("sg_saved_slot", slot)
	control.add_theme_stylebox_override(slot, PlaygroundUI.style(
		PlaygroundUI.mix(tint, Color.WHITE, 0.84), 18, tint, 2, 6, Color(0, 0, 0, 0.16)
	))
	control.pivot_offset = control.size * 0.5
	MotionKit.kill_owner(control)
	MotionKit.tween(control).tween_property(
		control, "scale", Vector2.ONE * 1.05, MotionKit.PRESS_UP
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 还原注册时的样式与缩放
static func clear_visual(control: Control) -> void:
	if control.has_meta("sg_saved_style"):
		var slot := str(control.get_meta("sg_saved_slot"))
		var saved: StyleBox = control.get_meta("sg_saved_style")
		control.add_theme_stylebox_override(slot, saved)
		control.remove_meta("sg_saved_style")
		control.remove_meta("sg_saved_slot")
	MotionKit.kill_owner(control)
	MotionKit.tween(control).tween_property(
		control, "scale", Vector2.ONE, MotionKit.PRESS_UP
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
