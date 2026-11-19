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
var _random_token := 0
var _launch_modes: Dictionary = {}
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
	# 后台线程预载全部封面，避免大厅首帧同步解码
	LobbyCoverCache.warmup(_cover_paths())
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
	# 封面线程加载状态轮询（完成后回填卡片）
	LobbyCoverCache.poll()
	# 排序拖拽贴近滚动区上下边缘时自动滚动
	if _sort_drag != null and _sort_drag.active:
		_sort_auto_scroll(delta)


func _cover_paths() -> Array:
	var paths: Array = []
	for id in ContentDB.default_order():
		var cover := str(ContentDB.game(id).get("cover", ""))
		if not cover.is_empty():
			paths.append(cover)
	return paths


func _on_resize() -> void:
	if card_grid != null and is_instance_valid(card_grid):
		card_grid.columns = _columns()


func _columns() -> int:
	return int(PlaygroundUI.layout_metrics(get_viewport_rect().size).columns)


func _rebuild_lobby() -> void:
	_cancel_sort_drag()
	if is_instance_valid(lobby_root):
		lobby_root.queue_free()
	lobby_root = Control.new()
	lobby_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(lobby_root)
	lobby_root.add_child(PlaygroundUI.background(Color("#dcefd8")))
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
		card.help_requested.connect(_show_game_help)
		card.move_requested.connect(_move_game)
		card.sort_drag_started.connect(_on_card_sort_started)
		card.sort_drag_moved.connect(_on_card_sort_moved)
		card.sort_drag_ended.connect(_on_card_sort_ended)
		card_grid.add_child(card)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.add_child(PlaygroundUI.label("🌱 每个游戏都会实时自动保存，切后台也会补存。", 12, PlaygroundUI.INK_SOFT, 500))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	footer.add_child(PlaygroundUI.button("👨‍👩‍👧 管理儿童档案", Color("#167d74"), _show_profile_manager, "ghost"))
	page.add_child(footer)
	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size.y = 8
	page.add_child(bottom_spacer)
	AudioFX.start_music("lobby")
	PlaygroundUI.fade_in(lobby_root, 0.18, 0.0)
	if sorting:
		show_toast("按住任意游戏卡拖到新位置")


func _lobby_header() -> Control:
	var metrics := PlaygroundUI.layout_metrics(get_viewport_rect().size)
	var compact := bool(metrics.compact_cards)
	var panel := PlaygroundUI.panel(Color(1, 1, 1, 0.72), 24, Color(0, 0, 0, 0.06), 1)
	panel.custom_minimum_size.y = 68 if compact else 74
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var mark := PlaygroundUI.panel(Color("#ffd56d"), 20, Color("#dca42c"), 2)
	mark.custom_minimum_size = Vector2(58, 58)
	var emoji := PlaygroundUI.label("🎡", 32, Color("#7c5411"), 700)
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_child(emoji)
	row.add_child(mark)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	brand.add_child(PlaygroundUI.label("童心游乐场", 24 if compact else 27, PlaygroundUI.INK, 700))
	if not compact:
		brand.add_child(PlaygroundUI.label("一家人一起玩的本地益智游戏", 12, PlaygroundUI.INK_SOFT, 500))
	row.add_child(brand)
	var greeting := PlaygroundUI.button(_greeting(), Color("#dca42c"), _show_continue_dialog, "soft")
	greeting.custom_minimum_size = Vector2(142 if compact else 300, 48)
	if compact:
		greeting.text = "▶ 继续游戏" if not SaveStore.resumable_sessions().is_empty() else "今天玩什么"
	row.add_child(greeting)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 7)
	for profile in SaveStore.profiles().slice(0, 2 if compact else 4):
		profile_row.add_child(_profile_chip(profile))
	row.add_child(profile_row)
	row.add_child(PlaygroundUI.button("＋", Color("#167d74"), _show_profile_manager, "soft"))
	if not _pending_update.is_empty():
		row.add_child(PlaygroundUI.button("⬆ 更新", Color("#c05b8f"), _show_update_dialog, "primary"))
	row.add_child(PlaygroundUI.icon_button("🔊", Color("#167d74"), _show_settings, "声音设置"))
	return panel


