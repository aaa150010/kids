class_name NativeGameScreen
extends Control

signal back_requested
signal restart_requested
signal pause_changed(paused: bool)

var game_id := ""
var game_meta: Dictionary = {}
var players: Array = []
var accent := Color("#167d74")
var paused := false
var immersive := false
var content_root: VBoxContainer
var overlay_root: Control
var topbar: Control
var layout_root: VBoxContainer
var _immersive_bar: HBoxContainer
var _immersive_canvas: Control
var _toast_canvas: Control
var _interaction_seat := -1
var _last_touch_msec := -1000
var _immersive_controls_generation := 0
var _immersive_tap_times: Array = []
var _immersive_tap_position := Vector2.ZERO
var toast_label: Label
var settings_button: Button
var _modal_stack: Array[Control] = []
var mode_id := "classic"
var level_id := 1
var session_id := ""
var difficulty_pref := "auto"
var difficulty := "normal"
var lesson_banner: PanelContainer
var lesson_label: Label
var lesson_step := 0
var lesson_actions: Array = []
var lesson_texts: Array = []
var lesson_visible := false
var _save_interval := 0.0


func setup(meta: Dictionary, selected_players: Array) -> void:
	game_meta = meta
	game_id = str(meta.get("id", ""))
	players = selected_players
	accent = PlaygroundUI.color(str(meta.get("accent", "#167d74")))
	mode_id = str(meta.get("modeId", "classic"))
	difficulty_pref = str(meta.get("difficultyPreference", "auto"))
	difficulty = GameTuning.resolve(difficulty_pref, players)
	if not GameTuning.supports(game_id):
		difficulty_pref = "auto"
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))


func build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	PlaygroundUI.install_theme(self)
	add_child(PlaygroundUI.background(accent))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var safe := PlaygroundUI.safe_insets(get_viewport_rect().size)
	var vertical_safe := minf(float(safe.top), float(safe.bottom))
	margin.add_theme_constant_override("margin_left", int(maxf(metrics.margin,float(safe.left)+10.0)))
	margin.add_theme_constant_override("margin_right", int(maxf(metrics.margin,float(safe.right)+10.0)))
	margin.add_theme_constant_override("margin_top", int(maxf(10.0,vertical_safe+6.0)))
	margin.add_theme_constant_override("margin_bottom", int(maxf(10.0,vertical_safe+6.0)))
	add_child(margin)
	layout_root = VBoxContainer.new()
	layout_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_root.add_theme_constant_override("separation", 12)
	margin.add_child(layout_root)
	topbar = _build_topbar()
	layout_root.add_child(topbar)
	immersive = true
	topbar.visible = false
	layout_root.add_theme_constant_override("separation", 6)
	lesson_banner = PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.85), 18, accent, 2)
	var lesson_row := HBoxContainer.new()
	lesson_label = PlaygroundUI.label("", 18, PlaygroundUI.INK, 700, true)
	lesson_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lesson_row.add_child(lesson_label)
	lesson_row.add_child(PlaygroundUI.button("跳过教学", accent, _finish_lesson, "soft"))
	lesson_banner.add_child(lesson_row)
	layout_root.add_child(lesson_banner)
	lesson_banner.hide()
	content_root = VBoxContainer.new()
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_theme_constant_override("separation", 12)
	layout_root.add_child(content_root)
	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_root)
	_build_immersive_bar()
	_toast_canvas = Control.new()
	_toast_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_canvas)
	TabletopLayout.layout_canvas(_toast_canvas, get_viewport_rect().size, 0.0)
	toast_label = PlaygroundUI.label("", 18, Color.WHITE, 700)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.z_index = 80
	toast_label.add_theme_stylebox_override("normal", PlaygroundUI.style(Color(0.15, 0.18, 0.16, 0.94), 12, Color.TRANSPARENT, 0))
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.modulate.a = 0.0
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(0, 24)
	_toast_canvas.add_child(toast_label)
	resized.connect(_layout_immersive_controls)


