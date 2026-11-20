extends Control

const GAME_SCRIPTS := {
	"jungle": "res://src/games/board_game.gd",
	"poetry": "res://src/games/poetry_game.gd",
	"math": "res://src/games/quiz_game.gd",
	"pinyin": "res://src/games/quiz_game.gd",
	"memory": "res://src/games/memory_game.gd",
	"patterns": "res://src/games/quiz_game.gd",
	"animals": "res://src/games/quiz_game.gd",
	"gomoku": "res://src/games/board_game.gd",
	"chess": "res://src/games/chess_game.gd",
	"sudoku": "res://src/games/sudoku_game.gd",
	"military": "res://src/games/military_game.gd",
	"workbook": "res://src/games/quiz_game.gd",
	"stories": "res://src/games/story_game.gd",
}
const MUSIC_THEMES := {
	"jungle": "forest",
	"poetry": "poetry",
	"math": "water",
	"pinyin": "forest",
	"memory": "rainbow",
	"patterns": "rainbow",
	"animals": "forest",
	"gomoku": "lobby",
	"chess": "poetry",
	"sudoku": "math",
	"military": "night",
	"workbook": "math",
	"stories": "poetry",
}
const AVATARS := ["🦊", "🐼", "🐯", "🐰", "🐻", "🦁", "🐧", "🐨", "🦉", "🐬"]
const PROFILE_COLORS := ["#d56c29", "#2878c8", "#64a244", "#8657a7", "#c05b8f", "#167d74", "#5b63b2", "#b69014"]

var lobby_root: Control
var screen_root: Control
var modal_root: Control
var card_grid: GridContainer
var scroll: ScrollContainer
var sorting := false
var current_screen: NativeGameScreen
var modal_stack: Array[Control] = []
var ipc: InteractionController
var dialogs: DialogManager
var _game_order: Array[String] = []
var _screen_game := ""
var _pending_update: Dictionary = {}
var _manual_check := false
var _launch_modes: Dictionary = {}
var _preparation: Dictionary = {}
var _lobby_scroll_offset := 0
var _pending_preparation_game := ""
var intro_sequence = null
# W3 大厅丝滑化：增量刷新与排序拖拽编排
var _heading_row: HBoxContainer = null
var _profile_row: HBoxContainer = null
var _sort_note_holder: VBoxContainer = null
var _sort_drag: DragController = null
var _sort_drag_card: LobbyGameCard = null
var _insert_line: ColorRect = null
var _drag_pointer := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not OS.has_feature("editor"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	PlaygroundUI.install_theme(self)
	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen_root)
	modal_root = Control.new()
	modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_root.z_index = 100
	add_child(modal_root)
	# 全局交互中枢：通过 main_hub 组暴露 ipc（输入仲裁）与 dialogs（统一弹窗）
	add_to_group("main_hub")
	ipc = InteractionController.new()
	ipc.name = "InteractionController"
	add_child(ipc)
	dialogs = DialogManager.new()
	dialogs.name = "DialogManager"
	add_child(dialogs)
	dialogs.dialog_closed.connect(_on_dialog_closed)
	dialogs.dialog_opened.connect(func(_layer: Control): _cancel_sort_drag())
	# 排序拖拽编排（ghost 浮层 / 插入位指示线）
	_sort_drag = DragController.new()
	_sort_drag.name = "LobbySortDrag"
	add_child(_sort_drag)
	get_viewport().size_changed.connect(_on_resize)
	UpdateService.update_available.connect(_on_update_available)
	UpdateService.check_finished.connect(_on_check_finished)
	UpdateService.content_downloaded.connect(func(version: int): show_toast("新内容已下载，下次启动会生效（内容版本 %s）" % version))
	UpdateService.check_failed.connect(_on_update_error)
	_rebuild_lobby()
	AudioFX.stop_music()
	intro_sequence = load("res://src/ui/intro_sequence.gd").new()
	intro_sequence.finished.connect(_on_intro_finished)
	add_child(intro_sequence)


func _on_intro_finished() -> void:
	if is_instance_valid(intro_sequence):
		intro_sequence.hide()
		intro_sequence.queue_free()
	intro_sequence = null
	AudioFX.start_music("lobby")
	if SaveStore.profiles().is_empty():
		_show_profile_manager()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		SaveStore.flush()
		if current_screen != null and current_screen.has_method("toggle_pause") and not current_screen.paused:
			current_screen.toggle_pause(true)
		AudioFX.stop_music()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_instance_valid(intro_sequence):
			return
		if current_screen == null:
			AudioFX.start_music("lobby")
		elif not current_screen.paused:
			AudioFX.start_music(str(MUSIC_THEMES.get(_screen_game, "lobby")))


func _process(delta: float) -> void:
	# 排序拖拽贴近滚动区上下边缘时自动滚动
	if _sort_drag != null and _sort_drag.active:
		_sort_auto_scroll(delta)


func _on_resize() -> void:
	if card_grid != null and is_instance_valid(card_grid):
		card_grid.columns = _columns()


func _columns() -> int:
	return int(PlaygroundUI.layout_metrics(get_viewport_rect().size).columns)


func _rebuild_lobby() -> void:
	_cancel_sort_drag()
	if is_instance_valid(scroll):
		_lobby_scroll_offset = scroll.scroll_vertical
	if is_instance_valid(lobby_root):
		lobby_root.queue_free()
	lobby_root = Control.new()
	lobby_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(lobby_root)
	lobby_root.add_child(PlaygroundUI.background(Color("#ead7b8")))
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var safe := PlaygroundUI.safe_insets(get_viewport_rect().size)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(maxf(metrics.margin,float(safe.left)+12.0)))
	margin.add_theme_constant_override("margin_right", int(maxf(metrics.margin,float(safe.right)+12.0)))
	margin.add_theme_constant_override("margin_top", int(maxf(12.0,float(safe.top)+8.0)))
	margin.add_theme_constant_override("margin_bottom", int(maxf(12.0,float(safe.bottom)+8.0)))
	lobby_root.add_child(margin)
	scroll = SmoothScrollContainer.create()
	var page_scroll := scroll
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	margin.add_child(scroll)
	var page := VBoxContainer.new()
	page.name = "LobbyPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.custom_minimum_size.x = maxf(1.0, page_scroll.size.x)
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	page_scroll.resized.connect(func(): page.custom_minimum_size.x = maxf(1.0, page_scroll.size.x))
	page.add_child(_lobby_header())
	_heading_row = _lobby_heading() as HBoxContainer
	page.add_child(_heading_row)
	# 排序说明条槽位：隐藏时不占布局间距，切换排序只增删内部节点
	_sort_note_holder = VBoxContainer.new()
	_sort_note_holder.visible = sorting
	var sort_note := _sort_note()
	if sort_note != null:
		_sort_note_holder.add_child(sort_note)
	page.add_child(_sort_note_holder)
	card_grid = GridContainer.new()
	card_grid.columns = _columns()
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_theme_constant_override("h_separation", int(metrics.gap))
	card_grid.add_theme_constant_override("v_separation", int(metrics.gap))
	page.add_child(card_grid)
	_game_order = SaveStore.lobby_order(ContentDB.default_order())
	for meta in ContentDB.ordered_games(_game_order):
		var game_id := str(meta.id)
		var can_resume := SaveStore.resumable_sessions().any(func(entry): return str(entry.get("gameId","")) == game_id)
		var card := LobbyGameCard.new()
		card.configure(meta, can_resume, sorting, get_viewport_rect().size)
		card.launch_requested.connect(_open_game_picker)
		card.resume_requested.connect(_continue_saved_game)
		card.help_requested.connect(_show_game_help)
		card.move_requested.connect(_move_game)
		card.sort_drag_started.connect(_on_card_sort_started)
		card.sort_drag_moved.connect(_on_card_sort_moved)
		card.sort_drag_ended.connect(_on_card_sort_ended)
		card_grid.add_child(card)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.add_child(PlaygroundUI.label("玩到哪里，就记到哪里。", 16, PlaygroundUI.INK_SOFT, 500))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	page.add_child(footer)
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size.y = 8
	page.add_child(bottom_spacer)
	AudioFX.start_music("lobby")
	PlaygroundUI.fade_in(lobby_root, 0.18, 0.0)
	page_scroll.set_deferred("scroll_vertical", _lobby_scroll_offset)
	if sorting:
		show_toast("按住任意游戏卡拖到新位置")


