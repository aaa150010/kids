class_name NativeSokobanGame
extends NativeGameScreen

const RULES = preload("res://src/games/sokoban_rules.gd")
const BOARD = preload("res://src/ui/sokoban_board.gd")
const CONTENT_PATH := "res://content/sokoban.json"
const FALLBACK_TITLE := "仓库推推乐"
const FALLBACK_ACCENT := "#8a5f3d"
const FALLBACK_SOFT := "#f2e5d7"
const BAND_LABELS := {
	"easy": "轻松仓库",
	"normal": "标准仓库",
	"challenge": "挑战仓库",
}
const BAND_AGES := {
	"easy": "推荐 4–6 岁",
	"normal": "推荐 7–9 岁",
	"challenge": "推荐 10–12 岁",
}

var engine = RULES.new()
var board = null
var game_header: Control
var status: Label
var game_tools: Control
var undo_button: Button
var view := "map"
var soft_accent := Color(FALLBACK_SOFT)
var _levels_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false


func _ready() -> void:
	if game_id.is_empty():
		game_id = "sokoban"
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
			difficulty = str(engine.state.get("difficulty", difficulty))
			level_id = int(engine.state.get("levelId", 1))
			view = str(engine.state.get("view", "board"))
			if (
				str(engine.state.get("phase", "")) == "finished"
				and not bool(stored.get("resume", true))
			):
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
	if recovery_level >= 1 and recovery_level <= _mode_levels().size():
		if _start_level(recovery_level, false):
			show_toast("上次的仓库记录不完整，已从第 %s 间开头重新整理。" % recovery_level, 3.0)
			return
	_show_map()


func _load_catalog() -> void:
	_catalog_issues.clear()
	_levels_cache.clear()
	var parsed: Variant = null
	if FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 sokoban.json 或内容格式不正确")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	if not bool(validation.get("ok", false)):
		for issue in _catalog_issues:
			push_warning("仓库推推乐内容：" + issue)
		return
	var levels_value: Variant = parsed.get("levels", [])
	if levels_value is Array:
		for raw in levels_value:
			if raw is Dictionary:
				_levels_cache.append(raw.duplicate(true))
	for issue in _catalog_issues:
		push_warning("仓库推推乐内容：" + issue)


func _mode_levels() -> Array:
	var result: Array = []
	var wants_coop := mode_id == "classic"
	for raw in _levels_cache:
		if raw is Dictionary and bool(raw.get("coop", false)) == wants_coop:
			result.append(raw)
	return result


func _level(number: int = -1) -> Dictionary:
	var levels := _mode_levels()
	if levels.is_empty():
		return {}
	var index := clampi((number if number > 0 else level_id) - 1, 0, levels.size() - 1)
	var entry: Variant = levels[index]
	return entry.duplicate(true) if entry is Dictionary else {}


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
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "playing":
		return false
	if int(engine.state.get("levelId", 0)) != number:
		return false
	return true


