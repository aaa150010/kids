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
var _toast_canvas: Control
var _interaction_seat := -1
var _last_actor_seat := -1
var _last_touch_msec := -1000
var toast_label: Label
var _toast_tween: Tween
var settings_button: Button
var _modal_stack: Array[Control] = []
var _pause_root_layer: Control
var _pause_origin_seat := -1
var _left_pause_rail: PanelContainer
var _right_pause_rail: PanelContainer
var _rail_press: Dictionary = {}
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
var _resume_on_start := false
var _suppress_resume_on_close := false
const RAIL_WIDTH := 60.0
const SYSTEM_GESTURE_GUARD := 24.0
const RAIL_MIN_HEIGHT_RATIO := 0.18
const RAIL_MAX_HEIGHT_RATIO := 0.82
const RAIL_TAP_SLOP := 16.0


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
	if bool(meta.get("resume", false)):
		_resume_on_start = true
	elif bool(meta.get("freshStart", false)):
		_resume_on_start = false
	else:
		var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
		_resume_on_start = not stored.is_empty() and bool(stored.get("resume", true))


func build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	PlaygroundUI.install_theme(self)
	add_child(PlaygroundUI.background(accent))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var safe := PlaygroundUI.safe_insets(get_viewport_rect().size)
	var vertical_safe := minf(float(safe.top), float(safe.bottom))
	var side_margin := maxf(metrics.margin, float(safe.left) + SYSTEM_GESTURE_GUARD + RAIL_WIDTH + 8.0)
	var opposite_margin := maxf(metrics.margin, float(safe.right) + SYSTEM_GESTURE_GUARD + RAIL_WIDTH + 8.0)
	margin.add_theme_constant_override("margin_left", int(side_margin))
	margin.add_theme_constant_override("margin_right", int(opposite_margin))
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
	_build_pause_rails()
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
	resized.connect(_layout_pause_rails)
	if _resume_on_start:
		call_deferred("_show_initial_resume_pause")


func _build_pause_rails() -> void:
	_left_pause_rail = _make_pause_rail(-1)
	_right_pause_rail = _make_pause_rail(1)
	overlay_root.add_child(_left_pause_rail)
	overlay_root.add_child(_right_pause_rail)
	call_deferred("_layout_pause_rails")


func _make_pause_rail(side: int) -> PanelContainer:
	var rail := PanelContainer.new()
	rail.name = "LeftPauseRail" if side < 0 else "RightPauseRail"
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	rail.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rail.focus_mode = Control.FOCUS_NONE
	rail.set_meta("pause_side", side)
	var paper := PlaygroundUI.style(Color(1, 1, 1, 0.24), 24, Color(accent, 0.22), 1)
	paper.content_margin_left = 0
	paper.content_margin_right = 0
	paper.content_margin_top = 0
	paper.content_margin_bottom = 0
	rail.add_theme_stylebox_override("panel", paper)
	var fold := VBoxContainer.new()
	fold.alignment = BoxContainer.ALIGNMENT_CENTER
	fold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fold.add_theme_constant_override("separation", 7)
	for index in 3:
		var dot := ColorRect.new()
		dot.color = Color(accent, 0.42)
		dot.custom_minimum_size = Vector2(5, 5)
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		fold.add_child(dot)
	rail.add_child(fold)
	rail.gui_input.connect(_on_pause_rail_input.bind(side))
	rail.mouse_entered.connect(func():
		rail.modulate = Color(1.05, 1.05, 1.05, 1.0)
	)
	rail.mouse_exited.connect(func():
		rail.modulate = Color.WHITE
		_rail_press.erase(side)
	)
	return rail


func _layout_pause_rails() -> void:
	if not is_instance_valid(_left_pause_rail) or not is_instance_valid(_right_pause_rail):
		return
	var viewport := get_viewport_rect().size
	var safe := PlaygroundUI.safe_insets(viewport)
	var left_offset := float(safe.get("left", 0.0)) + SYSTEM_GESTURE_GUARD
	var right_offset := float(safe.get("right", 0.0)) + SYSTEM_GESTURE_GUARD
	var top := viewport.y * RAIL_MIN_HEIGHT_RATIO
	var bottom := viewport.y * RAIL_MAX_HEIGHT_RATIO
	_left_pause_rail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_left_pause_rail.position = Vector2(left_offset, top)
	_left_pause_rail.size = Vector2(RAIL_WIDTH, bottom - top)
	_right_pause_rail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_right_pause_rail.position = Vector2(viewport.x - right_offset - RAIL_WIDTH, top)
	_right_pause_rail.size = Vector2(RAIL_WIDTH, bottom - top)
	var rails_visible := immersive and not paused and _modal_stack.is_empty()
	_left_pause_rail.visible = rails_visible
	_right_pause_rail.visible = rails_visible


