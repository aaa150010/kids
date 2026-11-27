class_name NativePinballGame
extends NativeGameScreen

const RULES = preload("res://src/games/pinball_rules.gd")
const FIELD = preload("res://src/ui/pinball_field.gd")
const CONTENT_PATH := "res://content/pinball.json"
const FALLBACK_TITLE := "弹珠星轨"
const FALLBACK_ACCENT := "#6f4b98"
const FALLBACK_SOFT := "#ede5f6"
const PINBALL_VERSION := 1
const BAND_LABELS := {"easy": "轻松", "normal": "标准", "challenge": "挑战"}
const BAND_AGES := {"easy": "推荐 4–6 岁", "normal": "推荐 7–9 岁", "challenge": "推荐 10–12 岁"}
const FALLBACK_MODES := {
	"adventure": {
		"id": "adventure",
		"name": "星轨弹珠",
		"player_range": [1, 1],
		"description": "18 张固定弹珠台，弹板、缓冲柱和目标灯",
	},
	"classic": {
		"id": "classic",
		"name": "双人守台",
		"player_range": [2, 2],
		"description": "两人各守一块弹板，共享分数和球权",
	},
}

var engine = RULES.new()
var field: PinballField
var soft_accent := Color(FALLBACK_SOFT)
var view := "map"
var _tables_cache: Array = []
var _catalog_issues: Array[String] = []
var _result_visible := false
var _save_clock := 0.0


func _ready() -> void:
	if game_id.is_empty():
		game_id = "pinball"
	if str(game_meta.get("title", "")).strip_edges().is_empty():
		game_meta.title = FALLBACK_TITLE
	if str(game_meta.get("accent", "")).strip_edges().is_empty():
		game_meta.accent = FALLBACK_ACCENT
		accent = PlaygroundUI.color(FALLBACK_ACCENT)
	if str(game_meta.get("soft", "")).strip_edges().is_empty():
		game_meta.soft = FALLBACK_SOFT
	soft_accent = PlaygroundUI.color(str(game_meta.get("soft", FALLBACK_SOFT)))
	if mode_id not in ["adventure", "classic"]:
		mode_id = "adventure" if players.size() <= 1 else "classic"
	elif mode_id == "adventure" and players.size() != 1:
		mode_id = "classic"
	elif mode_id == "classic" and players.size() != 2:
		mode_id = "adventure"
	_load_tables()
	SaveStore.set_context(game_id, mode_id, players.map(func(player): return str(player.id)))
	build_shell()
	pause_changed.connect(_on_pause_changed)
	var stored := SaveStore.load_state(game_id, players.map(func(player): return str(player.id)))
	var had_stored := not stored.is_empty()
	stored.modeId = mode_id
	if had_stored and engine.restore(stored):
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
			call_deferred("_show_result")
		return
	engine.state = {}
	var recovery_level := int(stored.get("levelId", 0)) if had_stored else 0
	if recovery_level >= 1 and recovery_level <= _mode_tables().size():
		if _start_table(recovery_level, false):
			show_toast("上次的弹珠存档不完整，已从第 %s 张台面重新准备。" % recovery_level, 3.0)
			return
	_show_map()


func preview_ready() -> void:
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _load_tables() -> void:
	_tables_cache.clear()
	_catalog_issues.clear()
	var parsed: Variant = null
	if ContentDB.get("pinball_data") is Dictionary:
		parsed = ContentDB.get("pinball_data")
	if not parsed is Dictionary and FileAccess.file_exists(CONTENT_PATH):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not parsed is Dictionary:
		_catalog_issues.append("找不到 pinball.json")
		return
	var validation: Dictionary = RULES.validate_catalog(parsed)
	for issue in validation.get("issues", []):
		_catalog_issues.append(str(issue))
	var valid_tables: Variant = validation.get("validTables", [])
	if not valid_tables is Array:
		return
	for raw in valid_tables:
		if raw is Dictionary:
			_tables_cache.append(raw.duplicate(true))
	if not bool(validation.get("ok", false)):
		for issue in _catalog_issues:
			push_warning("弹珠星轨内容：" + issue)


