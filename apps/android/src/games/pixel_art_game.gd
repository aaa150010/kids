class_name NativePixelArtGame
extends NativeGameScreen

const RULES = preload("res://src/games/pixel_art_rules.gd")
const BOARD = preload("res://src/ui/pixel_art_board.gd")
const CONTENT_PATH := "res://content/pixel_art.json"
const FALLBACK_TITLE := "像素小画家"
const FALLBACK_ACCENT := "#5c4a9a"
const FALLBACK_SOFT := "#ebe7f8"
const BAND_LABELS := {
	"easy": "小方画",
	"normal": "细致画",
	"challenge": "大画布",
}
const BAND_AGES := {
	"easy": "推荐 4–6 岁",
	"normal": "推荐 7–9 岁",
	"challenge": "推荐 10–12 岁",
}

var engine = RULES.new()
var board = null
var board_scroll: ScrollContainer
var game_header: Control
var status: Label
var game_tools: Control
var undo_button: Button
var eraser_button: Button
var color_buttons: Array[Button] = []
var view := "map"
var soft_accent := Color(FALLBACK_SOFT)
var _levels_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _erase_mode := false


func _ready() -> void:
	if game_id.is_empty():
		game_id = "pixel_art"
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	accent = PlaygroundUI.color(str(game_meta.get("accent", FALLBACK_ACCENT)))
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	if mode_id not in ["adventure", "classic"]:
		mode_id = "adventure" if players.size() <= 1 else "classic"
	_load_catalog()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	pause_changed.connect(_on_pause_changed)
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	if had_stored:
		stored.modeId = mode_id
		if engine.restore(stored):
			players = engine.state.players.duplicate(true)
			level_id = int(engine.state.get("levelId", 1))
			view = str(engine.state.get("view", "board"))
			if str(engine.state.get("phase", "")) == "finished" and not bool(stored.get("resume", true)):
				_show_map()
				return
			if view == "map":
				_show_map()
				return
			_build_board()
			_refresh()
			if str(engine.state.get("phase", "")) == "finished":
				_show_result()
			return
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
	if recovery_level >= 1 and not _find_level(recovery_level).is_empty():
		if _start_level(recovery_level, false):
			show_toast("上次的画稿记录不完整，已从第 %s 张开头重新铺纸。" % recovery_level, 3.2)
			return
	_show_map()


func _load_catalog() -> void:
	_catalog_issues.clear()
	_levels_cache.clear()
	var parsed: Variant = null
	if FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 pixel_art.json 或内容格式不正确")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	if not bool(validation.get("ok", false)):
		for issue in _catalog_issues:
			push_warning("像素小画家内容：" + issue)
		return
	_levels_cache = validation.get("validLevels", []).duplicate(true)


func _mode_levels() -> Array:
	var result: Array = []
	for raw in _levels_cache:
		if raw is Dictionary and str(raw.get("mode", "")) == mode_id:
			result.append(raw)
	result.sort_custom(func(first: Dictionary, second: Dictionary):
		return int(first.get("levelNumber", 0)) < int(second.get("levelNumber", 0))
	)
	return result


func _find_level(number: int) -> Dictionary:
	for raw in _levels_cache:
		if raw is Dictionary and str(raw.get("mode", "")) == mode_id and int(raw.get("levelNumber", 0)) == number:
			return raw.duplicate(true)
	return {}


