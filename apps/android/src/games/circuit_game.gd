class_name NativeCircuitGame
extends NativeGameScreen

const CONTENT_PATH := "res://content/circuit.json"
const FALLBACK_TITLE := "电路小工坊"
const FALLBACK_ACCENT := "#a55b2a"
const FALLBACK_SOFT := "#f6e7d9"
const SINGLE_LEVEL_COUNT := 24
const COOP_LEVEL_COUNT := 8
const BAND_LABELS := {"easy": "轻松小台", "normal": "标准工作台", "challenge": "挑战检修台"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}

var engine := CircuitRules.new()
var board: CircuitBoard
var status: Label
var status_icon: Control
var view := "map"
var soft_accent := Color(FALLBACK_SOFT)
var _levels_cache: Array = []
var _result_visible := false


func _ready() -> void:
	if game_id.is_empty():
		game_id = "circuit"
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
		accent = PlaygroundUI.color(FALLBACK_ACCENT)
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	if mode_id not in ["adventure", "classic"]:
		mode_id = "classic" if players.size() == 2 else "adventure"
	levels_loaded()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	stored.modeId = mode_id
	if stored.get("players") is Array and engine.restore(stored):
		players = engine.state.players.duplicate(true)
		level_id = int(engine.state.get("levelId", 1))
		view = str(engine.state.get("view", "board"))
		if engine.state.phase == "finished" and not bool(stored.get("resume", true)):
			_show_map()
		elif view == "map":
			_show_map()
		else:
			_build_board()
			_refresh()
	else:
		engine.state = {}
		var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
		if recovery_level >= 1 and recovery_level <= _level_count():
			if _start_level(recovery_level, int(stored.get("retries", 0))):
				show_toast("上次的安全电路存档不完整，已从第 %s 关开头重新开始。" % recovery_level, 3.0)
		else:
			_show_map()


func _show_initial_resume_pause() -> void:
	if view == "map":
		return
	super._show_initial_resume_pause()


func preview_ready() -> void:
	_refresh()