func _show_map() -> void:
	Speech.stop()
	_on_pause_changed(false)
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var levels := _mode_levels()
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("今天整理哪间仓库？", 30, accent, 700, true))
	copy.add_child(PlaygroundUI.label(_map_subtitle(), 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("一起推箱 · 不计输赢" if mode_id == "classic" else "单人闯关", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 1)
		warning.add_child(PlaygroundUI.label("仓库内容有 %s 处需要检查，暂时只显示完整可玩的关卡。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.30), 24, PlaygroundUI.TOOL_LINE, 2)
		var empty_box := VBoxContainer.new()
		empty_box.add_theme_constant_override("separation", 10)
		empty_box.add_child(PlaygroundUI.label("仓库地图还在准备中", 24, accent, 700, true))
		empty_box.add_child(PlaygroundUI.label("木箱和小圆点还没有装进这台平板，请稍后再来看看。", 18, PlaygroundUI.INK_SOFT, 500, true))
		empty.add_child(empty_box)
		content_root.add_child(empty)
		return
	var entries: Array = []
	var active_level := level_id if _can_resume_level(level_id) else -1
	for index in levels.size():
		var number := index + 1
		var entry: Dictionary = levels[index]
		var unlocked := _unlocked(number)
		var stars := _stars_for(number)
		var box_count: Variant = entry.get("boxes", [])
		var box_text := "木箱 %s 只" % box_count.size() if box_count is Array else "整理木箱"
		entries.append({
			"id": number,
			"title": str(entry.get("title", "仓库")),
			"subtitle": "%s · %s · %s" % [
				str(BAND_LABELS.get(str(entry.get("band", "")), "仓库")),
				str(BAND_AGES.get(str(entry.get("band", "")), "")),
				box_text,
			],
			"locked": not unlocked,
			"stars": stars,
			"in_progress": number == active_level,
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"title": "仓库地图",
		"subtitle": "每间仓库都可以慢慢想；走错了就撤回，箱子卡住时先退一步。",
		"accent": accent,
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择仓库")


func _map_subtitle() -> String:
	if mode_id == "classic":
		if players.size() >= 2:
			return "%s 和 %s 轮流移动一格，共用同一间仓库的进度。" % [
				str(players[0].get("name", "小朋友")),
				str(players[1].get("name", "小伙伴")),
			]
		return "两个人轮流移动一格，共用同一间仓库的进度，不比较输赢。"
	var name := str(players[0].get("name", "小整理员")) if not players.is_empty() else "小整理员"
	return "%s 一个人慢慢整理，把每只木箱都送到圆点。" % name


func _choose_level(number: int) -> void:
	if not _unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一间仓库，再来挑战这一间。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		engine.state.view = view
		_build_board()
		_refresh()
		_save("继续整理仓库")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_level(number, true))
		return
	_start_level(number, true)


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来整理仓库。")
		return false
	var entry := _level(number)
	if entry.is_empty():
		show_toast("这一间仓库还没有准备好。")
		return false
	level_id = number
	_result_visible = false
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
		engine.state = {}
		show_toast("这一间仓库的内容不完整，先回地图选一关。")
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始整理仓库")
	if announce:
		Speech.stop_owner("sokoban-result")
		Speech.stop_owner("sokoban-feedback")
		Speech.speak(str(entry.get("narration", "看清木箱和圆点，再选一个方向。")), "sokoban-narration")
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 10)
	var title_box: VBoxContainer
	if mode_id == "classic" and players.size() >= 2:
		game_header.add_child(_player_badge(0))
		var middle := CenterContainer.new()
		middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box = VBoxContainer.new()
		title_box.add_theme_constant_override("separation", 1)
		title_box.add_child(PlaygroundUI.label("第 %s 间 · %s" % [level_id, engine.level_title()], 20, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("轮流移动一格，共用仓库，不比较输赢", 13, PlaygroundUI.INK_SOFT, 500, true))
		middle.add_child(title_box)
		game_header.add_child(middle)
		game_header.add_child(_player_badge(1))
	else:
		title_box = VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.add_theme_constant_override("separation", 1)
		title_box.add_child(PlaygroundUI.label("第 %s 间 · %s" % [level_id, engine.level_title()], 25, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("推箱子只能向前推，不能拉；走错了可以撤销。", 16, PlaygroundUI.INK_SOFT, 500, true))
		game_header.add_child(title_box)
		game_header.add_child(PlaygroundUI.chip(str(BAND_LABELS.get(engine.level_band(), "仓库")), accent))
	game_header.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft", 17))
	content_root.add_child(game_header)

	board = BOARD.new()
	board.configure(engine.level_definition, accent, soft_accent)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.direction_selected.connect(_move)
	content_root.add_child(board)

	status = PlaygroundUI.label("", 18, accent, 600, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.custom_minimum_size = Vector2(0, 38)
	content_root.add_child(status)

	game_tools = HFlowContainer.new()
	game_tools.alignment = FlowContainer.ALIGNMENT_CENTER
	game_tools.add_theme_constant_override("h_separation", 10)
	game_tools.add_theme_constant_override("v_separation", 6)
	undo_button = PlaygroundUI.semantic_icon_button("undo", "撤销", accent, _undo, "soft", 18)
	undo_button.custom_minimum_size = Vector2(132, 48)
	game_tools.add_child(undo_button)
	var hint_button := PlaygroundUI.semantic_icon_button("hint", "提示", accent, _hint, "soft", 18)
	hint_button.custom_minimum_size = Vector2(122, 48)
	game_tools.add_child(hint_button)
	var restart_button := PlaygroundUI.semantic_icon_button("restart", "重开", accent, _confirm_restart, "ghost", 18)
	restart_button.custom_minimum_size = Vector2(122, 48)
	game_tools.add_child(restart_button)
	var map_button := PlaygroundUI.semantic_icon_button("game", "仓库地图", accent, _show_map, "ghost", 18)
	map_button.custom_minimum_size = Vector2(154, 48)
	game_tools.add_child(map_button)
	content_root.add_child(game_tools)
	board.set_state(engine.state)
	board.set_undo_preview(engine.undo_preview())
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
	var current := int(engine.state.get("turn", 0)) == index if engine.is_cooperative() else false
	copy.add_child(PlaygroundUI.label("轮到这一位" if current else "一起推箱", 11, PlaygroundUI.INK_SOFT, 500))
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
		return "先选一间仓库。"
	if str(engine.state.get("phase", "")) == "finished":
		return "木箱全部归位啦。"
	var prefix := ""
	if engine.is_cooperative():
		var index := engine.current_player_index()
		var name := str(players[index].get("name", "小朋友")) if index < players.size() else "小朋友"
		prefix = "轮到 %s · " % name
	var text := "%s木箱归位 %s / %s · 步数 %s · 标准 %s" % [
		prefix,
		engine.boxes_on_goals(),
		engine.goal_count(),
		int(engine.state.get("moves", 0)),
		int(engine.level_definition.get("parMoves", 0)),
	]
	if int(engine.state.get("hints", 0)) > 0 or int(engine.state.get("undos", 0)) > 0:
		text += " · 提示 %s · 撤销 %s" % [int(engine.state.get("hints", 0)), int(engine.state.get("undos", 0))]
	var deadlock_value: Variant = engine.state.get("deadlockBox", {})
	if deadlock_value is Dictionary and not deadlock_value.is_empty():
		text += " · 箱子卡住了，先撤回"
	return text


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	board.set_state(engine.state)
	board.set_undo_preview(engine.undo_preview())
	board.set_interaction_enabled(str(engine.state.get("phase", "")) == "playing")
	if undo_button != null and is_instance_valid(undo_button):
		undo_button.disabled = not engine.can_undo()
	if status != null and is_instance_valid(status):
		status.text = _status_text()
		var deadlock_value: Variant = engine.state.get("deadlockBox", {})
		var warning: bool = deadlock_value is Dictionary and not deadlock_value.is_empty()
		status.add_theme_color_override("font_color", Color("#b65a43") if warning else accent)
	if str(engine.state.get("phase", "")) == "finished" and not _result_visible:
		call_deferred("_show_result")


func _move(direction: String) -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "move", "direction": direction})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		FeedbackKit.haptic(8)
		show_toast(str(result.get("message", "这个方向走不过去")))
		return
	var finished := str(result.get("event", "")) == "finished"
	var deadlocked := bool(result.get("deadlocked", false))
	if finished:
		SfxMap.play(&"success")
		FeedbackKit.haptic(14)
		_save("所有木箱归位", false)
	elif deadlocked:
		SfxMap.play(&"error")
		FeedbackKit.haptic(9)
		_save("木箱进入死角，保留当前局面")
	else:
		SfxMap.play(&"move")
		FeedbackKit.haptic(6 if bool(result.get("pushed", false)) else 3)
		_save("推开木箱" if bool(result.get("pushed", false)) else "整理员向前走一格")
	_refresh()
	if deadlocked:
		var message := str(result.get("deadlockMessage", "箱子卡住了，先撤回。"))
		show_toast(message, 3.0)
		Speech.speak(message, "sokoban-feedback")
	elif not finished and immersive and engine.is_cooperative() and players.size() >= 2:
		var next_index := engine.current_player_index()
		var next_name := str(players[next_index].get("name", "小朋友"))
		show_toast("轮到 %s 推箱。" % next_name, 1.25)
	if finished:
		_show_result()


func _undo() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "undo"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "现在没有可以撤回的一步")))
		return
	SfxMap.play(&"deselect")
	FeedbackKit.haptic(5)
	_save("撤回上一步")
	_refresh()
	show_toast("已撤回一步，再慢慢想。", 1.5)


func _hint() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "现在没有提示")))
		return
	AudioFX.play("whoosh")
	FeedbackKit.haptic(4)
	_save("查看作者路线提示")
	_refresh()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icon := ArtLibrary.semantic_picture("hint", "ui", Vector2(58, 58))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(icon)
	var direction := str(result.get("direction", ""))
	if not direction.is_empty():
		var direction_chip := PlaygroundUI.chip("下一格向%s" % str(result.get("directionName", "")), accent)
		direction_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		body.add_child(direction_chip)
	var message := str(result.get("message", "先看木箱背后有没有空位。"))
	var message_label := PlaygroundUI.label(message, 21, PlaygroundUI.INK, 600, true)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(message_label)
	body.add_child(PlaygroundUI.label("看提示后仍可完成本关，但三颗星需要不看提示、不撤销并按标准步数完成。", 15, PlaygroundUI.INK_SOFT, 500, true))
	var spoken := message
	Speech.speak(spoken, "sokoban-hint")
	open_modal("路线提示", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "sokoban-hint")},
		{"text": "继续推箱", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("sokoban-hint"); _close_top_modal()},
	], "第 %s 次提示" % int(result.get("hints", 0)))