func _unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _stars_for(number: int) -> int:
	var stars := 0
	for player in players:
		var learning := SaveStore.learning(str(player.id), game_id, mode_id)
		stars = maxi(stars, int(learning.get("stars", {}).get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_level(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and str(engine.state.get("phase", "")) == "playing"
		and str(engine.state.get("modeId", "")) == mode_id
		and int(engine.state.get("levelId", 0)) == number
	)


func _show_map() -> void:
	Speech.stop()
	_on_pause_changed(false)
	view = "map"
	_result_visible = false
	_erase_mode = false
	PlaygroundUI.clear(content_root)
	board = null
	board_scroll = null
	color_buttons.clear()
	var levels := _mode_levels()
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("今天想画哪一张小画？", 30, accent, 700, true))
	copy.add_child(PlaygroundUI.label(_map_subtitle(), 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("一起共画 · 不计输赢" if mode_id == "classic" else "单人画册", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 1)
		warning.add_child(PlaygroundUI.label("像素画册有 %s 处需要检查，只显示完整可玩的画稿。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.30), 24, PlaygroundUI.TOOL_LINE, 2)
		var empty_box := VBoxContainer.new()
		empty_box.add_theme_constant_override("separation", 10)
		empty_box.add_child(PlaygroundUI.label("画纸还在准备中", 24, accent, 700, true))
		empty_box.add_child(PlaygroundUI.label("色号和像素格还没有装进这台平板，请稍后再来看看。", 18, PlaygroundUI.INK_SOFT, 500, true))
		empty.add_child(empty_box)
		content_root.add_child(empty)
		return
	var entries: Array = []
	var active_level := level_id if _can_resume_level(level_id) else -1
	for raw in levels:
		var number := int(raw.get("levelNumber", 0))
		if number <= 0:
			continue
		entries.append({
			"id": number,
			"title": str(raw.get("title", "像素画")),
			"subtitle": "%s · %s · %s×%s · %s 色" % [
				str(BAND_LABELS.get(str(raw.get("band", "")), "画稿")),
				str(BAND_AGES.get(str(raw.get("band", "")), "")),
				int(raw.get("width", 8)),
				int(raw.get("height", 8)),
				(raw.get("palette", []) as Array).size(),
			],
			"locked": not _unlocked(number),
			"stars": _stars_for(number),
			"in_progress": number == active_level,
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"title": "像素画册",
		"subtitle": "每一格都写着目标色号；点颜色再点格子，画错了可以重涂或擦掉。",
		"accent": accent,
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择画稿")


func _map_subtitle() -> String:
	if mode_id == "classic":
		if players.size() >= 2:
			return "%s 和 %s 轮流填一格，共用画布、色板和提示次数。" % [
				str(players[0].get("name", "小朋友")),
				str(players[1].get("name", "小伙伴")),
			]
		return "两个人轮流填一格，共用同一张画布。"
	var name := str(players[0].get("name", "小画家")) if not players.is_empty() else "小画家"
	return "%s 一个人按色号涂，缩放和局部提示都会帮上忙。" % name


func _choose_level(number: int) -> void:
	if not _unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一张画，再来画这一张。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		engine.state.view = view
		_build_board()
		_refresh()
		_save("继续涂色")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_level(number, true))
		return
	_start_level(number, true)


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来画画。")
		return false
	var entry := _find_level(number)
	if entry.is_empty():
		show_toast("第 %s 张画稿还没有准备好，编号不会被替换。" % number, 2.8)
		return false
	level_id = number
	_result_visible = false
	_erase_mode = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"level": entry,
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		var message := str(engine.state.get("loadError", "这张像素画的内容不完整。"))
		engine.state = {}
		show_toast(message + " 请回画册选另一张。", 3.0)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始画画")
	if announce:
		Speech.stop_owner("pixel-result")
		Speech.stop_owner("pixel-feedback")
		Speech.speak(str(entry.get("narration", "先看格子上的色号，再选颜色一格一格涂满。")), "pixel-narration")
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	color_buttons.clear()
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 10)
	var title_box: VBoxContainer
	if mode_id == "classic" and players.size() >= 2:
		game_header.add_child(_player_badge(0))
		var middle := CenterContainer.new()
		middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box = VBoxContainer.new()
		title_box.add_theme_constant_override("separation", 1)
		title_box.add_child(PlaygroundUI.label("第 %s 张 · %s" % [level_id, engine.state.get("levelTitle", "像素画")], 20, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("轮流填一格，共用画布，不比较输赢", 13, PlaygroundUI.INK_SOFT, 500, true))
		middle.add_child(title_box)
		game_header.add_child(middle)
		game_header.add_child(_player_badge(1))
	else:
		title_box = VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.add_theme_constant_override("separation", 1)
		title_box.add_child(PlaygroundUI.label("第 %s 张 · %s" % [level_id, engine.state.get("levelTitle", "像素画")], 25, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("选色号，再点格子；错了可以换颜色重涂或擦掉。", 16, PlaygroundUI.INK_SOFT, 500, true))
		game_header.add_child(title_box)
		game_header.add_child(PlaygroundUI.chip(str(BAND_LABELS.get(engine.state.get("levelBand", "easy"), "画稿")), accent))
	game_header.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft", 17))
	content_root.add_child(game_header)

	var stage := HBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 12)
	content_root.add_child(stage)

	var paper := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28), 22, PlaygroundUI.mix(accent, Color.WHITE, 0.52), 2)
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(paper)
	board_scroll = SmoothScrollContainer.create() as ScrollContainer
	board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	board_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	paper.add_child(board_scroll)
	board = BOARD.new()
	board.configure(engine.level_definition, accent, soft_accent)
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	board.cell_pressed.connect(_cell_pressed)
	board_scroll.add_child(board)

	var tools = VBoxContainer.new()
	tools.custom_minimum_size.x = 270
	tools.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools.add_theme_constant_override("separation", 8)
	stage.add_child(tools)
	tools.add_child(PlaygroundUI.label("本张画色板", 20, accent, 700, true))
	var palette_grid := HFlowContainer.new()
	palette_grid.add_theme_constant_override("h_separation", 7)
	palette_grid.add_theme_constant_override("v_separation", 7)
	tools.add_child(palette_grid)
	var color_group := ButtonGroup.new()
	var palette: Array = engine.palette()
	for index in palette.size():
		var number := index + 1
		var name := engine.color_name(number)
		var button := PlaygroundUI.choice_button("%s\n色号 %s" % [name, number], Color(str(palette[index])), color_group, number, number == int(engine.state.get("selectedColor", 1)), Vector2(118, 58), 14)
		button.pressed.connect(_select_color.bind(number))
		palette_grid.add_child(button)
		color_buttons.append(button)
	tools.add_child(PlaygroundUI.separator(PlaygroundUI.TOOL_LINE))
	eraser_button = PlaygroundUI.semantic_icon_button("erase", "橡皮擦：关", accent, _toggle_eraser, "soft", 17)
	eraser_button.custom_minimum_size = Vector2(0, 50)
	tools.add_child(eraser_button)
	var hint_button := PlaygroundUI.semantic_icon_button("hint", "局部提示", accent, _hint, "soft", 17)
	hint_button.custom_minimum_size = Vector2(0, 50)
	tools.add_child(hint_button)
	undo_button = PlaygroundUI.semantic_icon_button("undo", "撤销一下", accent, _undo, "soft", 17)
	undo_button.custom_minimum_size = Vector2(0, 50)
	tools.add_child(undo_button)
	tools.add_child(PlaygroundUI.label("缩放画布", 16, PlaygroundUI.INK_SOFT, 600))
	var zoom_row := HFlowContainer.new()
	zoom_row.add_theme_constant_override("h_separation", 5)
	zoom_row.add_theme_constant_override("v_separation", 5)
	for zoom_value in RULES.ZOOM_LEVELS:
		var zoom_button := PlaygroundUI.button(("原大" if is_equal_approx(float(zoom_value), 1.0) else "%s×" % zoom_value), accent, _zoom.bind(float(zoom_value)), "ghost")
		zoom_button.custom_minimum_size = Vector2(56, 46)
		zoom_row.add_child(zoom_button)
	tools.add_child(zoom_row)

	status = PlaygroundUI.label("", 17, accent, 600, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.custom_minimum_size = Vector2(0, 34)
	content_root.add_child(status)

	game_tools = HFlowContainer.new()
	game_tools.alignment = FlowContainer.ALIGNMENT_CENTER
	game_tools.add_theme_constant_override("h_separation", 10)
	game_tools.add_theme_constant_override("v_separation", 5)
	var restart_button := PlaygroundUI.semantic_icon_button("restart", "重画这张", accent, _confirm_restart, "ghost", 17)
	restart_button.custom_minimum_size = Vector2(150, 46)
	game_tools.add_child(restart_button)
	var map_button := PlaygroundUI.semantic_icon_button("game", "像素画册", accent, _show_map, "ghost", 17)
	map_button.custom_minimum_size = Vector2(150, 46)
	game_tools.add_child(map_button)
	content_root.add_child(game_tools)
	board.set_state(engine.state)
	board.set_tool_mode("paint")
	board.set_interaction_enabled(str(engine.state.get("phase", "")) == "playing")
	_on_immersive_changed(immersive)


func _player_badge(index: int) -> Control:
	var player: Dictionary = players[index] if index < players.size() else {}
	var tint := PlaygroundUI.color(str(player.get("color", accent.to_html(false))))
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.88), 16, PlaygroundUI.mix(tint, Color.WHITE, 0.44), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.add_child(ArtLibrary.profile_picture(player, Vector2(32, 34)))
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	copy.add_child(PlaygroundUI.label(str(player.get("name", "小朋友")), 15, PlaygroundUI.INK, 700, true))
	var current := engine.current_player_index() == index if engine.is_cooperative() else false
	copy.add_child(PlaygroundUI.label("轮到这一位" if current else "一起共画", 11, PlaygroundUI.INK_SOFT, 500))
	row.add_child(copy)
	panel.add_child(row)
	return panel


func _on_immersive_changed(value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.visible = not value
	if status != null and is_instance_valid(status):
		status.show()
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.show()


func _on_pause_changed(paused_value: bool) -> void:
	if paused_value and board != null and is_instance_valid(board):
		board.cancel_gesture()


func _status_text() -> String:
	if engine.state.is_empty():
		return "先选一张画稿。"
	if str(engine.state.get("phase", "")) == "finished":
		return "整张像素画都涂对啦。"
	var prefix := ""
	if engine.is_cooperative():
		var index := engine.current_player_index()
		var name := str(players[index].get("name", "小朋友")) if index < players.size() else "小朋友"
		prefix = "轮到 %s · " % name
	var painted: Array = engine.state.get("painted", [])
	var target: Array = engine.state.get("target", [])
	var done := 0
	for index in mini(painted.size(), target.size()):
		if int(painted[index]) == int(target[index]):
			done += 1
	var text := "%s正确 %s / %s · 涂色 %s · 错色 %s · 提示 %s · 缩放 %s×" % [
		prefix,
		done,
		target.size(),
		int(engine.state.get("moves", 0)),
		int(engine.state.get("errors", 0)),
		int(engine.state.get("hints", 0)),
		engine.state.get("zoom", 1.0),
	]
	if _erase_mode:
		text += " · 橡皮擦已打开"
	elif not engine.state.get("hintCells", []).is_empty():
		text += " · 亮起的小区域是提示"
	return text


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	board.set_state(engine.state)
	board.set_tool_mode("erase" if _erase_mode else "paint")
	board.set_interaction_enabled(str(engine.state.get("phase", "")) == "playing")
	if eraser_button != null and is_instance_valid(eraser_button):
		eraser_button.text = "橡皮擦：%s" % ("开" if _erase_mode else "关")
		eraser_button.disabled = str(engine.state.get("phase", "")) != "playing"
	if undo_button != null and is_instance_valid(undo_button):
		undo_button.disabled = engine.state.get("history", []).is_empty() or str(engine.state.get("phase", "")) != "playing"
	for index in color_buttons.size():
		if is_instance_valid(color_buttons[index]) and engine.state.get("phase", "") != "finished":
			color_buttons[index].set_pressed_no_signal(index + 1 == int(engine.state.get("selectedColor", 1)))
			color_buttons[index].disabled = _erase_mode
	if status != null and is_instance_valid(status):
		status.text = _status_text()
	if str(engine.state.get("phase", "")) == "finished" and not _result_visible:
		call_deferred("_show_result")


func _cell_pressed(index: int) -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	if _erase_mode:
		_erase_cell(index)
		return
	var result: Dictionary = engine.handle_input({"type": "paint", "index": index})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		FeedbackKit.haptic(6)
		show_toast(str(result.get("message", "这一格现在不能涂")))
		return
	if str(result.get("event", "")) == "finished":
		SfxMap.play(&"success")
		FeedbackKit.haptic(14)
		_save("整张像素画涂好", false)
	elif bool(result.get("correct", false)):
		SfxMap.play(&"move")
		FeedbackKit.haptic(3)
		_save("填对一格色号")
	else:
		SfxMap.play(&"error")
		FeedbackKit.haptic(7)
		var message := str(result.get("message", "颜色对不上色号。"))
		show_toast(message, 2.5)
		Speech.speak(message, "pixel-feedback")
		_save("涂错一格，保留原色供重涂")
	_refresh()
	if str(result.get("event", "")) != "finished" and immersive and engine.is_cooperative() and players.size() >= 2:
		var next_index := engine.current_player_index()
		var next_name := str(players[next_index].get("name", "小朋友"))
		show_toast("轮到 %s 填一格。" % next_name, 1.1)
	if str(result.get("event", "")) == "finished":
		_show_result()


func _erase_cell(index: int) -> void:
	var result: Dictionary = engine.handle_input({"type": "erase", "index": index})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "这一格不用擦")))
		return
	SfxMap.play(&"erase")
	FeedbackKit.haptic(4)
	_save("擦掉一格颜色")
	_refresh()
	if immersive and engine.is_cooperative() and players.size() >= 2:
		var next_index := engine.current_player_index()
		var next_name := str(players[next_index].get("name", "小朋友"))
		show_toast("轮到 %s 填一格。" % next_name, 1.1)


func _select_color(index: int) -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "select_color", "color": index})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "这个颜色不能用")))
		return
	_erase_mode = false
	SfxMap.play(&"select")
	_save("选择%s" % str(result.get("name", "颜色")))
	_refresh()