func _mode_tables() -> Array:
	var result := _tables_cache.filter(func(entry): return entry is Dictionary and str(entry.get("mode", "")) == mode_id)
	result.sort_custom(func(first, second):
		return int(first.get("levelNumber", 0)) < int(second.get("levelNumber", 0))
	)
	return result


func _table_for(number: int) -> Dictionary:
	if number < 1:
		return {}
	for raw in _mode_tables():
		if int(raw.get("levelNumber", 0)) == number:
			return raw.duplicate(true)
	return {}


func _mode_definition(identifier: String = "") -> Dictionary:
	var selected := identifier if not identifier.is_empty() else mode_id
	if ContentDB.has_method("mode"):
		var value: Variant = ContentDB.call("mode", game_id, selected)
		if value is Dictionary and not value.is_empty():
			return value
	return FALLBACK_MODES.get(selected, FALLBACK_MODES["adventure"]).duplicate(true)


func _star_count(number: int) -> int:
	var stars := 0
	for player in players:
		var progress := SaveStore.learning(str(player.id), game_id, mode_id)
		stars = maxi(stars, int(progress.get("stars", {}).get(str(number), 0)))
	return clampi(stars, 0, 3)


func _level_unlocked(number: int) -> bool:
	if mode_id == "classic":
		return true
	if players.is_empty():
		return false
	return SaveStore.level_unlocked(str(players[0].id), game_id, number, mode_id)


func _can_resume_table(number: int) -> bool:
	return (
		not engine.state.is_empty()
		and int(engine.state.get("levelId", -1)) == number
		and int(engine.state.get("levelNumber", -1)) == number
		and str(engine.state.get("modeId", "")) == mode_id
		and str(engine.state.get("phase", "")) == "playing"
		and int(engine.state.get("pinballVersion", 0)) == PINBALL_VERSION
	)


func _show_map() -> void:
	Speech.stop()
	view = "map"
	_result_visible = false
	PlaygroundUI.clear(content_root)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	copy.add_child(PlaygroundUI.label("星轨弹珠选择台", 30, accent, 700, true))
	var subtitle := "按住左右弹板，把弹珠送回上方。点亮全部目标灯后，让弹珠从中央落下。"
	if mode_id == "classic":
		subtitle = "两位小朋友各守一块弹板，共享分数和三颗弹珠，一起点亮同一个星轨。"
	copy.add_child(PlaygroundUI.label(subtitle, 18, PlaygroundUI.INK_SOFT, 500, true))
	heading.add_child(copy)
	heading.add_child(PlaygroundUI.chip("18 张星轨" if mode_id == "adventure" else "6 张双人台", accent))
	heading.add_child(PlaygroundUI.semantic_icon_button("rules", "怎么玩", accent, show_help, "soft"))
	content_root.add_child(heading)
	if not _catalog_issues.is_empty():
		var warning := PlaygroundUI.panel(
			PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28),
			16,
			PlaygroundUI.mix(accent, Color.WHITE, 0.45),
			1
		)
		warning.add_child(PlaygroundUI.label(
			"弹珠台有 %s 处需要检查，暂时只显示可玩的台面。" % _catalog_issues.size(),
			16,
			PlaygroundUI.INK_SOFT,
			600,
			true
		))
		content_root.add_child(warning)
	var tables := _mode_tables()
	if tables.is_empty():
		var empty := PlaygroundUI.panel(
			PlaygroundUI.mix(soft_accent, Color.WHITE, 0.28),
			22,
			PlaygroundUI.TOOL_LINE,
			2
		)
		empty.add_child(PlaygroundUI.label("弹珠台还没有准备好，请稍后再来看看。", 20, PlaygroundUI.INK_SOFT, 600, true))
		content_root.add_child(empty)
		if not engine.state.is_empty():
			engine.state.view = view
			_save("正在选择弹珠台")
		return
	var entries: Array = []
	for raw in tables:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		var number := int(entry.get("levelNumber", entries.size() + 1))
		entries.append({
			"id": number,
			"title": str(entry.get("title", "弹珠台")),
			"subtitle": "%s · %s" % [
				str(BAND_LABELS.get(str(entry.get("band", "")), "轻松")),
				str(BAND_AGES.get(str(entry.get("band", "")), "")),
			],
			"locked": not _level_unlocked(number),
			"stars": _star_count(number),
			"in_progress": _can_resume_table(number),
		})
	entries.sort_custom(func(first, second): return int(first.get("id", 0)) < int(second.get("id", 0)))
	var browser := GameBrowser.new()
	browser.configure(entries, {
		"accent": accent,
		"title": "选择一张弹珠星轨",
		"subtitle": "目标灯、缓冲柱和弹板位置每张都不同。",
	})
	browser.entry_selected.connect(func(number: Variant): _choose_table(int(number)))
	content_root.add_child(browser)
	if not engine.state.is_empty():
		engine.state.view = view
		_save("正在选择弹珠台")