func _greeting() -> String:
	if not SaveStore.resumable_sessions().is_empty():
		return "▶ 点这里继续上次游戏"
	return "🌤️ 今天想玩哪一关？"


func _profile_chip(profile: Dictionary) -> Control:
	var tint := PlaygroundUI.color(str(profile.get("color", "#d56c29")))
	var chip := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.86), 18, PlaygroundUI.mix(tint, Color.WHITE, 0.45), 2)
	chip.custom_minimum_size = Vector2(122, 52)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.add_child(PlaygroundUI.label(str(profile.get("avatar", "🦊")), 26, tint, 700))
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
	title.add_child(PlaygroundUI.label("🎪 今天玩什么？", 31, PlaygroundUI.INK, 700))
	title.add_child(PlaygroundUI.label("游戏和练习各自有独立风格，卡片顺序可以拖动调整", 13, PlaygroundUI.INK_SOFT, 500))
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(PlaygroundUI.button("🎡 随机游戏", Color("#c05b8f"), _show_random_game, "soft"))
	row.add_child(PlaygroundUI.button("✓ 完成排序" if sorting else "✋ 拖动排序", Color("#167d74"), func():
		sorting = not sorting
		AudioFX.play("select")
		_rebuild_lobby()
	, "primary" if sorting else "ghost"))
	return row


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
		_show_profile_manager()
		return
	var tint := PlaygroundUI.color(str(meta.accent))
	if chosen_mode.is_empty():
		var menu := VBoxContainer.new()
		menu.add_theme_constant_override("separation", 14)
		for entry in SaveStore.resumable_sessions():
			if str(entry.gameId) == game_id:
				menu.add_child(PlaygroundUI.button("继续 · " + str(entry.get("note", "上次游戏")), tint, func(): _close_top_modal(); _resume_entry(entry), "soft"))
		for entry in ContentDB.modes(game_id):
			var button := PlaygroundUI.button(str(entry.name) + "  →\n" + str(entry.get("description","")), tint, func(): _close_top_modal(); _open_game_picker(game_id, str(entry.id)), "soft")
			button.custom_minimum_size.y = 82
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			menu.add_child(button)
		_open_modal(str(meta.title), menu, [{"text":"关闭","kind":"ghost","callback":func(): _close_top_modal()}], "今天想怎么玩？")
		return
	_launch_modes[game_id] = chosen_mode
	var definition := ContentDB.mode(game_id,chosen_mode)
	var minimum := int(definition.player_range[0])
	var maximum := int(definition.player_range[1])
	var selected := SaveStore.selected_profiles(game_id, minimum, maximum)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.add_child(PlaygroundUI.label("选 %s 位小朋友" % minimum if minimum == maximum else "选 %s–%s 位小朋友" % [minimum, maximum], 20, PlaygroundUI.INK_SOFT, 700))
	var choice_row := HFlowContainer.new()
	choice_row.add_theme_constant_override("h_separation", 12)
	choice_row.add_theme_constant_override("v_separation", 12)
	var chosen_ids: Array = selected.map(func(player): return str(player.id)).slice(0,maximum)
	var difficulty_select := OptionButton.new()
	difficulty_select.custom_minimum_size = Vector2(230, 50)
	difficulty_select.add_theme_font_override("font", PlaygroundUI.font())
	difficulty_select.add_theme_font_size_override("font_size", 17)
	var difficulty_values := ["auto", "easy", "normal", "challenge"]
	for value in difficulty_values:
		difficulty_select.add_item(GameTuning.label(str(value)))
		difficulty_select.set_item_metadata(difficulty_select.item_count - 1, value)
	var preference_profile := str(chosen_ids[0]) if not chosen_ids.is_empty() else (str(SaveStore.profiles()[0].id) if not SaveStore.profiles().is_empty() else "")
	var current_preference := SaveStore.difficulty(game_id, preference_profile)
	difficulty_select.select(maxi(0, difficulty_values.find(current_preference)))
	if not GameTuning.supports(game_id):
		difficulty_select.disabled = true
		difficulty_select.select(0)
	content.add_child(PlaygroundUI.label("难度", 15, PlaygroundUI.INK_SOFT, 700))
	content.add_child(difficulty_select)
	var start_button := PlaygroundUI.button("开始 " + str(definition.name) + " →", tint, _start_from_picker.bind(game_id, chosen_ids, minimum, maximum, difficulty_select))
	start_button.disabled = chosen_ids.size() < minimum
	for profile in SaveStore.profiles():
		var button := PlaygroundUI.button("%s  %s · %s 岁" % [profile.avatar,profile.name,profile.age], PlaygroundUI.color(str(profile.color)), _toggle_picker_profile.bind(str(profile.id),chosen_ids,maximum,choice_row,minimum,start_button), "soft")
		button.custom_minimum_size = Vector2(210,64)
		button.set_meta("profile_id",str(profile.id))
		choice_row.add_child(button)
	content.add_child(choice_row)
	update_select_buttons(choice_row,chosen_ids,tint)
	_open_modal(str(meta.title) + " · " + str(definition.name), content, [
		{"text":"取消","kind":"ghost","callback":func(): _close_top_modal()},
			{"text":"开始游戏 →","kind":"primary","callback":_start_from_picker.bind(game_id,chosen_ids,minimum,maximum,difficulty_select)},
	], "每个孩子都有自己的进度")