func _on_pause_rail_input(event: InputEvent, side: int) -> void:
	if paused or not _modal_stack.is_empty():
		_rail_press.erase(side)
		return
	get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_last_touch_msec = Time.get_ticks_msec()
		if event.pressed:
			_rail_press[side] = {"start": event.position, "last": event.position}
		else:
			_finish_rail_tap(side, event.position)
	elif event is InputEventScreenDrag:
		_last_touch_msec = Time.get_ticks_msec()
		if _rail_press.has(side):
			var press: Dictionary = _rail_press[side]
			press["last"] = event.position
			var start: Vector2 = press.get("start", event.position)
			if start.distance_to(event.position) > RAIL_TAP_SLOP:
				_rail_press.erase(side)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _last_touch_msec < 500:
			return
		if event.pressed:
			_rail_press[side] = {"start": event.position, "last": event.position}
		else:
			_finish_rail_tap(side, event.position)
	elif event is InputEventMouseMotion and _rail_press.has(side):
		var press: Dictionary = _rail_press[side]
		press["last"] = event.position
		var start: Vector2 = press.get("start", event.position)
		if start.distance_to(event.position) > RAIL_TAP_SLOP:
			_rail_press.erase(side)


func _finish_rail_tap(side: int, position: Vector2) -> void:
	if not _rail_press.has(side):
		return
	var press: Dictionary = _rail_press[side]
	_rail_press.erase(side)
	var start: Vector2 = press.get("start", position)
	if start.distance_to(position) > RAIL_TAP_SLOP:
		return
	_interaction_seat = 0 if side < 0 else 1
	toggle_pause(true)


func _show_initial_resume_pause() -> void:
	if not paused and _modal_stack.is_empty():
		toggle_pause(true)


func face_to_face() -> bool:
	return TabletopLayout.enabled(game_id, players, mode_id)


func _current_seat() -> int:
	if not face_to_face():
		return 0
	var rules: Variant = get("engine")
	return clampi(int(rules.state.get("turn", 0)), 0, 1) if rules != null else 0


func _overlay_angle() -> float:
	return TabletopLayout.facing_angle(_interaction_seat if _interaction_seat >= 0 else _current_seat(), face_to_face())


func _build_topbar() -> Control:
	var bar := PlaygroundUI.panel(Color(1, 1, 1, 0.76), 24, PlaygroundUI.mix(accent, Color.WHITE, 0.6), 1)
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var compact := bool(metrics.compact_cards)
	bar.custom_minimum_size.y = metrics.topbar
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var back := PlaygroundUI.semantic_icon_button("back", "返回", accent, _handle_back, "soft", 18)
	back.custom_minimum_size = Vector2(92, 48)
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
	var pause := PlaygroundUI.semantic_icon_button("pause", "暂停", accent, toggle_pause, "soft", 18)
	pause.custom_minimum_size = Vector2(92, 48)
	row.add_child(pause)
	return bar


func _extra_topbar_actions(_row: HBoxContainer) -> void:
	pass


func show_game_rules() -> void:
	show_help()


func _on_immersive_changed(_value: bool) -> void:
	pass


func _clear_overlay_seat_if_idle() -> void:
	if _modal_stack.is_empty():
		_interaction_seat = -1