func _choose_table(number: int) -> void:
	if not _level_unlocked(number):
		SfxMap.play(&"error")
		show_toast("先完成前一关，再来挑战这张星轨。")
		return
	SfxMap.play(&"tap")
	if _can_resume_table(number):
		level_id = number
		view = "board"
		_build_board()
		_refresh()
		_save("继续上一张弹珠台")
		return
	if str(engine.state.get("phase", "")) == "playing":
		guard_level_switch(number, func(): _start_table(number, true), func(): _resume_table(number))
		return
	_start_table(number, true)


func _resume_table(number: int) -> void:
	if not _can_resume_table(number):
		return
	level_id = number
	view = "board"
	_build_board()
	_refresh()
	_save("继续上一张弹珠台")


func _start_table(number: int, announce: bool = true) -> bool:
	if players.is_empty():
		show_toast("先选择小朋友，再来玩弹珠星轨。")
		return false
	var entry := _table_for(number)
	if entry.is_empty():
		show_toast("这张弹珠台还没有准备好。")
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
		var reason := str(engine.state.get("reason", "这张弹珠台还不完整。"))
		engine.state = {}
		show_toast(reason)
		_show_map()
		return false
	session_id = str(engine.state.get("sessionId", ""))
	view = "board"
	_build_board()
	_refresh()
	_save("开始弹珠星轨")
	if announce:
		Speech.stop()
		Speech.speak(
			"第 %s 张弹珠台，%s。先按发射弹珠，再用左右弹板接住它。" % [
				number,
				str(entry.get("title", "星轨弹珠")),
			],
			"pinball-start"
		)
	return true


func _build_board() -> void:
	view = "board"
	PlaygroundUI.clear(content_root)
	field = FIELD.new()
	field.accent = accent
	field.soft = soft_accent
	field.bind(engine, self, players)
	field.action_requested.connect(_on_field_action)
	content_root.add_child(field)


func _refresh() -> void:
	if field != null and is_instance_valid(field):
		field.queue_redraw()


func _blocked() -> bool:
	return is_input_blocked()


func _on_pause_changed(paused_value: bool) -> void:
	if not is_instance_valid(field):
		return
	if paused_value:
		field.cancel_inputs()
		field.suspend_effects()
		engine.release_all_flippers()
		_save("暂停时松开弹板")
		_save_clock = 0.0
	else:
		field.queue_redraw()


func _process(delta: float) -> void:
	super._process(delta)
	if paused or view != "board" or not is_instance_valid(field) or _blocked():
		return
	var phase := str(engine.state.get("phase", ""))
	if phase == "playing":
		var changed := engine.tick(delta)
		var events: Array = engine.drain_events()
		if not events.is_empty():
			field.consume_events(events)
		if changed:
			_save_clock += delta
			if _save_clock >= 2.0:
				_save_clock = 0.0
				_save("弹珠星轨自动保存")
		if str(engine.state.get("phase", "")) == "finished":
			_save("弹珠星轨完成", false)
			_show_result()
	else:
		_save_clock = 0.0


