class_name LobbyGameCard
extends PanelContainer

signal launch_requested(game_id: String)
signal help_requested(game_id: String)
signal move_requested(game_id: String, direction: int)
signal sort_drag_started(game_id: String, global_pos: Vector2)
signal sort_drag_moved(game_id: String, global_pos: Vector2)
signal sort_drag_ended(game_id: String, global_pos: Vector2)

var game: Dictionary = {}
var game_id := ""
var accent := Color("#d56c29")
var sorting := false
var can_resume := false
var viewport_size := Vector2(1600, 1000)

var _recognizer: GestureRecognizer = null
var _cover: TextureRect = null
var _sort_dragging := false
var _pressed_visual := false
var _last_global := Vector2.ZERO
var _hover_bound := false


func configure(meta: Dictionary, resume: bool, sort_mode: bool, current_viewport_size: Vector2 = Vector2(1600, 1000)) -> void:
	game = meta
	game_id = str(meta.get("id", ""))
	accent = PlaygroundUI.color(str(meta.get("accent", "#d56c29")))
	can_resume = resume
	sorting = sort_mode
	viewport_size = current_viewport_size
	_build(true)


# 排序开关切换：只重建卡片内部，封面走缓存，不动大厅树
func set_sorting(value: bool) -> void:
	if sorting == value:
		return
	sorting = value
	_build(false)


# 排序落位/左右移动后的轻弹提示（只动 scale）
func pulse() -> void:
	_sync_pivot()
	MotionKit.kill_owner(self)
	modulate.a = 1.0
	var pop := MotionKit.tween(self)
	pop.tween_property(self, "scale", Vector2(1.045, 1.045), 0.09)
	pop.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if sorting:
		pop.tween_callback(_start_breathe)


