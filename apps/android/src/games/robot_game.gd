class_name NativeRobotGame
extends NativeGameScreen

const ROBOT_ACCENT := Color("#4266a8")
const ROBOT_SOFT := Color("#e4eaf8")
const BAND_NAMES := {
	"easy": "轻松",
	"normal": "标准",
	"challenge": "挑战",
}
const BAND_COPY := {
	"easy": "短路线，认识方向",
	"normal": "绕开纸墙，练会计划",
	"challenge": "长路线，留意每一扇门",
}

var engine := RobotRules.new()
var board: RobotBoard
var game_header: Control
var status: Label
var game_tools: Control
var view := "map"
var _levels_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _auto_running := false
var _auto_timer: Timer


func _ready() -> void:
	accent = ROBOT_ACCENT
	build_shell()
	_load_levels()
	_setup_auto_timer()
	pause_changed.connect(_on_pause_changed)
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	stored.modeId = mode_id
	var restored := had_stored and stored.get("players") is Array and engine.restore(stored)
	if restored:
		players = engine.state.players.duplicate(true)
		difficulty = str(engine.state.get("difficulty", difficulty))
		level_id = int(engine.state.get("levelId", 1))
		view = str(engine.state.get("view", "board"))
		if str(engine.state.get("phase", "")) == "result" and not bool(stored.get("resume", true)):
			_show_map()
			return
		if view == "map":
			_show_map()
			return
		_build_board()
		_refresh()
		if str(engine.state.get("phase", "")) == "result":
			_show_result()
		return
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
	if recovery_level >= 1 and recovery_level <= _levels_cache.size():
		if _start_level(recovery_level, false, true):
			show_toast("上次的路线记录不完整，已从第 %s 关开头重新排。" % recovery_level, 3.0)
			return
	_show_map()


func _load_levels() -> void:
	_catalog_issues.clear()
	_levels_cache.clear()
	var parsed: Variant = null
	var path := "res://content/robot.json"
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 robot.json 或内容格式不正确")
		return
	var validation := RobotRules.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	var levels_value: Variant = parsed.get("levels", [])
	if levels_value is Array:
		for raw in levels_value:
			if not raw is Dictionary:
				continue
			var entry_validation := RobotRules.validate_level(raw)
			if bool(entry_validation.get("ok", false)):
				_levels_cache.append(raw.duplicate(true))
	for issue in _catalog_issues:
		push_warning("路线小机器人内容：" + issue)


func _setup_auto_timer() -> void:
	_auto_timer = Timer.new()
	_auto_timer.one_shot = true
	_auto_timer.wait_time = 0.34
	_auto_timer.timeout.connect(_on_auto_timeout)
	add_child(_auto_timer)