func _confirm_restart() -> void:
	if view != "board":
		_close_pause_tools()
		show_toast("先选一间仓库，再重新开始。")
		return
	var copy := PlaygroundUI.label(
		"这一间仓库会回到起点，步数、提示和撤销次数也会重新计算。其他仓库和其他进度会保留。",
		19,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	open_modal("重新整理这一间？", copy, [
		{"text": "继续整理", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_level},
	], "仓库推推乐")


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
		show_toast(str(result.get("message", "这一间仓库暂时不能重新开始")))
		return
	_result_visible = false
	view = "board"
	SfxMap.play(&"drop")
	FeedbackKit.haptic(8)
	_refresh()
	_save("重新开始这一间仓库")
	Speech.speak("仓库回到起点，再慢慢整理。", "sokoban-feedback")


func _extra_pause_actions() -> Array:
	if view != "board":
		return []
	return [{
		"text": "仓库地图",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func show_help() -> void:
	if not paused:
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"每次移动一格。点右边的大方向键，或在棋盘上朝一个方向滑动。",
		"走到木箱旁边继续向前，就能把木箱推走；木箱不能被拉，也不能和另一只木箱重叠。",
		"把每一只木箱都推到小圆点上。箱子进入墙角时，先点撤销，保留局面再换路。",
		"提示会显示下一步；完成后至少一颗星。标准步数内且不看提示、不撤销可拿三颗星。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(["next", "game", "undo", "star"][index], "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var more_row := HBoxContainer.new()
	more_row.add_theme_constant_override("separation", 10)
	more_row.add_child(PlaygroundUI.semantic_icon_button("rules", "完整规则", accent, func(): _close_top_modal(); _show_rules(), "soft", 17))
	body.add_child(more_row)
	var spoken := "仓库推推乐玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("game-help"); _close_top_modal()},
	], "先看路，再推箱")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先看木箱和小圆点，再决定往哪个方向走一格。",
		"走到木箱背后，继续朝同一方向走，就能推动木箱；不能拉，也不能重叠。",
		"箱子卡在墙角时先撤销；所有木箱到圆点就完成，每一步都会自动保存。",
	]
	_lesson_icons = ["game", "next", "undo"]
	_show_lesson_page(0)


