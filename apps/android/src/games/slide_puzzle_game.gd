class_name NativeSlidePuzzleGame
extends NativeGameScreen

const RULES = preload("res://src/games/slide_puzzle_rules.gd")
const BOARD = preload("res://src/ui/slide_puzzle_board.gd")
const CONTENT_PATH := "res://content/slide_puzzle.json"
const FALLBACK_TITLE := "数字华容道"
const FALLBACK_ACCENT := "#4f6078"
const FALLBACK_SOFT := "#e8edf3"
const BAND_LABELS := {
	"easy": "轻松滑格",
	"normal": "动脑推格",
	"challenge": "高手拼盘",
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
		game_id = "slide_puzzle"
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
			show_toast("上次的华容道记录不完整，已从第 %s 盘开头重新摆好。" % recovery_level, 3.2)
			return
	_show_map()


func _load_catalog() -> void:
	_catalog_issues.clear()
	_levels_cache.clear()
	var parsed: Variant = null
	if FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 slide_puzzle.json 或内容格式不正确")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	if not bool(validation.get("ok", false)):
		for issue in _catalog_issues:
			push_warning("数字华容道内容：" + issue)
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
	PlaygroundUI.clear(content_root)
	board = null
	var levels := _mode_levels()
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("今天想把哪一盘排整齐？", 30, accent, 700, true))
	copy.add_child(PlaygroundUI.label(_map_subtitle(), 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("一起推格 · 不计输赢" if mode_id == "classic" else "单人闯关", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.92), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 1)
		warning.add_child(PlaygroundUI.label("华容道内容有 %s 处需要检查，只显示完整可玩的棋盘。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(soft_accent, Color.WHITE, 0.30), 24, PlaygroundUI.TOOL_LINE, 2)
		var empty_box := VBoxContainer.new()
		empty_box.add_theme_constant_override("separation", 10)
		empty_box.add_child(PlaygroundUI.label("滑格棋盘还在准备中", 24, accent, 700, true))
		empty_box.add_child(PlaygroundUI.label("数字和图案还没有装进这台平板，请稍后再来看看。", 18, PlaygroundUI.INK_SOFT, 500, true))
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
			"title": str(raw.get("title", "滑格拼盘")),
			"subtitle": "%s · %s · %s×%s · %s" % [
				str(BAND_LABELS.get(str(raw.get("band", "")), "滑格")),
				str(BAND_AGES.get(str(raw.get("band", "")), "")),
				int(raw.get("size", 3)),
				int(raw.get("size", 3)),
				"图案" if str(raw.get("kind", "number")) == "pattern" else "数字",
			],
			"locked": not _unlocked(number),
			"stars": _stars_for(number),
			"in_progress": number == active_level,
		})
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"title": "华容道盘面",
		"subtitle": "点空格旁边的数字或图案，把它滑进来；走错了可以撤销，作者解提示会指出下一格。",
		"accent": accent,
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择华容道")


func _map_subtitle() -> String:
	if mode_id == "classic":
		if players.size() >= 2:
			return "%s 和 %s 轮流滑一格，共用棋盘、撤销和提示次数。" % [
				str(players[0].get("name", "小朋友")),
				str(players[1].get("name", "小伙伴")),
			]
		return "两个人轮流滑一格，共用同一盘棋盘。"
	var name := str(players[0].get("name", "小挑战者")) if not players.is_empty() else "小挑战者"
	return "%s 一个人慢慢排，数字或图案都会回到自己的位置。" % name


func _choose_level(number: int) -> void:
	if not _unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一盘，再来挑战这一盘。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		view = "board"
		engine.state.view = view
		_build_board()
		_refresh()
		_save("继续推格")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_level(number, true))
		return
	_start_level(number, true)