func _toggle_eraser() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	_erase_mode = not _erase_mode
	SfxMap.play(&"select")
	board.set_tool_mode("erase" if _erase_mode else "paint")
	_refresh()
	show_toast("橡皮擦已打开，点格子擦掉颜色" if _erase_mode else "回到颜色画笔", 1.8)


func _zoom(value: float) -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "zoom", "zoom": value})
	if not bool(result.get("ok", false)):
		return
	board.set_zoom(float(result.get("zoom", value)))
	if board_scroll != null and is_instance_valid(board_scroll):
		board_scroll.scroll_horizontal = maxi(0, int(board.custom_minimum_size.x * 0.5 - board_scroll.size.x * 0.5))
		board_scroll.scroll_vertical = maxi(0, int(board.custom_minimum_size.y * 0.5 - board_scroll.size.y * 0.5))
	SfxMap.play(&"tap")
	_save("调整画布缩放")
	_refresh()


func _hint() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "现在没有提示")))
		return
	AudioFX.play("whoosh")
	_save("查看局部色号提示")
	_refresh()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icon := ArtLibrary.semantic_picture("search", "ui", Vector2(58, 58))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(icon)
	var message := str(result.get("message", "亮起的小区域会告诉你要用的色号。"))
	var message_label := PlaygroundUI.label(message, 21, PlaygroundUI.INK, 600, true)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(message_label)
	body.add_child(PlaygroundUI.label("提示不会直接替你涂色；亮框会保留到你下一次落笔。", 15, PlaygroundUI.INK_SOFT, 500, true))
	Speech.speak(message, "pixel-hint")
	open_modal("局部色号提示", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(message, "pixel-hint")},
		{"text": "继续画", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("pixel-hint"); _close_top_modal()},
	], "第 %s 次提示" % int(result.get("hints", 0)))


