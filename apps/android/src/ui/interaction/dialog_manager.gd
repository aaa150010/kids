class_name DialogManager
extends Node

## 统一弹窗管理（由 main 实例化，通过 main_hub 组的 dialogs 属性访问）
## 三档宽度：S / M / L，高度随内容展开；固定标题、正文、操作区，不显示内部滚动条
## 弹窗栈：close_top() 关栈顶；关闭后焦点恢复到打开前控件
## opts 支持的键：
##   title(String) / body(Control|String) / buttons(Array[{text,kind,callback}])
##   size("S"|"M"|"L") / width(float 覆盖)
##   accent(Color) / eyebrow(String) / dismissible(bool, 供返回键判断)
##   mask_close(bool, 点遮罩关闭，默认 false) / scroll(bool) / separation(int)
##   max_content_height(float) / fit_content(bool) / on_close(Callable)

signal dialog_opened(layer: Control)
signal dialog_closed(layer: Control)

const SIZE_RATIOS := {"S": 0.38, "M": 0.56, "L": 0.78}
const MAX_WIDTH := 1120.0
const MIN_WIDTH := 360.0
const MAX_HEIGHT := 900.0
const SAFE_MARGIN := 24.0        # 距屏幕边缘安全边距
const DIM_ALPHA := 0.38          # 遮罩不透明度
const ANIM_IN := 0.20            # 进场 180–220ms
const ANIM_OUT := 0.16
const BUTTON_HEIGHT := 60.0      # 主按钮高度 56–64px
const BUTTON_FONT := 22          # 按钮字号下限
const BUTTON_PAIR_MIN := 200.0   # 双按钮等宽最小值
const DEFAULT_ACCENT := Color("#167d74")

var _stack: Array[Control] = []
var _dialog_layer: CanvasLayer
var _toast_layer: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dialog_layer = CanvasLayer.new()
	_dialog_layer.layer = 100
	_dialog_layer.name = "DialogLayer"
	add_child(_dialog_layer)
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 128
	_toast_layer.name = "ToastLayer"
	add_child(_toast_layer)
	get_viewport().size_changed.connect(_resize_dialogs)
	get_viewport().gui_focus_changed.connect(_guard_focus)