func _start_level(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来排华容道。")
		return false
	var entry := _find_level(number)
	if entry.is_empty():
		show_toast("第 %s 盘还没有准备好，编号不会被替换。" % number, 2.8)
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
		var message := str(engine.state.get("loadError", "这一盘华容道的内容不完整。"))
		engine.state = {}
		show_toast(message + " 请回盘面选另一关。", 3.0)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始推格")
	if announce:
		Speech.stop_owner("slide-result")
		Speech.stop_owner("slide-feedback")
		Speech.speak(str(entry.get("narration", "先找空格，再把旁边的数字一格一格滑进去。")), "slide-narration")
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
		title_box.add_child(PlaygroundUI.label("第 %s 盘 · %s" % [level_id, engine.state.get("levelTitle", "华容道")], 20, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("轮流滑一格，共用盘面，不比较输赢", 13, PlaygroundUI.INK_SOFT, 500, true))
		middle.add_child(title_box)
		game_header.add_child(middle)
		game_header.add_child(_player_badge(1))
	else:
		title_box = VBoxContainer.new()
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.add_theme_constant_override("separation", 1)
		title_box.add_child(PlaygroundUI.label("第 %s 盘 · %s" % [level_id, engine.state.get("levelTitle", "华容道")], 25, accent, 700, true))
		title_box.add_child(PlaygroundUI.label("点空格旁边的格子，让它滑进空格。", 16, PlaygroundUI.INK_SOFT, 500, true))
		game_header.add_child(title_box)
		game_header.add_child(PlaygroundUI.chip(str(BAND_LABELS.get(engine.state.get("levelBand", "easy"), "滑格")), accent))
	game_header.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft", 17))
	content_root.add_child(game_header)

	board = BOARD.new()
	board.configure(engine.level_definition, accent, soft_accent)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.tile_pressed.connect(_move)
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
	undo_button.custom_minimum_size = Vector2(126, 48)
	game_tools.add_child(undo_button)
	var hint_button := PlaygroundUI.semantic_icon_button("hint", "作者提示", accent, _hint, "soft", 18)
	hint_button.custom_minimum_size = Vector2(150, 48)
	game_tools.add_child(hint_button)
	var restart_button := PlaygroundUI.semantic_icon_button("restart", "重摆", accent, _confirm_restart, "ghost", 18)
	restart_button.custom_minimum_size = Vector2(126, 48)
	game_tools.add_child(restart_button)
	var map_button := PlaygroundUI.semantic_icon_button("game", "盘面", accent, _show_map, "ghost", 18)
	map_button.custom_minimum_size = Vector2(126, 48)
	game_tools.add_child(map_button)
	content_root.add_child(game_tools)
	board.set_state(engine.state)
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
	copy.add_child(PlaygroundUI.label("轮到这一位" if current else "一起推格", 11, PlaygroundUI.INK_SOFT, 500))
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
		return "先选一盘华容道。"
	if str(engine.state.get("phase", "")) == "finished":
		return "每一格都回到自己的位置啦。"
	var prefix := ""
	if engine.is_cooperative():
		var index := engine.current_player_index()
		var name := str(players[index].get("name", "小朋友")) if index < players.size() else "小朋友"
		prefix = "轮到 %s · " % name
	var text := "%s步数 %s · 标准 %s · 撤销 %s · 提示 %s" % [
		prefix,
		int(engine.state.get("moves", 0)),
		int(engine.level_definition.get("parMoves", 0)),
		int(engine.state.get("undos", 0)),
		int(engine.state.get("hints", 0)),
	]
	if int(engine.state.get("hintTile", -1)) >= 0:
		text += " · 亮起的格子就是下一格"
	return text


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	board.set_state(engine.state)
	board.set_interaction_enabled(str(engine.state.get("phase", "")) == "playing")
	if undo_button != null and is_instance_valid(undo_button):
		undo_button.disabled = engine.state.get("history", []).is_empty() or str(engine.state.get("phase", "")) != "playing"
	if status != null and is_instance_valid(status):
		status.text = _status_text()
	if str(engine.state.get("phase", "")) == "finished" and not _result_visible:
		call_deferred("_show_result")


func _move(index: int) -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "move", "index": index})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		FeedbackKit.haptic(7)
		show_toast(str(result.get("message", "这一格现在不能滑")))
		return
	if str(result.get("event", "")) == "finished":
		SfxMap.play(&"success")
		FeedbackKit.haptic(14)
		_save("所有格子排好", false)
	else:
		SfxMap.play(&"move")
		FeedbackKit.haptic(4)
		_save("滑入%s格" % engine.tile_name(int(result.get("tile", 0))))
	_refresh()
	if str(result.get("event", "")) != "finished" and immersive and engine.is_cooperative() and players.size() >= 2:
		var next_index := engine.current_player_index()
		var next_name := str(players[next_index].get("name", "小朋友"))
		show_toast("轮到 %s 推一格。" % next_name, 1.1)
	if str(result.get("event", "")) == "finished":
		_show_result()


func _undo() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "undo"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "现在没有可以撤销的一步")))
		return
	SfxMap.play(&"deselect")
	FeedbackKit.haptic(5)
	_save("撤销一格")
	_refresh()
	show_toast("已经退回上一步，再慢慢排。", 1.4)


func _hint() -> void:
	if is_input_blocked() or _result_visible or engine.state.is_empty():
		return
	var result: Dictionary = engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "现在没有提示")))
		return
	AudioFX.play("whoosh")
	_save("查看作者解提示")
	_refresh()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icon := ArtLibrary.semantic_picture("hint", "ui", Vector2(58, 58))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(icon)
	var message := str(result.get("message", "先看空格旁边哪一格能滑。"))
	var message_label := PlaygroundUI.label(message, 21, PlaygroundUI.INK, 600, true)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(message_label)
	body.add_child(PlaygroundUI.label("提示只指出作者解下一格；离开作者路线时，先撤销回到亮起的盘面。", 15, PlaygroundUI.INK_SOFT, 500, true))
	Speech.speak(message, "slide-hint")
	open_modal("作者解提示", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(message, "slide-hint")},
		{"text": "继续推格", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("slide-hint"); _close_top_modal()},
	], "第 %s 次提示" % int(result.get("hints", 0)))