func _lobby_header() -> Control:
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var compact := bool(metrics.compact_cards)
	var panel := PlaygroundUI.panel(Color("#fff7e7"), 28, Color("#dbc29b"), 2)
	panel.custom_minimum_size.y = 80 if compact else 88
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var mark := PlaygroundUI.panel(Color("#ffd56d"), 20, Color("#dca42c"), 2)
	mark.custom_minimum_size = Vector2(58, 58)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/app-icon.svg")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(46, 46)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_child(logo)
	row.add_child(mark)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	brand.add_child(PlaygroundUI.label("童心游乐场", 24 if compact else 27, PlaygroundUI.INK, 700))
	if not compact:
		brand.add_child(PlaygroundUI.label("打开玩具柜，开始今天的发现", 16, PlaygroundUI.INK_SOFT, 500))
	row.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(PlaygroundUI.semantic_icon_button("sound", "声音", Color("#99644f"), _show_settings, "soft"))
	row.add_child(PlaygroundUI.semantic_icon_button("settings", "家长工具" + (" · 有更新" if not _pending_update.is_empty() else ""), Color("#99644f"), _show_parent_tools, "ghost"))
	return panel


func _greeting() -> String:
	if not SaveStore.resumable_sessions().is_empty():
		return "点这里继续上次游戏"
	return "今天想玩哪一关？"


func _profile_chip(profile: Dictionary) -> Control:
	var tint := PlaygroundUI.color(str(profile.get("color", "#d56c29")))
	var chip := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.86), 18, PlaygroundUI.mix(tint, Color.WHITE, 0.45), 2)
	chip.custom_minimum_size = Vector2(122, 52)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.add_child(ArtLibrary.profile_picture(profile, Vector2(34, 34)))
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	copy.add_child(PlaygroundUI.label(str(profile.get("name", "小朋友")), 15, PlaygroundUI.INK, 700))
	copy.add_child(PlaygroundUI.label("%s 岁" % int(profile.get("age", 8)), 11, PlaygroundUI.INK_SOFT, 500))
	row.add_child(copy)
	chip.add_child(row)
	return chip


func _lobby_heading() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title := VBoxContainer.new()
	var title_heading := HBoxContainer.new()
	title_heading.add_theme_constant_override("separation", 8)
	title_heading.add_child(PlaygroundUI.label("我的玩具柜", 32, PlaygroundUI.INK, 700))
	title.add_child(title_heading)
	var entries := SaveStore.resumable_sessions()
	title.add_child(PlaygroundUI.label("挑一件喜欢的，坐下来玩吧" if entries.is_empty() else _latest_session_caption(entries[0]), 17, PlaygroundUI.INK_SOFT, 500, true))
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if not entries.is_empty() and not sorting:
		var resume := PlaygroundUI.button("继续上次", Color("#b57926"), _show_continue_dialog)
		resume.custom_minimum_size = Vector2(154, 60)
		row.add_child(resume)
	row.add_child(PlaygroundUI.semantic_icon_button("shuffle", "随机游戏", Color("#c05b8f"), _show_random_game, "soft"))
	if sorting:
		row.add_child(PlaygroundUI.button("整理好了", Color("#99644f"), _toggle_lobby_sort, "primary"))
	return row


func _latest_session_caption(entry: Dictionary) -> String:
	var meta := ContentDB.game(str(entry.get("gameId", "")))
	return "%s还在等你" % str(meta.get("title", "上次的游戏"))


func _show_parent_tools() -> void:
	var tint := Color("#99644f")
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.add_child(PlaygroundUI.semantic_icon_button("profile", "儿童档案与成长记录", tint, func(): _close_top_modal(); _show_profile_manager(), "soft"))
	content.add_child(PlaygroundUI.semantic_icon_button("sort", "整理玩具柜", tint, func(): _close_top_modal(); _toggle_lobby_sort(), "soft"))
	content.add_child(PlaygroundUI.semantic_icon_button("undo", "恢复默认摆放", tint, _confirm_default_order, "ghost"))
	content.add_child(PlaygroundUI.semantic_icon_button("settings", "声音与应用更新", tint, func(): _close_top_modal(); _show_settings(), "ghost"))
	if not _pending_update.is_empty():
		content.add_child(PlaygroundUI.semantic_icon_button("restart", "查看新版本", tint, func(): _close_top_modal(); _show_update_dialog(), "soft"))
	_open_modal("家长工具", content, [{"text":"返回玩具柜","kind":"primary","callback":func(): _close_top_modal()}], "陪伴与整理", true, {"accent":tint})


func _toggle_lobby_sort() -> void:
	sorting = not sorting
	AudioFX.play("select")
	_rebuild_lobby()


func _confirm_default_order() -> void:
	var content := PlaygroundUI.label("游戏和练习会回到默认位置。每位孩子的进度都会保留。", 20, PlaygroundUI.INK_SOFT, 500, true)
	_open_modal("重新摆好玩具柜？", content, [
		{"text":"先不调整","kind":"ghost","callback":func(): _close_top_modal()},
		{"text":"恢复摆放","kind":"primary","callback":_reset_lobby_order},
	], "只调整卡片顺序", true, {"accent":Color("#99644f")})


func _reset_lobby_order() -> void:
	SaveStore.set_lobby_order(ContentDB.default_order())
	_close_top_modal()
	_close_top_modal()
	_rebuild_lobby()