func _on_field_action(action: Dictionary) -> void:
	if _blocked() or _result_visible or view != "board":
		return
	Speech.stop_owner("pinball-feedback")
	var result := engine.handle_input(action)
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "这个操作现在不能用")))
		SfxMap.play(&"error")
		return
	field.consume_events(engine.drain_events())
	_save("弹珠星轨操作保存")
	_refresh()
	if str(engine.state.get("phase", "")) == "finished":
		_save("弹珠星轨完成", false)
		_show_result()


func _save(note: String = "实时自动保存弹珠进度", resume: bool = true) -> void:
	if engine.state.is_empty() or players.is_empty():
		return
	_record_completion_if_needed()
	engine.state.view = view
	var primary_id := str(players[0].id)
	SaveStore.save_state(
		game_id,
		primary_id,
		engine.snapshot(),
		note,
		resume and str(engine.state.get("phase", "")) == "playing"
	)


func _record_completion_if_needed() -> bool:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return false
	if bool(engine.state.get("reported", false)):
		return false
	var summary := engine.result()
	if summary.is_empty():
		return false
	if not bool(summary.get("success", false)):
		engine.state.reported = true
		return true
	var stars := int(summary.get("stars", engine.stars()))
	var outcome := "played" if mode_id == "classic" else "win"
	var score := int(summary.get("score", 0))
	var lit := int(summary.get("targetsLit", 0))
	var total := int(summary.get("targetTotal", 0))
	var session_key := str(engine.state.get("sessionId", "pinball"))
	var all_recorded := true
	for player in players:
		var player_id := str(player.get("id", ""))
		if player_id.is_empty():
			continue
		SaveStore.complete_level(player_id, game_id, level_id, stars, mode_id)
		var recorded := SaveStore.record_outcome(
			player_id,
			game_id,
			outcome,
			score,
			lit,
			total,
			{"logic": {"correct": lit, "answered": total}},
			session_key
		)
		if not recorded:
			all_recorded = false
	if all_recorded:
		engine.state.reported = true
	return all_recorded