func _build_immersive_bar() -> void:
	_immersive_canvas = Control.new()
	_immersive_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_immersive_canvas)
	TabletopLayout.layout_canvas(_immersive_canvas, get_viewport_rect().size, 0.0)
	_immersive_bar = HBoxContainer.new()
	_immersive_bar.anchor_left = 1.0
	_immersive_bar.anchor_right = 1.0
	_immersive_bar.anchor_top = 0.0
	_immersive_bar.anchor_bottom = 0.0
	_immersive_bar.offset_left = -360.0
	_immersive_bar.offset_right = -16.0
	_immersive_bar.offset_top = 12.0
	_immersive_bar.offset_bottom = 60.0
	_immersive_bar.alignment = BoxContainer.ALIGNMENT_END
	_immersive_bar.add_theme_constant_override("separation", 8)
	_immersive_bar.z_index = 60
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(70, 48)
	rules.add_theme_font_size_override("font_size", 17)
	_immersive_bar.add_child(rules)
	var pause := PlaygroundUI.button("Ⅱ 暂停", accent, toggle_pause, "soft")
	pause.custom_minimum_size = Vector2(96, 48)
	pause.add_theme_font_size_override("font_size", 17)
	_immersive_bar.add_child(pause)
	var exit := PlaygroundUI.button("退出全屏", accent, func(): set_immersive(false), "primary")
	exit.custom_minimum_size = Vector2(112, 48)
	exit.add_theme_font_size_override("font_size", 17)
	_immersive_bar.add_child(exit)
	_immersive_bar.visible = false
	_immersive_canvas.add_child(_immersive_bar)


func face_to_face() -> bool:
	return TabletopLayout.enabled(game_id, players, mode_id)


func _current_seat() -> int:
	if not face_to_face():
		return 0
	var rules: Variant = get("engine")
	return clampi(int(rules.state.get("turn", 0)), 0, 1) if rules != null else 0


func _overlay_angle() -> float:
	return TabletopLayout.facing_angle(_interaction_seat if _interaction_seat >= 0 else _current_seat(), face_to_face())


func _layout_immersive_controls() -> void:
	if is_instance_valid(_immersive_canvas):
		TabletopLayout.layout_canvas(_immersive_canvas, get_viewport_rect().size, _overlay_angle())
		if face_to_face():
			var bar_width := maxf(344.0, _immersive_bar.get_combined_minimum_size().x)
			_immersive_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			_immersive_bar.offset_left = -bar_width * 0.5
			_immersive_bar.offset_right = bar_width * 0.5
			_immersive_bar.offset_top = -64.0
			_immersive_bar.offset_bottom = -16.0


func _build_topbar() -> Control:
	var bar := PlaygroundUI.panel(Color(1, 1, 1, 0.76), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.6), 1)
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var compact := bool(metrics.compact_cards)
	bar.custom_minimum_size.y = metrics.topbar
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var back := PlaygroundUI.icon_button("←", accent, _handle_back, "返回")
	back.custom_minimum_size = Vector2(52, 48)
	back.add_theme_font_size_override("font_size", 24)
	row.add_child(back)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 0)
	title_box.add_child(PlaygroundUI.label(str(game_meta.get("title", "小游戏")), 22 if compact else 24, PlaygroundUI.INK, 700))
	if not compact:
		var subtitle := str(game_meta.get("subtitle", ""))
		if GameTuning.supports(game_id):
			subtitle += " · " + GameTuning.label(difficulty)
		title_box.add_child(PlaygroundUI.label(subtitle, 12, PlaygroundUI.INK_SOFT, 500))
	row.add_child(title_box)
	if compact and GameTuning.supports(game_id):
		row.add_child(PlaygroundUI.chip(GameTuning.label(difficulty), accent))
	_extra_topbar_actions(row)
	var fullscreen := PlaygroundUI.button("全屏", accent, func(): set_immersive(true), "soft")
	fullscreen.custom_minimum_size = Vector2(64, 48)
	fullscreen.add_theme_font_size_override("font_size", 16)
	row.add_child(fullscreen)
	var pause := PlaygroundUI.button("Ⅱ  暂停", accent, toggle_pause, "soft")
	pause.custom_minimum_size = Vector2(108, 48)
	row.add_child(pause)
	return bar