func _sort_note() -> Control:
	if not sorting:
		return null
	var panel := PlaygroundUI.panel(Color("#fff4c8"), 16, Color("#e5c567"), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(PlaygroundUI.label("⠿", 26, Color("#a77b13"), 700))
	row.add_child(PlaygroundUI.label("按住游戏卡拖到新位置，松手后会记住。排序不会改变游戏进度。", 15, PlaygroundUI.INK_SOFT, 700, true))
	panel.add_child(row)
	return panel


func _open_game_picker(game_id: String, chosen_mode: String = "") -> void:
	if sorting:
		return
	var meta := ContentDB.game(game_id)
	if meta.is_empty():
		return
	if SaveStore.profiles().is_empty():
		_pending_preparation_game = game_id
		_show_profile_manager()
		return
	var tint := PlaygroundUI.color(str(meta.accent))
	var modes := ContentDB.modes(game_id)
	if modes.is_empty():
		show_toast("这个游戏暂时没有可用模式")
		return
	var mode_id := chosen_mode if not chosen_mode.is_empty() else str(_launch_modes.get(game_id, modes[0].id))
	var definition := ContentDB.mode(game_id, mode_id)
	if definition.is_empty() and not modes.is_empty():
		definition = modes[0]
	mode_id = str(definition.id)
	var minimum := int(definition.player_range[0])
	var maximum := int(definition.player_range[1])
	var selected := SaveStore.selected_profiles(game_id, minimum, maximum)
	var chosen_ids: Array = selected.map(func(player): return str(player.id)).slice(0, maximum)
	_preparation = {
		"gameId":game_id, "modeId":mode_id, "ids":chosen_ids,
		"preference":SaveStore.difficulty(game_id, str(chosen_ids[0]) if not chosen_ids.is_empty() else ""),
		"difficultyTouched":false, "modeButtons":[], "profileButtons":[], "difficultyButtons":[],
	}
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	content.add_child(columns)
	var mode_column := VBoxContainer.new()
	mode_column.custom_minimum_size.x = 280
	mode_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_column.add_theme_constant_override("separation", 12)
	mode_column.add_child(PlaygroundUI.label("怎么玩", 24, PlaygroundUI.INK, 700))
	columns.add_child(mode_column)
	var mode_group := ButtonGroup.new()
	for entry in modes:
		var button := PlaygroundUI.choice_button(str(entry.name), tint, mode_group, str(entry.id), str(entry.id) == mode_id, Vector2(0, 64), 21)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_preparation_mode.bind(str(entry.id)))
		mode_column.add_child(button)
		_preparation.modeButtons.append(button)
	var mode_description := PlaygroundUI.label("", 17, PlaygroundUI.INK_SOFT, 500, true)
	mode_column.add_child(mode_description)
	_preparation.description = mode_description
	var player_column := VBoxContainer.new()
	player_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_column.size_flags_stretch_ratio = 1.65
	player_column.add_theme_constant_override("separation", 12)
	columns.add_child(player_column)
	var player_heading := PlaygroundUI.label("", 24, PlaygroundUI.INK, 700)
	player_column.add_child(player_heading)
	_preparation.playerHeading = player_heading
	var choices := HFlowContainer.new()
	choices.add_theme_constant_override("h_separation", 10)
	choices.add_theme_constant_override("v_separation", 10)
	player_column.add_child(choices)
	for profile in SaveStore.profiles():
		var button := PlaygroundUI.choice_button("%s · %s 岁" % [profile.name, profile.age], PlaygroundUI.color(str(profile.color)), null, str(profile.id), str(profile.id) in chosen_ids, Vector2(200, 60), 20)
		var avatar_picture := ArtLibrary.profile_picture(profile, Vector2(38, 38))
		avatar_picture.position = Vector2(10, 11)
		button.add_child(avatar_picture)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box := button.get_theme_stylebox(state)
			if box is StyleBoxFlat:
				var copy := box.duplicate() as StyleBoxFlat
				copy.content_margin_left += 40
				button.add_theme_stylebox_override(state, copy)
		button.pressed.connect(_toggle_preparation_profile.bind(str(profile.id)))
		choices.add_child(button)
		_preparation.profileButtons.append(button)
	var difficulty_box := VBoxContainer.new()
	difficulty_box.add_theme_constant_override("separation", 10)
	difficulty_box.add_child(PlaygroundUI.label("练习难度", 22, PlaygroundUI.INK, 700))
	var difficulty_row := HFlowContainer.new()
	difficulty_row.add_theme_constant_override("h_separation", 8)
	difficulty_row.add_theme_constant_override("v_separation", 8)
	difficulty_box.add_child(difficulty_row)
	var difficulty_group := ButtonGroup.new()
	for value in ["auto", "easy", "normal", "challenge"]:
		var choice := PlaygroundUI.choice_button(GameTuning.label(value), tint, difficulty_group, value, value == str(_preparation.preference), Vector2(96, 52), 19)
		choice.pressed.connect(_select_preparation_difficulty.bind(value))
		difficulty_row.add_child(choice)
		_preparation.difficultyButtons.append(choice)
	difficulty_box.visible = GameTuning.supports(game_id)
	player_column.add_child(difficulty_box)
	var summary_panel := PlaygroundUI.panel(PlaygroundUI.color(str(meta.get("soft", "#fff2db"))), 22, PlaygroundUI.mix(tint, Color.WHITE, 0.55), 2)
	var summary := PlaygroundUI.label("", 20, PlaygroundUI.INK, 700, true)
	summary_panel.add_child(summary)
	content.add_child(summary_panel)
	_preparation.summary = summary
	var pause_hint := HBoxContainer.new()
	pause_hint.add_theme_constant_override("separation", 9)
	pause_hint.add_child(ArtLibrary.semantic_picture("pause", "ui", Vector2(28, 28)))
	var pause_copy := PlaygroundUI.label("游戏中轻点左右纸边，可以打开暂停、规则和声音。", 17, PlaygroundUI.INK_SOFT, 500, true)
	pause_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_hint.add_child(pause_copy)
	content.add_child(pause_hint)
	var layer := _open_modal(str(meta.title) + " · 开始前", content, [
		{"text":"返回玩具柜","kind":"ghost","callback":func(): _close_top_modal()},
		{"text":"开始游戏","kind":"primary","callback":_start_from_preparation},
	], "选玩法、选伙伴，准备好再出发", true, {"accent":tint,"width":1100.0,"size":"L","max_content_height":570.0})
	# 保存真正位于固定操作区的按钮，人数变化直接更新这一颗按钮。
	for control in layer.find_children("*", "Button", true, false):
		if control is Button and control.text == "开始游戏":
			_preparation.startButton = control
			break
	_refresh_preparation()


func _select_preparation_mode(mode_id: String) -> void:
	_preparation.modeId = mode_id
	var definition := ContentDB.mode(str(_preparation.gameId), mode_id)
	var ids: Array = _preparation.ids
	while ids.size() > int(definition.player_range[1]):
		ids.pop_back()
	_refresh_preparation()


func _toggle_preparation_profile(profile_id: String) -> void:
	var ids: Array = _preparation.ids
	var definition := ContentDB.mode(str(_preparation.gameId), str(_preparation.modeId))
	var maximum := int(definition.player_range[1])
	if profile_id in ids:
		ids.erase(profile_id)
	else:
		if ids.size() < maximum:
			ids.append(profile_id)
		else:
			show_toast("这一局最多选 %s 位小朋友，先取消一位再选" % maximum)
	if not bool(_preparation.difficultyTouched):
		_preparation.preference = SaveStore.difficulty(str(_preparation.gameId), str(ids[0]) if not ids.is_empty() else "")
	AudioFX.play("select")
	_refresh_preparation()


func _select_preparation_difficulty(preference: String) -> void:
	_preparation.preference = preference
	_preparation.difficultyTouched = true
	_refresh_preparation()