func _start_from_picker(game_id: String, chosen_ids: Array, minimum: int, maximum: int, difficulty_select: OptionButton) -> void:
	if chosen_ids.size() < minimum:
		show_toast("请先选好本局的小朋友")
		return
	var preference := "auto"
	if not difficulty_select.disabled and difficulty_select.selected >= 0:
		preference = str(difficulty_select.get_item_metadata(difficulty_select.selected))
	_confirm_game_start(game_id, chosen_ids, minimum, maximum, preference)


func _toggle_picker_profile(
	profile_id: String,
	chosen_ids: Array,
	maximum: int,
	choice_row: Control,
	minimum: int,
	start_button: Button
) -> void:
	if profile_id in chosen_ids:
		chosen_ids.erase(profile_id)
	elif chosen_ids.size() < maximum:
		chosen_ids.append(profile_id)
	AudioFX.play("select")
	update_select_buttons(choice_row, chosen_ids, Color.WHITE)
	start_button.disabled = chosen_ids.size() < minimum


func _confirm_game_start(game_id: String, chosen_ids: Array, minimum: int, maximum: int, difficulty_pref: String = "auto") -> void:
	if chosen_ids.size() < minimum:
		return
	_close_top_modal()
	SaveStore.select_profiles(game_id, chosen_ids)
	_start_game(game_id, SaveStore.selected_profiles(game_id, minimum, maximum), "", difficulty_pref)


func update_select_buttons(container: Control, chosen_ids: Array, accent: Color) -> void:
	for button in container.get_children():
		var choice := button as Button
		if choice == null:
			continue
		var id := str(choice.get_meta("profile_id", ""))
		var selected := id in chosen_ids
		choice.modulate = Color.WHITE if selected else Color(1, 1, 1, 0.72)
		choice.text = ("✓ " if selected else "") + choice.text.trim_prefix("✓ ")


func _start_game(game_id: String, selected: Array, chosen_mode: String = "", difficulty_pref: String = "auto") -> void:
	if selected.is_empty() or not GAME_SCRIPTS.has(game_id):
		return
	var target_mode := chosen_mode if not chosen_mode.is_empty() else str(_launch_modes.get(game_id,"classic"))
	var definition := ContentDB.mode(game_id,target_mode)
	if selected.size() < int(definition.player_range[0]) or selected.size() > int(definition.player_range[1]):
		_open_game_picker(game_id,target_mode)
		return
	var meta := ContentDB.game(game_id).duplicate(true)
	meta.modeId = target_mode
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
		_start_game(game_id,selected,target_mode,difficulty_pref)
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
		_start_game(str(entry.gameId),selected,str(entry.get("modeId","classic")))


func _continue_saved_game(game_id: String) -> void:
	_close_top_modal()
	_open_game_picker(game_id)