func _show_rules() -> void:
	var lines := [
		"纯网格推箱子，没有倒计时，也没有会自己移动的木箱。",
		"一次移动一格；木箱只能被向前推，不能被拉，也不能与另一只木箱重叠。",
		"所有木箱都在圆点上就完成。单人成功记为赢，双人协作只记为一起玩过。",
		"三星：步数不超过标准步数，且不用提示、不撤销。",
		"两星：步数不超过标准加四步，提示不超过一次，撤销不超过三次。",
		"完成至少一星；双人轮流移动一格，撤销会把轮次也退回上一位。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var copy := PlaygroundUI.label(str(lines[index]), 18, PlaygroundUI.INK_SOFT, 500, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "仓库推推乐规则。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "sokoban-rules")
	open_modal("仓库推推乐规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.speak(spoken, "sokoban-rules")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "木箱只能推，不能拉")


func show_game_rules() -> void:
	_show_rules()


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var summary: Dictionary = engine.result()
	var stars := int(summary.get("stars", engine.stars()))
	var goals := engine.goal_count()
	var session_key := str(engine.state.get("sessionId", "sokoban"))
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
			goals,
			goals,
			{"logic": {"correct": goals, "answered": goals}},
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
				goals,
				goals,
				{"logic": {"correct": goals, "answered": goals}},
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
	if _record_completion_if_needed():
		_save("所有木箱归位", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "一起整理好啦！" if mode_id == "classic" else "仓库整理好啦！"
	var title := PlaygroundUI.label(title_text, 26, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "步数 %s · 标准 %s · 推箱 %s · 提示 %s · 撤销 %s" % [
		int(summary.get("moves", 0)),
		int(summary.get("parMoves", 0)),
		int(summary.get("pushes", 0)),
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
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < stars else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var rating := "整整齐齐，一次路线都没浪费！" if stars == 3 else "整理好了，再试一条更短的路线就能拿三星。" if stars == 2 else "所有木箱都归位啦，下次可以少用一点提示和撤销。"
	var rating_label := PlaygroundUI.label(rating, 18, PlaygroundUI.INK, 600, true)
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(rating_label)
	var level: Dictionary = engine.level_definition
	var explanation := PlaygroundUI.label(str(level.get("explanation", "把每只木箱送到圆点，仓库就整理好了。")), 16, PlaygroundUI.INK_SOFT, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions := [
		{"text": "仓库地图", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("sokoban-result"); _close_top_modal(); _show_map()},
		{"text": "再推一次", "icon": "restart", "kind": "soft", "callback": func(): Speech.stop_owner("sokoban-result"); _close_top_modal(); _start_level(level_id, false)},
	]
	var next_number := level_id + 1
	if next_number <= _mode_levels().size() and (mode_id == "classic" or _unlocked(next_number)):
		actions.append({"text": "下一间", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({
			"text": "回游戏大厅",
			"icon": "home",
			"kind": "primary",
			"callback": func():
				Speech.stop_owner("sokoban-result")
				_close_all_game_dialogs()
				SaveStore.flush()
				back_requested.emit(),
		})
	open_modal("仓库整理完成", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := str(level.get("explanation", "所有木箱都送到圆点了。"))
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起把所有木箱都送到圆点啦。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "sokoban-result")


func _go_next_level() -> void:
	Speech.stop_owner("sokoban-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_levels().size():
		_show_map()
		return
	if mode_id == "adventure" and not _unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _save(note: String = "实时自动保存仓库进度", resume: bool = true) -> void:
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