func _level(number: int = -1) -> Dictionary:
	if _levels_cache.is_empty():
		return {}
	var index := clampi((number if number > 0 else level_id) - 1, 0, _levels_cache.size() - 1)
	var entry: Variant = _levels_cache[index]
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
		stars = maxi(stars, int(SaveStore.learning(str(player.id), game_id, mode_id).stars.get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_level(number: int) -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) == "result":
		return false
	if int(engine.state.get("levelId", 0)) != number:
		return false
	return str(engine.state.get("phase", "")) in ["program", "running", "retry"]


func _show_map() -> void:
	_stop_auto()
	Speech.stop()
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("机器人今天走哪条路线？", 30, accent, 700, true))
	copy.add_child(PlaygroundUI.label("看棋盘、排指令，再让机器人一步一步走到小旗。", 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("双人协作 · 不计胜负" if mode_id == "classic" else "单人闯关", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("hint", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.90), 16, PlaygroundUI.mix(accent, Color.WHITE, 0.48), 1)
		warning.add_child(PlaygroundUI.label("路线内容有 %s 处需要检查，暂时只显示可玩的关卡。" % _catalog_issues.size(), 16, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(warning)
	if _levels_cache.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.9), 22, PlaygroundUI.TOOL_LINE, 2)
		empty.add_child(PlaygroundUI.label("机器人路线还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		return
	var scroll := SmoothScrollContainer.create()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections.add_theme_constant_override("separation", 18)
	for band in RobotRules.BANDS:
		var entries: Array = []
		for index in _levels_cache.size():
			var entry: Dictionary = _levels_cache[index]
			if str(entry.get("band", "")) == str(band):
				entries.append({"number": index + 1, "level": entry})
		if entries.is_empty():
			continue
		var band_head := HBoxContainer.new()
		band_head.add_theme_constant_override("separation", 10)
		band_head.add_child(PlaygroundUI.chip("%s · %s" % [str(BAND_NAMES.get(band, band)), entries.size()], accent))
		band_head.add_child(PlaygroundUI.label(str(BAND_COPY.get(band, "")), 16, PlaygroundUI.INK_SOFT, 500, true))
		sections.add_child(band_head)
		var grid := GridContainer.new()
		var viewport_width := get_viewport_rect().size.x
		grid.columns = 3 if viewport_width <= 1180.0 else 4 if viewport_width < 1500.0 else 6
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		for item in entries:
			var number := int(item.number)
			var entry: Dictionary = item.level
			var unlocked := _unlocked(number)
			var resume_here := _can_resume_level(number)
			var stars := _stars_for(number)
			var state_text := "完成前一关解锁"
			if unlocked and resume_here:
				var active_program: Variant = engine.state.get("program", [])
				var active_count := 0
				if active_program is Array:
					active_count = active_program.size()
				state_text = "继续这一关 · 已排 %s 条" % active_count
			elif unlocked and stars > 0:
				state_text = "已获 %s / 3 星" % stars
			elif unlocked:
				state_text = "双人一起排程序" if mode_id == "classic" else "可以开始"
			var button := PlaygroundUI.semantic_icon_button(
				"play" if unlocked else "lock",
				"第 %s 关\n%s\n%s" % [number, str(entry.get("title", "路线小机器人")), state_text],
				accent,
				_choose_level.bind(number),
				"soft",
				16
			)
			button.custom_minimum_size = Vector2(0, 132)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.disabled = not unlocked
			grid.add_child(button)
		sections.add_child(grid)
	scroll.add_child(sections)
	content_root.add_child(scroll)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择机器人路线")


func _choose_level(number: int) -> void:
	if not _unlocked(number):
		show_toast("先完成前一关，再来挑战这条路。")
		return
	_stop_auto()
	if _can_resume_level(number):
		level_id = number
		view = "board"
		_build_board()
		_refresh()
		_save("继续机器人路线")
		return
	if str(engine.state.get("phase", "")) in ["program", "running", "retry"]:
		guard_level_switch(number, func(): _start_level(number, true, true))
		return
	_start_level(number, true, true)


func _start_level(number: int, announce: bool = true, build_now: bool = true) -> bool:
	_stop_auto()
	if players.is_empty():
		show_toast("先选择小朋友，再来安排路线。")
		return false
	var entry := _level(number)
	if entry.is_empty():
		show_toast("这一关的路线还没有准备好。")
		return false
	level_id = number
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"level": entry,
		"difficulty": difficulty,
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "program":
		show_toast(str(engine.state.get("reason", "这一关的路线还不完整。")))
		engine.state = {}
		return false
	view = "board"
	_result_visible = false
	_save("开始第 %s 条机器人路线" % number)
	if build_now:
		_build_board()
		_refresh()
	if announce:
		Speech.stop()
		Speech.speak(str(entry.get("narration", "看棋盘，排出方向指令。")), "robot-narration")
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	game_header = HBoxContainer.new()
	game_header.add_theme_constant_override("separation", 10)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	title_box.add_child(PlaygroundUI.label("第 %s 关 · %s" % [level_id, str(_level(level_id).get("title", "路线小机器人"))], 25, accent, 700, true))
	title_box.add_child(PlaygroundUI.label("撞墙会停在最后安全格；改好程序还能继续。", 16, PlaygroundUI.INK_SOFT, 500, true))
	game_header.add_child(title_box)
	if mode_id == "classic" and players.size() >= 2:
		game_header.add_child(_player_badge(0))
		game_header.add_child(_player_badge(1))
	else:
		game_header.add_child(PlaygroundUI.chip("方向规划", accent))
	content_root.add_child(game_header)

	board = RobotBoard.new()
	board.configure(_level(level_id), accent, ROBOT_SOFT)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.command_selected.connect(_add_command)
	board.program_item_selected.connect(_remove_command)
	content_root.add_child(board)

	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	status = PlaygroundUI.label("", 17, accent, 600, true)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.custom_minimum_size = Vector2(0, 44)
	bottom.add_child(status)
	game_tools = _build_tools()
	bottom.add_child(game_tools)
	content_root.add_child(bottom)
	board.set_state(engine.state)
	_on_immersive_changed(immersive)


func _build_tools() -> Control:
	var tools := HFlowContainer.new()
	tools.alignment = FlowContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override("h_separation", 10)
	tools.add_theme_constant_override("v_separation", 6)
	tools.add_child(PlaygroundUI.semantic_icon_button("next", "走一步", accent, _step_once, "primary", 18))
	tools.add_child(PlaygroundUI.semantic_icon_button("play", "走完这串", accent, _run_all, "soft", 18))
	tools.add_child(PlaygroundUI.semantic_icon_button("hint", "提示", accent, _show_hint, "soft", 18))
	tools.add_child(PlaygroundUI.semantic_icon_button("restart", "重开", accent, _confirm_restart, "ghost", 18))
	tools.add_child(PlaygroundUI.semantic_icon_button("back", "关卡地图", accent, _show_map, "ghost", 18))
	return tools


func _player_badge(index: int) -> Control:
	var player: Dictionary = players[index] if index < players.size() else {}
	var tint := PlaygroundUI.color(str(player.get("color", "#4266a8")))
	var panel := PlaygroundUI.panel(PlaygroundUI.mix(tint, Color.WHITE, 0.88), 16, PlaygroundUI.mix(tint, Color.WHITE, 0.44), 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.add_child(ArtLibrary.profile_picture(player, Vector2(32, 34)))
	row.add_child(PlaygroundUI.label(str(player.get("name", "小朋友")), 15, PlaygroundUI.INK, 700, true))
	panel.add_child(row)
	return panel


func _on_immersive_changed(value: bool) -> void:
	if game_header != null and is_instance_valid(game_header):
		game_header.visible = not value
	if status != null and is_instance_valid(status):
		status.show()
	if game_tools != null and is_instance_valid(game_tools):
		game_tools.show()


func _status_text() -> String:
	if engine.state.is_empty():
		return "先选择一条路线。"
	var program: Array = engine.state.get("program", [])
	var cursor := int(engine.state.get("cursor", 0))
	var prefix := ""
	if mode_id == "classic" and players.size() >= 2:
		var current_player: Dictionary = players[clampi(int(engine.state.get("turn", 0)), 0, players.size() - 1)]
		prefix = "轮到 %s 加一条指令。" % str(current_player.get("name", "小朋友"))
	var phase := str(engine.state.get("phase", ""))
	if phase == "result":
		return "到达小旗啦！程序保留在下面，可以回地图或再走一次。"
	if phase == "retry":
		return "%s%s" % [prefix, str(engine.state.get("reason", "机器人停在最后安全格，改好程序再试。"))]
	if program.is_empty():
		return "%s先从右边点方向指令，程序会按顺序排好。" % prefix
	if phase == "running":
		return "%s程序 %s / %s 条 · 已经走到第 %s 步。" % [prefix, program.size(), int(_level().get("slotLimit", program.size())), cursor]
	return "%s程序 %s / %s 条。点“走一步”慢慢看，或“走完这串”。" % [prefix, program.size(), int(_level().get("slotLimit", program.size()))]


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	board.set_state(engine.state)
	if status != null and is_instance_valid(status):
		status.text = _status_text()
		status.add_theme_color_override("font_color", Color("#b65a43") if str(engine.state.get("phase", "")) == "retry" else accent)
	if str(engine.state.get("phase", "")) == "result" and not _result_visible:
		_show_result()


func _add_command(command: String) -> void:
	if is_input_blocked() or _result_visible:
		return
	_stop_auto()
	Speech.stop_owner("robot-narration")
	var result := engine.handle_input({"type": "add_command", "command": command})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "这条指令现在放不进去")))
		return
	SfxMap.play(&"tap")
	FeedbackKit.haptic(4)
	_save("把方向指令接到程序末尾")
	_refresh()
	if bool(result.get("reset", false)):
		show_toast("程序改过了，机器人从起点重新准备。", 1.8)
	elif mode_id == "classic" and players.size() >= 2:
		var next_player: Dictionary = players[int(result.get("turn", 0))]
		show_toast("轮到 %s 啦。" % str(next_player.get("name", "小朋友")), 1.2)


func _remove_command(index: int) -> void:
	if is_input_blocked() or _result_visible:
		return
	_stop_auto()
	Speech.stop_owner("robot-narration")
	var result := engine.handle_input({"type": "remove_command", "index": index})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "这条指令已经删掉了")))
		return
	SfxMap.play(&"deselect")
	FeedbackKit.haptic(5)
	_save("删除一条程序指令")
	_refresh()
	show_toast("删掉一条指令，机器人从起点重新准备。", 1.6)