func _refresh_preparation() -> void:
	var game_id := str(_preparation.gameId)
	var definition := ContentDB.mode(game_id, str(_preparation.modeId))
	var ids: Array = _preparation.ids
	var minimum := int(definition.player_range[0])
	var maximum := int(definition.player_range[1])
	var selected: Array = []
	for profile_id in ids:
		selected.append(SaveStore.profile(str(profile_id)))
	_preparation.playerHeading.text = "谁来玩 · 选 %s 位" % minimum if minimum == maximum else "谁来玩 · 选 %s–%s 位" % [minimum, maximum]
	_preparation.description.text = str(definition.get("description", ""))
	for button in _preparation.modeButtons:
		button.set_pressed_no_signal(str(button.get_meta("choice_value")) == str(_preparation.modeId))
	for button in _preparation.profileButtons:
		button.set_pressed_no_signal(str(button.get_meta("choice_value")) in ids)
	for button in _preparation.difficultyButtons:
		var value := str(button.get_meta("choice_value"))
		button.set_pressed_no_signal(value == str(_preparation.preference))
		button.text = "自动 · " + GameTuning.label(GameTuning.resolve("auto", selected)) if value == "auto" else GameTuning.label(value)
	var summary := "再选 %s 位小朋友，就可以出发" % maxi(0, minimum - ids.size())
	if ids.size() >= minimum:
		if TabletopLayout.enabled(game_id, selected, str(_preparation.modeId)):
			summary = "左边：%s　　右边：%s\n两位小朋友坐在平板的左右短边" % [selected[0].name, selected[1].name]
		elif selected.size() == 2:
			summary = "%s 和 %s\n坐在平板下方，一人一次轮流玩" % [selected[0].name, selected[1].name]
		elif game_id == "poetry":
			summary = "%s 来背诗，家长拿好平板" % selected[0].name
		else:
			summary = "%s · %s" % [selected[0].name, definition.name]
		if GameTuning.supports(game_id):
			summary += "　·　" + GameTuning.label(GameTuning.resolve(str(_preparation.preference), selected))
	_preparation.summary.text = summary
	var start_button: Button = _preparation.get("startButton")
	if is_instance_valid(start_button):
		start_button.disabled = ids.size() < minimum or ids.size() > maximum


func _start_from_preparation() -> void:
	var game_id := str(_preparation.gameId)
	var mode_id := str(_preparation.modeId)
	var definition := ContentDB.mode(game_id, mode_id)
	var ids: Array = _preparation.ids.duplicate()
	if ids.size() < int(definition.player_range[0]) or ids.size() > int(definition.player_range[1]):
		_refresh_preparation()
		return
	var preference := str(_preparation.preference) if GameTuning.supports(game_id) else "auto"
	var entry := _matching_session(game_id, mode_id, ids)
	if not entry.is_empty():
		var explanation := PlaygroundUI.label("这几位小朋友还有一局正在进行。继续原来的发现，或重新开始？", 21, PlaygroundUI.INK_SOFT, 500, true)
		_open_modal("这局还在等你", explanation, [
			{"text":"返回准备","kind":"ghost","callback":func(): _close_top_modal()},
			{"text":"另开一局","kind":"soft","callback":_commit_prepared_start.bind(game_id, mode_id, ids, preference)},
			{"text":"继续这局","kind":"primary","callback":func(): _close_lobby_modals(); _resume_entry(entry)},
		], "另开一局只替换这局进度，成长记录会保留", true, {"accent":PlaygroundUI.color(str(ContentDB.game(game_id).accent))})
		return
	_commit_prepared_start(game_id, mode_id, ids, preference)


func _matching_session(game_id: String, mode_id: String, ids: Array) -> Dictionary:
	var ordered := ids.duplicate()
	ordered.sort()
	for entry in SaveStore.resumable_sessions():
		var participants: Array = entry.get("participantIds", []).duplicate()
		participants.sort()
		if str(entry.get("gameId", "")) == game_id and str(entry.get("modeId", "classic")) == mode_id and participants == ordered:
			return entry
	return {}


func _commit_prepared_start(game_id: String, mode_id: String, ids: Array, preference: String) -> void:
	_close_lobby_modals()
	SaveStore.select_profiles(game_id, ids)
	SaveStore.set_context(game_id, mode_id, ids)
	SaveStore.clear_state(game_id, str(ids[0]))
	var selected: Array = []
	for profile_id in ids:
		selected.append(SaveStore.profile(str(profile_id)))
	_start_game(game_id, selected, mode_id, preference)


func _close_lobby_modals() -> void:
	while not modal_stack.is_empty():
		_close_top_modal()


func _start_game(
	game_id: String,
	selected: Array,
	chosen_mode: String = "",
	difficulty_pref: String = "auto",
	resume_existing: bool = false
) -> void:
	if selected.is_empty() or not GAME_SCRIPTS.has(game_id):
		return
	var target_mode := chosen_mode if not chosen_mode.is_empty() else str(_launch_modes.get(game_id,"classic"))
	var definition := ContentDB.mode(game_id,target_mode)
	if definition.is_empty():
		_open_game_picker(game_id)
		return
	if selected.size() < int(definition.player_range[0]) or selected.size() > int(definition.player_range[1]):
		_open_game_picker(game_id,target_mode)
		return
	var meta := ContentDB.game(game_id).duplicate(true)
	meta.modeId = target_mode
	meta.resume = resume_existing
	meta.freshStart = not resume_existing
	if not GameTuning.supports(game_id):
		difficulty_pref = "auto"
	meta.difficultyPreference = difficulty_pref
	SaveStore.set_difficulty(game_id, str(selected[0].id), difficulty_pref)
	Close_previous_screen()
	var script = load(GAME_SCRIPTS[game_id])
	var screen = script.new()
	screen.setup(meta,selected)
	screen.back_requested.connect(_return_to_lobby)
	screen.restart_requested.connect(func():
		SaveStore.clear_state(game_id,str(selected[0].id))
		_start_game(game_id,selected,target_mode,difficulty_pref,false)
	)
	screen.pause_changed.connect(func(is_paused: bool):
		if is_paused:
			AudioFX.stop_all()
		else:
			AudioFX.start_music(str(MUSIC_THEMES.get(game_id,"lobby")))
	)
	screen_root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.modulate.a = 0.0
	var entrance := MotionKit.tween(screen)
	entrance.tween_property(screen, "modulate:a", 1.0, MotionKit.PAGE_FADE)
	current_screen = screen
	_screen_game = game_id
	_launch_modes[game_id] = target_mode
	if is_instance_valid(lobby_root):
		lobby_root.hide()
	AudioFX.start_music(str(MUSIC_THEMES.get(game_id,"lobby")))


func Close_previous_screen() -> void:
	if is_instance_valid(current_screen):
		current_screen.queue_free()
	current_screen = null
	_screen_game = ""


func _return_to_lobby() -> void:
	var leaving := current_screen
	current_screen = null
	_screen_game = ""
	if is_instance_valid(leaving):
		leaving.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fade := MotionKit.tween(leaving)
		fade.tween_property(leaving, "modulate:a", 0.0, 0.16)
		await fade.finished
		if is_instance_valid(leaving):
			leaving.queue_free()
	_rebuild_lobby()
	if is_instance_valid(lobby_root):
		lobby_root.show()