func _show_random_game() -> void:
	var games := ContentDB.ordered_games(_game_order)
	if games.is_empty():
		return
	var result: Dictionary = games.pick_random()
	_random_token += 1
	var token := _random_token
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 12)
	var icon := PlaygroundUI.label("🎡", 74, PlaygroundUI.color(str(result.accent)), 700)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(icon)
	var title := PlaygroundUI.label("转盘转动中…", 32, PlaygroundUI.INK, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var subtitle := PlaygroundUI.label("看看今天停在哪一款", 16, PlaygroundUI.INK_SOFT, 500)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)
	AudioFX.play("select")
	var random_layer := _open_modal("🎡 随机游戏", content, [
		{"text": "再转一次", "kind": "soft", "callback": func(): _close_top_modal(); _show_random_game()},
		{"text": "就玩这个", "kind": "primary", "callback": _play_random_result.bind(str(result.id))},
	], "今天玩什么？", false)
	for tick in 14:
		if not is_instance_valid(title):
			return
		var preview: Dictionary = games.pick_random()
		title.text = str(preview.title)
		icon.text = str(preview.icon)
		AudioFX.play("tap")
		await get_tree().create_timer(0.07 + tick * 0.006).timeout
	if is_instance_valid(title):
		title.text = str(result.title)
		icon.text = str(result.icon)
		subtitle.text = "转盘停在这里，马上出发！"
		AudioFX.play("win")
	await get_tree().create_timer(0.75).timeout
	if token == _random_token and is_instance_valid(random_layer) and random_layer in modal_stack:
		_close_top_modal()
		_play_random_result(str(result.id))


func _play_random_result(game_id: String) -> void:
	_close_top_modal()
	var meta := ContentDB.game(game_id)
	if meta.is_empty():
		return
	var modes: Array = ContentDB.modes(game_id)
	if modes.is_empty():
		return
	var definition: Dictionary = modes[0]
	var minimum := int(definition.player_range[0])
	var maximum := int(definition.player_range[1])
	var selected := SaveStore.selected_profiles(game_id,minimum,maximum)
	SaveStore.select_profiles(game_id,selected.map(func(player): return str(player.id)))
	if selected.size() >= minimum:
		_start_game(game_id,selected,str(definition.id))
	else:
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
		row.add_child(PlaygroundUI.label(str(profile.avatar), 32, tint, 700))
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
		actions.append({"text": "＋ 新建档案", "kind": "primary", "callback": func(): _close_top_modal(); _show_profile_form({})})
	actions.append({"text": "关闭", "kind": "soft", "callback": func(): _close_top_modal()})
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
	head.add_child(PlaygroundUI.label(str(profile.avatar), 36, tint, 700))
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
		content.add_child(PlaygroundUI.label("📚 故事听读足迹：读过 %s 篇 · 收藏 %s 篇\n这些是听读记录，不作为语言能力评分；可以请孩子讲讲最喜欢的片段。" % [heard.size(), favorites.size()], 16, PlaygroundUI.INK_SOFT, 500, true))
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
	intro.add_child(PlaygroundUI.label("🌟", 26, Color("#b69014"), 700))
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
		avatar_row.add_child(PlaygroundUI.choice_button(
			avatar,
			brand,
			avatar_group,
			avatar,
			avatar == starting_avatar,
			Vector2(58, 54),
			27
		))
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
		_close_top_modal()
		_rebuild_lobby()
		AudioFX.play("confirm")
	name_edit.text_submitted.connect(func(_text: String): save_profile.call())
	_open_modal(
		"编辑儿童档案" if not existing.is_empty() else "新建儿童档案",
		content,
		[
			{"text": "取消", "kind": "ghost", "callback": func(): _close_top_modal()},
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
	var labels := {"soundOn": "🔊 音效", "musicOn": "🎵 背景音乐", "speechOn": "🗣️ 中文朗读", "hapticsOn": "📳 触感反馈"}
	for key in ["soundOn", "musicOn", "speechOn", "hapticsOn"]:
		var state := "开" if bool(settings.get(key, true)) else "关"
		content.add_child(PlaygroundUI.button("%s：%s" % [labels[key], state], Color("#167d74"), _toggle_setting.bind(key), "soft"))
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
		show_toast("发现新版本，可在顶部点击“更新”")
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