func _confirm_restart() -> void:
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一盘华容道，再重新开始。")
		return
	var copy := PlaygroundUI.label(
		"这一盘会回到开头，步数、撤销和提示次数都会重新计算。其他棋盘和其他进度会保留。",
		19,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	open_modal("重摆这一盘？", copy, [
		{"text": "继续推格", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新摆好", "icon": "restart", "kind": "primary", "callback": _restart_level},
	], "数字华容道")


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
		show_toast(str(result.get("message", "这一盘暂时不能重新开始")))
		return
	_result_visible = false
	view = "board"
	SfxMap.play(&"drop")
	FeedbackKit.haptic(8)
	_refresh()
	_save("重新摆好这一盘")
	Speech.speak("棋盘回到开头，再慢慢把数字送回自己的位置。", "slide-feedback")


func _extra_pause_actions() -> Array:
	if view != "board":
		return []
	return [{
		"text": "华容道盘面",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func show_help() -> void:
	if not paused:
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"点空格上下左右相邻的一格，它就会滑进空格；一次只能滑一格。",
		"数字盘要按 1、2、3 的顺序排好；图案盘把彩色小块拼回完整图案。",
		"走错了可以撤销；提示会指出作者解的下一格，离开作者路线时先撤销。",
		"每一盘都有固定、可解的开头和作者解；自动保存会记住盘面、步数和轮次。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(["next", "game", "undo", "save"][index], "ui", Vector2(42, 42)))
		var copy_label := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy_label)
		body.add_child(row)
	var spoken := "数字华容道玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("game-help"); _close_top_modal()},
	], "点空格旁边的一格")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先找到空格，再点它上下左右相邻的一格，让那一格滑进来。",
		"数字盘排成 1 到最后一个数字，图案盘拼成完整图案；一次只滑一格。",
		"走错了用撤销，想不起来看作者提示；成功、轮次和每一步都会自动保存。",
	]
	_lesson_icons = ["next", "game", "undo"]
	_show_lesson_page(0)


func _show_rules() -> void:
	var lines := [
		"棋盘固定为 3×3 或 4×4，空格只有一个，没有倒计时。",
		"每步只能把空格上下左右相邻的格子滑入空格；不合法点击不会改变盘面。",
		"每盘的开头和作者解都已校验可解；提示只使用作者解，不运行时寻路。",
		"单人至少一星记赢；双人轮流滑一格，只记一起玩过，不比较输赢。",
		"三星：达到作者解步数且不用提示、不撤销；二星允许少量额外步数和辅助。",
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
	var spoken := "数字华容道规则。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "slide-rules")
	open_modal("数字华容道规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.speak(spoken, "slide-rules")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "固定可解，不靠运气")


func show_game_rules() -> void:
	_show_rules()


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var summary: Dictionary = engine.result()
	var stars := int(summary.get("stars", engine.stars()))
	var cells := engine.size() * engine.size() - 1
	var session_key := str(engine.state.get("sessionId", "slide_puzzle"))
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
	if _record_completion_if_needed():
		_save("所有格子排好", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(84, 84))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "一起排整齐啦！" if mode_id == "classic" else "华容道排好啦！"
	var title := PlaygroundUI.label(title_text, 26, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "步数 %s · 标准 %s · 撤销 %s · 提示 %s" % [
		int(summary.get("moves", 0)),
		int(summary.get("parMoves", 0)),
		int(summary.get("undos", 0)),
		int(summary.get("hints", 0)),
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
	var rating := "空格走得刚刚好，作者路线一次完成！" if stars == 3 else "已经整整齐齐，下次少撤销几次会更熟练。" if stars == 2 else "每一格都回家了，回头看提示会比较轻松。"
	var rating_label := PlaygroundUI.label(rating, 18, PlaygroundUI.INK, 600, true)
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(rating_label)
	var explanation := PlaygroundUI.label(str(engine.level_definition.get("explanation", "先规划空格怎么走，再一格一格滑。")), 16, PlaygroundUI.INK_SOFT, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions := [
		{"text": "盘面列表", "icon": "game", "kind": "soft", "callback": func(): Speech.stop_owner("slide-result"); _close_top_modal(); _show_map()},
		{"text": "再排一次", "icon": "restart", "kind": "soft", "callback": func(): Speech.stop_owner("slide-result"); _close_top_modal(); _start_level(level_id, false)},
	]
	var next_number := level_id + 1
	if not _find_level(next_number).is_empty() and (mode_id == "classic" or _unlocked(next_number)):
		actions.append({"text": "下一盘", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({
			"text": "回游戏大厅",
			"icon": "home",
			"kind": "primary",
			"callback": func():
				Speech.stop_owner("slide-result")
				_close_all_game_dialogs()
				SaveStore.flush()
				back_requested.emit(),
		})
	open_modal("华容道完成", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := str(engine.level_definition.get("explanation", "数字和图案都回到自己的位置啦。"))
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s轮流推格，一起把棋盘排整齐啦。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "slide-result")


func _go_next_level() -> void:
	Speech.stop_owner("slide-result")
	_close_top_modal()
	var next_number := level_id + 1
	if _find_level(next_number).is_empty():
		_show_map()
		return
	if mode_id == "adventure" and not _unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true)


func _save(note: String = "实时自动保存华容道进度", resume: bool = true) -> void:
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