func _player_pill(player: Dictionary, first: bool) -> Control:
	var tint := PlaygroundUI.color(str(player.get("color", "#d56c29")))
	var pill := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.88), 18, PlaygroundUI.mix(tint, Color.WHITE, 0.3), 2)
	pill.custom_minimum_size = Vector2(145, 58)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)
	var avatar := ArtLibrary.profile_picture(player, Vector2(34, 34))
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
	if not paused:
		_open_pause_tools()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	var guide := ContentDB.guide(game_id)
	var icons := ["play", "next", "check", "hint"]
	for index in guide.size():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var image := ArtLibrary.semantic_picture(str(icons[mini(index, icons.size() - 1)]), "ui", Vector2(44, 44))
		line.add_child(image)
		var text := PlaygroundUI.label(str(guide[index]), 20, PlaygroundUI.INK if index < 3 else PlaygroundUI.INK_SOFT, 600 if index < 3 else 500, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		content.add_child(line)
	var spoken_guide := PackedStringArray()
	for line in guide:
		spoken_guide.append(str(line))
	Speech.speak("%s玩法。%s" % [
		str(game_meta.get("title", "小游戏")),
		" ".join(spoken_guide),
	])
	var actions := [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	]
	actions.insert(0, {"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); begin_lesson(true)})
	if has_method("_show_rules"):
		actions.insert(1, {"text": "更多规则", "icon": "rules", "kind": "soft", "callback": func(): call("_show_rules")})
	open_modal("怎么玩", content, actions, "小玩家指南")


func toggle_pause(force: Variant = null) -> void:
	var target := not paused if force == null else bool(force)
	if target:
		if paused:
			return
		_open_pause_tools()
	else:
		if not paused:
			return
		_close_pause_tools()


func _open_pause_tools() -> void:
	if paused:
		return
	_pause_origin_seat = _interaction_seat
	if _pause_origin_seat < 0 and _last_actor_seat >= 0:
		_pause_origin_seat = _last_actor_seat
	if _pause_origin_seat < 0:
		_pause_origin_seat = _current_seat()
	_interaction_seat = _pause_origin_seat
	checkpoint("暂停游戏")
	lesson_action("pause")
	paused = true
	Speech.stop()
	AudioFX.stop_all()
	_rail_press.clear()
	MotionKit.set_paused_tree(self, true)
	pause_changed.emit(true)
	AudioFX.play("pause")
	var summary_text := PlaygroundUI.label(
		"%s · %s" % [
			str(game_meta.get("title", "小游戏")),
			str(ContentDB.mode(game_id, mode_id).get("name", "正在玩")),
		],
		20,
		PlaygroundUI.INK,
		600,
		true
	)
	summary_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pause_status := "已保存，可以放心休息" if not _resume_on_start else "已接着上次进度，准备好再继续"
	var actions := [
		{"text": "继续游戏", "icon": "play", "kind": "primary", "callback": func(): _close_top_modal()},
		{"text": "怎么玩", "icon": "rules", "kind": "soft", "callback": func(): show_help()},
		{"text": "声音与朗读", "icon": "sound", "kind": "soft", "callback": func(): _show_settings()},
	]
	actions.append_array(_extra_pause_actions())
	actions.append_array([
		{"text": "重开本局", "icon": "restart", "kind": "soft", "callback": func(): _confirm_restart()},
		{"text": "回游戏大厅", "icon": "home", "kind": "soft", "callback": func(): _confirm_exit()},
	])
	_pause_root_layer = open_modal("暂停一下", summary_text, actions, pause_status, false)
	_pause_root_layer.set_meta("pause_root", true)
	_pause_root_layer.set_meta("pause_seat", _pause_origin_seat)
	_layout_pause_rails()


func _extra_pause_actions() -> Array:
	return []


func _close_pause_tools() -> void:
	if not is_instance_valid(_pause_root_layer):
		_resume_after_pause()
		return
	var manager := _dialog_manager()
	if manager != null and manager.owns_layer(_pause_root_layer):
		while manager.has_open_dialog() and manager.top_layer() != _pause_root_layer:
			manager.close_top()
		manager.close_layer(_pause_root_layer)
		return
	_close_top_modal()


func _resume_after_pause() -> void:
	if not paused:
		return
	paused = false
	_suppress_resume_on_close = false
	_pause_root_layer = null
	_pause_origin_seat = -1
	_interaction_seat = -1
	_resume_on_start = false
	checkpoint("继续游戏")
	MotionKit.set_paused_tree(self, false)
	pause_changed.emit(false)
	AudioFX.play("tap")
	_layout_pause_rails()


func _show_settings() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var settings := SaveStore.settings()
	var buttons := [
		{"icon": "sound", "label": "音效", "key": "soundOn"},
		{"icon": "music", "label": "音乐", "key": "musicOn"},
		{"icon": "speech", "label": "中文朗读", "key": "speechOn"},
		{"icon": "haptics", "label": "触感", "key": "hapticsOn"},
	]
	for entry in buttons:
		var key := str(entry["key"])
		var state := "开" if bool(settings.get(key, true)) else "关"
		box.add_child(PlaygroundUI.semantic_icon_button(str(entry["icon"]), "%s：%s" % [str(entry["label"]), state], accent, _toggle_setting.bind(key), "soft"))
	box.add_child(volume_controls(accent))
	open_modal("声音与朗读", box, [
		{"text": "回到暂停", "icon": "back", "kind": "primary", "callback": func(): _close_top_modal()},
	], "开关会立即生效")


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
	# System tools stay upright even when the board is seated from its short edge.
	var angle := 0.0
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
			"size": "L",
			"facing_angle": 0.0,
		})
		_modal_stack.append(layer)
		_layout_pause_rails()
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
		var kind := str(action.get("kind", "primary"))
		var button: Button
		if action.has("icon"):
			button = PlaygroundUI.semantic_icon_button(
				str(action["icon"]),
				str(action.get("text", "好")),
				accent,
				action.get("callback", Callable()),
				kind,
				22
			)
		else:
			button = PlaygroundUI.button(
				str(action.get("text", "好")),
				accent,
				action.get("callback", Callable()),
				kind
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
	if layer == _pause_root_layer:
		_pause_root_layer = null
		if paused and not _suppress_resume_on_close:
			_resume_after_pause()
	call_deferred("_clear_overlay_seat_if_idle")
	call_deferred("_layout_pause_rails")


func _exit_tree() -> void:
	var manager := _dialog_manager()
	if manager != null:
		for layer in _modal_stack.duplicate():
			if manager.owns_layer(layer):
				manager.close_layer(layer)
	_modal_stack.clear()


func _confirm_restart() -> void:
	var text := PlaygroundUI.label("这局当前进度会被清空，重新开始。儿童档案和已获得成绩会保留。", 18, PlaygroundUI.INK_SOFT, 500, true)
	var restart_action := func():
		_suppress_resume_on_close = true
		_close_all_game_dialogs()
		paused = false
		_pause_root_layer = null
		MotionKit.set_paused_tree(self, false)
		pause_changed.emit(false)
		restart_requested.emit()
	open_modal("重开本局？", text, [
		{"text": "继续这局", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": restart_action},
	], "当前游戏")


func _confirm_exit() -> void:
	checkpoint("返回大厅前保存")
	var text := PlaygroundUI.label("当前进度已经保存。回大厅后可以从游戏卡片继续。", 18, PlaygroundUI.INK_SOFT, 500, true)
	var back_action := func():
		SaveStore.flush()
		Speech.stop()
		AudioFX.stop_music()
		_suppress_resume_on_close = true
		_close_all_game_dialogs()
		back_requested.emit()
	open_modal("回游戏大厅？", text, [
		{"text": "留在这里", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "回大厅", "icon": "home", "kind": "primary", "callback": back_action},
	], "进度已保存")


func _close_all_game_dialogs() -> void:
	var manager := _dialog_manager()
	if manager != null:
		for layer in _modal_stack.duplicate():
			if manager.owns_layer(layer):
				manager.close_layer(layer)
	_modal_stack.clear()
	_pause_root_layer = null


func _handle_back() -> void:
	var manager := _dialog_manager()
	if manager != null and manager.has_open_dialog():
		var top := manager.top_layer()
		if top in _modal_stack:
			if bool(top.get_meta("pause_root", false)):
				_close_pause_tools()
			else:
				manager.close_layer(top, true)
		return
	if not _modal_stack.is_empty():
		var top: Control = _modal_stack.back()
		if bool(top.get_meta("dismissible", true)):
			_close_top_modal()
		return
	if paused:
		_close_pause_tools()
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
	if _toast_tween != null and is_instance_valid(_toast_tween):
		_toast_tween.kill()
	TabletopLayout.layout_canvas(_toast_canvas, get_viewport_rect().size, TabletopLayout.facing_angle(_current_seat(), face_to_face()))
	toast_label.text = message
	toast_label.size = toast_label.get_minimum_size()
	var toast_y := _toast_canvas.size.y - toast_label.size.y - 24.0 if face_to_face() else 24.0
	toast_label.position = Vector2((_toast_canvas.size.x - toast_label.size.x) * 0.5, toast_y)
	toast_label.modulate.a = 1.0
	_toast_tween = MotionKit.tween(self)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.25)


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
		if not paused:
			call_deferred("toggle_pause", true)


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
		var state_text := "尚未解锁" if not unlocked else "已获 %s / 3 星" % stars
		var button := PlaygroundUI.button("%s\n%s\n%s" % [str(number) if unlocked else "锁", str(entry.title), state_text], accent, on_chosen.bind(number), "soft")
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
	if not paused:
		_open_pause_tools()
	lesson_step = 0
	var icon_names: Array[String] = []
	if game_id in ["math","pinyin","patterns","animals","workbook"]:
		lesson_actions = ["listen","answer","next"]
		lesson_texts = ["点听题，听听这一题在问什么。","点一个答案，看看正确答案与讲解。","读完讲解，再点下面的下一题。"]
		icon_names = ["listen","next","check"]
	elif game_id == "military":
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["双方棋子全部明示，红方先走。","点自己的棋子，再点亮起的位置移动。","两边都会显示可攻击结果，战斗后仍会留在棋盘上。"]
		icon_names = ["game","next","hint"]
	elif game_id == "sudoku":
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["先点一个空格。","再点右边的数字。","每行每列和小宫都不能重复，重复处会一起圈出。"]
		icon_names = ["next","erase","hint"]
	elif game_id == "chess":
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["红方先走，点自己的棋子。","按住目标先预览，松手确认，滑开取消。","马腿、象眼、炮架等阻挡原因会留在棋盘上。"]
		icon_names = ["game","next","hint"]
	elif game_id in ["jungle","gomoku"]:
		lesson_actions = ["select","move","pause"]
		lesson_texts = ["点一枚自己的棋子；五子棋请按住空交叉点。","按住目标先预览，松手确认，滑开取消。","轻点两侧纸边，打开暂停和规则。"]
		icon_names = ["game","next","pause"]
	elif game_id == "memory":
		lesson_actions = ["flip","pair","pause"]
		lesson_texts = ["点一张卡，把它翻过来。","再翻一张，记住两张图案的位置。","点暂停，回来还会停在这一局。"]
		icon_names = ["game","search","pause"]
	elif game_id == "poetry":
		lesson_actions = ["draw","evaluate","next"]
		lesson_texts = ["请家长拿好平板，点抽一首。","让孩子背对屏幕，背完后选择背对了或再复习。","原诗会留下，点下一首才继续。"]
		icon_names = ["poem","speech","next"]
	elif game_id == "stories":
		lesson_actions = ["open_story","listen","pause"]
		lesson_texts = ["选一个故事，翻开故事书。","点系统朗读开始听；没有点播放时不会自动开口。","轻点两侧纸边暂停，回来会从当前段落接着读。"]
		icon_names = ["story","speech","pause"]
	else:
		lesson_actions = ["roll","answer","pause"]
		lesson_texts = ["点掷骰子，看看角色走到哪里。","遇到题目慢慢答，讲解会留下。","试试暂停，回来继续本次冒险。"]
		icon_names = ["game","next","pause"]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lesson_texts.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(icon_names[index], "ui", Vector2(38, 38)))
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_child(PlaygroundUI.label("第 %s 步" % (index + 1), 15, accent, 700))
		copy.add_child(PlaygroundUI.label(str(lesson_texts[index]), 20, PlaygroundUI.INK, 600, true))
		row.add_child(copy)
		body.add_child(row)
	var spoken_steps := PackedStringArray()
	for step in lesson_texts:
		spoken_steps.append(str(step))
	Speech.speak("小课堂。 %s" % " ".join(spoken_steps))
	open_modal("怎么玩", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "开始试玩", "icon": "play", "kind": "primary", "callback": func(): _finish_lesson(); _close_top_modal()},
	], "三步就能开始")


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