func _extra_topbar_actions(_row: HBoxContainer) -> void:
	pass


func show_game_rules() -> void:
	show_help()


func set_immersive(value: bool) -> void:
	if immersive == value:
		return
	immersive = value
	if topbar != null and is_instance_valid(topbar):
		topbar.visible = not value
	if lesson_banner != null and is_instance_valid(lesson_banner):
		lesson_banner.visible = lesson_visible and not value
	if _immersive_bar != null and is_instance_valid(_immersive_bar):
		_immersive_bar.visible = false
	_immersive_controls_generation += 1
	_immersive_tap_times.clear()
	if layout_root != null:
		layout_root.add_theme_constant_override("separation", 6 if value else 12)
	_on_immersive_changed(value)
	checkpoint("进入沉浸模式" if value else "退出沉浸模式")
	AudioFX.play("tap")


func _on_immersive_changed(_value: bool) -> void:
	pass


func _show_immersive_controls() -> void:
	if not immersive or _immersive_bar == null or not is_instance_valid(_immersive_bar):
		return
	_immersive_controls_generation += 1
	var generation := _immersive_controls_generation
	_layout_immersive_controls()
	_immersive_bar.visible = true
	_immersive_bar.modulate.a = 1.0
	await get_tree().create_timer(4.0).timeout
	if generation == _immersive_controls_generation and immersive and is_instance_valid(_immersive_bar):
		_immersive_bar.visible = false
		_clear_overlay_seat_if_idle()


func _clear_overlay_seat_if_idle() -> void:
	if _modal_stack.is_empty() and (not is_instance_valid(_immersive_bar) or not _immersive_bar.visible):
		_interaction_seat = -1


func _notice_immersive_tap(position: Vector2) -> void:
	if not immersive:
		return
	if not _blank_at(position):
		_immersive_tap_times.clear()
		return
	var now := Time.get_ticks_msec()
	if _immersive_tap_times.is_empty() or position.distance_to(_immersive_tap_position) > 56.0:
		_immersive_tap_times.clear()
		_immersive_tap_position = position
	_immersive_tap_times = _immersive_tap_times.filter(func(stamp: int) -> bool: return now - stamp <= 720)
	_immersive_tap_times.append(now)
	if _immersive_tap_times.size() >= 3:
		_immersive_tap_times.clear()
		_interaction_seat = 0 if position.x < get_viewport_rect().size.x * 0.5 else 1
		_show_immersive_controls()


func _blank_at(position: Vector2) -> bool:
	if not _modal_stack.is_empty():
		return false
	for control in find_children("*", "Control", true, false):
		if not control.is_visible_in_tree():
			continue
		var local: Vector2 = control.get_global_transform_with_canvas().affine_inverse() * position
		if not Rect2(Vector2.ZERO, control.size).has_point(local):
			continue
		if control is BaseButton:
			return false
		if control.has_method("is_blank_at") and not bool(control.call("is_blank_at", local)):
			return false
	return true


func _input(event: InputEvent) -> void:
	if not immersive:
		return
	if event is InputEventScreenTouch and not event.pressed:
		_last_touch_msec = Time.get_ticks_msec()
		_notice_immersive_tap(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if Time.get_ticks_msec() - _last_touch_msec > 500:
			_notice_immersive_tap(event.position)


func _player_pill(player: Dictionary, first: bool) -> Control:
	var tint := PlaygroundUI.color(str(player.get("color", "#d56c29")))
	var pill := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.88), 18, PlaygroundUI.mix(tint, Color.WHITE, 0.3), 2)
	pill.custom_minimum_size = Vector2(145, 58)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)
	var avatar := PlaygroundUI.label(str(player.get("avatar", "🦊")), 28, tint, 700)
	row.add_child(avatar)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.add_child(PlaygroundUI.label(str(player.get("name", "小朋友")), 16, PlaygroundUI.INK, 700))
	text.add_child(PlaygroundUI.label("%s 岁" % int(player.get("age", 8)), 11, PlaygroundUI.INK_SOFT))
	row.add_child(text)
	return pill