func _show_game_help(game_id: String) -> void:
	var meta := ContentDB.game(game_id)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	for index in meta.get("guide", []).size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(PlaygroundUI.chip(str(index + 1), PlaygroundUI.color(str(meta.accent))))
		row.add_child(PlaygroundUI.label(str(meta.guide[index]), 17, PlaygroundUI.INK_SOFT, 500, true))
		content.add_child(row)
	Speech.speak("%s玩法。%s" % [meta.title, " ".join(meta.guide)])
	_open_modal("%s怎么玩" % str(meta.title), content, [
		{"text": "再读一遍", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道啦", "kind": "primary", "callback": func(): _close_top_modal()},
	], "给家长和小玩家")


func _show_continue_dialog() -> void:
	var items := SaveStore.resumable_sessions()
	if items.is_empty():
		show_toast("选一张游戏卡，开始新的发现吧")
		return
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	for entry in items:
		var meta := ContentDB.game(str(entry.gameId))
		if meta.is_empty():
			continue
		var names: Array = []
		for id in entry.get("participantIds",[]):
			names.append(str(SaveStore.profile(str(id)).get("name","小朋友")))
		var title := "%s · %s\n%s · %s" % [meta.title,ContentDB.mode(str(entry.gameId),str(entry.get("modeId","classic"))).get("name","经典模式"),"、".join(names),entry.get("note","已保存")]
		var button := PlaygroundUI.button(title,PlaygroundUI.color(str(meta.accent)),func(): _close_top_modal(); _resume_entry(entry),"soft")
		button.custom_minimum_size.y = 80
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		content.add_child(button)
	_open_modal("继续上次游戏",content,[{"text":"关闭","kind":"ghost","callback":func(): _close_top_modal()}],"每位孩子、每种玩法分别保存")


func _resume_entry(entry: Dictionary) -> void:
	var selected: Array = []
	for id in entry.get("participantIds",[]):
		var profile := SaveStore.profile(str(id))
		if not profile.is_empty():
			selected.append(profile)
	if selected.is_empty():
		_open_game_picker(str(entry.gameId),str(entry.get("modeId","classic")))
	else:
		var game_id := str(entry.gameId)
		var preference := SaveStore.difficulty(game_id, str(selected[0].id))
		_start_game(game_id, selected, str(entry.get("modeId","classic")), preference, true)


func _continue_saved_game(game_id: String) -> void:
	var matching: Array = SaveStore.resumable_sessions().filter(
		func(entry): return str(entry.get("gameId", "")) == game_id
	)
	if matching.is_empty():
		_open_game_picker(game_id)
	elif matching.size() == 1:
		_resume_entry(matching[0])
	else:
		_show_continue_dialog()


func _show_random_game() -> void:
	var games := ContentDB.ordered_games(_game_order)
	if games.is_empty():
		return
	var result: Dictionary = games.pick_random()
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	var icon := ArtLibrary.semantic_picture("shuffle", "ui", Vector2(74, 74))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(icon)
	var title := PlaygroundUI.label("转盘转动中…", 32, PlaygroundUI.INK, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var subtitle := PlaygroundUI.label("看看今天停在哪一款", 16, PlaygroundUI.INK_SOFT, 500)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	AudioFX.play("select")
	var random_layer := _open_modal("随机游戏", content, [
		{"text": "再转一次", "icon": "repeat", "kind": "soft", "callback": func(): _close_top_modal(); _show_random_game()},
		{"text": "就玩这个", "icon": "play", "kind": "primary", "callback": _play_random_result.bind(str(result.id))},
	], "今天玩什么？", false)
	var accept_button: Button
	for control in random_layer.find_children("*", "Button", true, false):
		if control is Button and control.text == "就玩这个":
			accept_button = control
			break
	if is_instance_valid(accept_button):
		accept_button.disabled = true
	for tick in 14:
		if not is_instance_valid(title):
			return
		var preview: Dictionary = games.pick_random()
		title.text = str(preview.title)
		AudioFX.play("tap")
		await get_tree().create_timer(0.07 + tick * 0.006).timeout
	if is_instance_valid(title):
		title.text = str(result.title)
		var old_icon := icon
		icon = ArtLibrary.semantic_picture("continue", "ui", Vector2(74, 74))
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.add_child(icon)
		content.move_child(icon,0)
		if is_instance_valid(old_icon):
			old_icon.queue_free()
		subtitle.text = "转盘停在这里，由你决定是否出发"
		if is_instance_valid(accept_button):
			accept_button.disabled = false
		AudioFX.play("win")


func _play_random_result(game_id: String) -> void:
	_close_top_modal()
	var meta := ContentDB.game(game_id)
	if meta.is_empty():
		return
	var modes: Array = ContentDB.modes(game_id)
	if modes.is_empty():
		return
	var definition: Dictionary = modes[0]
	_open_game_picker(game_id,str(definition.id))


func _reorder_game(from_id: String, to_id: String) -> void:
	var from_index := _game_order.find(from_id)
	if from_index < 0 or not (to_id in _game_order):
		return
	_game_order.remove_at(from_index)
	var target_index := _game_order.find(to_id)
	_game_order.insert(target_index if target_index >= 0 else _game_order.size(), from_id)
	SaveStore.set_lobby_order(_game_order)
	AudioFX.play("confirm")
	_rebuild_lobby()


func _move_game(game_id: String, direction: int) -> void:
	var index := _game_order.find(game_id)
	var target := clampi(index + direction, 0, _game_order.size() - 1)
	if index < 0 or target == index:
		return
	_game_order.remove_at(index)
	_game_order.insert(target, game_id)
	SaveStore.set_lobby_order(_game_order)
	AudioFX.play("select")
	_rebuild_lobby()


func _show_profile_manager() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	for profile in SaveStore.profiles():
		var tint := PlaygroundUI.color(str(profile.color))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.add_child(ArtLibrary.profile_picture(profile, Vector2(44, 44)))
		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_child(PlaygroundUI.label(str(profile.name), 18, PlaygroundUI.INK, 700))
		copy.add_child(PlaygroundUI.label("%s 岁" % profile.age, 12, PlaygroundUI.INK_SOFT, 500))
		row.add_child(copy)
		row.add_child(PlaygroundUI.button("成长", tint, _show_profile_report.bind(profile), "ghost"))
		row.add_child(PlaygroundUI.button("编辑", tint, _show_profile_form.bind(profile), "soft"))
		row.add_child(PlaygroundUI.button("删除", Color("#c35a48"), _confirm_delete_profile.bind(profile), "ghost"))
		content.add_child(row)
	if SaveStore.profiles().is_empty():
		content.add_child(PlaygroundUI.label("还没有儿童档案。先给孩子建一个名字和年龄吧。", 17, PlaygroundUI.INK_SOFT, 500, true))
	var actions := []
	if SaveStore.profiles().size() < SaveStore.MAX_PROFILES:
		actions.append({"text": "新建档案", "icon": "profile", "kind": "primary", "callback": func(): _close_top_modal(); _show_profile_form({})})
	actions.append({"text": "关闭", "kind": "soft", "callback": func(): _pending_preparation_game = ""; _close_top_modal()})
	_open_modal("儿童档案", content, actions, "最多 8 位，数据只保存在本机", false)


func _show_profile_report(profile: Dictionary) -> void:
	_close_top_modal()
	var records := SaveStore.records_for(str(profile.id))
	var skills: Dictionary = records.get("skills", {})
	var tint := PlaygroundUI.color(str(profile.color))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(ArtLibrary.profile_picture(profile, Vector2(54, 54)))
	var copy := VBoxContainer.new()
	copy.add_child(PlaygroundUI.label(str(profile.name), 24, PlaygroundUI.INK, 700))
	copy.add_child(PlaygroundUI.label("%s 岁 · 最近 40 场保存在本机" % profile.age, 13, PlaygroundUI.INK_SOFT, 500))
	head.add_child(copy)
	content.add_child(head)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	var radar := ReportRadar.new()
	radar.configure(skills, tint)
	split.add_child(radar)
	var advice := VBoxContainer.new()
	advice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advice.add_theme_constant_override("separation", 7)
	var names := {"math": "数算", "language": "语言", "science": "科学", "logic": "逻辑", "memory": "记忆", "strategy": "策略"}
	var suggestions := {
		"math": "可以多用生活里的加减法和购物题练习。",
		"language": "可以每天读一首短诗，再讲讲诗里的画面。",
		"science": "可以一起观察动物住在哪里、吃什么。",
		"logic": "可以玩图形规律和棋类，让孩子说说下一步为什么。",
		"memory": "翻牌时先说出位置，再做一次回忆。",
		"strategy": "棋类对局结束后回顾一个关键选择。",
	}
	var has_skill := false
	for key in ["math", "language", "science", "logic", "memory", "strategy"]:
		var item: Dictionary = skills.get(key, {})
		var answered := int(item.get("answered", 0))
		if answered <= 0:
			continue
		has_skill = true
		var ratio := float(item.get("correct", 0)) / float(answered)
		advice.add_child(PlaygroundUI.label(
			"%s：%s%% · %s" % [names[key], roundi(ratio * 100), suggestions[key] if ratio < 0.75 else "保持练习，可以试试更丰富的题。"],
			14,
			PlaygroundUI.INK_SOFT,
			500,
			true
		))
	if not has_skill:
		advice.add_child(PlaygroundUI.label("还没有能力记录。先完成一局游戏，这里会按六个维度显示练习情况。", 15, PlaygroundUI.INK_SOFT, 500, true))
	split.add_child(advice)
	content.add_child(split)
	var shelf_value: Variant = SaveStore.learning(str(profile.id), "stories").get("storyShelf", {})
	var story_learning: Dictionary = shelf_value if shelf_value is Dictionary else {}
	if not story_learning.is_empty():
		var heard: Array = story_learning.get("completed", []) if story_learning.get("completed") is Array else []
		var favorites: Array = story_learning.get("favorites", []) if story_learning.get("favorites") is Array else []
		var story_note := HBoxContainer.new()
		story_note.add_theme_constant_override("separation", 8)
		var story_icon := ArtLibrary.semantic_picture("story", "ui", Vector2(28, 28))
		story_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		story_note.add_child(story_icon)
		var story_text := PlaygroundUI.label("故事听读足迹：读过 %s 篇 · 收藏 %s 篇\n这些是听读记录，不作为语言能力评分；可以请孩子讲讲最喜欢的片段。" % [heard.size(), favorites.size()], 16, PlaygroundUI.INK_SOFT, 500, true)
		story_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		story_note.add_child(story_text)
		content.add_child(story_note)
	_open_modal("%s 的成长报告" % profile.name, content, [
		{"text": "关闭", "kind": "primary", "callback": func(): _close_top_modal()},
	], "只用于本机辅导，不显示排行")


func _show_profile_form(existing: Dictionary) -> void:
	var starting_age := int(existing.get("age", 7))
	var starting_avatar := str(existing.get("avatar", "🦊"))
	var starting_color := str(existing.get("color", "#d56c29"))
	var brand := Color("#167d74")
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var intro := HBoxContainer.new()
	intro.add_theme_constant_override("separation", 10)
	intro.add_child(ArtLibrary.semantic_picture("profile", "ui", Vector2(26, 26)))
	var intro_copy := PlaygroundUI.label("给孩子起个名字，再挑一个喜欢的头像和代表色。", 17, PlaygroundUI.INK_SOFT, 500, true)
	intro_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.add_child(intro_copy)
	content.add_child(intro)
	var name_section := VBoxContainer.new()
	name_section.add_theme_constant_override("separation", 7)
	name_section.add_child(PlaygroundUI.label("孩子怎么称呼？", 16, PlaygroundUI.INK, 700))
	var name_edit := PlaygroundUI.text_field("孩子的名字", str(existing.get("name", "")), brand)
	name_section.add_child(name_edit)
	var form_columns := HBoxContainer.new()
	form_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_columns.add_theme_constant_override("separation", 22)
	var form_left := VBoxContainer.new()
	form_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_left.add_theme_constant_override("separation", 14)
	var form_right := VBoxContainer.new()
	form_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_right.add_theme_constant_override("separation", 14)
	form_columns.add_child(form_left)
	form_columns.add_child(form_right)
	form_left.add_child(name_section)
	var age_group := ButtonGroup.new()
	var age_row := HFlowContainer.new()
	age_row.add_theme_constant_override("h_separation", 8)
	age_row.add_theme_constant_override("v_separation", 8)
	for age in range(4, 13):
		age_row.add_child(PlaygroundUI.choice_button(
			"%s 岁" % age,
			brand,
			age_group,
			age,
			age == starting_age,
			Vector2(72, 50)
		))
	form_left.add_child(_profile_form_section("年龄", "会用来匹配适合孩子的题目难度", age_row))
	var avatar_group := ButtonGroup.new()
	var avatar_row := HFlowContainer.new()
	avatar_row.add_theme_constant_override("h_separation", 8)
	avatar_row.add_theme_constant_override("v_separation", 8)
	for avatar in AVATARS:
		var avatar_button := PlaygroundUI.choice_button(
			"",
			brand,
			avatar_group,
			avatar,
			avatar == starting_avatar,
			Vector2(58, 54),
			27
		)
		var avatar_index := maxi(0, AVATARS.find(avatar))
		var avatar_picture := ArtLibrary.profile_picture(
			{"avatar": avatar, "color": PROFILE_COLORS[avatar_index % PROFILE_COLORS.size()]},
			Vector2(40, 40)
		)
		var avatar_center := CenterContainer.new()
		avatar_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		avatar_center.add_child(avatar_picture)
		avatar_button.add_child(avatar_center)
		avatar_row.add_child(avatar_button)
	form_right.add_child(_profile_form_section("头像", "每个孩子都可以选自己的小动物", avatar_row))
	var color_names := {
		"#d56c29": "橙色",
		"#2878c8": "湖蓝",
		"#64a244": "草绿",
		"#8657a7": "藤紫",
		"#c05b8f": "玫粉",
		"#167d74": "青绿",
		"#5b63b2": "靛蓝",
		"#b69014": "明黄",
	}
	var color_group := ButtonGroup.new()
	var color_row := HFlowContainer.new()
	color_row.add_theme_constant_override("h_separation", 8)
	color_row.add_theme_constant_override("v_separation", 8)
	for color in PROFILE_COLORS:
		var tint := PlaygroundUI.color(str(color))
		var color_button := PlaygroundUI.choice_button(
			str(color_names.get(str(color), "代表色")),
			tint,
			color_group,
			str(color),
			str(color) == starting_color,
			Vector2(78, 50),
			16
		)
		color_button.tooltip_text = str(color)
		color_row.add_child(color_button)
	form_right.add_child(_profile_form_section("代表色", "会用在档案卡片和本局玩家标识上", color_row))
	content.add_child(form_columns)
	var save_profile := func():
		var name := name_edit.text.strip_edges()
		if name.is_empty():
			name_edit.grab_focus()
			show_toast("先给孩子起个名字")
			return
		var age := int(_profile_choice_value(age_row, starting_age))
		var avatar := str(_profile_choice_value(avatar_row, starting_avatar))
		var tint := str(_profile_choice_value(color_row, starting_color))
		if existing.is_empty():
			SaveStore.add_profile(name, age, avatar, tint)
		else:
			SaveStore.update_profile(str(existing.id), name, age, avatar, tint)
		var reopen_game := _pending_preparation_game
		_pending_preparation_game = ""
		_close_top_modal()
		_rebuild_lobby()
		AudioFX.play("confirm")
		if not reopen_game.is_empty():
			call_deferred("_open_game_picker", reopen_game)
	name_edit.text_submitted.connect(func(_text: String): save_profile.call())
	_open_modal(
		"编辑儿童档案" if not existing.is_empty() else "新建儿童档案",
		content,
		[
			{"text": "取消", "kind": "ghost", "callback": func(): _pending_preparation_game = ""; _close_top_modal()},
			{"text": "保存修改" if not existing.is_empty() else "保存档案", "kind": "primary", "callback": save_profile},
		],
		"名字和年龄会用于开局",
		false,
		{"size": "L", "width": 1000.0, "fit_content": true, "scroll": false, "separation": 16}
	)


func _profile_form_section(title: String, hint: String, control: Control) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	section.add_child(PlaygroundUI.label(title, 16, PlaygroundUI.INK, 700))
	section.add_child(PlaygroundUI.label(hint, 13, PlaygroundUI.INK_SOFT, 500))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(control)
	return section


func _profile_choice_value(container: Control, fallback: Variant) -> Variant:
	for child in container.get_children():
		var choice := child as Button
		if choice != null and choice.button_pressed:
			return choice.get_meta("choice_value", fallback)
	return fallback


func _confirm_delete_profile(profile: Dictionary) -> void:
	_close_top_modal()
	var content := VBoxContainer.new()
	content.add_child(PlaygroundUI.label("会删除 %s 的档案、游戏进度和成长记录，其他孩子不会受到影响。" % profile.name, 17, PlaygroundUI.INK_SOFT, 500, true))
	_open_modal("删除 %s 的档案？" % profile.name, content, [
		{"text": "先保留", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "确认删除", "kind": "primary", "callback": _delete_profile_confirmed.bind(profile)},
	], "请家长确认", false)


func _delete_profile_confirmed(profile: Dictionary) -> void:
	SaveStore.delete_profile(str(profile.id))
	_close_top_modal()
	_rebuild_lobby()


func _show_settings() -> void:
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	var settings := SaveStore.settings()
	var labels := {
		"soundOn": {"icon": "sound", "text": "音效"},
		"musicOn": {"icon": "music", "text": "背景音乐"},
		"speechOn": {"icon": "speech", "text": "中文朗读"},
		"hapticsOn": {"icon": "haptics", "text": "触感反馈"},
	}
	for key in ["soundOn", "musicOn", "speechOn", "hapticsOn"]:
		var state := "开" if bool(settings.get(key, true)) else "关"
		var entry: Dictionary = labels[key]
		content.add_child(PlaygroundUI.semantic_icon_button(str(entry["icon"]), "%s：%s" % [str(entry["text"]), state], Color("#167d74"), _toggle_setting.bind(key), "soft"))
	content.add_child(NativeGameScreen.volume_controls(Color("#167d74")))
	content.add_child(PlaygroundUI.separator())
	content.add_child(PlaygroundUI.label("应用更新", 15, PlaygroundUI.INK_SOFT, 700))
	content.add_child(PlaygroundUI.button("检查新版本", Color("#5b63b2"), func():
		_manual_check = true
		show_toast("正在检查更新…")
		UpdateService.check_for_updates(true)
	, "soft"))
	_open_modal("声音与朗读", content, [
		{"text": "关闭", "kind": "primary", "callback": func(): _close_top_modal()},
	], "切到后台也会自动暂停音乐")


func _toggle_setting(key: String) -> void:
	SaveStore.set_setting(key, not bool(SaveStore.settings().get(key, true)))
	AudioFX.refresh_settings()
	Speech.stop()
	_close_top_modal()
	_show_settings()


func _on_update_available(info: Dictionary) -> void:
	_pending_update = info
	if is_instance_valid(lobby_root) and current_screen == null:
		show_toast("发现新版本，可在“家长工具”中查看")
		_rebuild_lobby()


func _on_update_error(message: String) -> void:
	if _manual_check:
		_manual_check = false
		show_toast(message)


func _on_check_finished(info: Dictionary) -> void:
	if _manual_check:
		var apk: Dictionary = info.get("apk", {})
		if int(apk.get("versionCode", 0)) <= UpdateService.app_version_code():
			show_toast("当前已经是最新版本")
		_manual_check = false


func _show_update_dialog() -> void:
	if _pending_update.is_empty():
		show_toast("当前已经是最新版本")
		return
	var apk: Dictionary = _pending_update.get("apk", {})
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.add_child(PlaygroundUI.label("新版本 %s（%s）" % [apk.get("versionName", ""), apk.get("versionCode", "")], 24, PlaygroundUI.INK, 700))
	if not str(apk.get("notes", "")).is_empty():
		content.add_child(PlaygroundUI.label(str(apk.get("notes", "")), 15, PlaygroundUI.INK_SOFT, 500, true))
	content.add_child(PlaygroundUI.label("更新会保留全部儿童档案与游戏进度。可以现在安装，也可以稍后回大厅处理。", 15, PlaygroundUI.INK_SOFT, 500, true))
	var actions := [
		{"text": "稍后更新", "kind": "soft", "callback": func(): _close_top_modal()},
	]
	if not UpdateService.install_permission_allowed():
		actions.append({"text": "允许安装更新", "kind": "soft", "callback": func(): UpdateService.open_install_permission_settings()})
	var download_action := func():
		_close_top_modal()
		show_toast("正在下载安装包…", 4.0)
		UpdateService.download_apk()
	actions.append({"text": "下载并安装", "kind": "primary", "callback": download_action})
	_open_modal("发现新版本", content, actions, "更新检测")


func _open_modal(
	title: String,
	content: Control,
	actions: Array,
	eyebrow: String = "",
	dismissible: bool = true,
	options: Dictionary = {}
) -> Control:
	if dialogs != null:
		# 统一走 DialogManager（全局弹窗栈），本地 modal_stack 只做镜像供返回键判断
		var opts := options.duplicate()
		opts["title"] = title
		opts["body"] = content
		opts["buttons"] = actions
		opts["eyebrow"] = eyebrow
		opts["dismissible"] = dismissible
		if not opts.has("accent"):
			opts["accent"] = Color("#167d74")
		if not opts.has("width"):
			opts["width"] = 840.0
		var managed: Control = dialogs.show_dialog(opts)
		modal_stack.append(managed)
		return managed
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var viewport_size := get_viewport_rect().size
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 120
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.16, 0.13, 0.44)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := PlaygroundUI.panel(PlaygroundUI.PAPER, 30, Color("#d8c9a9"), 2)
	var modal_width := minf(float(options.get("width", 780.0)), maxf(360.0, viewport_size.x - metrics.margin * 4.0))
	card.custom_minimum_size = Vector2(modal_width, 0.0)
	card.modulate.a = 0.0
	card.scale = Vector2(0.97, 0.97)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(options.get("separation", 13)))
	card.add_child(column)
	if not eyebrow.is_empty():
		column.add_child(PlaygroundUI.label(eyebrow, 13, Color("#167d74"), 700))
	column.add_child(PlaygroundUI.label(title, 31, PlaygroundUI.INK, 700, true))
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bool(options.get("scroll", true)):
		var content_scroll := ScrollContainer.new()
		content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		content_scroll.add_child(content)
		var max_height := minf(float(options.get("max_content_height", 430.0)), viewport_size.y * 0.46)
		var desired_content_height := clampf(content.get_combined_minimum_size().y + 8.0, 72.0, max_height)
		content_scroll.custom_minimum_size.y = desired_content_height
		column.add_child(content_scroll)
	else:
		column.add_child(content)
	if not actions.is_empty():
		var action_row := HFlowContainer.new()
		action_row.alignment = FlowContainer.ALIGNMENT_END
		action_row.add_theme_constant_override("separation", 10)
		for action in actions:
			var button := PlaygroundUI.button(str(action.text), Color("#167d74"), action.callback, str(action.get("kind", "primary")))
			button.custom_minimum_size.x = 132
			action_row.add_child(button)
		column.add_child(action_row)
	modal_root.add_child(layer)
	modal_stack.append(layer)
	card.resized.connect(func(): card.pivot_offset = Vector2(card.size.x * 0.5, 0))
	var animation := MotionKit.tween(self)
	animation.set_parallel(true)
	animation.tween_property(card, "modulate:a", 1.0, MotionKit.MODAL_IN)
	animation.tween_property(card, "scale", Vector2.ONE, MotionKit.MODAL_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return layer


func _close_top_modal() -> void:
	if modal_stack.is_empty():
		return
	var layer: Control = modal_stack.back()
	if dialogs != null and dialogs.owns_layer(layer):
		dialogs.close_layer(layer)
		return
	modal_stack.erase(layer)
	if not is_instance_valid(layer):
		return
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MotionKit.fade_out_and_free(layer, self, MotionKit.MODAL_OUT)


func show_toast(message: String, seconds: float = 2.4) -> void:
	if dialogs != null:
		dialogs.show_toast(message, seconds)
		return
	var toast := PlaygroundUI.panel(Color(0.15, 0.18, 0.16, 0.92), 15, Color.TRANSPARENT)
	toast.z_index = 200
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(0, 72)
	toast.add_child(PlaygroundUI.label(message, 15, Color.WHITE, 700))
	add_child(toast)
	toast.modulate.a = 0.0
	var tween := MotionKit.tween(self)
	tween.tween_property(toast, "modulate:a", 1.0, 0.14)
	tween.tween_interval(seconds)
	tween.tween_property(toast, "modulate:a", 0.0, 0.25)
	tween.tween_callback(toast.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if current_screen != null:
			return
		if dialogs != null and dialogs.has_open_dialog():
			dialogs.close_top(true)
		elif not modal_stack.is_empty():
			if bool(modal_stack.back().get_meta("dismissible", true)):
				_close_top_modal()
		else:
			_confirm_exit_app()
		get_viewport().set_input_as_handled()


func _on_dialog_closed(layer: Control) -> void:
	modal_stack.erase(layer)


func _on_card_sort_started(game_id: String, global_pos: Vector2) -> void:
	if not sorting or dialogs.has_open_dialog():
		return
	for card in card_grid.get_children():
		if card is LobbyGameCard and card.game_id == game_id:
			_sort_drag_card = card
			break
	if not is_instance_valid(_sort_drag_card):
		return
	if scroll is SmoothScrollContainer:
		scroll.cancel_gesture()
	_drag_pointer = global_pos
	var started := _sort_drag.begin(game_id, func():
		var ghost := PlaygroundUI.panel(PlaygroundUI.PAPER, 24, _sort_drag_card.accent, 2)
		ghost.custom_minimum_size = Vector2(240, 90)
		ghost.size = ghost.custom_minimum_size
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.add_child(PlaygroundUI.label(str(_sort_drag_card.game.get("title", "游戏")), 24, _sort_drag_card.accent, 700))
		return ghost
	, {"start": global_pos, "hit_test": _sort_hit_test, "on_drop": _sort_drop, "on_cancel": _clear_sort_visuals})
	if not started:
		_sort_drag_card.cancel_gesture()
		_clear_sort_visuals()
		return
	_sort_drag_card.modulate.a = 0.45
	_insert_line = ColorRect.new()
	_insert_line.color = _sort_drag_card.accent
	_insert_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_root.add_child(_insert_line)
	_update_insert_line()


func _on_card_sort_moved(_game_id: String, global_pos: Vector2) -> void:
	_drag_pointer = global_pos
	_sort_drag.move_to(global_pos)
	_update_insert_line()


func _on_card_sort_ended(_game_id: String, global_pos: Vector2) -> void:
	_sort_drag.drop(global_pos)


func _sort_hit_test(global_pos: Vector2) -> Variant:
	if not is_instance_valid(card_grid) or not scroll.get_global_rect().has_point(global_pos):
		return null
	for card in card_grid.get_children():
		if card is LobbyGameCard and card != _sort_drag_card and card.get_global_rect().has_point(global_pos):
			return card.game_id
	return null


func _update_insert_line() -> void:
	if not is_instance_valid(_insert_line):
		return
	var target: Variant = _sort_hit_test(_drag_pointer)
	_insert_line.visible = target != null
	if target == null:
		return
	for card in card_grid.get_children():
		if card is LobbyGameCard and card.game_id == target:
			var rect: Rect2 = card.get_global_rect()
			_insert_line.position = modal_root.get_global_transform_with_canvas().affine_inverse() * (rect.position - Vector2(4, 0))
			_insert_line.size = Vector2(5, rect.size.y)
			return


func _sort_auto_scroll(delta: float) -> void:
	if not is_instance_valid(scroll):
		_cancel_sort_drag()
		return
	var rect := scroll.get_global_rect()
	var direction := 0.0
	if _drag_pointer.y < rect.position.y + 64.0:
		direction = -1.0
	elif _drag_pointer.y > rect.end.y - 64.0:
		direction = 1.0
	scroll.scroll_vertical += roundi(direction * 560.0 * delta)
	_sort_drag.move_to(_drag_pointer)
	_update_insert_line()


func _sort_drop(payload: Variant, _position: Vector2, target: Variant) -> void:
	_clear_sort_visuals()
	if target == null or payload == target:
		return
	var from := _game_order.find(str(payload))
	if from < 0:
		return
	_game_order.remove_at(from)
	_game_order.insert(_game_order.find(str(target)), str(payload))
	SaveStore.set_lobby_order(_game_order)
	for index in _game_order.size():
		for card in card_grid.get_children():
			if card is LobbyGameCard and card.game_id == _game_order[index]:
				card_grid.move_child(card, index)
				break


func _clear_sort_visuals() -> void:
	if is_instance_valid(_sort_drag_card):
		_sort_drag_card.modulate = Color.WHITE
		_sort_drag_card.cancel_gesture()
	_sort_drag_card = null
	if is_instance_valid(_insert_line):
		_insert_line.queue_free()
	_insert_line = null


func _cancel_sort_drag() -> void:
	if is_instance_valid(_sort_drag) and _sort_drag.active:
		_sort_drag.cancel()
	_clear_sort_visuals()


func _confirm_exit_app() -> void:
	var content := VBoxContainer.new()
	content.add_child(PlaygroundUI.label("所有游戏已经自动保存。确定要关闭童心游乐场吗？", 17, PlaygroundUI.INK_SOFT, 500, true))
	_open_modal("退出应用？", content, [
		{"text": "继续玩", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "退出", "kind": "primary", "callback": _quit_after_save},
	], "返回键")


func _quit_after_save() -> void:
	SaveStore.flush()
	get_tree().quit()