func _undo() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "undo"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "现在没有可以撤销的一下")))
		return
	SfxMap.play(&"deselect")
	FeedbackKit.haptic(5)
	_save("撤销上一格")
	_refresh()
	show_toast("已经退回上一下，再慢慢画。", 1.4)


func _confirm_restart() -> void:
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一张画稿，再重新开始。")
		return
	var copy := PlaygroundUI.label(
		"这张画会回到空白画纸，涂色、错色、提示和撤销次数都会重新计算。其他画稿和其他进度会保留。",
		19,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	open_modal("重画这一张？", copy, [
		{"text": "继续画", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新铺纸", "icon": "restart", "kind": "primary", "callback": _restart_level},
	], "像素小画家")


func _restart_level() -> void:
	var was_paused := paused
	_suppress_resume_on_close = was_paused
	_close_all_game_dialogs()
	if was_paused:
		paused = false
		_pause_root_layer = null
		MotionKit.set_paused_tree(self, false)
		pause_changed.emit(false)
	_suppress_resume_on_close = false
	var result: Dictionary = engine.handle_input({"type": "restart"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "这张画暂时不能重新开始")))
		return
	_result_visible = false
	_erase_mode = false
	view = "board"
	SfxMap.play(&"drop")
	FeedbackKit.haptic(8)
	_refresh()
	_save("重新铺好这张画纸")
	Speech.speak("画纸恢复空白，再按色号慢慢涂。", "pixel-feedback")


func _extra_pause_actions() -> Array:
	if view != "board":
		return []
	return [{
		"text": "像素画册",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func show_help() -> void:
	if not paused:
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"先看画布格子里的目标色号，再在色板选同色号。",
		"点格子涂色；涂错可以换正确颜色重涂，也可以打开橡皮擦点格子擦掉。",
		"局部提示会圈出下一块 3×3 小区域，显示要用的色号；缩放只改变观察大小。",
		"每个格子都和色号一致就完成。完成时会收起格线和色号，展示整张作品。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(["practice", "erase", "search", "star"][index], "ui", Vector2(42, 42)))
		var copy_label := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy_label)
		body.add_child(row)
	var spoken := "像素小画家玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("game-help"); _close_top_modal()},
	], "看色号，选颜色")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先选一种颜色，格子上的数字就是这一格要用的色号。",
		"一格一格涂满；错了换正确颜色重涂或打开橡皮擦，提示和缩放不会清空画布。",
		"全部格子都对就完成；画作会收起格线展示，下一次打开仍会回到这幅画。",
	]
	_lesson_icons = ["practice", "erase", "star"]
	_show_lesson_page(0)