func _build(animate: bool = true) -> void:
	MotionKit.kill_owner(self)
	scale = Vector2.ONE
	modulate = Color.WHITE
	for child in get_children():
		remove_child(child)
		child.queue_free()
	# 手势识别器（tap / 长按 / 拖动仲裁），Node 类型不参与 Container 布局
	_recognizer = GestureRecognizer.new()
	_recognizer.name = "GestureRecognizer"
	add_child(_recognizer)
	_recognizer.tap.connect(_on_tap)
	_recognizer.long_press.connect(_on_long_press)
	_recognizer.drag_start.connect(_on_recognizer_drag_start)
	_recognizer.drag_move.connect(_on_recognizer_drag_move)
	_recognizer.drag_end.connect(_on_recognizer_drag_end)
	if not resized.is_connected(_sync_pivot):
		resized.connect(_sync_pivot)
	_sync_pivot()
	var soft := PlaygroundUI.color(str(game.get("soft", "#ffead3")))
	var metrics := PlaygroundUI.layout_metrics(viewport_size)
	var compact := bool(metrics.compact_cards)
	var columns := int(metrics.columns)
	var grid_margin := float(metrics.margin)
	var grid_gap := float(metrics.gap)
	var estimated_grid_width: float = viewport_size.x - grid_margin * 2.0 - 8.0 - grid_gap * float(columns - 1)
	var estimated_card_width: float = estimated_grid_width / float(columns)
	var cover_height: float = maxf(132.0, roundf(maxf(1.0, estimated_card_width - 32.0) * 9.0 / 16.0))
	add_theme_stylebox_override("panel", PlaygroundUI.style(soft, 24, PlaygroundUI.mix(accent, Color.WHITE, 0.58), 2, 7, Color(0, 0, 0, 0.13)))
	custom_minimum_size = Vector2(metrics.card_min_width, 324 if compact else 342)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 9)
	add_child(column)
	var cover_wrap := PanelContainer.new()
	cover_wrap.custom_minimum_size.y = cover_height
	cover_wrap.clip_contents = true
	cover_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 封面圆角与卡片内侧圆角保持一致
	cover_wrap.add_theme_stylebox_override("panel", PlaygroundUI.style(PlaygroundUI.mix(accent, Color.WHITE, 0.86), 20, Color.TRANSPARENT))
	_cover = TextureRect.new()
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cover_path := str(game.get("cover", ""))
	var cached := LobbyCoverCache.texture(cover_path)
	if cached != null:
		_cover.texture = cached
	elif not cover_path.is_empty():
		# 缓存未命中：先显示 cover_wrap 占位色块，线程解码完成后回填
		_cover.modulate.a = 0.0
		LobbyCoverCache.request(cover_path, _on_cover_ready.bind(_cover, cover_path))
	cover_wrap.add_child(_cover)
	var cover_tint := ColorRect.new()
	cover_tint.color = Color(accent, 0.08)
	cover_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_wrap.add_child(cover_tint)
	var deco_token := str(game.get("icon", "🎮"))
	if ArtLibrary.texture(deco_token) != null:
		var deco := ArtLibrary.picture(deco_token, Vector2(48, 48))
		deco.position = Vector2(16, 12)
		cover_wrap.add_child(deco)
	else:
		var deco := PlaygroundUI.label(deco_token, 48, accent, 700)
		deco.position = Vector2(16, 12)
		deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover_wrap.add_child(deco)
	column.add_child(cover_wrap)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 7)
	tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_child(PlaygroundUI.chip(str(game.get("category", "小游戏")), accent))
	if can_resume:
		tag_row.add_child(PlaygroundUI.chip("▶ 可继续", Color("#d98b2b")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_row.add_child(spacer)
	var help := PlaygroundUI.icon_asset_button("📖", accent, func(): help_requested.emit(game_id), "查看玩法")
	help.custom_minimum_size = Vector2(48, 48)
	help.tooltip_text = "查看玩法"
	tag_row.add_child(help)
	column.add_child(tag_row)
	var title := PlaygroundUI.label(str(game.get("title", "小游戏")), 22 if compact else 25, PlaygroundUI.INK, 700, true)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var subtitle := PlaygroundUI.label(str(game.get("subtitle", "")), 13 if compact else 14, PlaygroundUI.INK_SOFT, 500, true)
	subtitle.max_lines_visible = 1 if compact else 2
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(subtitle)
	var feature_row := HFlowContainer.new()
	feature_row.add_theme_constant_override("h_separation", 5)
	feature_row.add_theme_constant_override("v_separation", 5)
	feature_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not compact:
		for feature in game.get("features", []).slice(0, 2):
			feature_row.add_child(PlaygroundUI.chip(str(feature), accent))
		column.add_child(feature_row)
	var stretch := Control.new()
	stretch.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stretch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(stretch)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var players := PlaygroundUI.label(str(game.get("players", "1 人")), 12, PlaygroundUI.INK_SOFT, 700)
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(players)
	var start_text := "继续" if can_resume else "开始"
	var start := PlaygroundUI.button(start_text, accent, func(): launch_requested.emit(game_id))
	start.custom_minimum_size = Vector2(112, 48)
	start.add_theme_font_size_override("font_size", 20)
	start.disabled = sorting
	footer.add_child(start)
	column.add_child(footer)
	if sorting:
		var sort_overlay := ColorRect.new()
		sort_overlay.color = Color(1, 1, 1, 0.12)
		sort_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sort_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sort_overlay)
		var grip := PlaygroundUI.label("⠿ 长按拖动", 15, accent, 700)
		grip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		grip.position = Vector2(-118, 12)
		grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(grip)
		var controls := HBoxContainer.new()
		controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
		controls.position = Vector2(10, 10)
		controls.add_theme_constant_override("separation", 4)
		var left := PlaygroundUI.button("←", accent, func(): move_requested.emit(game_id, -1), "soft")
		var right := PlaygroundUI.button("→", accent, func(): move_requested.emit(game_id, 1), "soft")
		left.custom_minimum_size = Vector2(48, 48)
		right.custom_minimum_size = Vector2(48, 48)
		controls.add_child(left)
		controls.add_child(right)
		add_child(controls)
		_start_breathe()
	_bind_hover_once()
	if animate:
		MotionKit.fade_in(self, self, MotionKit.CARD_IN, 0.0)


# 排序模式的呼吸摆动提示（仅 scale，交错相位避免整屏同步晃动）
func _start_breathe() -> void:
	if not sorting or not is_inside_tree():
		return
	_sync_pivot()
	var phase := float(absi(hash(game_id)) % 100) / 100.0 * 0.4
	var breathe := MotionKit.tween(self)
	breathe.set_loops()
	breathe.tween_interval(phase)
	breathe.tween_property(self, "scale", Vector2(1.015, 1.015), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(self, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _sync_pivot() -> void:
	pivot_offset = size * 0.5


func _bind_hover_once() -> void:
	if _hover_bound:
		return
	_hover_bound = true
	mouse_entered.connect(_on_hover_enter)
	mouse_exited.connect(_on_hover_exit)


func _on_hover_enter() -> void:
	if sorting or _sort_dragging or _pressed_visual:
		return
	MotionKit.kill_owner(self)
	MotionKit.tween(self).tween_property(self, "scale", Vector2(1.012, 1.012), 0.12)


func _on_hover_exit() -> void:
	if sorting or _sort_dragging:
		return # 排序态的呼吸动画自行管理 scale
	MotionKit.kill_owner(self)
	MotionKit.tween(self).tween_property(self, "scale", Vector2.ONE, 0.12)


# 手势仲裁入口：卡片抢占触点焦点，之后的拖动/松开先到本卡
# ——普通拖动不 accept，事件冒泡给上层 SmoothScrollContainer 滚动；
# ——排序模式长按 ≥0.45s 且位移 <16px 才进入排序拖拽，之后拖动由本卡 accept
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch and event.canceled:
		cancel_gesture()
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# 触摸事件在 _gui_input 中本来就是视口全局坐标
		_last_global = event.position
	elif event is InputEventMouse:
		# 鼠标事件在 _gui_input 中已被转换为卡片本地坐标，换回全局
		_last_global = get_global_transform_with_canvas() * event.position
	var is_press: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	var is_release: bool = (event is InputEventScreenTouch and not event.pressed) \
		or (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if is_press:
		_press_visual(true)
		accept_event()
	elif is_release:
		accept_event()
		if _sort_dragging:
			# 长按后未拖满 16px 时识别器不会发 drag_end，这里兜底收尾
			_sort_dragging = false
			sort_drag_ended.emit(game_id, _last_global)
		_recognizer.forward(event)
		_press_visual(false)
		return
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _sort_dragging:
		accept_event()
	_recognizer.forward(event)


func _press_visual(pressed: bool) -> void:
	if pressed == _pressed_visual:
		return
	_pressed_visual = pressed
	_sync_pivot()
	MotionKit.kill_owner(self)
	if pressed:
		SfxMap.play(&"tap")
		MotionKit.tween(self).tween_property(self, "scale", Vector2.ONE * 0.97, MotionKit.PRESS_DOWN)
	else:
		var back := MotionKit.tween(self)
		back.tween_property(self, "scale", Vector2.ONE, MotionKit.PRESS_UP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if sorting and not _sort_dragging:
			back.tween_callback(_start_breathe)


func _on_tap(_position: Vector2, _index: int) -> void:
	if sorting:
		return
	launch_requested.emit(game_id)


func _on_long_press(_position: Vector2, _index: int) -> void:
	if not sorting or _sort_dragging:
		return
	_sort_dragging = true
	_press_visual(false)
	sort_drag_started.emit(game_id, _last_global)


func _on_recognizer_drag_start(_position: Vector2, _index: int) -> void:
	if _sort_dragging:
		return
	# 位移超过阈值：判定为滚动，取消按压态，事件冒泡给滚动容器
	_press_visual(false)


func _on_recognizer_drag_move(_position: Vector2, _delta: Vector2, _index: int) -> void:
	if _sort_dragging:
		sort_drag_moved.emit(game_id, _last_global)


func _on_recognizer_drag_end(_position: Vector2, _index: int) -> void:
	if _sort_dragging:
		_sort_dragging = false
		sort_drag_ended.emit(game_id, _last_global)
	_press_visual(false)


func cancel_gesture() -> void:
	if is_instance_valid(_recognizer):
		_recognizer.cancel_all()
	_sort_dragging = false
	_press_visual(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCROLL_BEGIN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_gesture()


# 封面线程解码完成后的回填
func _on_cover_ready(loaded: Texture2D, target: TextureRect, path: String) -> void:
	if loaded == null or not is_instance_valid(target) or target != _cover or is_queued_for_deletion() or path != str(game.get("cover", "")):
		return
	_cover.texture = loaded
	var fade := MotionKit.tween(self)
	fade.tween_property(_cover, "modulate:a", 1.0, 0.18)