func _step_once() -> void:
	if is_input_blocked() or _result_visible:
		return
	_stop_auto()
	_advance_one(false)


func _run_all() -> void:
	if is_input_blocked() or _result_visible:
		return
	if engine.state.is_empty():
		return
	if str(engine.state.get("phase", "")) == "retry":
		show_toast("先改一改程序里的指令，再出发。")
		return
	var program: Variant = engine.state.get("program", [])
	if not program is Array or program.is_empty():
		show_toast("先排几条方向指令，再让机器人出发。")
		return
	if _auto_running:
		return
	Speech.stop_owner("robot-narration")
	_auto_running = true
	if board != null and is_instance_valid(board):
		board.set_auto_running(true)
	_auto_timer.start(0.05)


func _on_auto_timeout() -> void:
	if not _auto_running:
		return
	if is_input_blocked() or view != "board" or _result_visible:
		_stop_auto()
		return
	if not _advance_one(true):
		_stop_auto()
		return
	_auto_timer.start()


func _advance_one(auto: bool) -> bool:
	var result := engine.handle_input({"type": "step"})
	if not bool(result.get("ok", false)):
		if not auto:
			show_toast(str(result.get("message", "先改一改程序再试")))
		return false
	var event := str(result.get("event", ""))
	if event == "blocked":
		_stop_auto()
		SfxMap.play(&"error")
		FeedbackKit.haptic(12)
		_save("机器人撞到纸墙，停在最后安全格")
		_refresh()
		var reason := str(result.get("reason", "机器人停在最后安全格，改好程序再试。"))
		show_toast(reason, 3.0)
		Speech.speak(reason, "robot-feedback")
		return false
	if event == "dead_end":
		_stop_auto()
		SfxMap.play(&"error")
		FeedbackKit.haptic(9)
		_save("程序走完但没有到达小旗")
		_refresh()
		var reason := str(result.get("reason", "程序走完了，小旗还在前面。"))
		show_toast(reason, 2.8)
		Speech.speak(reason, "robot-feedback")
		return false
	if event == "finished":
		_stop_auto()
		SfxMap.play(&"success")
		FeedbackKit.haptic(14)
		_save("机器人到达小旗", false)
		_refresh()
		_show_result()
		return false
	SfxMap.play(&"select")
	FeedbackKit.haptic(3)
	_save("机器人向前走一步")
	_refresh()
	return true