func set_content(node: Control) -> void:
	PlaygroundUI.clear(content_root)
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(node)


func show_help() -> void:
	if face_to_face() and has_method("_show_rules"):
		call("_show_rules")
		return
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	for index in ContentDB.guide(game_id).size():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var number := PlaygroundUI.chip(str(index + 1), accent)
		number.custom_minimum_size = Vector2(42, 38)
		line.add_child(number)
		var text := PlaygroundUI.label(str(ContentDB.guide(game_id)[index]), 18, PlaygroundUI.INK_SOFT, 500, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		content.add_child(line)
	Speech.speak("%s玩法。%s" % [
		str(game_meta.get("title", "小游戏")),
		" ".join(ContentDB.guide(game_id)),
	])
	var actions := [
		{"text": "再读一遍", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道啦", "kind": "primary", "callback": func(): _close_top_modal()},
	]
	actions.insert(0, {"text": "重玩小课堂", "kind": "soft", "callback": func(): _close_top_modal(); begin_lesson(true)})
	open_modal("怎么玩", content, actions, "小玩家指南")


func toggle_pause(force: Variant = null) -> void:
	if _modal_stack.size() > 0 and force == null:
		_close_top_modal()
		return
	paused = not paused if force == null else bool(force)
	checkpoint("暂停游戏" if paused else "继续游戏")
	if paused:
		lesson_action("pause")
	AudioFX.play("pause" if paused else "tap")
	Speech.stop()
	pause_changed.emit(paused)
	MotionKit.set_paused_tree(self, paused)
	if not paused:
		return
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	panel.add_child(PlaygroundUI.label("进度已经自动保存", 15, PlaygroundUI.INK_SOFT, 500, true))
	var actions := [
		{"text": "继续游戏", "kind": "primary", "callback": func(): _close_top_modal(); toggle_pause(false)},
		{"text": "看玩法", "kind": "soft", "callback": func(): _close_top_modal(); show_help()},
		{"text": "声音与朗读", "kind": "soft", "callback": func(): _close_top_modal(); _show_settings()},
		{"text": "重开本局", "kind": "soft", "callback": func(): _confirm_restart()},
		{"text": "回游戏大厅", "kind": "soft", "callback": func(): _confirm_exit()},
	]
	var pause_layer := open_modal("暂停一下", panel, actions, "随时可以回来", false)
	pause_layer.set_meta("resume_on_back", true)


func _show_settings() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var settings := SaveStore.settings()
	var buttons := [
		{"icon": "🔊", "label": "音效", "key": "soundOn"},
		{"icon": "🎹", "label": "音乐", "key": "musicOn"},
		{"icon": "🎤", "label": "中文朗读", "key": "speechOn"},
		{"icon": "✋", "label": "触感", "key": "hapticsOn"},
	]
	for entry in buttons:
		var key := str(entry["key"])
		var state := "开" if bool(settings.get(key, true)) else "关"
		box.add_child(PlaygroundUI.icon_text_button(str(entry["icon"]), "%s：%s" % [str(entry["label"]), state], accent, _toggle_setting.bind(key), "soft"))
	box.add_child(volume_controls(accent))
	open_modal("声音与朗读", box, [
		{"text": "关掉窗口", "kind": "primary", "callback": func(): _close_top_modal()},
	], "三项都可以随时切换")


static func volume_controls(tint: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var settings := SaveStore.settings()
	for entry in [["音效音量", "sfxVolume", "set_sfx_volume"], ["音乐音量", "musicVolume", "set_music_volume"], ["朗读音量", "speechVolume", "set_speech_volume"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var value := clampf(float(settings.get(entry[1], 1.0)), 0.0, 1.0)
		var caption := PlaygroundUI.label("%s %s%%" % [entry[0], roundi(value * 100.0)], 16, tint, 700)
		caption.custom_minimum_size.x = 160
		row.add_child(caption)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = value
		slider.custom_minimum_size = Vector2(120, 48)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(volume: float):
			caption.text = "%s %s%%" % [entry[0], roundi(volume * 100.0)]
			AudioFX.call(str(entry[2]), volume)
		)
		row.add_child(slider)
		box.add_child(row)
	return box


func _toggle_setting(key: String) -> void:
	SaveStore.set_setting(key, not bool(SaveStore.settings().get(key, true)))
	AudioFX.refresh_settings()
	Speech.stop()
	_close_top_modal()
	_show_settings()


func open_modal(
	title: String,
	content: Control,
	actions: Array,
	eyebrow: String = "",
	dismissible: bool = true
) -> Control:
	var angle := _overlay_angle()
	var contains_board := content.has_method("position_for")
	for child in content.find_children("*", "Control", true, false):
		if child.has_method("position_for"):
			contains_board = true
	if contains_board:
		angle = 0.0
	var manager := _dialog_manager()
	if manager != null:
		if not manager.dialog_closed.is_connected(_on_dialog_closed):
			manager.dialog_closed.connect(_on_dialog_closed)
		# 本地栈按关闭信号同步，不能根据全局栈顶猜测身份
		var layer: Control = manager.show_dialog({
			"title": title,
			"body": content,
			"buttons": actions,
			"eyebrow": eyebrow,
			"dismissible": dismissible,
			"accent": accent,
			"size": "M",
			"facing_angle": angle,
		})
		_modal_stack.append(layer)
		return layer
	return _open_modal_fallback(title, content, actions, eyebrow, dismissible, angle)


func _dialog_manager() -> DialogManager:
	var tree := get_tree()
	if tree == null:
		return null
	var hub := tree.get_first_node_in_group("main_hub")
	if hub == null:
		return null
	return hub.get("dialogs")


func _open_modal_fallback(
	title: String,
	content: Control,
	actions: Array,
	eyebrow: String = "",
	dismissible: bool = true,
	angle: float = 0.0
) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 60
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.set_meta("dismissible",dismissible)
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.16, 0.13, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)
	var available := TabletopLayout.canvas_size(get_viewport_rect().size, angle)
	TabletopLayout.layout_canvas(canvas, get_viewport_rect().size, angle)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	var card := PlaygroundUI.panel(PlaygroundUI.PAPER, 30, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2)
	card.custom_minimum_size = Vector2(minf(680, available.x - maxf(32.0, available.x * 0.08)), 0)
	card.modulate.a = 0.0
	card.scale = Vector2(0.97, 0.97)
	card.pivot_offset = Vector2(card.size.x * 0.5, 0)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	if not eyebrow.is_empty():
		column.add_child(PlaygroundUI.label(eyebrow, 14, accent, 700))
	column.add_child(PlaygroundUI.label(title, 32, PlaygroundUI.INK, 700, true))
	var content_scroll := ScrollContainer.new()
	content_scroll.custom_minimum_size.y = minf(430.0, available.y * 0.50)
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	var desired_content_height := clampf(content.get_combined_minimum_size().y + 8.0, 72.0, 360.0)
	content_scroll.custom_minimum_size.y = desired_content_height
	column.add_child(content_scroll)
	var actions_row := HFlowContainer.new()
	actions_row.alignment = FlowContainer.ALIGNMENT_END
	actions_row.add_theme_constant_override("separation", 10)
	for action in actions:
		var button := PlaygroundUI.button(
			str(action.get("text", "好")),
			accent,
			action.get("callback", Callable()),
			str(action.get("kind", "primary"))
		)
		button.custom_minimum_size.x = 132
		actions_row.add_child(button)
	column.add_child(actions_row)
	overlay_root.add_child(layer)
	_modal_stack.append(layer)
	var animation := MotionKit.tween(self)
	animation.set_parallel(true)
	animation.tween_property(card, "modulate:a", 1.0, MotionKit.MODAL_IN)
	animation.tween_property(card, "scale", Vector2.ONE, MotionKit.MODAL_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var controls := card.find_children("*", "Button", true, false)
	if not controls.is_empty():
		controls[0].call_deferred("grab_focus")
	return layer


func _close_top_modal() -> void:
	if _modal_stack.is_empty():
		return
	var layer: Control = _modal_stack.back()
	var manager := _dialog_manager()
	if manager != null and manager.owns_layer(layer):
		manager.close_layer(layer)
		return
	_modal_stack.erase(layer)
	if not is_instance_valid(layer):
		return
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MotionKit.fade_out_and_free(layer, self, MotionKit.MODAL_OUT)
	call_deferred("_clear_overlay_seat_if_idle")


func _on_dialog_closed(layer: Control) -> void:
	_modal_stack.erase(layer)
	call_deferred("_clear_overlay_seat_if_idle")


func _exit_tree() -> void:
	var manager := _dialog_manager()
	if manager != null:
		for layer in _modal_stack.duplicate():
			if manager.owns_layer(layer):
				manager.close_layer(layer)
	_modal_stack.clear()


func _confirm_restart() -> void:
	_close_top_modal()
	var text := PlaygroundUI.label("这局当前进度会被清空，重新开始。儿童档案和已获得成绩会保留。", 18, PlaygroundUI.INK_SOFT, 500, true)
	var restart_action := func():
		_close_top_modal()
		paused = false
		pause_changed.emit(false)
		restart_requested.emit()
	open_modal("重开本局？", text, [
		{"text": "继续这局", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "kind": "primary", "callback": restart_action},
	], "当前游戏")


func _confirm_exit() -> void:
	checkpoint("返回大厅前保存")
	_close_top_modal()
	var text := PlaygroundUI.label("当前进度已经保存。回大厅后可以从游戏卡片继续。", 18, PlaygroundUI.INK_SOFT, 500, true)
	var back_action := func():
		SaveStore.flush()
		Speech.stop()
		AudioFX.stop_music()
		back_requested.emit()
	open_modal("回游戏大厅？", text, [
		{"text": "留在这里", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "回大厅", "kind": "primary", "callback": back_action},
	], "进度已保存")


func _handle_back() -> void:
	if _modal_stack.is_empty():
		_interaction_seat = -1
	var manager := _dialog_manager()
	if manager != null and manager.has_open_dialog():
		var top := manager.top_layer()
		if top in _modal_stack and bool(top.get_meta("resume_on_back", false)):
			manager.close_layer(top)
			toggle_pause(false)
		else:
			manager.close_layer(top, true)
		return
	if not _modal_stack.is_empty():
		var top: Control = _modal_stack.back()
		if bool(top.get_meta("resume_on_back", false)):
			_close_top_modal()
			toggle_pause(false)
		elif bool(top.get_meta("dismissible", true)):
			_close_top_modal()
		return
	if immersive:
		set_immersive(false)
		return
	if paused:
		toggle_pause(false)
		return
	toggle_pause(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_handle_back()
		get_viewport().set_input_as_handled()


func show_toast(message: String, seconds: float = 2.4) -> void:
	TabletopLayout.layout_canvas(_toast_canvas, get_viewport_rect().size, TabletopLayout.facing_angle(_current_seat(), face_to_face()))
	toast_label.text = message
	toast_label.size = toast_label.get_minimum_size()
	var toast_y := _toast_canvas.size.y - toast_label.size.y - 24.0 if face_to_face() else 24.0
	toast_label.position = Vector2((_toast_canvas.size.x - toast_label.size.x) * 0.5, toast_y)
	toast_label.modulate.a = 1.0
	var tween := MotionKit.tween(self)
	tween.tween_interval(seconds)
	tween.tween_property(toast_label, "modulate:a", 0.0, 0.25)


func add_saved_meta(note: String, resume: bool = true) -> void:
	var primary := SaveStore.primary_id(game_id)
	if not primary.is_empty():
		var state := SaveStore.load_state(game_id, [primary])
		SaveStore.save_state(game_id, primary, state, note, resume)


func checkpoint(note: String = "实时自动保存") -> void:
	if has_method("_save"):
		call("_save", note)
	elif has_method("_save_profile"):
		call("_save_profile", note)
	SaveStore.flush()


func _process(delta: float) -> void:
	_save_interval += delta
	if _save_interval >= 2.0:
		_save_interval = 0.0
		checkpoint()


func _notification(what: int) -> void:
	if is_inside_tree() and content_root != null and what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		checkpoint("切后台保存")
		Speech.stop()
		AudioFX.stop_all()


func level_map(on_chosen: Callable) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var grid := GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	for entry in ContentDB.chapters.get(game_id, []):
		var number := int(entry.id)
		var unlocked := SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)
		var stars := clampi(int(SaveStore.learning(str(players[0].id),game_id,mode_id).stars.get(str(number),0)),0,3)
		var button := PlaygroundUI.button("%s\n%s\n%s" % [str(number) if unlocked else "锁", str(entry.title), "★".repeat(stars) + "☆".repeat(3-stars)], accent, on_chosen.bind(number), "soft")
		button.custom_minimum_size = Vector2(0, 136)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not unlocked
		grid.add_child(button)
	scroll.add_child(grid)
	return scroll


func begin_lesson(force: bool = false) -> void:
	if players.is_empty():
		return
	if not force:
		return
	if immersive:
		set_immersive(false)
	if not force and bool(SaveStore.learning(str(players[0].id),game_id,mode_id).tutorialSeen):
		return
	lesson_step = 0
	if game_id in ["math","pinyin","patterns","animals","workbook"]:
		lesson_actions = ["listen","answer","next"]
		lesson_texts = ["点听题，听听这一题在问什么。","点一个答案，看看正确答案与讲解。","读完讲解，再点下面的下一题。"]
	elif game_id == "military":
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["双方棋子全部明示，红方先走。","点自己的棋子，再点亮起的位置移动。","点暂停，军棋会自动保存，回来继续。"]
	elif game_id == "sudoku":
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["先点一个空格。","再点下面的数字。","每行每列和小宫都不能重复，进度会自动保存。"]
	elif game_id == "chess":
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["红方先走，点自己的棋子。","点发光的交叉点走棋；炮要隔一颗棋子才能吃子。","吃掉对方将帅就获胜，进度会自动保存。"]
	elif game_id in ["jungle","gomoku"]:
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["点一枚自己的棋子；五子棋请按住空交叉点。","点亮起的位置，走出第一步。","试试上方暂停按钮，进度会自动保存。"]
	elif game_id == "memory":
		lesson_actions = ["flip","pair","pause"]
		lesson_texts = ["点一张卡，把它翻过来。","再翻一张，记住两张图案的位置。","点暂停，回来还会停在这一局。"]
	elif game_id == "poetry":
		lesson_actions = ["draw","evaluate","next"]
		lesson_texts = ["请家长拿好平板，点抽一首。","让孩子背对屏幕，背完后选择背对了或再复习。","原诗会留下，点下一首才继续。"]
	elif game_id == "stories":
		lesson_actions = ["open_story","listen","pause"]
		lesson_texts = ["选一个故事，翻开故事书。","点听故事；第一次需要联网下载，下载后就能离线听。","试试暂停，回来可以接着上次的位置听。"]
	else:
		lesson_actions = ["roll","answer","pause"]
		lesson_texts = ["点掷骰子，看看角色走到哪里。","遇到题目慢慢答，讲解会留下。","试试暂停，回来继续本次冒险。"]
	lesson_visible = true
	_show_lesson_step()


func lesson_action(action: String) -> void:
	if not lesson_visible or lesson_step >= lesson_actions.size() or action != lesson_actions[lesson_step]:
		return
	lesson_step += 1
	if lesson_step == lesson_actions.size():
		_finish_lesson()
	else:
		_show_lesson_step()


func _show_lesson_step() -> void:
	lesson_banner.visible = not immersive
	lesson_label.text = "小课堂 %s/%s  ·  %s" % [lesson_step+1,lesson_actions.size(),lesson_texts[lesson_step]]
	Speech.speak(str(lesson_texts[lesson_step]))


func _finish_lesson() -> void:
	lesson_visible = false
	lesson_banner.hide()
	for player in players:
		SaveStore.learning(str(player.id),game_id,mode_id).tutorialSeen = true
	SaveStore.flush()