func show_dialog(opts: Dictionary) -> Control:
	var screen_size := get_viewport().get_visible_rect().size
	var angle := float(opts.get("facing_angle", 0.0))
	var viewport_size := TabletopLayout.canvas_size(screen_size, angle)
	var accent: Color = opts.get("accent", DEFAULT_ACCENT)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.set_meta("dismissible", bool(opts.get("dismissible", true)))
	if opts.has("on_close"):
		layer.set_meta("on_close", opts["on_close"])
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.16, 0.13, DIM_ALPHA)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	if bool(opts.get("mask_close", false)):
		dim.gui_input.connect(func(event: InputEvent):
			var clicked: bool = event is InputEventScreenTouch and event.pressed
			clicked = clicked or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
			if clicked:
				close_layer(layer, true)
		)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)
	TabletopLayout.layout_canvas(canvas, screen_size, angle)
	layer.set_meta("facing_canvas", canvas)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	var card := PanelContainer.new()
	var panel_style := PlaygroundUI.style(
		PlaygroundUI.PAPER, 28, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2, 12, Color(0, 0, 0, 0.22)
	)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 20
	panel_style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", panel_style)
	var card_size := _card_size(str(opts.get("size", "M")), viewport_size, opts)
	card.custom_minimum_size = Vector2(card_size.x, 0.0)
	layer.set_meta("card", card)
	layer.set_meta("options", opts.duplicate())
	layer.focus_mode = Control.FOCUS_ALL
	center.add_child(card)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", int(opts.get("separation", 16)))
	card.add_child(column)
	var eyebrow := str(opts.get("eyebrow", ""))
	var title := str(opts.get("title", ""))
	var dismissible := bool(opts.get("dismissible", true))
	if dismissible or not eyebrow.is_empty() or not title.is_empty():
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 16)
		var heading := VBoxContainer.new()
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_theme_constant_override("separation", 3)
		if not eyebrow.is_empty():
			heading.add_child(PlaygroundUI.label(eyebrow, 14, accent, 700))
		if not title.is_empty():
			heading.add_child(PlaygroundUI.label(title, 30, PlaygroundUI.INK, 700, true))
		header.add_child(heading)
		if dismissible:
			var close := PlaygroundUI.icon_button("×", accent, func(): close_layer(layer, true), "关闭")
			close.focus_mode = Control.FOCUS_NONE
			header.add_child(close)
		column.add_child(header)
		column.add_child(PlaygroundUI.separator(PlaygroundUI.mix(accent, Color.WHITE, 0.78)))
	var body_value: Variant = opts.get("body")
	var body: Control
	if body_value is Control:
		body = body_value
	else:
		# 允许直接传文本
		body = PlaygroundUI.label("" if body_value == null else str(body_value), 16, PlaygroundUI.INK_SOFT, 500, true)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fit_content := bool(opts.get("fit_content", false))
	if fit_content or not bool(opts.get("scroll", true)):
		# 表单弹窗按内容自然展开，不套滚动框。
		column.add_child(body)
	else:
		var body_scroll := ScrollContainer.new()
		body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_scroll.add_child(body)
		body_scroll.custom_minimum_size.y = minf(maxf(52.0, body.get_combined_minimum_size().y), _body_limit(viewport_size, opts))
		column.add_child(body_scroll)
		layer.set_meta("body_scroll", body_scroll)
		layer.set_meta("body", body)
	var buttons: Array = opts.get("buttons", [])
	if not buttons.is_empty():
		column.add_child(PlaygroundUI.separator(PlaygroundUI.mix(accent, Color.WHITE, 0.82)))
		column.add_child(_button_row(buttons, accent, card_size.x))
	var prev_focus := get_viewport().gui_get_focus_owner()
	if prev_focus != null:
		layer.set_meta("prev_focus", prev_focus)
	_dialog_layer.add_child(layer)
	_stack.append(layer)
	layer.tree_exiting.connect(func(): _forget_layer(layer))
	# 进场动画：scale 0.9 → 1（back-out）+ 淡入
	card.modulate.a = 0.0
	card.scale = Vector2.ONE * 0.9
	card.resized.connect(func(): card.pivot_offset = card.size * 0.5)
	var animation := MotionKit.tween(self)
	animation.set_parallel(true)
	animation.tween_property(card, "modulate:a", 1.0, ANIM_IN)
	animation.tween_property(card, "scale", Vector2.ONE, ANIM_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var focusables := card.find_children("*", "BaseButton", true, false).filter(
		func(control): return (control as Control).focus_mode != Control.FOCUS_NONE
	)
	if not focusables.is_empty():
		focusables[0].call_deferred("grab_focus")
	_claim_ipc()
	SfxMap.play(&"dialog_open")
	dialog_opened.emit(layer)
	return layer


func show_confirm(
	title: String,
	body: String,
	confirm_text := "确定",
	cancel_text := "取消",
	accent := DEFAULT_ACCENT,
	on_confirm := Callable(),
	on_cancel := Callable()
) -> Control:
	var manager := self
	var identity := []
	var cancel_action := func():
		manager.close_layer(identity[0])
		if on_cancel.is_valid():
			on_cancel.call()
	var confirm_action := func():
		manager.close_layer(identity[0])
		if on_confirm.is_valid():
			on_confirm.call()
	var layer := show_dialog({
		"title": title,
		"body": PlaygroundUI.label(body, 17, PlaygroundUI.INK_SOFT, 500, true),
		"accent": accent,
		"size": "S",
		"buttons": [
			{"text": cancel_text, "kind": "ghost", "callback": cancel_action},
			{"text": confirm_text, "kind": "primary", "callback": confirm_action},
		],
	})
	identity.append(layer)
	return layer


func show_toast(text: String, duration := 2.4) -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(holder)
	var toast := PanelContainer.new()
	toast.add_theme_stylebox_override("panel", PlaygroundUI.style(
		Color(0.15, 0.18, 0.16, 0.92), 16, Color.TRANSPARENT, 0, 8, Color(0, 0, 0, 0.25)
	))
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(PlaygroundUI.label(text, 16, Color.WHITE, 700))
	holder.add_child(toast)
	toast.position = Vector2(0, 56)
	toast.modulate.a = 0.0
	var tween := MotionKit.tween(self)
	tween.set_parallel(true)
	tween.tween_property(toast, "modulate:a", 1.0, 0.14)
	tween.tween_property(toast, "position:y", 72.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT) # 淡入上浮
	tween.chain().tween_interval(duration)
	tween.tween_property(toast, "modulate:a", 0.0, 0.25)
	tween.tween_callback(holder.queue_free)


func close_top(respect_dismissible: bool = false) -> bool:
	if _stack.is_empty():
		return false
	return close_layer(_stack.back(), respect_dismissible)


func owns_layer(layer: Control) -> bool:
	return is_instance_valid(layer) and layer in _stack


func close_layer(layer: Control, respect_dismissible: bool = false) -> bool:
	if not owns_layer(layer):
		return false
	if respect_dismissible and not bool(layer.get_meta("dismissible", true)):
		return false
	layer.hide()
	_forget_layer(layer)
	layer.queue_free()
	SfxMap.play(&"dialog_close")
	return true


func _forget_layer(layer: Control) -> void:
	if layer not in _stack:
		return
	var was_top: bool = layer == _stack.back()
	var previous: Variant = layer.get_meta("prev_focus") if layer.has_meta("prev_focus") else null
	# 中间层被移除时，把其焦点链接续到后继层。
	for above in _stack:
		var focus: Variant = above.get_meta("prev_focus") if above.has_meta("prev_focus") else null
		if is_instance_valid(focus) and layer.is_ancestor_of(focus):
			above.set_meta("prev_focus", previous)
	_stack.erase(layer)
	if _stack.is_empty():
		_release_ipc()
	dialog_closed.emit(layer)
	if layer.has_meta("on_close"):
		var on_close: Callable = layer.get_meta("on_close")
		if on_close.is_valid():
			on_close.call()
	if was_top:
		_restore_focus(layer)


func _resize_dialogs() -> void:
	for layer in _stack:
		var card: Control = layer.get_meta("card")
		var opts: Dictionary = layer.get_meta("options")
		var screen_size := get_viewport().get_visible_rect().size
		var angle := float(opts.get("facing_angle", 0.0))
		var viewport_size := TabletopLayout.canvas_size(screen_size, angle)
		var canvas: Control = layer.get_meta("facing_canvas")
		TabletopLayout.layout_canvas(canvas, screen_size, angle)
		var target := _card_size(str(opts.get("size", "M")), viewport_size, opts)
		card.custom_minimum_size = Vector2(target.x, 0.0)
		if layer.has_meta("body_scroll"):
			var body_scroll: ScrollContainer = layer.get_meta("body_scroll")
			var body: Control = layer.get_meta("body")
			body_scroll.custom_minimum_size.y = minf(
				maxf(52.0, body.get_combined_minimum_size().y),
				_body_limit(viewport_size, opts)
			)


func _guard_focus(control: Control) -> void:
	if _stack.is_empty():
		return
	var top: Control = _stack.back()
	if control != top and not top.is_ancestor_of(control):
		top.call_deferred("grab_focus")


func close_all() -> void:
	while close_top():
		pass


func has_open_dialog() -> bool:
	return not _stack.is_empty()


func stack_size() -> int:
	return _stack.size()


func top_layer() -> Control:
	return null if _stack.is_empty() else _stack.back()


func _card_size(tier: String, viewport_size: Vector2, opts: Dictionary) -> Vector2:
	var ratio := float(SIZE_RATIOS.get(tier, SIZE_RATIOS["M"]))
	var available := maxf(MIN_WIDTH, viewport_size.x - SAFE_MARGIN * 2.0)
	var width := clampf(viewport_size.x * ratio, minf(MIN_WIDTH, available), minf(MAX_WIDTH, available))
	if opts.has("width"):
		width = clampf(float(opts["width"]), minf(MIN_WIDTH, available), minf(MAX_WIDTH, available))
	return Vector2(width, 0.0)


func _body_limit(viewport_size: Vector2, opts: Dictionary) -> float:
	var max_card_height := minf(maxf(320.0, viewport_size.y - SAFE_MARGIN * 2.0), MAX_HEIGHT)
	var limit := maxf(180.0, max_card_height - 240.0)
	if opts.has("max_content_height"):
		limit = minf(limit, maxf(120.0, float(opts["max_content_height"])))
	return limit


func _button_row(actions: Array, accent: Color, card_width: float) -> Control:
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_END
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 10)
	var pair := actions.size() == 2
	# 宽屏不再把两个操作拉满整行，保持紧凑的玩具按钮比例。
	var pair_width := clampf((card_width - 72.0) * 0.5, BUTTON_PAIR_MIN, 240.0)
	for action in actions:
		var button := PlaygroundUI.button(
			str(action.get("text", "好")),
			accent,
			action.get("callback", Callable()),
			str(action.get("kind", "primary"))
		)
		button.custom_minimum_size.y = BUTTON_HEIGHT
		button.add_theme_font_size_override("font_size", BUTTON_FONT)
		button.custom_minimum_size.x = pair_width if pair else maxf(button.custom_minimum_size.x, 160.0)
		row.add_child(button)
	return row


func _restore_focus(layer: Control) -> void:
	var control: Control = layer.get_meta("prev_focus") if layer.has_meta("prev_focus") else null
	if is_instance_valid(control) and not control.is_queued_for_deletion() and control.is_visible_in_tree():
		if _stack.is_empty() or _stack.back().is_ancestor_of(control):
			control.grab_focus()
			return
	if not _stack.is_empty():
		_stack.back().grab_focus()


func _ipc() -> InteractionController:
	var tree := get_tree()
	if tree == null:
		return null
	var hub := tree.get_first_node_in_group("main_hub")
	if hub == null:
		return null
	return hub.get("ipc")


func _claim_ipc() -> void:
	var controller := _ipc()
	if controller != null:
		controller.claim(&"dialog", InteractionController.PRIORITY_DIALOG)


func _release_ipc() -> void:
	var controller := _ipc()
	if controller != null:
		controller.release(&"dialog")