func levels_loaded() -> Array:
	if not _levels_cache.is_empty():
		return _levels_cache
	var candidates: Array = []
	if ContentDB != null and ContentDB.has_method("circuit_levels"):
		var content_levels: Variant = ContentDB.call("circuit_levels")
		if content_levels is Array and not content_levels.is_empty():
			candidates = content_levels.filter(func(entry): return entry is Dictionary)
	if candidates.is_empty() and FileAccess.file_exists(CONTENT_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
		if parsed is Dictionary and int(parsed.get("version", 0)) == 1 and parsed.get("levels") is Array:
			candidates = parsed.levels.filter(func(entry): return entry is Dictionary)
	if candidates.is_empty():
		return []
	var validation: Dictionary = CircuitRules.validate_catalog({"version": 1, "levels": candidates})
	if not bool(validation.get("ok", false)):
		for issue in validation.get("issues", []):
			push_warning("电路小工坊内容：" + str(issue))
		return []
	_levels_cache = candidates
	return _levels_cache


func _level_count() -> int:
	return _levels_for_mode().size()


func _levels_for_mode() -> Array:
	var all_levels := levels_loaded()
	var marked := all_levels.filter(func(entry): return entry is Dictionary and str(entry.get("mode", "")) == mode_id)
	if not marked.is_empty():
		return marked
	if mode_id == "classic":
		var start := mini(SINGLE_LEVEL_COUNT, all_levels.size())
		return all_levels.slice(start, mini(start + COOP_LEVEL_COUNT, all_levels.size()))
	return all_levels.slice(0, mini(SINGLE_LEVEL_COUNT, all_levels.size()))


func _level_for(number: int) -> Dictionary:
	var levels := _levels_for_mode()
	if number <= 0 or number > levels.size():
		return {}
	return levels[number - 1]


func _show_map() -> void:
	view = "map"
	_result_visible = false
	Speech.stop()
	board = null
	PlaygroundUI.clear(content_root)
	var levels := _levels_for_mode()
	if levels.is_empty():
		var empty := PlaygroundUI.panel(PlaygroundUI.mix(accent, Color.WHITE, 0.91), 24, PlaygroundUI.TOOL_LINE, 2)
		var empty_box := VBoxContainer.new()
		empty_box.add_theme_constant_override("separation", 10)
		empty_box.add_child(PlaygroundUI.label("安全电路还在准备中", 24, accent, 700, true))
		empty_box.add_child(PlaygroundUI.label("电路内容还没有装进这台平板，请稍后再来看看。", 18, PlaygroundUI.INK_SOFT, 500, true))
		empty.add_child(empty_box)
		content_root.add_child(empty)
		return
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var title := PlaygroundUI.label("今天拧哪一颗小螺丝？" if mode_id == "adventure" else "两个人修哪一条电路？", 30, accent, 700, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(PlaygroundUI.chip("%s 关" % levels.size(), accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	var mode_copy := ""
	if mode_id == "classic":
		if players.size() >= 2:
			mode_copy = "%s 和 %s 一起看着同一块电路板。每转一次导线或扳一次开关，就换另一位小伙伴。" % [
				str(players[0].get("name", "小朋友")),
				str(players[1].get("name", "小伙伴")),
			]
		else:
			mode_copy = "两人共享同一块安全电路，轮流转动导线和开关，不比较输赢。"
	else:
		mode_copy = "从 3 伏玩具电池出发，接通灯泡、风扇和蜂鸣器。每一段都接好，这一关就完成。"
	content_root.add_child(PlaygroundUI.label(mode_copy, 18, PlaygroundUI.INK_SOFT, 500, true))
	var browser := GameBrowser.new()
	browser.configure(_map_entries(levels), {
		"accent": accent,
		"title": "安全电路地图",
		"subtitle": "点导线转 90°，点开关合上或断开。断开的接头会亮起提示。",
	})
	browser.entry_selected.connect(func(number: Variant): _choose_level(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = "map"
		_save("正在选择安全电路")


func _map_entries(levels: Array) -> Array:
	var entries: Array = []
	for index in levels.size():
		var level: Dictionary = levels[index]
		var number := index + 1
		var unlocked := _level_unlocked(number)
		var stars := _level_stars(number)
		var in_progress := _can_resume_level(number)
		var band := str(level.get("band", "normal"))
		entries.append({
			"id": number,
			"title": str(level.get("title", "安全电路")),
			"subtitle": "%s · %s" % [str(BAND_LABELS.get(band, band)), str(BAND_AGES.get(band, ""))],
			"locked": not unlocked,
			"stars": stars,
			"in_progress": in_progress,
		})
	return entries


func _level_unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _level_stars(number: int) -> int:
	var stars := 0
	for player in players:
		stars = maxi(stars, int(SaveStore.learning(str(player.id), game_id, mode_id).stars.get(str(number), 0)))
	return clampi(stars, 0, 3)


func _can_resume_level(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and int(engine.state.get("levelId", -1)) == number
		and str(engine.state.get("phase", "")) == "playing"
		and int(engine.state.get("circuitVersion", 0)) == CircuitRules.VERSION
	)


func _choose_level(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成这个工作台里的前一关，再来挑战。")
		return
	SfxMap.play(&"tap")
	if _can_resume_level(number):
		level_id = number
		engine.state.view = "board"
		view = "board"
		_build_board()
		_refresh()
		_save("继续安全电路")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_level(number, 0))
		return
	_start_level(number, 0)


func _start_level(number: int, retries: int = 0) -> bool:
	var entry := _level_for(number)
	if entry.is_empty():
		show_toast("这一关的内容还没有准备好。")
		return false
	level_id = number
	_result_visible = false
	engine.create_session({
		"gameId": game_id,
		"modeId": mode_id,
		"players": players.duplicate(true),
		"levelId": number,
		"level": entry,
		"retries": maxi(0, retries),
		"seed": Time.get_ticks_usec(),
	})
	if str(engine.state.get("phase", "")) != "playing":
		engine.state = {}
		show_toast("这一关的安全电路内容不完整，先回到地图选一关。")
		_show_map()
		return false
	session_id = str(engine.state.sessionId)
	view = "board"
	_build_board()
	_refresh()
	_save("开始安全电路")
	if not _resume_on_start:
		call_deferred("_speak_level_intro")
	return true


func _speak_level_intro() -> void:
	if engine.state.is_empty() or paused or str(engine.state.get("phase", "")) != "playing":
		return
	Speech.speak(engine.level_narration(), "circuit-intro")


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 10)
	status_icon = ArtLibrary.semantic_picture("hint", "ui", Vector2(28, 28))
	status_row.add_child(status_icon)
	status = PlaygroundUI.label("", 18, PlaygroundUI.INK, 600, true)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.custom_minimum_size.y = 45
	status_row.add_child(status)
	var goal_chip := PlaygroundUI.chip("第 %s 关 · %s" % [level_id, engine.level_title()], accent)
	status_row.add_child(goal_chip)
	content_root.add_child(status_row)
	board = CircuitBoard.new()
	board.accent = accent
	board.soft = soft_accent
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.part_tapped.connect(_on_part_tapped)
	board.hint_requested.connect(_hint)
	content_root.add_child(board)
	board.bind(engine)
	_on_immersive_changed(immersive)


func _on_immersive_changed(_value: bool) -> void:
	if status != null and is_instance_valid(status):
		status.show()
	if status_icon != null and is_instance_valid(status_icon):
		status_icon.show()


func _on_part_tapped(index: int) -> void:
	if paused or _result_visible:
		return
	var tapped := engine.piece_at(index)
	var tapped_type := str(tapped.get("type", ""))
	var result := engine.handle_input({"type": "tap", "index": index})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "这个元件现在不能动。")))
		if board != null and is_instance_valid(board):
			board.queue_redraw()
		return
	if str(result.get("action", "")) == "toggle":
		AudioFX.play("flip")
	else:
		SfxMap.play(&"move")
	FeedbackKit.haptic(6)
	_save("接通安全电路")
	_refresh()
	if bool(result.get("completed", false)):
		call_deferred("_show_result")
		return
	var notice := str(result.get("message", "")).strip_edges()
	if engine.is_cooperative():
		var next_name := _player_name(engine.current_player_index())
		if not notice.is_empty():
			notice = "轮到 %s。%s" % [next_name, notice]
		else:
			notice = "轮到 %s 找下一段断开的接头。" % next_name
	show_toast(notice if not notice.is_empty() else "对照闪光的接头再检查一遍。", 3.4)
	if not notice.is_empty():
		Speech.speak(notice, "circuit-fault")
	elif tapped_type == "wire":
		Speech.speak("这一段还没有接通。", "circuit-fault")


func _hint() -> void:
	if paused or _result_visible:
		return
	var result := engine.handle_input({"type": "hint"})
	if not bool(result.get("ok", false)):
		SfxMap.play(&"error")
		show_toast(str(result.get("message", "先把明显的断点接起来，再看看提示。")))
		return
	SfxMap.play(&"select")
	_save("查看电路提示")
	_refresh()
	var message := str(result.get("message", "看看闪着暖光的那一段。"))
	show_toast(message, 3.4)
	Speech.speak(message, "circuit-hint")


func _refresh() -> void:
	if board == null or not is_instance_valid(board) or engine.state.is_empty():
		return
	var playing := not paused and str(engine.state.get("phase", "")) == "playing" and not _result_visible
	board.set_interactive(playing)
	board.set_feedback(engine.fault_index(), engine.hint_index())
	board.call("_sync_dock")
	var headline := ""
	if str(engine.state.get("phase", "")) == "finished":
		headline = "全部小电器都通电啦 · 操作 %s 次" % int(engine.state.get("actions", 0))
	else:
		var fault := engine.last_fault()
		if fault.is_empty():
			fault = "找一找哪一段导线或开关还没有接通。"
		headline = "已通电 %s / %s · %s" % [
			engine.powered_goal_count(),
			engine.goal_count(),
			fault,
		]
	if engine.is_cooperative() and str(engine.state.get("phase", "")) == "playing":
		headline = "轮到 %s · %s" % [_player_name(engine.current_player_index()), headline]
	status.text = headline
	if str(engine.state.get("phase", "")) == "finished" and not _result_visible:
		call_deferred("_show_result")


func _player_name(index: int) -> String:
	if index >= 0 and index < players.size():
		return str(players[index].get("name", "小朋友"))
	return "小朋友"


func _extra_topbar_actions(row: HBoxContainer) -> void:
	var rules := PlaygroundUI.button("规则", accent, show_game_rules, "soft")
	rules.custom_minimum_size = Vector2(72, 48)
	row.add_child(rules)


func show_game_rules() -> void:
	_show_rules()


func _extra_pause_actions() -> Array:
	if view != "board":
		return []
	return [{
		"text": "安全电路地图",
		"icon": "game",
		"kind": "soft",
		"callback": func(): _close_pause_tools(); _show_map(),
	}]


func _confirm_restart() -> void:
	if view != "board":
		_close_pause_tools()
		show_toast("先选一块工作台，再开始接安全电路。")
		return
	var retries := int(engine.state.get("retries", 0)) + 1
	var text := PlaygroundUI.label(
		"这一关的导线和开关会回到起点，重试次数会加一。已经得到的星星和其他游戏会保留。",
		19,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	open_modal("重开这一关？", text, [
		{"text": "继续接线", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_from_confirm.bind(retries)},
	], "电路小工坊")


func _restart_from_confirm(retries: int) -> void:
	var was_paused := paused
	_suppress_resume_on_close = was_paused
	_close_all_game_dialogs()
	if was_paused:
		paused = false
		_pause_root_layer = null
		MotionKit.set_paused_tree(self, false)
		pause_changed.emit(false)
	_suppress_resume_on_close = false
	SfxMap.play(&"drop")
	_start_level(level_id, retries)


func show_help() -> void:
	if not paused and view == "board":
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"点一下导线，它会顺时针转九十度。点小开关，就能合上或断开。",
		"电流从 3 伏玩具电池出发。只有两边接口都对齐的铜件，电流才会继续前进。",
		"接线端子和电阻是固定零件；看暖光流动的位置，也看黄色小圆点指出的断点。",
		"所有小灯泡、小风扇和蜂鸣器都工作就完成。这里只用低压玩具电池，不碰家里的插座。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(["next", "hint", "lock", "star"][index], "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(lines[index], 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "电路小工坊玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{"text": "三步小课堂", "icon": "play", "kind": "soft", "callback": func(): _close_top_modal(); call_deferred("begin_lesson", true)},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): Speech.stop_owner("game-help"); _close_top_modal()},
	], "从电池出发，点亮每一个小目标")


func _show_rules() -> void:
	var lines := [
		"点可转导线会顺时针转九十度，点开关会合上或断开。",
		"电池只从亮着的一端供电；导线两端接口都对齐，电流才能通过。",
		"开关打开时线路断开，合上后继续向下走；接线端子和电阻是固定零件。",
		"所有灯泡、风扇、蜂鸣器都通电就完成，不比较两人的输赢。",
		"黄色圆点会指出断开的一段；提示会圈出可调整的元件。重开本关会把重试次数加一。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(PlaygroundUI.chip(str(index + 1), accent))
		var copy := PlaygroundUI.label(lines[index], 18, PlaygroundUI.INK_SOFT, 500, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	Speech.speak(" ".join(PackedStringArray(lines)), "circuit-help")
	open_modal("电路小工坊规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "安全低压，只看纸板上的铜线")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused:
		_open_pause_tools()
	lesson_texts = [
		"点一下导线，它会顺时针转九十度。",
		"点小开关，让闸刀合上；接口对齐后，电流会亮起来。",
		"所有小电器都工作就完成。黄色小圆点指出还没接上的那一段。",
	]
	_lesson_icons = ["next", "game", "hint"]
	call("_show_lesson_page", 0)


func _show_result() -> void:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return
	_record_completion_if_needed()
	_save("安全电路完成", false)
	if _result_visible:
		return
	_result_visible = true
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var trophy := ArtLibrary.semantic_picture("trophy", "ui", Vector2(80, 80))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var result_title := "一起把电路接通啦！" if mode_id == "classic" else "小工坊亮起来啦！"
	var title := PlaygroundUI.label(result_title, 24, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var copy := PlaygroundUI.label(engine.level_explanation(), 18, PlaygroundUI.INK_SOFT, 500, true)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(copy)
	var totals := PlaygroundUI.label(
		"操作 %s 次 · 提示 %s 次 · 重开 %s 次" % [
			int(engine.state.get("actions", 0)),
			int(engine.state.get("hints", 0)),
			int(engine.state.get("retries", 0)),
		],
		16,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(totals)
	var stars_row := HBoxContainer.new()
	stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for index in 3:
		var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
		star.modulate = Color.WHITE if index < int(engine.state.get("stars", 0)) else Color(1, 1, 1, 0.24)
		stars_row.add_child(star)
	body.add_child(stars_row)
	var can_next := level_id < _level_count() and _level_unlocked(level_id + 1)
	var actions := [
		{
			"text": "回看电路",
			"icon": "back",
			"kind": "soft",
			"callback": func(): _result_visible = false; Speech.stop_owner("circuit-result"); _close_top_modal(),
		},
		{
			"text": "关卡地图",
			"icon": "game",
			"kind": "soft",
			"callback": func(): Speech.stop_owner("circuit-result"); _close_top_modal(); _show_map(),
		},
	]
	if can_next:
		actions.append({
			"text": "下一关",
			"icon": "next",
			"kind": "primary",
			"callback": func(): Speech.stop_owner("circuit-result"); _close_top_modal(); _choose_level(level_id + 1),
		})
	else:
		actions.append({
			"text": "回游戏大厅",
			"icon": "home",
			"kind": "primary",
			"callback": func(): Speech.stop_owner("circuit-result"); _close_all_game_dialogs(); back_requested.emit(),
		})
	open_modal("电路小工坊完成", body, actions, SaveStore.save_status_text())
	SfxMap.play(&"win")
	FeedbackKit.haptic(14)
	var spoken := engine.level_explanation()
	if mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起把安全电路接通啦。%s" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
			engine.level_explanation(),
		]
	Speech.speak(spoken, "circuit-result")


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var stars := int(engine.state.get("stars", engine.stars()))
	var all_recorded := true
	for index in players.size():
		var player_id := str(players[index].id)
		SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		var recorded := SaveStore.record_outcome(
			player_id,
			game_id,
			"win" if mode_id == "adventure" else "played",
			stars,
			engine.goal_count(),
			engine.goal_count(),
			{"science": {"correct": engine.goal_count(), "answered": engine.goal_count()}},
			str(engine.state.get("sessionId", "circuit"))
		)
		if not recorded:
			all_recorded = false
	if all_recorded:
		engine.state.reported = true
	return all_recorded


func _save(note: String = "实时自动保存电路进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	SaveStore.save_state(
		game_id,
		str(players[0].id),
		engine.snapshot(),
		note,
		resume and str(engine.state.get("phase", "")) == "playing" and view in ["board", "map"]
	)