func _show_result() -> void:
	if engine.state.is_empty() or str(engine.state.get("phase", "")) != "finished":
		return
	var summary := engine.result()
	if summary.is_empty():
		return
	if _record_completion_if_needed():
		_save("弹珠星轨结算保存", false)
	if _result_visible:
		return
	_result_visible = true
	var success := bool(summary.get("success", false))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var trophy := ArtLibrary.semantic_picture("trophy" if success else "hint", "ui", Vector2(82, 82))
	trophy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(trophy)
	var title_text := "星轨完成啦！"
	if not success:
		title_text = "还差一点，再试一次"
	elif mode_id == "classic" and players.size() >= 2:
		title_text = "两位小朋友一起点亮星轨！"
	var title := PlaygroundUI.label(title_text, 27, accent, 700, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var stats := "目标灯 %s / %s · 缓冲柱 %s 次 · 分数 %s · 弹珠 %s · 保护 %s 次" % [
		int(summary.get("targetsLit", 0)),
		int(summary.get("targetTotal", 0)),
		int(summary.get("bumperHits", 0)),
		int(summary.get("score", 0)),
		int(summary.get("ballsLeft", 0)),
		int(summary.get("ballSavesUsed", 0)),
	]
	var stats_label := PlaygroundUI.label(stats, 18, PlaygroundUI.INK_SOFT, 500, true)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(stats_label)
	if success:
		var stars_row := HBoxContainer.new()
		stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
		stars_row.add_theme_constant_override("separation", 8)
		for index in 3:
			var star := ArtLibrary.semantic_picture("star", "ui", Vector2(38, 38))
			star.modulate = Color.WHITE if index < int(summary.get("stars", 0)) else Color(1, 1, 1, 0.24)
			stars_row.add_child(star)
		body.add_child(stars_row)
	var explanation_text := str(engine.state.get("level", {}).get("explanation", ""))
	if not success:
		explanation_text = str(summary.get("reason", "再看看目标灯的位置。")) + "\n" + explanation_text
	if not explanation_text.is_empty():
		var explanation := PlaygroundUI.label(explanation_text, 18, PlaygroundUI.INK, 500, true)
		explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(explanation)
	var actions: Array = [
		{
			"text": "回看台面",
			"icon": "back",
			"kind": "soft",
			"callback": _close_result_for_board,
		},
		{
			"text": "弹珠台列表",
			"icon": "game",
			"kind": "soft",
			"callback": _open_map_from_result,
		},
	]
	if not success:
		actions = [
			{
				"text": "弹珠台列表",
				"icon": "game",
				"kind": "soft",
				"callback": _open_map_from_result,
			},
			{
				"text": "再试一次",
				"icon": "restart",
				"kind": "primary",
				"callback": _retry_current_table,
			},
		]
	elif level_id < _mode_tables().size() and _level_unlocked(level_id + 1):
		actions.append({"text": "下一张星轨", "icon": "next", "kind": "primary", "callback": _go_next_table})
	else:
		actions.append({
			"text": "回游戏大厅",
			"icon": "home",
			"kind": "primary",
			"callback": _return_to_lobby_from_result,
		})
	open_modal("弹珠星轨", body, actions, SaveStore.save_status_text(), false)
	SfxMap.play(&"win" if success else &"error")
	FeedbackKit.haptic(14 if success else 7)
	var spoken := "星轨完成，获得 %s 颗评价星。" % int(summary.get("stars", 0))
	if not success:
		spoken = "这次还没有点亮全部目标灯，再试一次就会更熟练。"
	elif mode_id == "classic" and players.size() >= 2:
		spoken = "%s和%s一起点亮了弹珠星轨。" % [
			str(players[0].get("name", "小朋友")),
			str(players[1].get("name", "小伙伴")),
		]
	Speech.speak(spoken, "pinball-result")


func _close_result_for_board() -> void:
	_result_visible = false
	Speech.stop_owner("pinball-result")
	_close_top_modal()


func _open_map_from_result() -> void:
	Speech.stop_owner("pinball-result")
	_close_top_modal()
	_show_map()


func _retry_current_table() -> void:
	Speech.stop_owner("pinball-result")
	_close_top_modal()
	_start_table(level_id, false)


func _return_to_lobby_from_result() -> void:
	Speech.stop_owner("pinball-result")
	_close_all_game_dialogs()
	back_requested.emit()


func _go_next_table() -> void:
	Speech.stop_owner("pinball-result")
	_close_top_modal()
	var next_number := level_id + 1
	if next_number > _mode_tables().size() or not _level_unlocked(next_number):
		_show_map()
		return
	_start_table(next_number, true)


func _extra_pause_actions() -> Array:
	if view != "board" or str(engine.state.get("phase", "")) != "playing":
		return []
	return [
		{
			"text": "弹珠台列表",
			"icon": "game",
			"kind": "soft",
			"callback": _pause_open_map,
		},
		{"text": "看看提示", "icon": "hint", "kind": "soft", "callback": _show_hint},
	]


func _pause_open_map() -> void:
	_close_pause_tools()
	_show_map()


func _show_hint() -> void:
	var result := engine.hint()
	if not bool(result.get("ok", false)):
		field.flash_notice(str(result.get("message", "暂时没有提示")))
		return
	_save("看了弹珠提示")
	field.flash_notice(str(result.get("hint", "先用弹板把弹珠送回上方。")), 3.0)
	SfxMap.play(&"tap")
	_refresh()


func _confirm_restart() -> void:
	if view != "board" or engine.state.is_empty():
		_close_pause_tools()
		show_toast("先选一张弹珠台，再重新开始。")
		return
	var text := PlaygroundUI.label(
		"这张台面会回到发射前；其他弹珠台、已获得星星和儿童档案不会受影响。",
		19,
		PlaygroundUI.INK_SOFT,
		500,
		true
	)
	open_modal("重开这张弹珠台？", text, [
		{"text": "继续这局", "icon": "back", "kind": "soft", "callback": func(): _close_top_modal()},
		{"text": "重新开始", "icon": "restart", "kind": "primary", "callback": _restart_from_confirm},
	], "弹珠星轨")


func _restart_from_confirm() -> void:
	var was_paused := paused
	_suppress_resume_on_close = was_paused
	_close_all_game_dialogs()
	if was_paused:
		paused = false
		_pause_root_layer = null
		MotionKit.set_paused_tree(self, false)
		pause_changed.emit(false)
	_suppress_resume_on_close = false
	_start_table(level_id, false)


func show_help() -> void:
	if not paused and view == "board":
		_open_pause_tools()
	Speech.stop()
	var lines := [
		"先点发射弹珠，让弹珠沿右侧轨道进入台面。",
		"弹珠靠近下方时，按住左侧或右侧区域。弹板会把它送回上方。",
		"撞到圆缓冲柱会加分，碰到目标灯会把它点亮。",
		"全部目标灯点亮后，让弹珠从中央落下，就会出现落球保护或完成星轨。",
		"双人时左弹板由第一位小朋友控制，右弹板由第二位小朋友控制，分数和球权共享。",
	]
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var icons := ["play", "hint", "star", "trophy", "game"]
	for index in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(ArtLibrary.semantic_picture(str(icons[index]), "ui", Vector2(42, 42)))
		var copy := PlaygroundUI.label(str(lines[index]), 19, PlaygroundUI.INK, 600, true)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		body.add_child(row)
	var spoken := "弹珠星轨玩法。" + " ".join(PackedStringArray(lines))
	Speech.speak(spoken, "game-help")
	open_modal("怎么玩", body, [
		{
			"text": "三步小课堂",
			"icon": "play",
			"kind": "soft",
			"callback": _start_help_lesson,
		},
		{"text": "再读一遍", "icon": "repeat", "kind": "soft", "callback": func(): Speech.speak(spoken, "game-help")},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "按住弹板，点亮全部目标灯")


func _start_help_lesson() -> void:
	_close_top_modal()
	call_deferred("begin_lesson", true)


func _show_rules() -> void:
	var lines := [
		"弹珠从右侧发射道出发，受重力和台面反弹影响，规则固定按 120Hz 小步计算。",
		"弹珠撞到圆缓冲柱会得分；碰到目标灯会永久点亮本局目标，重复碰撞只加少量分数。",
		"弹珠从中央落口掉下时会先使用落球保护。保护用完才消耗一颗球。",
		"全部目标灯点亮后，再从中央落口掉下就完成星轨。两颗挑战台的大多数台面只有两次机会。",
		"双人合作共享分数、球权和落球保护，不会比较输赢。",
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
	Speech.speak(" ".join(PackedStringArray(lines)), "pinball-help")
	open_modal("弹珠星轨规则", body, [
		{"text": "读给我听", "icon": "speech", "kind": "soft", "callback": func(): Speech.repeat()},
		{"text": "知道了", "icon": "check", "kind": "primary", "callback": func(): _close_top_modal()},
	], "固定弹板、缓冲柱和目标灯")


func begin_lesson(force: bool = false) -> void:
	if not force:
		return
	if not paused and view == "board":
		_open_pause_tools()
	var copy := [
		"先按发射弹珠，看弹珠沿着右侧轨道升到台面上方。",
		"弹珠回到下方时，按住离它近的弹板；松开后弹板会慢慢回位。",
		"点亮全部目标灯，再让弹珠从中央落下，就会完成这张星轨。",
	]
	if mode_id == "classic":
		copy[1] = "左边的小朋友守左弹板，右边的小朋友守右弹板，看到球靠近就按住。"
	lesson_texts = copy
	_lesson_icons = ["play", "hint", "star"]
	call("_show_lesson_page", 0)