func _show_rules() -> void:
	var lines := [
		"每张画稿都有固定尺寸、原创色板和每格目标色号，没有倒计时。",
		"选择色板颜色后点格子；点错颜色会保留并标出错色，可以换正确颜色重涂或擦除。",
		"局部提示只圈出下一块小区域的色号，不代替填色；缩放范围为 0.75× 到 2×。",
		"单人至少一星记赢；双人每次成功涂色或擦除一格后换手，只记一起玩过。",
		"三星：一次全对，不用提示、不撤销；二星允许少量错色和辅助。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var copy_label := PlaygroundUI.label(str(lines[index]), 18, PlaygroundUI.INK_SOFT, 500, true)
		copy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy_label)
		body.add_child(row)
	var spoken := "像素小画家规则。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "pixel-rules")
	open_modal("像素小画家规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.speak(spoken, "pixel-rules")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "按色号画，不靠猜")


func show_game_rules() -> void:
	_show_rules()


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var summary: Dictionary = engine.result()
	var stars := int(summary.get("stars", engine.stars()))
	var cells := int(engine.level_definition.get("width", 0)) * int(engine.level_definition.get("height", 0))
	var session_key := str(engine.state.get("sessionId", "pixel_art"))
	var all_recorded := true
	if mode_id == "adventure":
		if players.is_empty():
			return false
		var player_id := str(players[0].id)
		SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		if not SaveStore.record_outcome(
			player_id,
			game_id,
			"win",
			stars,
			cells,
			cells,
			{"logic": {"correct": cells, "answered": cells}},
			session_key
		):
			all_recorded = false
	else:
		for player in players:
			var player_id := str(player.id)
			SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
			if not SaveStore.record_outcome(
				player_id,
				game_id,
				"played",
				stars,
				cells,
				cells,
				{"logic": {"correct": cells, "answered": cells}},
				session_key
			):
				all_recorded = false
	if all_recorded:
		engine.state.reported = true
	return all_recorded


func _show_result() -> void:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return
	var summary: Dictionary = engine.result()
	if summary.is_empty():
		return
	engine.state.showcase = true
	if board != null and is_instance_valid(board):
		board.set_showcase(true)
	if _record_completion_if_needed():
		_save("完成像素画", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(70, 70))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var preview := BOARD.new()
	preview.configure(engine.level_definition, accent, soft_accent)
	preview.set_state(engine.state)
	preview.set_showcase(true)
	preview.set_interaction_enabled(false)
	preview.custom_minimum_size = Vector2(300, 300)
	var preview_center := CenterContainer.new()
	preview_center.add_child(preview)
	body.add_child(preview_center)
	var title_text := "一起画好啦！" if mode_id == "classic" else "整幅画完成啦！"
	var title := PlaygroundUI.label(title_text, 25, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "涂色 %s 下 · 标准 %s 格 · 错色 %s · 提示 %s · 撤销 %s" % [
		int(summary.get("moves", 0)),
		int(summary.get("parCells", 0)),
		int(summary.get("errors", 0)),
		int(summary.get("hints", 0)),
		int(summary.get("undos", 0)),
	]
	var stats_label := PlaygroundUI.label(stats, 17, PlaygroundUI.INK_SOFT, 500, true)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stats_label)
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 8)
	var stars := int(summary.get("stars", 0))
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(36, 36))
		star.modulate = Color.WHITE if index < stars else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var rating := "色号一格没错，画得又准又漂亮！" if stars == 3 else "整幅画完成了，下次少错几格会更顺。" if stars == 2 else "坚持涂完整幅画，已经很了不起啦。"
	var rating_label := PlaygroundUI.label(rating, 18, PlaygroundUI.INK, 600, true)
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(rating_label)
	var explanation := PlaygroundUI.label(str(engine.level_definition.get("explanation", "每一格都按色号涂好，完整图案就出现了。")), 16, PlaygroundUI.INK_SOFT, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions := [
		{"text": "像素画册", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("pixel-result"); _close_top_modal(); _show_map()},
		{"text": "再画一次", "icon": "restart", "kind": "soft", "callback": func(): Speech.stop_owner("pixel-result"); _close_top_modal(); _start_level(level_id, false)},
	]
	var next_number := level_id + 1
	if not _find_level(next_number).is_empty() and (mode_id == "classic" or _unlocked(next_number)):
		actions.append({"text": "下一张", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({
			"text": "回游戏大厅",
			"icon": "home",
			"kind": "primary",
			"callback": func():
				Speech.stop_owner("pixel-result")
				_close_all_game_dialogs()
				SaveStore.flush()
				back_requested.emit(),
		})
	open_modal("像素画完成", body, actions, SaveStore.save_status_text(), false, {"width": 760.0, "size": "L", "max_content_height": 620.0})
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := str(engine.level_definition.get("explanation", "整幅像素画都涂对啦。"))
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s轮流填色，一起画完了整幅画。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "pixel-result")


func _go_next_level() -> void:
	Speech.stop_owner("pixel-result")
	_close_top_modal()
	var next_number := level_id + 1
	if _find_level(next_number).is_empty():
		_show_map()
		return
	if mode_id == "adventure" and not _unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _save(note: String = "实时自动保存像素画", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	var phase := str(engine.state.get("phase", ""))
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and phase == "playing" and view in ["board", "map"]
	)