func _stop_auto() -> void:
	_auto_running = false
	if is_instance_valid(_auto_timer):
		_auto_timer.stop()
	if board != null and is_instance_valid(board):
		board.set_auto_running(false)


func _on_pause_changed(paused_value: bool) -> void:
	if paused_value:
		_stop_auto()


func _show_hint() -> void:
	if is_input_blocked() or _result_visible:
		return
	_stop_auto()
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		show_toast(str(result.get("message", "现在没有提示")))
		return
	AudioFX.play("whoosh")
	_save("查看机器人路线提示")
	_refresh()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icon := ArtLibrary.semantic_picture("hint", "ui", Vector2(58, 58))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(icon)
	body.add_child(PlaygroundUI.label(str(result.get("hint", "先看小旗在哪一边。")), 21, PlaygroundUI.INK, 600, true))
	body.add_child(PlaygroundUI.label("看提示会少一颗星，但路线仍然可以完成。", 16, PlaygroundUI.INK_SOFT, 500, true))
	var spoken := str(result.get("hint", "先看小旗在哪一边。"))
	Speech.speak(spoken, "robot-hint")
	open_modal("路线提示", body, [
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "robot-hint")},
		{"text": "继续排程序", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("robot-hint"); _close_top_modal()},
	], "第 %s 次提示" % int(result.get("hints", 0)))


