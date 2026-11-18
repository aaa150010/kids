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
var content_root: VBoxContainer
var overlay_root: Control
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
	margin.add_theme_constant_override("margin_left", int(maxf(metrics.margin,float(safe.left)+10.0)))
	margin.add_theme_constant_override("margin_right", int(maxf(metrics.margin,float(safe.right)+10.0)))
	margin.add_theme_constant_override("margin_top", int(maxf(10.0,float(safe.top)+6.0)))
	margin.add_theme_constant_override("margin_bottom", int(maxf(14.0,float(safe.bottom)+8.0)))
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	layout.add_child(_build_topbar())
	lesson_banner = PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.85), 18, accent, 2)
	var lesson_row := HBoxContainer.new()
	lesson_label = PlaygroundUI.label("", 18, PlaygroundUI.INK, 700, true)
	lesson_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lesson_row.add_child(lesson_label)
	lesson_row.add_child(PlaygroundUI.button("跳过教学", accent, _finish_lesson, "soft"))
	lesson_banner.add_child(lesson_row)
	layout.add_child(lesson_banner)
	lesson_banner.hide()
	content_root = VBoxContainer.new()
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_theme_constant_override("separation", 12)
	layout.add_child(content_root)
	overlay_root = Control.new()
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_root)
	toast_label = PlaygroundUI.label("", 18, Color.WHITE, 700)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.z_index = 80
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.modulate.a = 0.0
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(0, 24)
	add_child(toast_label)


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
	var pause := PlaygroundUI.button("Ⅱ  暂停", accent, toggle_pause, "soft")
	pause.custom_minimum_size = Vector2(108, 48)
	row.add_child(pause)
	return bar


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
	if game_id != "garden":
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
		["🔊 音效", "soundOn", "soundOn"],
		["🎵 音乐", "musicOn", "musicOn"],
		["🗣️ 中文朗读", "speechOn", "speechOn"],
		["📳 触感", "hapticsOn", "hapticsOn"],
	]
	for entry in buttons:
		var key := str(entry[1])
		var state := "开" if bool(settings.get(key, true)) else "关"
		box.add_child(PlaygroundUI.button("%s：%s" % [entry[0], state], accent, _toggle_setting.bind(key), "soft"))
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
		})
		_modal_stack.append(layer)
		return layer
	return _open_modal_fallback(title, content, actions, eyebrow, dismissible)


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
	dismissible: bool = true
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
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := PlaygroundUI.panel(PlaygroundUI.PAPER, 30, PlaygroundUI.mix(accent, Color.WHITE, 0.55), 2)
	card.custom_minimum_size = Vector2(minf(680, size.x - maxf(32.0, size.x * 0.08)), 0)
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
	content_scroll.custom_minimum_size.y = minf(430.0, size.y * 0.50)
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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


func _on_dialog_closed(layer: Control) -> void:
	_modal_stack.erase(layer)


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
	toast_label.text = message
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
	if game_id == "garden" or players.is_empty():
		return
	if not force and bool(SaveStore.learning(str(players[0].id),game_id,mode_id).tutorialSeen):
		return
	lesson_step = 0
	if game_id in ["math","pinyin","patterns","animals","workbook"]:
		lesson_actions = ["listen","answer","next"]
		lesson_texts = ["点听题，听听这一题在问什么。","点一个答案，看看正确答案与讲解。","读完讲解，再点下面的下一题。"]
	elif game_id in ["jungle","gomoku","military"]:
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
	lesson_banner.show()
	lesson_label.text = "小课堂 %s/%s  ·  %s" % [lesson_step+1,lesson_actions.size(),lesson_texts[lesson_step]]
	Speech.speak(str(lesson_texts[lesson_step]))


func _finish_lesson() -> void:
	lesson_visible = false
	lesson_banner.hide()
	for player in players:
		SaveStore.learning(str(player.id),game_id,mode_id).tutorialSeen = true
	SaveStore.flush()