func _show_result() -> void:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "result":
		return
	var summary := engine.result()
	if summary.is_empty():
		return
	if not bool(engine.state.get("reported", false)):
		engine.state.reported = true
		var stars := int(summary.get("stars", engine.stars()))
		var outcome := str(summary.get("outcome", "played"))
		if mode_id == "adventure":
			var player_id := str(players[0].id)
			SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
			SaveStore.record_outcome(
				player_id,
				game_id,
				outcome,
				stars,
				1,
				1,
				{"logic": {"correct": 1, "answered": 1}},
				str(engine.state.get("sessionId", "robot"))
			)
		else:
			for player in players:
				var player_id := str(player.id)
				SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
				SaveStore.record_outcome(
					player_id,
					game_id,
					"played",
					stars,
					1,
					1,
					{"logic": {"correct": 1, "answered": 1}},
					str(engine.state.get("sessionId", "robot"))
				)
		_save("机器人路线完成", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(86, 86))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var result_title := "一起完成路线啦！" if mode_id == "classic" else "路线完成啦！"
	var result_label := PlaygroundUI.label(result_title, 26, accent, 700, true)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(result_label)
	var stats := "走了 %s 步 · 标准 %s 步 · 提示 %s 次 · 重试 %s 次" % [
		int(summary.get("steps", 0)),
		int(summary.get("par", 0)),
		int(summary.get("hints", 0)),
		int(summary.get("retries", 0)),
	]
	var stats_label := PlaygroundUI.label(stats, 18, PlaygroundUI.INK_SOFT, 500, true)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stats_label)
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stars_row.add_theme_constant_override("separation", 8)
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < int(summary.get("stars", 0)) else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var explanation := PlaygroundUI.label(str(_level().get("explanation", "小机器人到达了小旗。")), 18, PlaygroundUI.INK, 500, true)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(explanation)
	var actions: Array = [
		{"text": "关卡地图", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal(); _show_map()},
		{"text": "再走一次", "icon": "restart", "kind": "soft", "callback": func(): _close_top_modal(); _start_level(level_id, false, true)},
	]
	if level_id < _levels_cache.size():
		actions.append({"text": "下一关", "icon": "next", "kind": "primary", "callback": _go_next_level})
	else:
		actions.append({"text": "回大厅", "icon": "home", "kind": "primary", "callback": func(): _close_top_modal(); back_requested.emit()})
	open_modal("路线完成", body, actions, "本关已自动保存", false)
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := str(_level().get("explanation", "小机器人到达了小旗。"))
	Speech.speak(spoken, "robot-result")


func _go_next_level() -> void:
	Speech.stop_owner("robot-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _levels_cache.size():
		_show_map()
		return
	if not _unlocked(next_number):
		_show_map()
		return
	_start_level(next_number, true, true)


func _confirm_restart() -> void:
	if view == "map":
		_close_pause_tools()
		show_toast("先选一条路线，再重新开始。")
		return
	var copy := PlaygroundUI.label("这一关的程序会清空，机器人回到起点。其他关卡和其他游戏的进度会保留。", 19, PlaygroundUI.INK_SOFT, 500, true)
	open_modal("重新走这一关？", copy, [
		{"text": "继续这一关", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_level},
	], "路线小机器人")


func _restart_level() -> void:
	_close_top_modal()
	Speech.stop_owner("robot-result")
	Speech.stop_owner("robot-feedback")
	_start_level(level_id, false, true)


func _extra_pause_actions() -> Array:
	if view == "map":
		return []
	return [{"text": "关卡地图", "icon": "back", "kind": "soft", "callback": func(): _close_pause_tools(); _show_map()}]


func show_help() -> void:
	if not paused:
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"看小旗在棋盘什么位置，再从右边点方向指令。",
		"程序会按顺序执行；点一条已经排好的指令，就能把它删掉。",
		"点“走一步”逐格观察，或点“走完这串”自动走；撞墙会停在最后安全格。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(["play", "next", "hint"][index], "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 20, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "路线小机器人玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "跟着纸格子一步一步来")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"先看小机器人、纸墙和小旗，再点右边一条方向指令。",
		"指令会排进下面的小火车；点已经排好的指令，可以把它删掉。",
		"点“走一步”看机器人移动，撞墙会停在最后安全格；改好程序再走到小旗。",
	]
	_lesson_icons = ["game", "next", "check"]
	call("_show_lesson_page", 0)


func _save(note: String = "自动保存机器人路线", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	engine.state.view = view
	var phase := str(engine.state.get("phase", ""))
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and phase != "result"
	)
